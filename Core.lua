local ADDON, ns = ...

local CIC = { producer = {}, results = {} }
ns.CIC = CIC
_G.CanICraft = CIC -- handy for /dump while debugging

local MAX_DEPTH = 4   -- how many levels of "craft the part first" to follow
local MAX_COUNT = 99  -- stop counting craftable amounts past this

local defaults = {
    vendor      = {},    -- [itemID] = unit price in copper (learned from vendors)
    ignore      = {},    -- [itemID] = true (never treat as vendor-bought)
    includeBank = false, -- count bank items as available
    showList    = true,  -- [n] counts in the recipe list
}

local function Print(msg, ...)
    print("|cff33ff99Can I Craft:|r " .. msg:format(...))
end
CIC.Print = Print

function CIC:InitDB()
    CanICraftDB = CanICraftDB or {}
    for k, v in pairs(defaults) do
        if CanICraftDB[k] == nil then
            CanICraftDB[k] = (type(v) == "table") and {} or v
        end
    end
    self.db = CanICraftDB
end

---------------------------------------------------------------------------
-- Vendor knowledge
---------------------------------------------------------------------------

function CIC:IsVendorItem(itemID)
    if type(itemID) ~= "number" or self.db.ignore[itemID] then return false end
    return self.db.vendor[itemID] ~= nil or ns.VendorSeed[itemID] ~= nil
end

function CIC:GetVendorPrice(itemID)
    local v = self.db.vendor[itemID]
    return type(v) == "number" and v or nil
end

function CIC:ScanMerchant()
    if not GetMerchantNumItems then return end
    local added = 0
    for i = 1, GetMerchantNumItems() do
        local itemID = GetMerchantItemID and GetMerchantItemID(i)
        if itemID then
            local price, stack, numAvailable, extendedCost
            if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
                local info = C_MerchantFrame.GetItemInfo(i)
                if info then
                    price, stack, numAvailable, extendedCost =
                        info.price, info.stackCount, info.numAvailable, info.hasExtendedCost
                end
            elseif GetMerchantItemInfo then
                local _
                _, _, price, stack, numAvailable, _, _, extendedCost = GetMerchantItemInfo(i)
            end
            -- Only unlimited stock bought with plain gold counts as "buyable".
            if price and price > 0 and numAvailable == -1 and not extendedCost then
                if self.db.vendor[itemID] == nil and not ns.VendorSeed[itemID] then
                    added = added + 1
                end
                self.db.vendor[itemID] = price / math.max(1, stack or 1)
            end
        end
    end
    if added > 0 then self:Invalidate() end
end

---------------------------------------------------------------------------
-- Inventory
---------------------------------------------------------------------------

local function ItemCount(itemID)
    local bank = CIC.db.includeBank
    if C_Item and C_Item.GetItemCount then
        return C_Item.GetItemCount(itemID, bank, false, bank, bank) or 0
    end
    return GetItemCount(itemID, bank) or 0
end

local function CurrencyCount(key)
    local id = tonumber(key:match("^currency:(%d+)$"))
    local info = id and C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo(id)
    return info and info.quantity or 0
end

---------------------------------------------------------------------------
-- Recipes
---------------------------------------------------------------------------

local recipeCache = {}

