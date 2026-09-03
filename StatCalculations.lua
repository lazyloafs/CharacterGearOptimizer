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

    -- Hit/Expertise/Defense/Resilience ratings were all removed from the
    -- game on Mainline (Legion secondary-stat squish removed Hit/Expertise;
    -- Defense/Resilience were removed even earlier, in Cataclysm/MoP). None
    -- of these caps apply to a Retail character, so report "no cap" rather
    -- than reusing stale WotLK cap values against modern stat values.
    if addon.isMainline then
        return false, 0, 0
    end

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

-- ============================================================================
-- PAWN STRING IMPORT & EXPORT PARSER ENGINE
-- ============================================================================
StatCalc.PAWN_STAT_IMPORT_MAP = {
    -- Primary Stats
    strength             = "STR",
    str                  = "STR",
    agility              = "AGI",
    agi                  = "AGI",
    stamina              = "STA",
    sta                  = "STA",
    intellect            = "INT",
    int                  = "INT",
    spirit               = "SPI",
    spi                  = "SPI",

    -- Attack & Spell Power / Regen
    ap                   = "AP",
    attackpower          = "AP",
    attack_power         = "AP",
    rap                  = "AP",
    rangedattackpower    = "AP",
    ranged_attack_power  = "AP",
    feralap              = "FAP",
    feralattackpower     = "FAP",
    feral_attack_power   = "FAP",
    sp                   = "SP",
    spellpower           = "SP",
    spell_power          = "SP",
    spelldamage          = "SP",
    spell_damage         = "SP",
    damageandhealing     = "SP",
    healing              = "HEAL",
    heal                 = "HEAL",
    mp5                  = "MP5",
    manaregen            = "MP5",
    mana_per_5           = "MP5",

    -- Combat Ratings: Hit / Crit / Haste / Expertise
    hitrating            = "HIT",
    hit_rating           = "HIT",
    hit                  = "HIT",
    spellhitrating       = "SPELLHIT",
    spell_hit_rating     = "SPELLHIT",
    spellhit             = "SPELLHIT",
    critrating           = "CRIT",
    crit_rating          = "CRIT",
    crit                 = "CRIT",
    meleecritrating      = "MELEECRIT",
    melee_crit_rating    = "MELEECRIT",
    meleecrit            = "MELEECRIT",
    spellcritrating      = "SPELLCRIT",
    spell_crit_rating    = "SPELLCRIT",
    spellcrit            = "SPELLCRIT",
    hasterating          = "HASTE",
    haste_rating         = "HASTE",
    haste                = "HASTE",
    spellhaste           = "HASTE",
    spellhasterating     = "HASTE",
    meleehaste           = "HASTE",
    meleehasterating     = "HASTE",
    expertiserating      = "EXP",
    expertise_rating     = "EXP",
    expertise            = "EXP",
    exp                  = "EXP",

    -- Defensive & Tank Stats
    defenserating        = "DEF",
    defense_rating       = "DEF",
    defense              = "DEF",
    def                  = "DEF",
    dodgerating          = "DODGE",
    dodge_rating         = "DODGE",
    dodge                = "DODGE",
    parryrating          = "PARRY",
    parry_rating         = "PARRY",
    parry                = "PARRY",
    resiliencerating     = "RESIL",
    resilience_rating    = "RESIL",
    resilience           = "RESIL",
    resil                = "RESIL",
    armorpenetration     = "ARP",
    armorpenetrationrating = "ARP",
    armor_penetration    = "ARP",
    arp                  = "ARP",
    blockrating          = "BLOCK_RATING",
    block_rating         = "BLOCK_RATING",
    block                = "BLOCK_RATING",
    blockvalue           = "BLOCK_VALUE",
    block_value          = "BLOCK_VALUE",
    bv                   = "BLOCK_VALUE",
    armor                = "ARMOR",
    bonusarmor           = "ARMOR",
    spellpenetration     = "SPELL_PEN",
    spell_penetration    = "SPELL_PEN",
    spellpen             = "SPELL_PEN",

    -- Weapon DPS
    dps                  = "WEAPON_DPS",
    weapondps            = "WEAPON_DPS",
    weapon_dps           = "WEAPON_DPS",
    mastery              = "MASTERY",
    masteryrating        = "MASTERY",
    versatility          = "VERSATILITY",
    vers                 = "VERSATILITY",
}

