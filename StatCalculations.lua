-- ============================================================================
-- CharacterGearOptimizer: StatCalculations.lua
-- Multi-version stat calculations, combat ratings conversion, armor DR,
-- cap detection, and effective health pool (EHP) calculations.
-- ============================================================================

local addonName, addon = ...
local addon = addon or _G.CharacterGearOptimizer or {}
_G.CharacterGearOptimizer = addon

addon.StatCalc = addon.StatCalc or {}
local StatCalc = addon.StatCalc

-- Default rating tables (WotLK / Classic fallback)
local DEFAULT_RATING = {
    HIT_PER_PCT           = 8.0,
    SPELL_HIT_PER_PCT     = 8.0,
    CRIT_PER_PCT          = 45.91,
    HASTE_PER_PCT         = 32.79,
    EXPERTISE_PER_SKILL   = 8.1974,
    DEFENSE_PER_SKILL     = 4.918,
    DODGE_PER_RATING      = 39.35,
    PARRY_PER_RATING      = 49.18,
    BLOCK_PER_RATING      = 16.39,
    RESIL_PER_PCT         = 81.97,
    AVOID_PER_DEF_SKILL   = 0.16,
    BASE_MISS_PCT         = 5.0,

    MELEE_HIT_CAP_PCT     = 14.0,
    SPELL_HIT_CAP_PCT     = 14.0,
    EXPERTISE_SOFT_CAP    = 26,
    DEFENSE_CAP           = 540,
    UNCRUSHABLE_PCT       = 102.4,
    BOSS_CRIT_PCT         = 5.6,

    ARMOR_DR_CAP_PCT      = 75,
    ARMOR_CAP_VALUE       = 49905,
    ARMOR_CONSTANT        = 16635,

    CR_DEFENSE            = 2,
    CR_DODGE              = 3,
    CR_PARRY              = 4,
    CR_BLOCK              = 5,
    CR_HIT_MELEE          = 6,
    CR_HIT_RANGED         = 7,
    CR_HIT_SPELL          = 8,
    CR_CRIT_MELEE         = 9,
    CR_CRIT_RANGED        = 10,
    CR_CRIT_SPELL         = 11,
    CR_HASTE_MELEE        = 18,
    CR_HASTE_RANGED       = 19,
    CR_HASTE_SPELL        = 20,
    CR_EXPERTISE          = 24,
    CR_ARMOR_PEN          = 25,
}

addon.RATING = addon.RATING or DEFAULT_RATING

-- ============================================================================
-- Armor Damage Reduction
-- ============================================================================
function StatCalc:GetArmorDR(armor, attackerLevel)
    if not armor or armor <= 0 then return 0 end
    local level = attackerLevel or (UnitLevel("player") or 80)
    
    if addon.isMainline then
        -- Modern Retail armor formula
        local k = (level > 60) and (85 * level + 400) or (400 + 85 * level)
        local dr = armor / (armor + k)
        return math.min(dr * 100, 85)
    else
        -- Classic / TBC / Wrath formula
        local mobLevel = level + 3
        local k = (467.5 * mobLevel) - 22167.5
        if k <= 0 then k = 16635 end
        local dr = armor / (armor + k)
        return math.min(dr * 100, 75)
    end
end

-- ============================================================================
-- Effective Health Pool (EHP) Calculation
-- ============================================================================
function StatCalc:CalculateEHP(health, armor, avoidancePct, attackerLevel)
    health = health or 1
    armor = armor or 0
    avoidancePct = avoidancePct or 0
    
    local armorDR = self:GetArmorDR(armor, attackerLevel) / 100
    local armorMultiplier = 1 - armorDR
    if armorMultiplier <= 0.01 then armorMultiplier = 0.01 end
    
    local ehpArmor = health / armorMultiplier
    local avoidanceMultiplier = 1 - math.min(avoidancePct / 100, 0.99)
    if avoidanceMultiplier <= 0.01 then avoidanceMultiplier = 0.01 end
    
    local totalEHP = ehpArmor / avoidanceMultiplier
    return math.floor(totalEHP + 0.5), math.floor(ehpArmor + 0.5)
end

-- ============================================================================
-- Get Combat Rating Helper
-- ============================================================================
function StatCalc:GetCombatRating(crID)
    if not crID then return 0 end
    if GetCombatRating then
        return GetCombatRating(crID) or 0
    end
    return 0
end

function StatCalc:GetCombatRatingBonus(crID)
    if not crID then return 0 end
    if GetCombatRatingBonus then
        return GetCombatRatingBonus(crID) or 0
    end
    return 0
end

-- ============================================================================
-- Cap Status Inspector
-- ============================================================================
function StatCalc:CheckCap(statKey, currentValue, specData)
    local R = addon.RATING or DEFAULT_RATING
    currentValue = currentValue or 0
    
    if statKey == "HIT" or statKey == "SPELLHIT" then
        local cap = (specData and specData.caps and specData.caps.HIT) or R.MELEE_HIT_CAP_PCT or 8
        local capped = currentValue >= cap
        return capped, cap, currentValue - cap
    elseif statKey == "DEF" or statKey == "DEFENSE" then
        local cap = (specData and specData.caps and specData.caps.DEFENSE) or R.DEFENSE_CAP or 540
        local capped = currentValue >= cap
        return capped, cap, currentValue - cap
    elseif statKey == "EXP" or statKey == "EXPERTISE" then
        local cap = (specData and specData.caps and specData.caps.EXPERTISE) or R.EXPERTISE_SOFT_CAP or 26
        local capped = currentValue >= cap
        return capped, cap, currentValue - cap
    elseif statKey == "RESIL" or statKey == "RESILIENCE" then
        local cap = R.RESIL_CAP_RATING or 410
        local capped = currentValue >= cap
        return capped, cap, currentValue - cap
    end
    
    return false, 0, 0
end

-- Expose to main addon table
addon.CalculateEHP = function(self, health, armor, avoidance, level)
    return StatCalc:CalculateEHP(health, armor, avoidance, level)
end

addon.GetArmorDR = function(self, armor, level)
    return StatCalc:GetArmorDR(armor, level)
end
