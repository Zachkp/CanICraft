local _, ns = ...
local CIC = ns.CIC

local UI = {}
ns.UI = UI

-- Our font strings, keyed by Blizzard's row frames. Kept outside the Blizzard
-- frames so we never write fields onto them.
local rowTags = setmetatable({}, { __mode = "k" })
local hookedRows = setmetatable({}, { __mode = "k" })

-- Gold [n]: craftable if you buy vendor reagents and/or craft the parts first.
local COLOR = "|cffffd100"

local DecorateRow

-- Rows get reused for different recipes (scrolling, collapsing a category).
-- Re-run after the row's own Init so the number follows the new name.
local function HookRow(frame)
    if hookedRows[frame] or type(frame.Init) ~= "function" then return end
    hookedRows[frame] = true
    hooksecurefunc(frame, "Init", function(self, node) DecorateRow(self, node) end)
end

function DecorateRow(frame, elementData)
    HookRow(frame)
    local tag = rowTags[frame]
    elementData = elementData or (frame.GetElementData and frame:GetElementData())
    local data = elementData and elementData.GetData and elementData:GetData()
    local info = type(data) == "table" and data.recipeInfo

    -- Nothing to add if it's not a learned recipe, or Blizzard already shows a count.
    if not (info and info.learned and CIC.db.showList) or (info.numAvailable or 0) > 0 then
        if tag then tag:SetText("") end
        return
    end

    CIC:EnsureReady()
    local n, capped = CIC:GetResult(info.recipeID)
    if n <= 0 then
        if tag then tag:SetText("") end
        return
    end

    if not tag then
        tag = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        rowTags[frame] = tag
    end
    tag:SetText(("%s[%d%s]|r"):format(COLOR, n, capped and "+" or ""))

    -- Pinned to the right end of the row, clear of the name and Blizzard's count.
    tag:ClearAllPoints()
    tag:SetPoint("RIGHT", frame, "RIGHT", -6, 0)
end

local function GetRecipeList()
    local page = ProfessionsFrame and ProfessionsFrame.CraftingPage
    return page and page.RecipeList
end

function UI:RefreshList()
    local list = GetRecipeList()
    local box = list and list.ScrollBox
    if box and box.ForEachFrame then
        box:ForEachFrame(function(frame, elementData) DecorateRow(frame, elementData) end)
    end
end

function UI:Hook()
    if self.hooked then return end
    local list = GetRecipeList()
    if not (list and list.ScrollBox and ScrollUtil) then return end
    self.hooked = true

    local function OnRow(frame, elementData) DecorateRow(frame, elementData) end
    if ScrollUtil.AddInitializedFrameCallback then
        ScrollUtil.AddInitializedFrameCallback(list.ScrollBox, OnRow, UI, true)
    else
        ScrollUtil.AddAcquiredFrameCallback(list.ScrollBox, OnRow, UI, true)
    end
    ProfessionsFrame.CraftingPage:HookScript("OnShow", function() UI:QueueRefresh() end)
end

function UI:QueueRefresh()
    if self.pending then return end
    self.pending = true
    C_Timer.After(0.15, function()
        self.pending = false
        if ProfessionsFrame and ProfessionsFrame:IsShown() then self:RefreshList() end
    end)
end

local function SelectedRecipeID()
    local form = ProfessionsFrame and ProfessionsFrame.CraftingPage and ProfessionsFrame.CraftingPage.SchematicForm
    local info = form and form.GetRecipeInfo and form:GetRecipeInfo()
    return info and info.recipeID
end

function UI:Debug()
    local list = GetRecipeList()
    CIC.Print("ProfessionsFrame: %s, recipe list: %s, scroll box: %s, hooked: %s",
        tostring(ProfessionsFrame ~= nil), tostring(list ~= nil),
        tostring(list and list.ScrollBox ~= nil), tostring(self.hooked == true))
end

-- Prints the selected recipe's raw reagent data, to check the addon reads it right.
function UI:DumpSelected()
    local rid = SelectedRecipeID()
    if not rid then return CIC.Print("select a recipe in the profession window first") end
    local s = C_TradeSkillUI.GetRecipeSchematic(rid, false)
    CIC.Print("recipe %d, makes item %s x%s", rid, tostring(s and s.outputItemID), tostring(s and s.quantityMin))
    for i, slot in ipairs(s and s.reagentSlotSchematics or {}) do
        local ids = {}
        for _, rg in ipairs(slot.reagents or {}) do
            local id = rg.itemID or rg.currencyID
            ids[#ids + 1] = ("%s (%s)"):format(tostring(id), tostring(id and C_Item.GetItemNameByID(id)))
        end
        print(("  slot %d: qty %s, required %s, type %s, dataSlotType %s, reagents: %s"):format(
            i, tostring(slot.quantityRequired), tostring(slot.required), tostring(slot.reagentType),
            tostring(slot.dataSlotType), table.concat(ids, ", ")))
    end
end