StatCalc.PAWN_STAT_EXPORT_KEYS = {
    STR          = "Strength",
    AGI          = "Agility",
    STA          = "Stamina",
    INT          = "Intellect",
    SPI          = "Spirit",
    AP           = "Ap",
    FAP          = "FeralAp",
    SP           = "SpellPower",
    HEAL         = "Healing",
    MP5          = "Mp5",
    HIT          = "HitRating",
    SPELLHIT     = "SpellHitRating",
    CRIT         = "CritRating",
    SPELLCRIT    = "SpellCritRating",
    MELEECRIT    = "MeleeCritRating",
    HASTE        = "HasteRating",
    EXP          = "ExpertiseRating",
    DEF          = "DefenseRating",
    DODGE        = "DodgeRating",
    PARRY        = "ParryRating",
    RESIL        = "ResilienceRating",
    ARP          = "ArmorPenetration",
    BLOCK_RATING = "BlockRating",
    BLOCK_VALUE  = "BlockValue",
    ARMOR        = "Armor",
        SPELL_PEN    = "SpellPenetration",
        WEAPON_DPS   = "Dps",
    MASTERY      = "MasteryRating",
    VERSATILITY  = "Versatility",
}

StatCalc.PAWN_CANONICAL_ORDER = {
    "STR", "AGI", "STA", "INT", "SPI",
    "AP", "FAP", "SP", "HEAL", "MP5",
    "HIT", "SPELLHIT", "CRIT", "SPELLCRIT", "MELEECRIT", "HASTE", "EXP",
    "DEF", "DODGE", "PARRY", "RESIL", "ARP",
    "BLOCK_RATING", "BLOCK_VALUE", "ARMOR", "SPELL_PEN",
        "WEAPON_DPS", "MASTERY", "VERSATILITY"
}

addon.PAWN_STAT_IMPORT_MAP = StatCalc.PAWN_STAT_IMPORT_MAP
addon.PAWN_STAT_EXPORT_KEYS = StatCalc.PAWN_STAT_EXPORT_KEYS

--- Parse a standard Pawn string: ( Pawn: v1: "ScaleName": Class=..., Stat=1.23, ... )
function StatCalc:ParsePawnString(input)
    if not input or type(input) ~= "string" or input == "" then
        return nil, nil, nil
    end

    local clean = input:match("^%s*(.-)%s*$")
    local scaleName = nil
    local metadata = {}
    local weights = {}

    -- Extract Pawn scale name: ( Pawn: v1: "ScaleName": ... ) or Pawn: v1: "ScaleName": ...
    local nameMatch, bodyMatch = clean:match('^[%(%s]*[Pp][Aa][Ww][Nn]:%s*[Vv]%d+:%s*"([^"]+)"%s*:%s*(.*)')
    if not nameMatch then
        nameMatch, bodyMatch = clean:match('^[%(%s]*"([^"]+)"%s*:%s*(.*)')
    end

    if nameMatch then
        scaleName = nameMatch
        clean = bodyMatch or clean
    end

    -- Strip trailing parenthesis or whitespace
    clean = clean:gsub('%)%s*$', '')

    -- Parse key=value or key: value pairs
    for token in clean:gmatch("([^,]+)") do
        local key, val = token:match("([^:=]+)%s*[:=]%s*(.+)")
        if key and val then
            key = key:match("^%s*(.-)%s*$")
            val = val:match("^%s*(.-)%s*$")
            -- Strip wrapping quotes if any
            val = val:gsub('^"', ''):gsub('"$', '')

            local num = tonumber(val)
            local lkey = key:lower():gsub("[%s_%-]", "")
            if num then
                local internalKey = StatCalc.PAWN_STAT_IMPORT_MAP[lkey]
                if internalKey then
                    weights[internalKey] = num
                else
                    metadata[key] = num
                end
            else
                metadata[key] = val
            end
        end
    end

    -- If no key=value comma pairs matched, fallback to regex search
    if not next(weights) then
        for key, val in clean:gmatch('([%w_]+)%s*=%s*([%-]?%d+%.?%d*)') do
            local num = tonumber(val)
            local internalKey = StatCalc.PAWN_STAT_IMPORT_MAP[key:lower():gsub("[%s_%-]", "")]
            if num and internalKey then
                weights[internalKey] = num
            end
        end
    end

    metadata.scaleName = scaleName
    if metadata.Class then
        metadata.className = metadata.Class
    end

    if not next(weights) then
        return nil, metadata, scaleName
    end

    return weights, metadata, scaleName
