-- ============================================================================
-- CharacterGearOptimizer: Weights.lua
-- WotLK 3.3.5 (Ascension) stat weight definitions for every class and spec.
-- WotLK merges: Spell Power (no separate spell dmg/healing), unified Hit/Crit/
-- Haste ratings (no separate spell hit/crit rating on items).
-- ============================================================================

CharacterGearOptimizer = CharacterGearOptimizer or {}

-- ============================================================================
-- STAT LABEL MAP (internal key -> display label)
-- ============================================================================
CharacterGearOptimizer.STAT_LABELS = {
    STR = "Str", AGI = "Agi", STA = "Sta", INT = "Int", SPI = "Spi",
    AP = "AP", FAP = "FAP", SP = "SP", HEAL = "Heal", MP5 = "MP5",
    HIT = "Hit", SPELLHIT = "Spell Hit", CRIT = "Crit", SPELLCRIT = "Spell Crit", MELEECRIT = "Melee Crit", HASTE = "Haste", EXP = "Exp",
    DODGE = "Dodge", PARRY = "Parry", DEF = "Def", RESIL = "Resil",
    ARP = "ArP", BLOCK_RATING = "Block", BLOCK_VALUE = "BV",
    ARMOR = "Armor", SPELL_PEN = "SPen", WEAPON_DPS = "Weapon DPS", PVP_POWER = "PvP Power",
    PVE_POWER = "PvE Power",
    META_SOCKET = "Meta", RED_SOCKET = "Socket", YELLOW_SOCKET = "Socket",
    BLUE_SOCKET = "Socket",
    -- Modern (Mainline/Retail) secondary stats -- removed on Classic-family
    -- clients, so these keys are only ever populated when addon.isMainline.
    MASTERY = "Mastery", VERSATILITY = "Vers", AVOIDANCE = "Avoid",
    LEECH = "Leech", SPEED = "Speed",
}

