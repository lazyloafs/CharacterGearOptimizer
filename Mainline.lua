-- ============================================================================
-- CharacterGearOptimizer: Mainline.lua
-- Retail (The War Within 11.x / Midnight 12.x) compatibility module.
-- Modern spec detection, combat rating maps, and specialization profiles.
-- ============================================================================

local addonName, addon = ...
local addon = addon or _G.CharacterGearOptimizer or {}
_G.CharacterGearOptimizer = addon

addon.Mainline = addon.Mainline or {}
local Mainline = addon.Mainline

-- Only initialize full Retail features when on Mainline client
if not addon.isMainline then
    return
end

-- ============================================================================
-- Modern Combat Ratings
-- ============================================================================
addon.RATING_MAINLINE = {
    CR_CRIT_MELEE           = 9,
    CR_HASTE_MELEE          = 18,
    CR_MASTERY              = 26,
    CR_VERSATILITY_DAMAGE_DONE = 29,
    CR_VERSATILITY_DAMAGE_TAKEN = 31,
    CR_SPEED                = 14,
    CR_LIFESTEAL            = 17,
    CR_AVOIDANCE            = 21,
}

-- ============================================================================
-- Modern Spec Detection
-- ============================================================================
function Mainline:DetectSpec()
    if not GetSpecialization then return nil end
    local specIndex = GetSpecialization()
    if not specIndex or specIndex <= 0 then return nil end

    local specID, specName, specDesc, specIcon, specRole, primaryStat = GetSpecializationInfo(specIndex)
    if not specName then return nil end

    return {
        id = specID,
        index = specIndex,
        name = specName,
        role = specRole or "DAMAGER",
        icon = specIcon,
        primaryStat = primaryStat
    }
end

-- ============================================================================
-- Modern Item Stat Extraction
-- ============================================================================
function Mainline:ExtractModernStats(itemLink)
    if not itemLink then return {} end
    local stats = {}
    
    if C_Item and C_Item.GetItemStats then
        local rawStats = C_Item.GetItemStats(itemLink)
        if rawStats then
            for statKey, value in pairs(rawStats) do
                if statKey == "ITEM_MOD_CRIT_RATING_SHORT" then
                    stats["CRIT"] = (stats["CRIT"] or 0) + value
                elseif statKey == "ITEM_MOD_HASTE_RATING_SHORT" then
                    stats["HASTE"] = (stats["HASTE"] or 0) + value
                elseif statKey == "ITEM_MOD_MASTERY_RATING_SHORT" then
                    stats["MASTERY"] = (stats["MASTERY"] or 0) + value
                elseif statKey == "ITEM_MOD_VERSATILITY" then
                    stats["VERSATILITY"] = (stats["VERSATILITY"] or 0) + value
                elseif statKey == "ITEM_MOD_STRENGTH_SHORT" then
                    stats["STR"] = (stats["STR"] or 0) + value
                elseif statKey == "ITEM_MOD_AGILITY_SHORT" then
                    stats["AGI"] = (stats["AGI"] or 0) + value
                elseif statKey == "ITEM_MOD_INTELLECT_SHORT" then
                    stats["INT"] = (stats["INT"] or 0) + value
                elseif statKey == "ITEM_MOD_STAMINA_SHORT" then
                    stats["STA"] = (stats["STA"] or 0) + value
                elseif statKey == "ITEM_MOD_CR_AVOIDANCE_SHORT" then
                    stats["AVOIDANCE"] = (stats["AVOIDANCE"] or 0) + value
                elseif statKey == "ITEM_MOD_CR_LIFESTEAL_SHORT" then
                    stats["LEECH"] = (stats["LEECH"] or 0) + value
                elseif statKey == "ITEM_MOD_CR_SPEED_SHORT" then
                    stats["SPEED"] = (stats["SPEED"] or 0) + value
                end
            end
        end
    end
    
    return stats
end

-- Hook Retail spec detector if active
if addon.isMainline then
    addon.DetectMainlineSpec = function(self)
        return Mainline:DetectSpec()
    end
end