end

--- Create a valid, standard Pawn scale string from stat weights
function StatCalc:CreatePawnString(weights, scaleName, metadata)
    if type(weights) ~= "table" then return "" end

    scaleName = scaleName or (addon.currentCustomProfile and addon.currentCustomProfile.name) or "CGO Custom"
    scaleName = tostring(scaleName):gsub('"', "'")

    local parts = {}

    -- Include class metadata if available
    local className = nil
    if type(metadata) == "table" and metadata.Class then
        className = metadata.Class
    elseif type(metadata) == "string" and metadata ~= "" then
        className = metadata
    elseif addon.currentClass then
        className = addon.currentClass
    end

    if className then
        -- Normalize class name to Title Case for Pawn convention
        local titleClass = className:sub(1,1):upper() .. className:sub(2):lower()
        if className == "DEATHKNIGHT" then titleClass = "DeathKnight" end
        table.insert(parts, "Class=" .. titleClass)
    end

    if type(metadata) == "table" and metadata.Spec then
        table.insert(parts, "Spec=" .. tostring(metadata.Spec))
    end

    -- Append non-zero stat weights in canonical order
    local handled = {}
    for _, statKey in ipairs(StatCalc.PAWN_CANONICAL_ORDER) do
        local val = tonumber(weights[statKey])
        if val and val ~= 0 then
            local pawnKey = StatCalc.PAWN_STAT_EXPORT_KEYS[statKey] or statKey
            local formattedVal = string.format("%.2f", val):gsub("%.?0+$", "")
            table.insert(parts, pawnKey .. "=" .. formattedVal)
            handled[statKey] = true
        end
    end

    -- Append any custom stats not in canonical list
    for statKey, val in pairs(weights) do
        if not handled[statKey] then
            local num = tonumber(val)
            if num and num ~= 0 then
                local pawnKey = StatCalc.PAWN_STAT_EXPORT_KEYS[statKey] or statKey
                local formattedVal = string.format("%.2f", num):gsub("%.?0+$", "")
                table.insert(parts, pawnKey .. "=" .. formattedVal)
            end
        end
    end

    return string.format('( Pawn: v1: "%s": %s )', scaleName, table.concat(parts, ", "))
end

--- Universal export helper supporting "pawn", "simc", "json", and "cloud"
function StatCalc:ExportWeights(weights, arg2, arg3, class, specIdx)
    local scaleName = "CGO Profile"
    local format = "pawn"

    if arg2 == "pawn" or arg2 == "simc" or arg2 == "json" or arg2 == "cloud" then
        format = arg2
        scaleName = arg3 or scaleName
    elseif arg3 == "pawn" or arg3 == "simc" or arg3 == "json" or arg3 == "cloud" then
        scaleName = arg2 or scaleName
        format = arg3
    elseif arg2 and type(arg2) == "string" then
        scaleName = arg2
    end
    format = (format or "pawn"):lower()

    if format == "cloud" then
        if addon.CloudSync and addon.CloudSync.BuildProfileData and addon.CloudSync.EncodeProfileToString then
            local profile = addon.CloudSync:BuildProfileData(scaleName, weights)
            return addon.CloudSync:EncodeProfileToString(profile)
        end
    elseif format == "pawn" then
        return self:CreatePawnString(weights, scaleName, class)
    elseif format == "simc" then
        local lines = { "# CharacterGearOptimizer SimC Export: " .. scaleName }
        for _, statKey in ipairs(StatCalc.PAWN_CANONICAL_ORDER) do
            local val = tonumber(weights and weights[statKey])
            if val and val ~= 0 then
                table.insert(lines, string.format("%s=%.2f", statKey, val):gsub("%.?0+$", ""))
            end
        end
        return table.concat(lines, "\n")
    elseif format == "json" then
        local entries = {}
        for _, statKey in ipairs(StatCalc.PAWN_CANONICAL_ORDER) do
            local val = tonumber(weights and weights[statKey])
            if val and val ~= 0 then
                local keyName = (StatCalc.PAWN_STAT_EXPORT_KEYS[statKey] or statKey):lower()
                table.insert(entries, string.format('    "%s": %.2f', keyName, val))
            end
        end
        return string.format('{\n  "name": "%s",\n  "weights": {\n%s\n  }\n}', scaleName, table.concat(entries, ",\n"))
    end

    return self:CreatePawnString(weights, scaleName, class)
