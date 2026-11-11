local _, ns = ...

-- Reagents that profession supply vendors sell in unlimited quantity.
-- Item IDs are from the original game, which WoW Forever is built on.
-- This list is only a starting point: every time you open a vendor, the addon
-- records whatever that vendor sells in unlimited supply (with its price), so
-- anything Forever added or changed gets picked up automatically.
-- You can also manage it in game with /cic add and /cic remove.
ns.VendorSeed = {
    -- Leatherworking
    [4289]  = true, -- Salt
    -- Thread (Leatherworking / Tailoring)
    [2320]  = true, -- Coarse Thread
    [2321]  = true, -- Fine Thread
    [4291]  = true, -- Silken Thread
    [8343]  = true, -- Heavy Silken Thread
    [14341] = true, -- Rune Thread
    -- Dyes and bleach
    [2324]  = true, -- Bleach
    [2325]  = true, -- Black Dye
    [2604]  = true, -- Red Dye
    [2605]  = true, -- Green Dye
    [4340]  = true, -- Gray Dye
    [4341]  = true, -- Yellow Dye
    [4342]  = true, -- Purple Dye
    [6260]  = true, -- Blue Dye
    [6261]  = true, -- Orange Dye
    [10290] = true, -- Pink Dye
    -- Blacksmithing
    [2880]  = true, -- Weak Flux
    [3466]  = true, -- Strong Flux
    -- Alchemy
    [3371]  = true, -- Empty Vial
    [3372]  = true, -- Leaded Vial
    [8925]  = true, -- Crystal Vial
    [18256] = true, -- Imbued Vial
    -- Enchanting / Engineering
    [6217]  = true, -- Copper Rod
    [4470]  = true, -- Simple Wood
    -- Cooking
    [159]   = true, -- Refreshing Spring Water
    [2678]  = true, -- Mild Spices
    [2692]  = true, -- Hot Spices
    [3713]  = true, -- Soothing Spices
}