-- ============================================================================
-- GetItemStats KEY -> INTERNAL STAT KEY MAPPING
-- ============================================================================
CharacterGearOptimizer.ITEM_STAT_MAP = {
    ["ITEM_MOD_STRENGTH_SHORT"]                  = "STR",
    ["ITEM_MOD_AGILITY_SHORT"]                   = "AGI",
    ["ITEM_MOD_STAMINA_SHORT"]                   = "STA",
    ["ITEM_MOD_INTELLECT_SHORT"]                 = "INT",
    ["ITEM_MOD_SPIRIT_SHORT"]                    = "SPI",
    ["ITEM_MOD_ATTACK_POWER_SHORT"]              = "AP",
    ["ITEM_MOD_FERAL_ATTACK_POWER_SHORT"]        = "FAP",
    ["ITEM_MOD_HIT_RATING_SHORT"]                = "HIT",
    ["ITEM_MOD_HIT_SPELL_RATING_SHORT"]           = "SPELLHIT",
    ["ITEM_MOD_CRIT_RATING_SHORT"]               = "CRIT",
    ["ITEM_MOD_CRIT_SPELL_RATING_SHORT"]         = "SPELLCRIT",
    ["ITEM_MOD_CRIT_MELEE_RATING_SHORT"]         = "MELEECRIT",
    ["ITEM_MOD_HASTE_RATING_SHORT"]              = "HASTE",
    ["ITEM_MOD_EXPERTISE_RATING_SHORT"]          = "EXP",
    ["ITEM_MOD_DODGE_RATING_SHORT"]              = "DODGE",
    ["ITEM_MOD_PARRY_RATING_SHORT"]              = "PARRY",
    ["ITEM_MOD_DEFENSE_SKILL_RATING_SHORT"]      = "DEF",
    ["ITEM_MOD_RESILIENCE_RATING_SHORT"]         = "RESIL",
    ["ITEM_MOD_ARMOR_PENETRATION_RATING_SHORT"]  = "ARP",
    ["ITEM_MOD_BLOCK_RATING_SHORT"]              = "BLOCK_RATING",
    ["ITEM_MOD_BLOCK_VALUE_SHORT"]               = "BLOCK_VALUE",
    ["RESISTANCE0_NAME"]                          = "ARMOR",
    ["ARMOR"]                                     = "ARMOR",  -- some API variants might use plain "ARMOR"
    ["ITEM_MOD_SPELL_POWER_SHORT"]               = "SP",
    ["ITEM_MOD_SPELL_DAMAGE_DONE_SHORT"]         = "SP",    -- legacy TBC-converted items
    ["ITEM_MOD_SPELL_HEALING_DONE_SHORT"]        = "HEAL",  -- legacy TBC-converted items
    ["ITEM_MOD_SPELL_PENETRATION_SHORT"]         = "SPELL_PEN",
    ["ITEM_MOD_MANA_REGENERATION_SHORT"]         = "MP5",
    ["ITEM_MOD_RANGED_ATTACK_POWER_SHORT"]       = "AP",
    ["ITEM_MOD_DAMAGE_PER_SECOND_SHORT"]         = "WEAPON_DPS",
    ["ITEM_MOD_PVP_POWER_SHORT"]                 = "PVP_POWER",
    -- Ascension custom modifiers (no stock GetItemStats key; tooltip-scanned)

    -- Modern (Mainline/Retail) secondary stat ratings. These API keys never
    -- appear in GetItemStats() results on Classic-family clients (the ratings
    -- don't exist pre-Legion), so it's safe to register them unconditionally
    -- here -- they simply stay unused/empty outside of Retail gear scans.
    ["ITEM_MOD_MASTERY_RATING_SHORT"]            = "MASTERY",
    ["ITEM_MOD_VERSATILITY"]                     = "VERSATILITY",
    ["ITEM_MOD_VERSATILITY_RATING_SHORT"]        = "VERSATILITY",
    ["ITEM_MOD_CR_AVOIDANCE_SHORT"]              = "AVOIDANCE",
    ["ITEM_MOD_CR_LIFESTEAL_SHORT"]              = "LEECH",
    ["ITEM_MOD_CR_SPEED_SHORT"]                  = "SPEED",
}

-- Ascension exposes PvE Power as a plain tooltip line ("Equip: Increases
-- PvE Power by 25."), so it never appears in GetItemStats. The scan patterns
-- below handle both powers; this alias keeps any future API key supported.
CharacterGearOptimizer.ITEM_STAT_MAP["ITEM_MOD_PVE_POWER_SHORT"] = "PVE_POWER"
-- ============================================================================
-- TOOLTIP SCAN PATTERNS (for stats not returned by GetItemStats)
-- ============================================================================
CharacterGearOptimizer.TOOLTIP_PATTERNS = {
    -- Armor (some cheap items like rings only show on tooltip)
    -- match both "+180 Armor" and "180 Armor" lines
{ pattern = "%+?(%d+) Armor",                           stat = "ARMOR", bonus = false },
-- Bonus armor may appear separately or inside parentheses; include both cases
{ pattern = "%+(%d+) Bonus Armor",                      stat = "ARMOR", bonus = true },
{ pattern = "Increases.-armor.-by (%d+)",               stat = "ARMOR", bonus = true },
    { pattern = "Increases attack power by (%d+) in Cat",     stat = "FAP" },
    { pattern = "attack power by (%d+) in Cat",              stat = "FAP" },

    -- MP5
    { pattern = "Restores (%d+) mana per 5 sec",             stat = "MP5" },
    { pattern = "(%d+) mana per 5 sec",                       stat = "MP5" },
    { pattern = "%+(%d+) [Mm]ana [Pp]er 5",                  stat = "MP5" },
    { pattern = "%+(%d+) [Mm][Pp]5",                          stat = "MP5" },

    -- Healing power (separate from spell power in TBC)
    { pattern = "Increases healing done by up to (%d+)",      stat = "HEAL" },
    { pattern = "Increases healing done by spells and effects by up to (%d+)", stat = "HEAL" },
    { pattern = "%+(%d+) Healing",                             stat = "HEAL" },

    -- Spell power (WotLK merged stat; keep TBC wordings for converted items)
    { pattern = "Increases damage and healing done by magical spells and effects by up to (%d+)", stat = "SP" },
    { pattern = "Increases spell power by (%d+)",             stat = "SP" },
    { pattern = "%+(%d+) Spell Power",                        stat = "SP" },
    { pattern = "%+(%d+) Spell Damage",                       stat = "SP" },
    { pattern = "%+(%d+) Damage and Healing",                 stat = "SP" },

    -- Weapon DPS: Ascension weapon damage scales at the standard AP/14 rate.
    { pattern = "([%d%.]+) [Dd]amage per [Ss]econd",             stat = "WEAPON_DPS", maxMode = true },

    -- Attack Power (Equip: lines and Mystic Enchant rolled stats)
    { pattern = "Increases attack power by (%d+)%.",          stat = "AP" },
    { pattern = "%+(%d+) Attack Power",                       stat = "AP" },
    { pattern = "Increases ranged attack power by (%d+)",     stat = "AP" },
    { pattern = "%+(%d+) Ranged Attack Power",                stat = "AP" },

    -- Armor Penetration Rating (WotLK)
    { pattern = "Increases your armor penetration rating by (%d+)", stat = "ARP" },
    { pattern = "Increases armor penetration rating by (%d+)",      stat = "ARP" },
    { pattern = "%+(%d+) Armor Penetration Rating",                 stat = "ARP" },

    -- Block value from tooltip
    { pattern = "Increases the block value of your shield by (%d+)", stat = "BLOCK_VALUE" },
    { pattern = "%+(%d+) Block Value",                        stat = "BLOCK_VALUE" },

    -- Defense Rating (fallback if GetItemStats misses it)
    { pattern = "Increases defense rating by (%d+)",          stat = "DEF" },
    { pattern = "%+(%d+) Defense Rating",                     stat = "DEF" },

    -- Hit Rating ("Equip: Improves hit rating by X" on converted vanilla items)
    { pattern = "Improves hit rating by (%d+)",               stat = "HIT" },
    { pattern = "Increases your hit rating by (%d+)",         stat = "HIT" },
    { pattern = "%+(%d+) Hit Rating",                         stat = "HIT" },

    -- Expertise Rating ("Equip: Increases your expertise rating by X")
    { pattern = "Increases your expertise rating by (%d+)",   stat = "EXP" },
    { pattern = "Improves expertise rating by (%d+)",         stat = "EXP" },
    { pattern = "%+(%d+) Expertise Rating",                   stat = "EXP" },

    -- Spell Crit Rating (spell-only; must appear BEFORE generic crit patterns)
    { pattern = "Improves spell critical strike rating by (%d+)",       stat = "SPELLCRIT" },
    { pattern = "Increases your spell critical strike rating by (%d+)", stat = "SPELLCRIT" },
    { pattern = "%+(%d+) Spell Critical Strike Rating",                 stat = "SPELLCRIT" },

    -- Melee Crit Rating (melee-only; must appear BEFORE generic crit patterns)
    { pattern = "Improves melee critical strike rating by (%d+)",       stat = "MELEECRIT" },
    { pattern = "Increases your melee critical strike rating by (%d+)", stat = "MELEECRIT" },
    { pattern = "%+(%d+) Melee Critical Strike Rating",                 stat = "MELEECRIT" },

    -- Crit Rating (physical/melee only; fallback for Equip: effect items)
    { pattern = "Improves critical strike rating by (%d+)",   stat = "CRIT" },
    { pattern = "Increases your critical strike rating by (%d+)", stat = "CRIT" },
    { pattern = "%+(%d+) Critical Strike Rating",             stat = "CRIT" },

    -- Haste Rating (fallback)
    { pattern = "Improves haste rating by (%d+)",             stat = "HASTE" },
    { pattern = "Increases your haste rating by (%d+)",       stat = "HASTE" },
    { pattern = "%+(%d+) Haste Rating",                       stat = "HASTE" },

    -- Dodge Rating (fallback)
    { pattern = "Increases your dodge rating by (%d+)",       stat = "DODGE" },
    { pattern = "%+(%d+) Dodge Rating",                       stat = "DODGE" },

    -- Parry Rating (fallback)
    { pattern = "Increases your parry rating by (%d+)",       stat = "PARRY" },
    { pattern = "%+(%d+) Parry Rating",                       stat = "PARRY" },

    -- Spell Hit Rating (items that only give spell hit)
    { pattern = "Increases your spell hit rating by (%d+)",   stat = "SPELLHIT" },
    { pattern = "%+(%d+) Spell Hit Rating",                   stat = "SPELLHIT" },

    -- Ascension PvP Power
    { pattern = "Increases.-[Pp][Vv][Pp] [Pp]ower.-by (%d+)", stat = "PVP_POWER" },
    { pattern = "%+(%d+) [Pp][Vv][Pp] [Pp]ower",             stat = "PVP_POWER" },

    -- Ascension PvE Power (e.g. "Equip: Increases PvE Power by 25.")
    { pattern = "Increases.-[Pp][Vv][Ee] [Pp]ower.-by (%d+)", stat = "PVE_POWER" },
    { pattern = "[Pp][Vv][Ee] [Pp]ower by (%d+)", stat = "PVE_POWER" },
    { pattern = "%+(%d+) [Pp][Vv][Ee] [Pp]ower",             stat = "PVE_POWER" },

    -- Resilience Rating (fallback)
    { pattern = "Increases your resilience rating by (%d+)",  stat = "RESIL" },
    { pattern = "%+(%d+) Resilience Rating",                  stat = "RESIL" },

    -- Weapon Skill â†’ _WSKILL (converted to EXP after scan; maxMode keeps
    -- only the highest value since you only benefit from one weapon type)
    { pattern = "%+(%d+) Sword Skill",          stat = "_WSKILL", maxMode = true },
    { pattern = "%+(%d+) Axe Skill",            stat = "_WSKILL", maxMode = true },
    { pattern = "%+(%d+) Mace Skill",           stat = "_WSKILL", maxMode = true },
    { pattern = "%+(%d+) Dagger Skill",         stat = "_WSKILL", maxMode = true },
    { pattern = "%+(%d+) Fist Weapon Skill",    stat = "_WSKILL", maxMode = true },
    { pattern = "%+(%d+) Gun Skill",            stat = "_WSKILL", maxMode = true },
    { pattern = "%+(%d+) Bow Skill",            stat = "_WSKILL", maxMode = true },
    { pattern = "%+(%d+) Crossbow Skill",       stat = "_WSKILL", maxMode = true },

    -- Sockets (fixed value = 1)
    { pattern = "Meta Socket",   stat = "META_SOCKET",   value = 1 },
    { pattern = "Red Socket",    stat = "RED_SOCKET",    value = 1 },
    { pattern = "Yellow Socket", stat = "YELLOW_SOCKET", value = 1 },
    { pattern = "Blue Socket",   stat = "BLUE_SOCKET",   value = 1 },
}

-- ============================================================================
-- GEM SCAN PATTERNS (for scoring individual gems)
-- ============================================================================
CharacterGearOptimizer.GEM_PATTERNS = {
    { pattern = "%+(%d+) Strength",                weight = "STR",   label = "Str" },
    { pattern = "%+(%d+) Agility",                 weight = "AGI",   label = "Agi" },
    { pattern = "%+(%d+) Stamina",                 weight = "STA",   label = "Sta" },
    { pattern = "%+(%d+) Intellect",               weight = "INT",   label = "Int" },
    { pattern = "%+(%d+) Spirit",                  weight = "SPI",   label = "Spi" },
    { pattern = "%+(%d+) Attack Power",            weight = "AP",    label = "AP" },
    { pattern = "%+(%d+) Spell Power",             weight = "SP",    label = "SP" },
    { pattern = "%+(%d+) Spell Damage",            weight = "SP",    label = "SP" },
    { pattern = "%+(%d+) Healing",                 weight = "HEAL",  label = "Heal" },
    { pattern = "%+(%d+) Hit Rating",              weight = "HIT",   label = "Hit" },
    { pattern = "%+(%d+) Spell Hit Rating",        weight = "SPELLHIT", label = "Spell Hit" },
    { pattern = "%+(%d+) Spell Critical Strike Rating", weight = "SPELLCRIT", label = "Spell Crit" },
    { pattern = "%+(%d+) Melee Critical Strike Rating", weight = "MELEECRIT", label = "Melee Crit" },
    { pattern = "%+(%d+) Critical Strike Rating",  weight = "CRIT",  label = "Crit" },
    { pattern = "%+(%d+) Haste Rating",            weight = "HASTE", label = "Haste" },
    { pattern = "%+(%d+) Expertise Rating",        weight = "EXP",   label = "Exp" },
    { pattern = "%+(%d+) Dodge Rating",            weight = "DODGE", label = "Dodge" },
    { pattern = "%+(%d+) Parry Rating",            weight = "PARRY", label = "Parry" },
    { pattern = "%+(%d+) Defense Rating",          weight = "DEF",   label = "Def" },
    { pattern = "%+(%d+) Resilience Rating",       weight = "RESIL", label = "Resil" },
    { pattern = "%+(%d+) Armor Penetration Rating", weight = "ARP",  label = "ArP" },
    { pattern = "%+(%d+) Block Rating",            weight = "BLOCK_RATING", label = "Block" },
    { pattern = "%+(%d+) Block Value",             weight = "BLOCK_VALUE",  label = "BV" },
    { pattern = "(%d+) mana per 5 sec",            weight = "MP5",   label = "MP5" },
    { pattern = "%+(%d+) [Pp][Vv][Pp] [Pp]ower",   weight = "PVP_POWER", label = "PvP Power" },
    { pattern = "%+(%d+) [Pp][Vv][Ee] [Pp]ower",   weight = "PVE_POWER", label = "PvE Power" },
}

-- ============================================================================
-- EQUIP SLOT MAP (equipLoc -> inventory slot ID)
-- ============================================================================
CharacterGearOptimizer.SLOT_MAP = {
    INVTYPE_HEAD            = 1,
    INVTYPE_NECK            = 2,
    INVTYPE_SHOULDER        = 3,
    INVTYPE_BODY            = 4,
    INVTYPE_CHEST           = 5,
    INVTYPE_ROBE            = 5,
    INVTYPE_WAIST           = 6,
    INVTYPE_LEGS            = 7,
    INVTYPE_FEET            = 8,
    INVTYPE_WRIST           = 9,
    INVTYPE_HAND            = 10,
    INVTYPE_FINGER          = 11,
    INVTYPE_TRINKET         = 13,
    INVTYPE_CLOAK           = 15,
    INVTYPE_2HWEAPON        = 16,
    INVTYPE_WEAPON          = 16,
    INVTYPE_WEAPONMAINHAND  = 16,
    INVTYPE_WEAPONOFFHAND   = 17,
    INVTYPE_HOLDABLE        = 17,
    INVTYPE_SHIELD          = 17,
    INVTYPE_RANGED          = 18,
    INVTYPE_RANGEDRIGHT     = 18,
    INVTYPE_THROWN           = 18,
    INVTYPE_RELIC           = 18,
}

-- ============================================================================
-- TALENT TREE -> SPEC INDEX MAP (TBC Classic talent tree ordering)
-- ============================================================================
CharacterGearOptimizer.TALENT_TREE_MAP = {
    DEATHKNIGHT = { "Blood", "Frost",        "Unholy" },
    WARRIOR = { "Arms",     "Fury",          "Protection" },
    PALADIN = { "Holy",     "Protection",    "Retribution" },
    HUNTER  = { "Beast Mastery", "Marksmanship", "Survival" },
    ROGUE   = { "Assassination", "Combat",   "Subtlety" },
    PRIEST  = { "Discipline", "Holy",        "Shadow" },
    SHAMAN  = { "Elemental", "Enhancement",  "Restoration" },
    MAGE    = { "Arcane",    "Fire",         "Frost" },
    WARLOCK = { "Affliction", "Demonology",  "Destruction" },
    DRUID   = { "Balance",   "Feral Cat",    "Restoration" },
}

-- ============================================================================
-- CLASS COLORS (WoW class color hex codes)
-- ============================================================================
CharacterGearOptimizer.CLASS_COLORS = {
    DEATHKNIGHT = "C41F3B",
    WARRIOR = "C79C6E",
    PALADIN = "F58CBA",
    HUNTER  = "ABD473",
    ROGUE   = "FFF569",
    PRIEST  = "FFFFFF",
    SHAMAN  = "0070DE",
    MAGE    = "69CCF0",
    WARLOCK = "9482C9",
    DRUID   = "FF7D0A",
    HERO    = "A335EE",
}

-- ============================================================================
-- ARMOR PROFICIENCY (highest wearable armor type per class)
-- Only true body-armor subtypes are checked: Plate, Mail, Leather, Cloth.
-- Cloaks (always "Cloth"), Shields, Relics, Jewelry, and Weapons are exempt.
-- ============================================================================
CharacterGearOptimizer.CLASS_ARMOR_PROFICIENCY = {
    DEATHKNIGHT = { Plate = true, Mail = true, Leather = true, Cloth = true },
    WARRIOR = { Plate = true, Mail = true, Leather = true, Cloth = true },
    PALADIN = { Plate = true, Mail = true, Leather = true, Cloth = true },
    HUNTER  = { Mail = true, Leather = true, Cloth = true },
    SHAMAN  = { Mail = true, Leather = true, Cloth = true },
    ROGUE   = { Leather = true, Cloth = true },
    DRUID   = { Leather = true, Cloth = true },
    PRIEST  = { Cloth = true },
    MAGE    = { Cloth = true },
    WARLOCK = { Cloth = true },
    HERO    = { Plate = true, Mail = true, Leather = true, Cloth = true },
}

-- Equip locations that are true body-armor (subject to proficiency check)
CharacterGearOptimizer.ARMOR_EQUIP_LOCS = {
    INVTYPE_HEAD     = true,
    INVTYPE_SHOULDER = true,
    INVTYPE_CHEST    = true,
    INVTYPE_ROBE     = true,
    INVTYPE_WAIST    = true,
    INVTYPE_LEGS     = true,
    INVTYPE_FEET     = true,
    INVTYPE_WRIST    = true,
    INVTYPE_HAND     = true,
}

-- ============================================================================
-- WEAPON PROFICIENCY (allowed weapon subtypes per class, TBC Classic)
-- Keys must match the itemSubType strings returned by GetItemInfo().
-- ============================================================================
CharacterGearOptimizer.CLASS_WEAPON_PROFICIENCY = {
    DEATHKNIGHT = {
        ["One-Handed Swords"] = true, ["Two-Handed Swords"] = true,
        ["One-Handed Axes"]   = true, ["Two-Handed Axes"]   = true,
        ["One-Handed Maces"]  = true, ["Two-Handed Maces"]  = true,
        ["Polearms"] = true,
    },
    WARRIOR = {
        ["One-Handed Swords"] = true, ["Two-Handed Swords"] = true,
        ["One-Handed Axes"]   = true, ["Two-Handed Axes"]   = true,
        ["One-Handed Maces"]  = true, ["Two-Handed Maces"]  = true,
        ["Daggers"] = true, ["Fist Weapons"] = true,
        ["Polearms"] = true, ["Staves"] = true,
        ["Bows"] = true, ["Crossbows"] = true, ["Guns"] = true,
        ["Thrown"] = true,
    },
    PALADIN = {
        ["One-Handed Swords"] = true, ["Two-Handed Swords"] = true,
        ["One-Handed Axes"]   = true, ["Two-Handed Axes"]   = true,
        ["One-Handed Maces"]  = true, ["Two-Handed Maces"]  = true,
        ["Polearms"] = true,
    },
    HUNTER = {
        ["One-Handed Swords"] = true, ["Two-Handed Swords"] = true,
        ["One-Handed Axes"]   = true, ["Two-Handed Axes"]   = true,
        ["Daggers"] = true, ["Fist Weapons"] = true,
        ["Polearms"] = true, ["Staves"] = true,
        ["Bows"] = true, ["Crossbows"] = true, ["Guns"] = true,
        ["Thrown"] = true,
    },
    ROGUE = {
        ["One-Handed Swords"] = true, ["One-Handed Maces"] = true,
        ["Daggers"] = true, ["Fist Weapons"] = true,
        ["Bows"] = true, ["Crossbows"] = true, ["Guns"] = true,
        ["Thrown"] = true,
    },
    PRIEST = {
        ["One-Handed Maces"] = true, ["Daggers"] = true,
        ["Staves"] = true, ["Wands"] = true,
    },
    SHAMAN = {
        ["One-Handed Axes"]  = true, ["Two-Handed Axes"]  = true,
        ["One-Handed Maces"] = true, ["Two-Handed Maces"] = true,
        ["Daggers"] = true, ["Fist Weapons"] = true,
        ["Staves"] = true,
    },
    MAGE = {
        ["One-Handed Swords"] = true, ["Daggers"] = true,
        ["Staves"] = true, ["Wands"] = true,
    },
    WARLOCK = {
        ["One-Handed Swords"] = true, ["Daggers"] = true,
        ["Staves"] = true, ["Wands"] = true,
    },
    DRUID = {
        ["One-Handed Maces"] = true, ["Two-Handed Maces"] = true,
        ["Daggers"] = true, ["Fist Weapons"] = true,
        ["Polearms"] = true, ["Staves"] = true,
    },
}

-- Classes that can equip shields
CharacterGearOptimizer.CLASS_SHIELD_PROFICIENCY = {
    WARRIOR = true,
    PALADIN = true,
    SHAMAN  = true,
    HERO    = true,
}

-- Relic subtypes each class can equip
CharacterGearOptimizer.CLASS_RELIC_PROFICIENCY = {
    PALADIN     = { Librams = true },
    DRUID       = { Idols   = true },
    SHAMAN      = { Totems  = true },
    DEATHKNIGHT = { Sigils  = true },
}

-- ============================================================================
-- ROLE DEFINITIONS
-- ============================================================================
-- "melee_dps"   = physical melee (hit/exp/crit/haste caps)
-- "ranged_dps"  = physical ranged (hit/crit)
-- "caster_dps"  = spell DPS (spell hit cap)
-- "healer"      = healing (mp5/int/haste)
-- "tank"        = plate tank (defense/uncrushable/avoidance/EHP)
-- "tank_druid"  = bear tank (leather/cloth armor, agility, stamina)
-- "tank_barrier"= Mana-forged Barrier tank (intellect / mana / absorption)

-- ============================================================================
-- WotLK RATING CONSTANTS (Level 80)
-- ============================================================================
CharacterGearOptimizer.RATING = {
    HIT_PER_PCT           = 8.0,     -- Ascension universal hit: 8 rating per 1%
    SPELL_HIT_PER_PCT     = 8.0,     -- Ascension uses the same rating for all damage
    CRIT_PER_PCT          = 45.91,   -- crit rating per 1% crit
    HASTE_PER_PCT         = 32.79,   -- haste rating per 1%
    EXPERTISE_PER_SKILL   = 8.1974,  -- expertise rating per 1 expertise
    DEFENSE_PER_SKILL     = 4.918,   -- defense rating per 1 defense skill
    DODGE_PER_RATING      = 39.35,   -- dodge rating per 1% dodge (pre-DR)
    PARRY_PER_RATING      = 49.18,   -- parry rating per 1% parry (pre-DR)
    BLOCK_PER_RATING      = 16.39,   -- block rating per 1% block
    RESIL_PER_PCT         = 81.97,   -- resilience rating per 1% crit reduction
    AVOID_PER_DEF_SKILL   = 0.16,   -- total avoidance % per defense skill (0.04 Ã— 4)
    BASE_MISS_PCT         = 5.0,    -- base miss chance vs +3 boss

    -- Caps
    MELEE_HIT_CAP_PCT     = 14.0,    -- Ascension static PvE hit cap
    SPELL_HIT_CAP_PCT     = 14.0,    -- Ascension static PvE hit cap
    EXPERTISE_SOFT_CAP    = 26,      -- 6.5% dodge reduction
    DEFENSE_CAP           = 540,     -- uncrittable vs +3 boss (140 over 400 base)
    UNCRUSHABLE_PCT       = 102.4,   -- miss+dodge+parry+block (mostly moot in WotLK)
    BOSS_CRIT_PCT         = 5.6,     -- boss crit chance vs player

    -- Armor DR cap
    ARMOR_DR_CAP_PCT      = 75,       -- maximum armor damage reduction %
    ARMOR_CAP_VALUE       = 49905,    -- armor needed for 75% DR vs lvl 83

    -- PvP caps (vs same-level player, not +3 boss)
    PVP_MELEE_HIT_CAP_PCT  = 5.0,     -- vs same-level player
    PVP_SPELL_HIT_CAP_PCT  = 3.0,     -- vs same-level player
    PVP_EXPERTISE_SOFT_CAP = 0,       -- not needed vs players (can't dodge from behind)
    PVP_ARMOR_CONSTANT     = 15232.5, -- armor constant for lvl 80 attacker
    PVP_ARMOR_CAP_VALUE    = 45698,   -- armor needed for 75% DR vs lvl 80

    -- PvP Resilience cap
    RESIL_CRIT_IMMUNE_PCT = 5.0,      -- crit reduction needed for PvP crit immune
    RESIL_CAP_RATING      = 410,      -- resilience rating for 5% at lvl 80

    -- Haste GCD cap
    HASTE_GCD_CAP_PCT     = 50.0,     -- haste % for 1.0s GCD floor
    HASTE_SPELL_CAP_RATING = 1640,    -- spell haste rating for 50%
    HASTE_MELEE_CAP_RATING = 1640,    -- melee haste rating for 50%

    -- Armor formula constant for level 83 attacker (467.5*83 - 22167.5)
    ARMOR_CONSTANT        = 16635,

    -- Combat rating IDs (3.3.5)
    CR_HIT_MELEE          = 6,
    CR_HIT_SPELL          = 8,
    CR_CRIT_MELEE         = 9,
    CR_CRIT_SPELL         = 11,
    CR_HASTE_MELEE        = 18,
    CR_HASTE_SPELL        = 20,
    CR_EXPERTISE          = 24,
    CR_ARMOR_PEN          = 25,
    CR_DEFENSE            = 2,
    CR_DODGE              = 3,
    CR_PARRY              = 4,
    CR_BLOCK              = 5,
    CR_RESILIENCE         = 15,   -- CR_CRIT_TAKEN_MELEE (resilience) in 3.3.5
}

-- ============================================================================
-- SPEC WEIGHT TABLES
-- Organized by class -> spec index -> { name, role, weights, gemValue, metaValue }
-- gemValue  = weighted score per colored socket (best available gem)
-- metaValue = weighted score per meta socket
-- ============================================================================

CharacterGearOptimizer.CLASS_SPECS = {

    -- ========================================================================
    -- DEATH KNIGHT (WotLK)
    -- ========================================================================
    DEATHKNIGHT = {
        [1] = { -- Blood (tank-oriented default)
            name = "Blood",
            role = "tank",
            weights = {
                STA = 2.0, STR = 1.0, AGI = 1.0, AP = 0.3,
                DEF = 1.5, DODGE = 1.2, PARRY = 1.0, RESIL = 0.5,
                HIT = 0.6, EXP = 0.9, ARMOR = 0.08,
            },
            gemValue  = 24 * 2.0,  -- Solid Majestic Zircon (+24 STA)
            metaValue = 50,
        },
        [2] = { -- Frost
            name = "Frost",
            role = "melee_dps",
            weights = {
                STR = 2.3, AGI = 0.8, STA = 0.1, AP = 1.0,
                HIT = 2.0, EXP = 2.2, CRIT = 1.5, MELEECRIT = 1.5, HASTE = 1.3,
                ARP = 1.2,
            },
            gemValue  = 20 * 2.3,  -- Bold Cardinal Ruby (+20 STR)
            metaValue = 60,
        },
        [3] = { -- Unholy
            name = "Unholy",
            role = "melee_dps",
            weights = {
                STR = 2.3, AGI = 0.8, STA = 0.1, AP = 1.0,
                HIT = 2.0, EXP = 2.0, CRIT = 1.6, MELEECRIT = 1.6, HASTE = 1.4,
                ARP = 1.0,
            },
            gemValue  = 20 * 2.3,
            metaValue = 60,
        },
    },

    -- ========================================================================
    -- WARRIOR
    -- ========================================================================
    WARRIOR = {
        [1] = { -- Arms
            name = "Arms",
            role = "melee_dps",
            weights = {
                STR = 2.21, AGI = 1.6, STA = 0.1, AP = 1.0,
                HIT = 2.0, EXP = 2.5, CRIT = 1.8, MELEECRIT = 1.8, HASTE = 1.0,
                ARP = 0.6,
            },
            gemValue  = 8 * 2.21,  -- Bold Living Ruby (+8 STR)
            metaValue = 30,
        },
        [2] = { -- Fury
            name = "Fury",
            role = "melee_dps",
            weights = {
                STR = 2.21, AGI = 1.4, STA = 0.1, AP = 1.0,
                HIT = 2.2, EXP = 2.5, CRIT = 1.6, MELEECRIT = 1.6, HASTE = 1.4,
                ARP = 0.5,
            },
            gemValue  = 8 * 2.21,
            metaValue = 30,
        },
        [3] = { -- Protection
            name = "Protection",
            role = "tank",
            weights = {
                STA = 2.0, STR = 0.5, AGI = 1.2, AP = 0.2,
                DEF = 1.5, DODGE = 1.1, PARRY = 1.0, RESIL = 0.5,
                BLOCK_RATING = 1.8, BLOCK_VALUE = 0.5,
                HIT = 0.5, EXP = 0.8, ARMOR = 0.05,
            },
            gemValue  = 12 * 2.0,  -- Solid Star of Elune (+12 STA)
            metaValue = 28,
        },
    },

    -- ========================================================================
    -- PALADIN
    -- ========================================================================
    PALADIN = {
        [1] = { -- Holy
            name = "Holy",
            role = "healer",
            weights = {
                INT = 1.0, SPI = 0.5, SP = 0.9, HEAL = 1.0,
                SPELLCRIT = 0.7, HASTE = 1.3, MP5 = 1.5, STA = 0.05,
            },
            gemValue  = 18 * 1.0,  -- Teardrop Living Ruby (+18 Healing)
            metaValue = 24,
        },
        [2] = { -- Protection
            name = "Protection",
            role = "tank",
            weights = {
                STA = 1.0, INT = 0.1, STR = 0.023, AGI = 0.64,
                DEF = 0.845, DODGE = 0.66, PARRY = 0.53, RESIL = 0.32,
                BLOCK_RATING = 1.585, BLOCK_VALUE = 0.046,
                HIT = 0.1, EXP = 0.2, SP = 0.9,
                ARMOR = 0.05, MELEECRIT = 0.45, SPELLCRIT = 0.45,
            },
            gemValue  = 12 * 1.0,
            metaValue = 18,
        },
        [3] = { -- Retribution
            name = "Retribution",
            role = "melee_dps",
            weights = {
                STR = 2.21, AGI = 0.64, STA = 0.1, AP = 1.0,
                HIT = 1.8, EXP = 2.0, CRIT = 1.5, MELEECRIT = 1.5, HASTE = 1.2,
                SP = 0.3,
            },
            gemValue  = 8 * 2.21,
            metaValue = 30,
        },
    },

    -- ========================================================================
    -- HUNTER
    -- ========================================================================
    HUNTER = {
        [1] = { -- Beast Mastery
            name = "Beast Mastery",
            role = "ranged_dps",
            weights = {
                AGI = 2.8, AP = 1.0, INT = 0.4, STA = 0.05,
                HIT = 2.0, CRIT = 1.6, MELEECRIT = 1.6, HASTE = 1.5, ARP = 0.3,
            },
            gemValue  = 8 * 2.8,
            metaValue = 34,
        },
        [2] = { -- Marksmanship
            name = "Marksmanship",
            role = "ranged_dps",
            weights = {
                AGI = 2.5, AP = 1.0, INT = 0.5, STA = 0.05,
                HIT = 2.0, CRIT = 1.8, MELEECRIT = 1.8, HASTE = 1.2, ARP = 0.4,
            },
            gemValue  = 8 * 2.5,
            metaValue = 32,
        },
        [3] = { -- Survival
            name = "Survival",
            role = "ranged_dps",
            weights = {
                AGI = 3.0, AP = 1.0, INT = 0.6, STA = 0.05,
                HIT = 2.0, CRIT = 1.5, MELEECRIT = 1.5, HASTE = 1.0, ARP = 0.3,
            },
            gemValue  = 8 * 3.0,
            metaValue = 36,
        },
    },

    -- ========================================================================
    -- ROGUE
    -- ========================================================================
    ROGUE = {
        [1] = { -- Assassination
            name = "Assassination",
            role = "melee_dps",
            weights = {
                AGI = 2.2, STR = 1.1, AP = 1.0, STA = 0.05,
                HIT = 2.2, EXP = 2.3, CRIT = 2.0, MELEECRIT = 2.0, HASTE = 1.0,
            },
            gemValue  = 8 * 2.2,
            metaValue = 28,
        },
        [2] = { -- Combat
            name = "Combat",
            role = "melee_dps",
            weights = {
                AGI = 2.5, STR = 1.1, AP = 1.0, STA = 0.05,
                HIT = 2.5, EXP = 2.5, CRIT = 1.8, MELEECRIT = 1.8, HASTE = 1.5,
                ARP = 0.6,
            },
            gemValue  = 8 * 2.5,
            metaValue = 32,
        },
        [3] = { -- Subtlety
            name = "Subtlety",
            role = "melee_dps",
            weights = {
                AGI = 2.4, STR = 1.1, AP = 1.0, STA = 0.05,
                HIT = 2.0, EXP = 2.0, CRIT = 1.5, MELEECRIT = 1.5, HASTE = 0.8,
                ARP = 0.3,
            },
            gemValue  = 8 * 2.4,
            metaValue = 30,
        },
    },

    -- ========================================================================
    -- PRIEST
    -- ========================================================================
    PRIEST = {
        [1] = { -- Discipline
            name = "Discipline",
            role = "healer",
            weights = {
                INT = 1.0, SPI = 0.6, SP = 0.8, HEAL = 1.0,
                SPELLCRIT = 0.8, HASTE = 1.2, MP5 = 1.0, STA = 0.05,
            },
            gemValue  = 18 * 1.0,
            metaValue = 24,
        },
        [2] = { -- Holy
            name = "Holy",
            role = "healer",
            weights = {
                INT = 0.875, SPI = 0.875, SP = 0.9, HEAL = 1.0,
                SPELLCRIT = 0.5, HASTE = 1.5, MP5 = 1.25, STA = 0.05,
            },
            gemValue  = 18 * 1.0,
            metaValue = 37.5,
        },
        [3] = { -- Shadow
            name = "Shadow",
            role = "caster_dps",
            weights = {
                SP = 1.0, INT = 0.8, SPI = 0.5, STA = 0.05,
                HIT = 1.5, SPELLCRIT = 0.7, HASTE = 1.2,
            },
            gemValue  = 9 * 1.0,
            metaValue = 14,
        },
    },

    -- ========================================================================
    -- SHAMAN
    -- ========================================================================
    SHAMAN = {
        [1] = { -- Elemental
            name = "Elemental",
            role = "caster_dps",
            weights = {
                SP = 1.0, INT = 0.8, STA = 0.05,
                HIT = 1.5, SPELLCRIT = 0.8, HASTE = 1.3,
            },
            gemValue  = 9 * 1.0,
            metaValue = 14,
        },
        [2] = { -- Enhancement
            name = "Enhancement",
            role = "melee_dps",
            weights = {
                STR = 1.1, AGI = 1.6, AP = 1.0, STA = 0.1,
                HIT = 1.8, EXP = 2.0, CRIT = 1.5, MELEECRIT = 1.5, HASTE = 1.2,
            },
            gemValue  = 8 * 1.6,
            metaValue = 20,
        },
        [3] = { -- Restoration
            name = "Restoration",
            role = "healer",
            weights = {
                INT = 0.9, SPI = 0.3, SP = 0.6, HEAL = 1.0,
                SPELLCRIT = 0.5, HASTE = 1.0, MP5 = 1.5, STA = 0.05,
            },
            gemValue  = 18 * 1.0,
            metaValue = 24,
        },
    },

    -- ========================================================================
    -- MAGE
    -- ========================================================================
    MAGE = {
        [1] = { -- Arcane
            name = "Arcane",
            role = "caster_dps",
            weights = {
                SP = 1.0, INT = 1.0, SPI = 0.3, STA = 0.05,
                HIT = 1.2, SPELLCRIT = 0.5, HASTE = 1.5,
            },
            gemValue  = 9 * 1.0,
            metaValue = 14,
        },
        [2] = { -- Fire
            name = "Fire",
            role = "caster_dps",
            weights = {
                SP = 1.0, INT = 0.7, STA = 0.05,
                HIT = 1.5, SPELLCRIT = 0.9, HASTE = 1.3,
            },
            gemValue  = 9 * 1.0,
            metaValue = 14,
        },
        [3] = { -- Frost
            name = "Frost",
            role = "caster_dps",
            weights = {
                SP = 1.0, INT = 0.7, SPI = 0.1, STA = 0.05,
                HIT = 1.3, SPELLCRIT = 0.7, HASTE = 1.0,
            },
            gemValue  = 9 * 1.0,
            metaValue = 14,
        },
    },

    -- ========================================================================
    -- WARLOCK
    -- ========================================================================
    WARLOCK = {
        [1] = { -- Affliction
            name = "Affliction",
            role = "caster_dps",
            weights = {
                SP = 1.0, INT = 0.6, SPI = 0.3, STA = 0.2,
                HIT = 1.5, SPELLCRIT = 0.5, HASTE = 1.2,
            },
            gemValue  = 9 * 1.0,
            metaValue = 14,
        },
        [2] = { -- Demonology
            name = "Demonology",
            role = "caster_dps",
            weights = {
                SP = 1.0, INT = 0.7, STA = 0.3,
                HIT = 1.5, SPELLCRIT = 0.6, HASTE = 1.2,
            },
            gemValue  = 9 * 1.0,
            metaValue = 14,
        },
        [3] = { -- Destruction
            name = "Destruction",
            role = "caster_dps",
            weights = {
                SP = 1.0, INT = 0.6, STA = 0.2,
                HIT = 1.5, SPELLCRIT = 0.8, HASTE = 1.3,
            },
            gemValue  = 9 * 1.0,
            metaValue = 14,
        },
    },

    -- ========================================================================
    -- DRUID
    -- ========================================================================
    DRUID = {
        [1] = { -- Balance
            name = "Balance",
            role = "caster_dps",
            weights = {
                SP = 1.0, INT = 0.8, SPI = 0.4, STA = 0.05,
                HIT = 1.5, SPELLCRIT = 0.8, HASTE = 1.3,
            },
            gemValue  = 9 * 1.0,
            metaValue = 14,
        },
        [2] = { -- Feral Cat (default for Feral tree; user can switch to Bear)
            name = "Feral Cat",
            role = "melee_dps",
            weights = {
                AP = 1.0, FAP = 1.0, STR = 2.266, AGI = 3.0,
                HIT = 2.9, EXP = 2.9, CRIT = 1.9, MELEECRIT = 1.9, HASTE = 1.1,
                ARP = 0.43, STA = 0.05,
            },
            gemValue  = 8 * 3.0,  -- Delicate Living Ruby (+8 AGI)
            metaValue = 34,
        },
        -- Feral Bear is stored as index 4 (virtual spec, user-toggled)
        [4] = {
            name = "Feral Bear",
            role = "tank_druid",
            weights = {
                STA = 2.0, AGI = 1.5, STR = 0.3, AP = 0.1,
                DEF = 1.0, DODGE = 1.5, RESIL = 0.5,
                ARMOR = 0.05, HIT = 0.3, EXP = 0.5,
            },
            gemValue  = 12 * 2.0,
            metaValue = 28,
            -- Bear form multipliers
            bearArmorMultiplier   = 5.5,  -- Dire Bear 5x * Thick Hide 1.1x
            bearStaminaMultiplier = 1.5,  -- 1.25 Bear * 1.2 HotW
            agilityToArmor        = 2,
            agilityToDodge        = 0.053,
        },
        [3] = { -- Restoration
            name = "Restoration",
            role = "healer",
            weights = {
                INT = 0.9, SPI = 0.8, SP = 0.5, HEAL = 1.0,
                SPELLCRIT = 0.4, HASTE = 1.0, MP5 = 1.2, STA = 0.05,
            },
            gemValue  = 18 * 1.0,
            metaValue = 24,
        },
    },
}

-- ============================================================================
-- WotLK STAT MERGE NORMALIZATION
-- WotLK items carry unified Hit/Crit ratings and merged Spell Power, so make
-- sure every default profile values the merged stats at least as much as the
-- old TBC school-specific ones (SPELLHIT->HIT, SPELLCRIT/MELEECRIT->CRIT,
-- HEAL->SP). Keeps the TBC keys too, in case converted items still show them.
-- ============================================================================
-- Ascension Wildcard HERO profiles. DPS paths occupy the first three slots;
-- tank paths follow so the same dropdown can pick Barrier / Bear / generic
-- tanks. Healer paths come last: Attack Power Healer derives weights from
-- live stats, Spell Power Healer uses static caster weights.
-- Intelligence DPS (Path of Intelligence) is a static-weight caster DPS
-- profile picked from the dropdown; it is not part of path auto-detection.
CharacterGearOptimizer.CLASS_SPECS.HERO = {
    [1] = { name = "Strength DPS", role = "melee_dps", path = "strength", weights = {} },
    [2] = { name = "Agility DPS",  role = "melee_dps", path = "agility",  weights = {} },
    [3] = { name = "Duality DPS",  role = "melee_dps", path = "duality",  weights = {} },
    [4] = {
        name = "Barrier Tank",
        role = "tank_barrier",
        path = "barrier",
        weights = {
            INT = 3.5, SP = 1.4, STA = 0.9, SPI = 0.35,
            HIT = 1.3, SPELLHIT = 1.3, HASTE = 0.35, CRIT = 0.2,
            ARMOR = 0.03, DEF = 0.15,
        },
        gemValue = 20 * 3.5,
        metaValue = 40,
    },
    [5] = {
        name = "Bear Tank",
        role = "tank_druid",
        path = "bear",
        preferredArmor = { Leather = true, Cloth = true },
        weights = {
            STA = 2.2, AGI = 2.0, STR = 0.4, AP = 0.15, FAP = 0.15,
            ARMOR = 0.12, DEF = 0.9, DODGE = 1.1, RESIL = 0.4,
            HIT = 0.7, EXP = 0.7,
        },
        gemValue = 24 * 2.2,
        metaValue = 36,
        bearArmorMultiplier   = 5.5,
        bearStaminaMultiplier = 1.5,
        agilityToArmor        = 2,
        agilityToDodge        = 0.053,
    },
    [6] = {
        name = "Strength Tank",
        role = "tank",
        path = "tank_strength",
        weights = {
            STA = 2.5, STR = 1.3, AP = 0.35, AGI = 0.9,
            DEF = 2.0, DODGE = 1.15, PARRY = 1.05, RESIL = 0.45,
            ARMOR = 0.08, BLOCK_RATING = 1.45, BLOCK_VALUE = 0.65,
            HIT = 1.85, EXP = 1.85,
        },
        gemValue = 24 * 2.5,
        metaValue = 36,
    },
    [7] = {
        name = "Spell Power Tank",
        role = "tank",
        path = "tank_spell",
        weights = {
            STA = 2.5, SP = 1.5, INT = 0.7, STR = 0.35,
            DEF = 2.0, DODGE = 1.05, PARRY = 0.95, RESIL = 0.45,
            ARMOR = 0.08, BLOCK_RATING = 1.25, BLOCK_VALUE = 0.5,
            HIT = 1.85, SPELLHIT = 1.85, EXP = 1.6,
        },
        gemValue = 24 * 2.5,
        metaValue = 36,
    },
    [8] = {
        name = "Attack Power Healer",
        role = "healer",
        path = "healer_ap",
        weights = {},
    },
    [9] = {
        name = "Spell Power Healer",
        role = "healer",
        path = "healer_sp",
        weights = {
            HEAL = 1.0, SP = 1.0, INT = 0.8, SPI = 0.6,
            SPELLCRIT = 0.45, HASTE = 0.55, MP5 = 0.9, STA = 0.3,
        },
        gemValue  = 18 * 1.0,  -- Teardrop Living Ruby (+18 Healing)
        metaValue = 24,
    },
    [10] = {
        -- Path of Intelligence: item/effect Spell Power is doubled and the
        -- path grants bonus Intellect/Spirit. User ratios: SP 2.0, INT 1.0,
        -- AP 1.0 (= 1 AP per point of base, pre-doubling Spell Power).
        name = "Intelligence DPS",
        role = "caster_dps",
        path = "intellect_dps",
        weights = {
            SP = 2.0, INT = 1.0, AP = 1.0, FAP = 1.0,
            SPI = 0.4, STA = 0.3,
            HIT = 1.5, CRIT = 1.0, HASTE = 1.2,
        },
        gemValue  = 9 * 2.0,   -- Runed Living Ruby (+9 SP, doubled by the path)
        metaValue = 28,
    },
}
do
    for _, specs in pairs(CharacterGearOptimizer.CLASS_SPECS) do
        for _, spec in pairs(specs) do
            local w = spec.weights
            if w then
                w.HIT  = math.max(w.HIT or 0, w.SPELLHIT or 0)
                w.CRIT = math.max(w.CRIT or 0, w.SPELLCRIT or 0, w.MELEECRIT or 0)
                w.SP   = math.max(w.SP or 0, w.HEAL or 0)
            end
        end
    end
end

-- ============================================================================
-- MAINLINE (RETAIL) SECONDARY STAT OVERRIDE
-- CLASS_SPECS above is WotLK-indexed and has no notion of Mastery,
-- Versatility, Avoidance, Leech, or Speed -- ratings that don't exist
-- pre-Legion. On a Mainline client, DetectSpec() still indexes CLASS_SPECS
-- by GetSpecialization() (1-4), so every entry keeps its class/role/name and
-- primary-stat weights (STR/AGI/INT/AP/SP/etc. already fit Retail fine); we
-- only need to layer in generic, role-based secondary-stat weights here and
-- zero out ratings that were removed from the game (Expertise/Defense/
-- Resilience/Block). These are intentionally generic fallbacks (not per-spec
-- sims) since exact Retail spec weighting is outside this addon's scope.
if CharacterGearOptimizer.isMainline then
    local MAINLINE_ROLE_SECONDARY = {
        tank      = { MASTERY = 1.2, VERSATILITY = 1.1, AVOIDANCE = 1.4, HASTE = 0.8, CRIT = 0.6, LEECH = 0.7, SPEED = 0.3 },
        healer    = { MASTERY = 1.2, VERSATILITY = 1.0, HASTE = 1.3, CRIT = 0.9, LEECH = 0.2, SPEED = 0.3 },
        melee_dps = { MASTERY = 1.3, VERSATILITY = 1.0, HASTE = 1.2, CRIT = 1.2, LEECH = 0.3, SPEED = 0.3 },
        ranged_dps= { MASTERY = 1.3, VERSATILITY = 1.0, HASTE = 1.2, CRIT = 1.2, LEECH = 0.3, SPEED = 0.3 },
        caster_dps= { MASTERY = 1.3, VERSATILITY = 1.0, HASTE = 1.2, CRIT = 1.2, LEECH = 0.3, SPEED = 0.3 },
    }
    for _, specs in pairs(CharacterGearOptimizer.CLASS_SPECS) do
        for _, spec in pairs(specs) do
            local w = spec.weights
            if w then
                -- Ratings removed from the game entirely (Legion+); zero them
                -- so leftover WotLK weights never influence Mainline scoring.
                w.EXP, w.DEF, w.RESIL, w.BLOCK_RATING, w.BLOCK_VALUE = 0, 0, 0, 0, 0
                local secondary = MAINLINE_ROLE_SECONDARY[spec.role] or MAINLINE_ROLE_SECONDARY.melee_dps
                for stat, value in pairs(secondary) do
                    if not w[stat] or w[stat] == 0 then
                        w[stat] = value
                    end
                end
            end
        end
    end
end

-- ============================================================================
-- BREAKPOINT DEFINITIONS PER ROLE
-- Each breakpoint: { stat, label, cap, ratingPer, crID, unit }
-- ============================================================================
CharacterGearOptimizer.ROLE_BREAKPOINTS = {
    melee_dps = {
        { label = "Hit",       cap = 8.0,  ratingPer = 32.79,  crID = 6,  unit = "%%" },
        { label = "Expertise", cap = 26,   ratingPer = 8.1974, crID = 24, unit = " skill", isExpertise = true },
    },
    ranged_dps = {
        { label = "Hit",       cap = 8.0,  ratingPer = 32.79,  crID = 6,  unit = "%%" },
    },
    caster_dps = {
        { label = "Spell Hit", cap = 17.0, ratingPer = 26.23,  crID = 8,  unit = "%%" },
    },
    tank = {
        { label = "Defense",   cap = 540,  ratingPer = 4.918,  crID = 2,  unit = " skill", isDefense = true },
    },
    tank_druid = {
        -- Druid tanks use SotF + defense + resilience for uncrittable (no 490 defense cap)
    },
    tank_barrier = {
        { label = "Spell Hit", cap = 17.0, ratingPer = 26.23, crID = 8, unit = "%%" },
    },
    healer = {
        -- Healers don't have hard caps, just display mana stats
    },
}
