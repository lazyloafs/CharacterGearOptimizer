-- ============================================================================
-- CharacterGearOptimizer: Classic.lua
-- Classic Era (1.15.x / SoD), TBC Classic (2.5.x), Wrath (3.3.5 / 3.4.x),
-- and Cataclysm Classic (4.4.x) compatibility module.
-- ============================================================================

local addonName, addon = ...
local addon = addon or _G.CharacterGearOptimizer or {}
_G.CharacterGearOptimizer = addon

addon.Classic = addon.Classic or {}
local Classic = addon.Classic

-- Only initialize Classic helpers when on Classic/Legacy clients
if addon.isMainline then
    return
end

-- ============================================================================
-- Classic Talent Tree Spec Detection
-- ============================================================================
function Classic:DetectSpecFromTalents(classSpecs)
    if not classSpecs then return nil, 1 end

    local maxTab, maxPoints = 1, 0
    local numTabs = GetNumTalentTabs and GetNumTalentTabs() or 3

    for tab = 1, numTabs do
        local tabPoints = 0
        local numTalents = GetNumTalents and GetNumTalents(tab) or 0
        for t = 1, numTalents do
            local rank
            if GetTalentInfo then
                _, _, _, _, rank = GetTalentInfo(tab, t)
            end
            if rank and type(rank) == "number" then
                tabPoints = tabPoints + rank
            else
                tabPoints = tabPoints + (tonumber(rank) or 0)
            end
        end
        if tabPoints > maxPoints then
            maxTab = tab
            maxPoints = tabPoints
        end
    end

    local spec = classSpecs[maxTab] or classSpecs[1]
    return spec, maxTab
end

-- ============================================================================
-- Season of Discovery Rune Detection
-- ============================================================================
function Classic:GetActiveEngravings()
    local engravings = {}
    if C_Engraving and C_Engraving.IsEngravingEnabled and C_Engraving.IsEngravingEnabled() then
        local equipmentSlots = { 1, 3, 5, 6, 7, 8, 9, 10 }
        for _, slotID in ipairs(equipmentSlots) do
            local engravingInfo = C_Engraving.GetRuneForEquipmentSlot(slotID)
            if engravingInfo then
                table.insert(engravings, engravingInfo)
            end
        end
    end
    return engravings
end

-- ============================================================================
-- Classic Defense & Hit Caps
-- ============================================================================
function Classic:GetDefenseCapForExpansion()
    if addon.isVanilla then
        return 440 -- Level 60 raid defense cap vs +3 boss
    elseif addon.isTBC then
        return 490 -- Level 70 raid defense cap (140 rating over 350)
    elseif addon.isWrath then
        return 540 -- Level 80 raid defense cap (140 rating over 400)
    elseif addon.isCata then
        return 540 -- Cataclysm mastery/avoidance model
    end
    return 540
end

addon.Classic = Classic