-- Returns { id, output, perCraft, slots = { {items = {itemID,...}, qty} | {currency=key, qty} } }
function CIC:GetRecipe(recipeID)
    local cached = recipeCache[recipeID]
    if cached ~= nil then return cached or nil end

    local ok, s = pcall(C_TradeSkillUI.GetRecipeSchematic, recipeID, false)
    if not ok or type(s) ~= "table" then
        recipeCache[recipeID] = false
        return nil
    end

    local r = {
        id = recipeID,
        output = s.outputItemID,
        perCraft = math.max(1, s.quantityMin or 1),
        slots = {},
    }
    for _, slot in ipairs(s.reagentSlotSchematics or {}) do
        -- Optional / finishing reagents have required == false; skip them.
        if slot.required ~= false then
            local qty = slot.quantityRequired or 1
            local items = {}
            for _, rg in ipairs(slot.reagents or {}) do
                local itemID = rg.itemID or (type(rg.reagent) == "table" and rg.reagent.itemID)
                if itemID then
                    items[#items + 1] = itemID
                elseif rg.currencyID and #items == 0 then
                    r.slots[#r.slots + 1] = { currency = "currency:" .. rg.currencyID, qty = qty }
                    break
                end
            end
            if #items > 0 and qty > 0 then
                r.slots[#r.slots + 1] = { items = items, qty = qty }
            end
        end
    end
    recipeCache[recipeID] = r
    return r
end

-- Map "item a recipe creates" -> recipeID, for every learned recipe of the open profession.
function CIC:RebuildProducers()
    wipe(self.producer)
    if not (C_TradeSkillUI and C_TradeSkillUI.GetAllRecipeIDs) then return end
    for _, rid in ipairs(C_TradeSkillUI.GetAllRecipeIDs() or {}) do
        local info = C_TradeSkillUI.GetRecipeInfo(rid)
        if info and info.learned then
            local r = self:GetRecipe(rid)
            if r and r.output and #r.slots > 0 and not self.producer[r.output] then
                self.producer[r.output] = rid
            end
        end
    end
end

---------------------------------------------------------------------------
-- Planner: simulates crafting against a virtual copy of your bags.
---------------------------------------------------------------------------

local function NewCtx(allowVendor, allowCraft)
    return { inv = {}, buy = {}, craft = {}, missing = {},
             allowVendor = allowVendor, allowCraft = allowCraft }
end

local function Avail(ctx, key)
    local v = ctx.inv[key]
    if v == nil then
        v = (type(key) == "number") and ItemCount(key) or CurrencyCount(key)
        ctx.inv[key] = v
    end
    return v
end

local function copy(t)
    local n = {}
    for k, v in pairs(t) do n[k] = v end
    return n
end

local function Snapshot(ctx)
    return { copy(ctx.inv), copy(ctx.buy), copy(ctx.craft), copy(ctx.missing) }
end

local function Restore(ctx, s)
    ctx.inv, ctx.buy, ctx.craft, ctx.missing = s[1], s[2], s[3], s[4]
end

local function add(t, k, n) t[k] = (t[k] or 0) + n end

local CraftOnce -- forward declaration

-- Get `need` more of itemID after the bags ran out: craft it, or buy it.
local function Obtain(ctx, itemID, need, depth, visiting)
    local rid = ctx.allowCraft and CIC.producer[itemID]
    local recipe = rid and not visiting[rid] and depth < MAX_DEPTH and CIC:GetRecipe(rid)
    local canBuy = ctx.allowVendor and CIC:IsVendorItem(itemID)

    if recipe then
        local before = Snapshot(ctx)
        local crafts = math.ceil(need / recipe.perCraft)
        local ok = true
        visiting[rid] = true
        for _ = 1, crafts do
            if not CraftOnce(ctx, recipe, depth + 1, visiting) then ok = false end
        end
        visiting[rid] = nil
        if ok then
            add(ctx.craft, rid, crafts)
            local surplus = crafts * recipe.perCraft - need
            if surplus > 0 then add(ctx.inv, itemID, surplus) end
            return true
        end
        if not canBuy then
            -- Leave the deeper shortfall (e.g. "Heavy Hide") recorded: more useful than "Cured Heavy Hide".
            return false
        end
        Restore(ctx, before)
    end

    if canBuy then
        add(ctx.buy, itemID, need)
        return true
    end
    add(ctx.missing, itemID, need)
    return false
end

local function AcquireSlot(ctx, slot, depth, visiting)
    local need = slot.qty

    if slot.currency then
        local have = Avail(ctx, slot.currency)
        if have >= need then
            ctx.inv[slot.currency] = have - need
            return true
        end
        ctx.inv[slot.currency] = 0
        add(ctx.missing, slot.currency, need - have)
        return false
    end

    -- Use what's in the bags first (any of the accepted items).
    for _, id in ipairs(slot.items) do
        local have = Avail(ctx, id)
        local take = math.min(have, need)
        if take > 0 then
            ctx.inv[id] = have - take
            need = need - take
            if need == 0 then return true end
        end
    end

    if #slot.items == 1 then
        return Obtain(ctx, slot.items[1], need, depth, visiting)
    end
    for _, id in ipairs(slot.items) do
        local before = Snapshot(ctx)
        if Obtain(ctx, id, need, depth, visiting) then return true end
        Restore(ctx, before)
    end
    return Obtain(ctx, slot.items[1], need, depth, visiting)
end

function CraftOnce(ctx, recipe, depth, visiting)
    local ok = true
    for _, slot in ipairs(recipe.slots) do
        -- Keep going after a failure so every shortfall gets listed.
        if not AcquireSlot(ctx, slot, depth, visiting) then ok = false end
    end
    return ok
end

local function Cost(ctx)
    local total, unknown = 0, false
    for itemID, n in pairs(ctx.buy) do
        local p = CIC:GetVendorPrice(itemID)
        if p then total = total + p * n else unknown = true end
    end
    return math.ceil(total), unknown
end
CIC.Cost = Cost

-- Plan `qty` crafts. Returns ctx with .ok, .buy, .craft, .missing, .cost, .unknownPrice
function CIC:Plan(recipeID, qty, allowVendor, allowCraft)
    local recipe = self:GetRecipe(recipeID)
    if not recipe then return nil end
    local ctx = NewCtx(allowVendor, allowCraft)
    ctx.ok = true
    for _ = 1, qty do
        if not CraftOnce(ctx, recipe, 0, { [recipeID] = true }) then ctx.ok = false end
    end
    ctx.cost, ctx.unknownPrice = Cost(ctx)
    return ctx
end

-- How many times can this be crafted? Returns count, hitCap, limitedByGold
function CIC:MaxCraftable(recipeID, allowVendor, allowCraft)
    local recipe = self:GetRecipe(recipeID)
    if not recipe or #recipe.slots == 0 then return 0, false, false end
    local ctx = NewCtx(allowVendor, allowCraft)
    local money = GetMoney and GetMoney() or math.huge
    local n = 0
    while n < MAX_COUNT do
        local before = Snapshot(ctx)
        if not CraftOnce(ctx, recipe, 0, { [recipeID] = true }) then
            Restore(ctx, before)
            return n, false, false
        end
        if allowVendor and Cost(ctx) > money then
            Restore(ctx, before)
            return n, false, true
        end
        n = n + 1
    end
    return n, true, false
end

-- True if every reagent is vendor-bought (directly, or via parts made only from
-- vendor reagents). Those recipes aren't interesting, so they get no count.
function CIC:IsVendorOnly(recipeID, depth)
    depth = depth or 0
    local r = self:GetRecipe(recipeID)
    if not r or #r.slots == 0 or depth > MAX_DEPTH then return false end
    for _, slot in ipairs(r.slots) do
        if slot.currency then return false end
        local ok = false
        for _, id in ipairs(slot.items) do
            local maker = self.producer[id]
            if self:IsVendorItem(id)
               or (maker and maker ~= recipeID and self:IsVendorOnly(maker, depth + 1)) then
                ok = true
                break
            end
        end
        if not ok then return false end
    end
    return true
end

-- How many you could make if you buy vendor reagents and craft parts first.
-- Cached per recipe; wiped whenever bags/money change. Returns count, hitCap.
function CIC:GetResult(recipeID)
    local res = self.results[recipeID]
    if not res then
        local n, capped = 0, false
        if not self:IsVendorOnly(recipeID) then
            n, capped = self:MaxCraftable(recipeID, true, true)
        end
        res = { n, capped }
        self.results[recipeID] = res
    end
    return res[1], res[2]
end

function CIC:Invalidate()
    wipe(self.results)
    if ns.UI then ns.UI:QueueRefresh() end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("TRADE_SKILL_SHOW")
ev:RegisterEvent("TRADE_SKILL_LIST_UPDATE")
ev:RegisterEvent("BAG_UPDATE_DELAYED")
ev:RegisterEvent("PLAYER_MONEY")
ev:RegisterEvent("MERCHANT_SHOW")
ev:RegisterEvent("MERCHANT_UPDATE")

local producersDirty = true

ev:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == ADDON then
            CIC:InitDB()
        elseif arg1 == "Blizzard_Professions" then
            ns.UI:Hook()
        end
    elseif event == "PLAYER_LOGIN" then
        local loaded = (C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded)("Blizzard_Professions")
        if loaded then ns.UI:Hook() end
    elseif event == "TRADE_SKILL_SHOW" then
        ns.UI:Hook()
        producersDirty = true
        CIC:Invalidate()
    elseif event == "TRADE_SKILL_LIST_UPDATE" then
        producersDirty = true
        CIC:Invalidate()
    elseif event == "BAG_UPDATE_DELAYED" or event == "PLAYER_MONEY" then
        CIC:Invalidate()
    elseif event == "MERCHANT_SHOW" or event == "MERCHANT_UPDATE" then
        CIC:ScanMerchant()
    end
end)

-- Called by the UI right before it reads results.
function CIC:EnsureReady()
    if producersDirty and C_TradeSkillUI and C_TradeSkillUI.IsTradeSkillReady
       and C_TradeSkillUI.IsTradeSkillReady() then
        self:RebuildProducers()
        wipe(self.results)
        producersDirty = false
    end
end

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------

local function ParseItem(text)
    return tonumber(text:match("item:(%d+)")) or tonumber(text:match("^%s*(%d+)%s*$"))
end

local function Name(itemID)
    return (C_Item and C_Item.GetItemNameByID(itemID)) or ("item " .. itemID)
end

SLASH_CANICRAFT1 = "/cic"
SLASH_CANICRAFT2 = "/canicraft"
SlashCmdList.CANICRAFT = function(msg)
    local cmd, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
    cmd = cmd:lower()
    local db = CIC.db

    if cmd == "add" then
        local id = ParseItem(rest)
        if not id then return Print("usage: /cic add <item link or ID>") end
        db.ignore[id] = nil
        if db.vendor[id] == nil then db.vendor[id] = true end
        Print("%s will be treated as buyable from a vendor.", Name(id))
        CIC:Invalidate()
    elseif cmd == "remove" then
        local id = ParseItem(rest)
        if not id then return Print("usage: /cic remove <item link or ID>") end
        db.vendor[id] = nil
        db.ignore[id] = true
        Print("%s will no longer be treated as buyable.", Name(id))
        CIC:Invalidate()
    elseif cmd == "list" then
        local seen = {}
        Print("vendor-bought reagents:")
        local function show(id)
            if seen[id] or db.ignore[id] then return end
            seen[id] = true
            local p = CIC:GetVendorPrice(id)
            print(("  %s%s"):format(Name(id), p and (" - " .. GetMoneyString(math.ceil(p), true)) or ""))
        end
        for id in pairs(ns.VendorSeed) do show(id) end
        for id in pairs(db.vendor) do show(id) end
    elseif cmd == "bank" then
        db.includeBank = not db.includeBank
        Print("count bank items: %s", db.includeBank and "on" or "off")
        CIC:Invalidate()
    elseif cmd == "toggle" then
        db.showList = not db.showList
        Print("recipe counts: %s", db.showList and "on" or "off")
        CIC:Invalidate()
    elseif cmd == "dump" then
        ns.UI:DumpSelected()
    elseif cmd == "debug" then
        Print("interface %s", tostring(select(4, GetBuildInfo())))
        ns.UI:Debug()
    else
        Print("commands:")
        print("  /cic add <item>  - mark a reagent as vendor-bought")
        print("  /cic remove <item>  - stop treating a reagent as vendor-bought")
        print("  /cic list  - show known vendor reagents and prices")
        print("  /cic bank  - toggle counting bank items")
        print("  /cic toggle  - turn the [n] counts on/off")
        print("  /cic dump  - print the selected recipe's reagents (for bug reports)")
        print("  /cic debug  - show what the addon could hook into")
    end
end