end

--- Universal import parser supporting Pawn strings, JSON, SimC, Cloud Code, and key=value pairs
function StatCalc:ImportWeights(input)
    if not input or type(input) ~= "string" or input == "" then
        return nil, nil
    end

    local clean = input:match("^%s*(.-)%s*$")
    local weights = {}
    local scaleName = nil
    local detectedFormat = "unknown"
    local metadata = {}

    -- 0. Try Cloud Code format: !CGO1:...
    if clean:match("^!CGO1:") and clean:match("!$") then
        if addon.CloudSync and addon.CloudSync.DecodeProfileFromString then
            local profile, err, fmt = addon.CloudSync:DecodeProfileFromString(clean)
            if profile and profile.weights and next(profile.weights) then
                metadata = profile
                metadata.format = "cloud"
                metadata.scaleName = profile.name
                return profile.weights, metadata, profile.name or "Cloud Profile", "cloud"
            end
        end
    end

    -- 1. Try Pawn format
    if clean:match('[Pp][Aa][Ww][Nn]:') or clean:match('^%(%s*[Pp][Aa][Ww][Nn]:') or clean:match('^%(%s*"') then
        detectedFormat = "pawn"
        local pWeights, pMeta, pName = self:ParsePawnString(clean)
        if pWeights and next(pWeights) then
            pMeta = pMeta or {}
            pMeta.format = "pawn"
            return pWeights, pMeta, pMeta.scaleName or pName, detectedFormat
        end
    end

    -- 2. Try JSON format: { "key": 1.23 }
    if clean:match('^{') and clean:match('}$') then
        detectedFormat = "json"
        scaleName = clean:match('"name"%s*:%s*"([^"]+)"')
        for key, val in clean:gmatch('"([%w_]+)"%s*:%s*"?([%-]?%d+%.?%d*)"?') do
            local num = tonumber(val)
            local lkey = key:lower():gsub("[%s_%-]", "")
            local internalKey = StatCalc.PAWN_STAT_IMPORT_MAP[lkey]
            if num and internalKey then
                weights[internalKey] = num
            end
        end
        if next(weights) then
            metadata.scaleName = scaleName
            metadata.format = "json"
            return weights, metadata, scaleName, detectedFormat
        end
    end

    -- 3. Try SimC / key=value / INI format (e.g. Str=2.5, Agi=1.2 or multiline)
    detectedFormat = "simc"
    -- Strip comments
    local stripped = clean:gsub('#[^\n]*', ''):gsub('//[^\n]*', '')
    for key, val in stripped:gmatch('([%w_]+)%s*[:=]%s*([%-]?%d+%.?%d*)') do
        local num = tonumber(val)
        local lkey = key:lower():gsub("[%s_%-]", "")
        local internalKey = StatCalc.PAWN_STAT_IMPORT_MAP[lkey]
        if num and internalKey then
            weights[internalKey] = num
        end
    end

    if next(weights) then
        metadata.format = "simc"
        return weights, metadata, scaleName, detectedFormat
    end

    return nil, nil
end

-- Wire to addon global methods for DevTool and UI accessibility
addon.ParsePawnString = function(self, input)
    return StatCalc:ParsePawnString(input)
end

addon.CreatePawnString = function(self, weights, scaleName, metadata)
    return StatCalc:CreatePawnString(weights, scaleName, metadata)
end

addon.ExportWeights = function(self, weights, scaleName, format)
    return StatCalc:ExportWeights(weights, scaleName, format)
end

addon.ImportWeights = function(self, input)
    return StatCalc:ImportWeights(input)
end

