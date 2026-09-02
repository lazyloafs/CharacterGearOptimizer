-- ============================================================================
-- CharacterGearOptimizer: Tooltip.lua
-- Stat extraction (hybrid GetItemStats + tooltip scan), weighted scoring,
-- per-stat diff comparison, gem scoring, EHP comparison for tanks
-- ============================================================================

CharacterGearOptimizer = CharacterGearOptimizer or {}

local function ToLower(text)
    return text and string.lower(text) or ""
end

local SOCKET_VALUE_MULTIPLIER = 0.5

-- ============================================================================
-- STAT EXTRACTION: GetItemStats + tooltip scan
-- Returns a table of { statKey = value, ... }
-- ============================================================================
function CharacterGearOptimizer:IsMetaGemLink(itemLink)
    if not itemLink then return false end

    local tip = self.scanTooltip
    tip:SetOwner(WorldFrame, "ANCHOR_NONE")
    tip:ClearLines()
    tip:SetHyperlink(itemLink)

    for i = 2, tip:NumLines() do
        local leftLine = _G["CGOScanTooltipTextLeft" .. i]
        if leftLine then
            local text = ToLower(leftLine:GetText())
            if text ~= "" then
                if text:find("meta gem socket", 1, true)
                    or text:find("meta socket", 1, true)
                    or text:find("requires at least", 1, true) then
                    return true
                end
            end
        end
    end

    return false
end

function CharacterGearOptimizer:GetFilledSocketCounts(itemLink)
    local colored, meta = 0, 0
    if not itemLink or not GetItemGem then return colored, meta end

    for socketIndex = 1, 4 do
        local _, gemLink = GetItemGem(itemLink, socketIndex)
        if gemLink then
            if self:IsMetaGemLink(gemLink) then
                meta = meta + 1
            else
                colored = colored + 1
            end
        end
    end

    return colored, meta
end

function CharacterGearOptimizer:ExtractItemStats(itemLink, sourceTooltip)
    if not itemLink then return {} end

    local stats = {}

    -- 1) GetItemStats API for standard stats
    local itemStats = GetItemStats(itemLink)
    if itemStats then
        for apiKey, internalKey in pairs(self.ITEM_STAT_MAP) do
            local val = itemStats[apiKey]
            if val and val > 0 then
                stats[internalKey] = (stats[internalKey] or 0) + val
            end
        end
    end

    -- 2) Tooltip scan for special stats (FAP, MP5, sockets, etc.)
    -- We'll track any armor values separately and then override the API result
    -- so that the tooltip (base + bonus) is always authoritative.
    local tip = sourceTooltip or self.scanTooltip
    if not sourceTooltip then
        tip:SetOwner(WorldFrame, "ANCHOR_NONE")
        tip:ClearLines()
        tip:SetHyperlink(itemLink)
    end

    local tooltipArmor = 0
    local tipName = tip:GetName()
    local primaryPatterns = {
        { pattern = "%+(%d+) Strength", stat = "STR" },
        { pattern = "%+(%d+) Agility", stat = "AGI" },
        { pattern = "%+(%d+) Stamina", stat = "STA" },
        { pattern = "%+(%d+) Intellect", stat = "INT" },
        { pattern = "%+(%d+) Spirit", stat = "SPI" },
    }

    for i = 2, tip:NumLines() do
        local leftLine = _G[tipName .. "TextLeft" .. i]
        if leftLine then
            local text = leftLine:GetText()
            if text then
                local scanText = text:match("^Socket Bonus:%s*(.+)$") or text
                scanText = scanText:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
                -- Rendered comparison tooltips contain Ascension's actual scaled
                -- values. Override GetItemStats primary values with those lines.
                if sourceTooltip then
                    for _, primary in ipairs(primaryPatterns) do
                        local value = tonumber(scanText:match(primary.pattern))
                        if value then stats[primary.stat] = value end
                    end
                end
                local lineMatched = {} -- prevent multiple patterns matching the same stat on one line
                for _, pat in ipairs(self.TOOLTIP_PATTERNS) do
                    if not lineMatched[pat.stat] then
                        if pat.value then
                            -- Fixed-value pattern (sockets)
                            if scanText:find(pat.pattern) then
                                stats[pat.stat] = (stats[pat.stat] or 0) + pat.value
                                lineMatched[pat.stat] = true
                            end
                        else
                            local val = scanText:match(pat.pattern)
                            if val then
                                val = tonumber(val) or 0
                                if val > 0 then
                                    if pat.stat == "ARMOR" then
                                        -- Skip false positives: "Armor Penetration" lines
                                        if not scanText:find("Penetration") then
                                            tooltipArmor = tooltipArmor + val
                                        end
                                    elseif pat.stat == "SP" and (stats["SP"] or 0) > 0 then
                                        -- skip, already captured via GetItemStats
                                    elseif pat.stat == "HEAL" then
                                        -- Healing power is separate from spell power
                                        stats["HEAL"] = (stats["HEAL"] or 0) + val
                                    else
                                        if pat.maxMode then
                                            stats[pat.stat] = math.max(stats[pat.stat] or 0, val)
                                        else
                                            stats[pat.stat] = (stats[pat.stat] or 0) + val
                                        end
                                    end
                                    lineMatched[pat.stat] = true
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    if tooltipArmor > 0 then
        stats["ARMOR"] = tooltipArmor
    end

    -- Filled sockets no longer show their socket-color lines in the tooltip,
    -- so restore those counts from the actual gems in the item link.
    do
        local filledColored, filledMeta = self:GetFilledSocketCounts(itemLink)
        if filledColored > 0 then
            -- Colored sockets are all valued the same for scoring, so one bucket is enough.
            stats["RED_SOCKET"] = (stats["RED_SOCKET"] or 0) + filledColored
        end
        if filledMeta > 0 then
            stats["META_SOCKET"] = (stats["META_SOCKET"] or 0) + filledMeta
        end
    end

    -- Weapon skill Ã¢â€ â€™ Expertise: only the highest weapon type counts at a time
    if stats["_WSKILL"] then
        stats["EXP"] = (stats["EXP"] or 0) + stats["_WSKILL"]
        stats["_WSKILL"] = nil
    end

    if self.DebugLog then self:DebugLog(string.format("SCAN %s PVE=%s", tostring(itemLink), tostring(stats.PVE_POWER or 0))) end
    return stats

end

-- ============================================================================
-- EFFECTIVE GEM VALUE: prefer explicit spec tuning, otherwise fall back to a
-- strong per-socket estimate based on the active weight table.
-- ============================================================================
local SOCKET_VALUE_FALLBACKS = {
    { stat = "STR",        amount = 8 },
    { stat = "AGI",        amount = 8 },
    { stat = "STA",        amount = 12 },
    { stat = "INT",        amount = 8 },
    { stat = "SPI",        amount = 8 },
    { stat = "AP",         amount = 16 },
    { stat = "SP",         amount = 9 },
    { stat = "HEAL",       amount = 18 },
    { stat = "MP5",        amount = 4 },
    { stat = "HIT",        amount = 8 },
    { stat = "SPELLHIT",   amount = 8 },
    { stat = "CRIT",       amount = 8 },
    { stat = "SPELLCRIT",  amount = 8 },
    { stat = "MELEECRIT",  amount = 8 },
    { stat = "HASTE",      amount = 8 },
    { stat = "DEF",        amount = 8 },
    { stat = "DODGE",      amount = 8 },
    { stat = "PARRY",      amount = 8 },
    { stat = "RESIL",      amount = 8 },
    { stat = "ARP",        amount = 8 },
    { stat = "BLOCK_RATING", amount = 8 },
}

function CharacterGearOptimizer:GetEffectiveGemValue(specData)
    if not specData or not specData.weights then return 0 end

    if specData.gemValue and specData.gemValue > 0 then
        return specData.gemValue * SOCKET_VALUE_MULTIPLIER
    end

    local maxW = 0
    for _, w in pairs(specData.weights) do
        if w > maxW then maxW = w end
    end

    local bestFallback = 0
    for _, candidate in ipairs(SOCKET_VALUE_FALLBACKS) do
        local w = specData.weights[candidate.stat] or 0
        local value = w * candidate.amount
        if value > bestFallback then
            bestFallback = value
        end
    end

    return math.max(bestFallback, maxW * 8) * SOCKET_VALUE_MULTIPLIER
end

function CharacterGearOptimizer:GetEffectiveMetaValue(specData)
    if not specData then return 0 end
    if specData.metaValue and specData.metaValue > 0 then
        return specData.metaValue * SOCKET_VALUE_MULTIPLIER
    end
    return self:GetEffectiveGemValue(specData) * 1.5
end

-- ============================================================================
-- SCORE CALCULATION: weighted sum based on active spec
-- ============================================================================
function CharacterGearOptimizer:CalculateScore(stats, specData)
    if not stats or not specData then return 0 end

    local total = 0
    local weights = specData.weights

    for stat, value in pairs(stats) do
        local w = weights[stat] or 0
        if w > 0 then
            total = total + (value * w)
        end
    end

    -- Socket scoring: each colored socket = highest stat weight
    local coloredSockets = (stats.RED_SOCKET or 0) + (stats.YELLOW_SOCKET or 0) + (stats.BLUE_SOCKET or 0)
    local metaSockets    = stats.META_SOCKET or 0
    local gemValue = self:GetEffectiveGemValue(specData)
    local metaValue = self:GetEffectiveMetaValue(specData)

    total = total + (coloredSockets * gemValue)
    total = total + (metaSockets * metaValue)

    return total
end

-- ============================================================================
-- BUILD STAT BREAKDOWN: ordered list of { label, raw, weighted, weight }
-- ============================================================================
function CharacterGearOptimizer:BuildBreakdown(stats, specData)
    if not stats or not specData then return {} end

    local breakdown = {}
    local weights = specData.weights

    -- Stat order priority (meaningful stats first)
    local order = {
        "STR", "AGI", "STA", "INT", "SPI",
        "AP", "FAP", "SP", "HEAL", "MP5",
        "HIT", "CRIT", "SPELLCRIT", "MELEECRIT", "HASTE", "EXP",
        "DEF", "DODGE", "PARRY", "RESIL",
        "BLOCK_RATING", "BLOCK_VALUE", "ARMOR", "ARP", "SPELL_PEN",
        "PVP_POWER", "PVE_POWER", "WEAPON_DPS",
    }

    for _, stat in ipairs(order) do
        local val = stats[stat]
        if val and val > 0 and weights[stat] then
            table.insert(breakdown, {
                label    = self.STAT_LABELS[stat] or stat,
                stat     = stat,
                raw      = val,
                weighted = val * weights[stat],
                weight   = weights[stat],
            })
        end
    end

    return breakdown
end

-- ============================================================================
-- ADD PER-STAT DIFFS TO TOOLTIP (shared by single-slot and dual-slot paths)
-- ============================================================================
function CharacterGearOptimizer:AddStatDiffs(tooltip, newStats, newBreak, eqStats, eqBreak, specData)
    local statOrder = {}
    local seen = {}

    for _, entry in ipairs(newBreak) do
        if not seen[entry.stat] then
            table.insert(statOrder, entry.stat)
            seen[entry.stat] = true
        end
    end
    for _, entry in ipairs(eqBreak) do
        if not seen[entry.stat] then
            table.insert(statOrder, entry.stat)
            seen[entry.stat] = true
        end
    end

    local weights = specData.weights
    for _, stat in ipairs(statOrder) do
        local nRaw = newStats[stat] or 0
        local eRaw = eqStats[stat] or 0
        local w    = weights[stat] or 0
        local diff = nRaw - eRaw

        if diff ~= 0 and w > 0 then
            local wDiff = diff * w
            local c = diff > 0 and "|cff00ff00" or "|cffff0000"
            tooltip:AddDoubleLine(
                string.format("  %s (x%.2f):", self.STAT_LABELS[stat] or stat, w),
                string.format("%s%+d|r = %s%+.1f|r", c, diff, c, wDiff),
                0.7, 0.7, 0.7
            )
        end
    end
end

-- ============================================================================
-- ADD SOCKET DIFFS TO TOOLTIP
-- ============================================================================
function CharacterGearOptimizer:AddSocketDiffs(tooltip, newStats, eqStats, specData)
    local newColored = (newStats.RED_SOCKET or 0) + (newStats.YELLOW_SOCKET or 0) + (newStats.BLUE_SOCKET or 0)
    local eqColored  = (eqStats.RED_SOCKET or 0) + (eqStats.YELLOW_SOCKET or 0) + (eqStats.BLUE_SOCKET or 0)
    local sockDiff   = newColored - eqColored
    local gemValue   = self:GetEffectiveGemValue(specData)
    local newMeta    = newStats.META_SOCKET or 0
    local eqMeta     = eqStats.META_SOCKET or 0
    local metaDiff   = newMeta - eqMeta
    local metaValue  = self:GetEffectiveMetaValue(specData)

    if newColored > 0 or eqColored > 0 then
        local sockValDiff = sockDiff * gemValue
        local sc = sockDiff > 0 and "|cff00ff00" or (sockDiff < 0 and "|cffff0000" or "|cffffffff")
        tooltip:AddDoubleLine(
            string.format("  |cffda70d6Sockets|r (x%.1f ea):", gemValue),
            string.format("%s%d|r vs %s%d|r = %s%+.1f|r",
                sc, newColored, "|cffffffff", eqColored,
                sockDiff ~= 0 and sc or "|cffffffff", sockValDiff),
            0.7, 0.7, 0.7
        )
    end

    if newMeta > 0 or eqMeta > 0 then
        local metaValDiff = metaDiff * metaValue
        local mc = metaDiff > 0 and "|cff00ff00" or (metaDiff < 0 and "|cffff0000" or "|cffffffff")
        tooltip:AddDoubleLine(
            string.format("  |cff00ffffMeta Socket|r (x%.1f ea):", metaValue),
            string.format("%s%d|r vs %s%d|r = %s%+.1f|r",
                mc, newMeta, "|cffffffff", eqMeta,
                metaDiff ~= 0 and mc or "|cffffffff", metaValDiff),
            0.7, 0.7, 0.7
        )
    end
end

-- ============================================================================
-- GEM SCORING (standalone gem item)
-- ============================================================================
function CharacterGearOptimizer:ScoreGem(itemLink, specData)
    if not itemLink or not specData then return 0, {} end

    local tip = self.scanTooltip
    tip:SetOwner(WorldFrame, "ANCHOR_NONE")
    tip:ClearLines()
    tip:SetHyperlink(itemLink)

    local totalScore = 0
    local breakdown = {}

    for i = 2, tip:NumLines() do
        local line = _G["CGOScanTooltipTextLeft" .. i]
        if line then
            local text = line:GetText()
            if text then
                for _, pat in ipairs(self.GEM_PATTERNS) do
                    local val = text:match(pat.pattern)
                    if val then
                        val = tonumber(val) or 0
                        if val > 0 then
                            local w = specData.weights[pat.weight] or 0
                            if w > 0 then
                                local weighted = val * w
                                totalScore = totalScore + weighted
                                table.insert(breakdown, {
                                    label    = pat.label,
                                    raw      = val,
                                    weighted = weighted,
                                    weight   = w,
                                })
                            end
                        end
                    end
                end
            end
        end
    end

    if self:IsMetaGemLink(itemLink) then
        totalScore = math.max(totalScore, self:GetEffectiveMetaValue(specData))
    end

    return totalScore, breakdown
end

-- ============================================================================
-- EHP CALCULATION (for tank specs)
-- ============================================================================
local function CalculateDamageReduction(armor)
    if armor <= 0 then return 0 end
    return armor / (armor + CharacterGearOptimizer.RATING.ARMOR_CONSTANT)
end

function CharacterGearOptimizer:CalculateEHP(hp, armor, avoidancePct)
    local dr = CalculateDamageReduction(armor)
    if dr >= 1 then dr = 0.99 end

    local avoid = (avoidancePct or 0)
    if avoid >= 1 then avoid = 0.99 end

    local rawEHP   = hp / (1 - dr)
    local totalEHP = rawEHP / (1 - avoid)
    return rawEHP, totalEHP
end

-- ============================================================================
-- TANK TOOLTIP: EHP diff for tank specs
-- ============================================================================
function CharacterGearOptimizer:AddTankEHPTooltip(tooltip, newStats, equippedStats, specData)
    -- Only for tank roles
    local role = specData.role
    if role ~= "tank" and role ~= "tank_druid" and role ~= "tank_barrier" then return end

    local armorDiff  = (newStats.ARMOR or 0) - (equippedStats.ARMOR or 0)
    local staDiff    = (newStats.STA or 0) - (equippedStats.STA or 0)
    local agiDiff    = (newStats.AGI or 0) - (equippedStats.AGI or 0)
    local defDiff    = (newStats.DEF or 0) - (equippedStats.DEF or 0)
    local dodgeDiff  = (newStats.DODGE or 0) - (equippedStats.DODGE or 0)
    local parryDiff  = (newStats.PARRY or 0) - (equippedStats.PARRY or 0)
    local resilDiff  = (newStats.RESIL or 0) - (equippedStats.RESIL or 0)

    -- Get current player stats for EHP calculation
    local baseArmor, effectiveArmor = UnitArmor("player")
    local maxHP = UnitHealthMax("player")
    local dodge = GetDodgeChance()
    local parry = GetParryChance and GetParryChance() or 0

    local R = self.RATING

    -- Current avoidance
    local defOverCap = 0
    if UnitDefense then
        local base, mod = UnitDefense("player")
        defOverCap = (base + mod) - (UnitLevel("player") * 5)
    end
    local miss = math.max(0, 5.0 - 0.6 + defOverCap * 0.04)

    local currentAvoid = (dodge + parry + miss) / 100

    if role == "tank_druid" then
        -- Bear form multipliers
        local bam = specData.bearArmorMultiplier or 5.5
        local bsm = specData.bearStaminaMultiplier or 1.5
        local a2a = specData.agilityToArmor or 2
        local a2d = specData.agilityToDodge or 0.053

        local agiArmorBonus = agiDiff * a2a
        local totalArmorDiff = (armorDiff + agiArmorBonus) * bam
        local totalStaDiff   = staDiff * bsm
        local hpDiff         = totalStaDiff * 10

        -- Avoidance change
        local agiDodge = agiDiff * a2d
        local ratingDodge = dodgeDiff / R.DODGE_PER_RATING
        local defSkillDiff = defDiff / R.DEFENSE_PER_SKILL
        local defDodge = defSkillDiff * 0.04
        local defMiss  = defSkillDiff * 0.04
        local totalAvoidDiff = agiDodge + ratingDodge + defDodge + defMiss

        local newArmor = (effectiveArmor or 0) + totalArmorDiff
        local newHP    = maxHP + hpDiff
        local newAvoid = currentAvoid + (totalAvoidDiff / 100)

        local _, currentEHP = self:CalculateEHP(maxHP, effectiveArmor or 0, currentAvoid)
        local _, newEHP     = self:CalculateEHP(newHP, newArmor, newAvoid)
        local ehpDiff = newEHP - currentEHP

        -- Display
        tooltip:AddLine(" ")
        local ac = totalArmorDiff >= 0 and "|cff00ff00" or "|cffff0000"
        local sc = totalStaDiff >= 0 and "|cff00ff00" or "|cffff0000"
        local vc = totalAvoidDiff >= 0 and "|cff00ff00" or "|cffff0000"
        local ec = ehpDiff >= 0 and "|cff00ff00" or "|cffff0000"

        tooltip:AddDoubleLine("Armor (Bear):", string.format("%s%+.0f|r", ac, totalArmorDiff), 1,1,1)
        tooltip:AddDoubleLine("Stamina (Bear):", string.format("%s%+.1f|r", sc, totalStaDiff), 1,1,1)
        if totalAvoidDiff ~= 0 then
            tooltip:AddDoubleLine("Avoidance:", string.format("%s%+.2f%%|r", vc, totalAvoidDiff), 1,1,1)
        end
        tooltip:AddDoubleLine("|cffffd700EHP:|r", string.format("%s%+.0f|r", ec, ehpDiff), 1,1,1)

    else
        -- Plate tank (Warrior/Paladin Prot)
        local hpDiff = staDiff * 10

        -- Avoidance
        local ratingDodge = dodgeDiff / R.DODGE_PER_RATING
        local ratingParry = parryDiff / R.PARRY_PER_RATING
        local defSkillDiff = defDiff / R.DEFENSE_PER_SKILL
        local defDodge = defSkillDiff * 0.04
        local defParry = defSkillDiff * 0.04
        local defMiss  = defSkillDiff * 0.04
        local totalAvoidDiff = ratingDodge + ratingParry + defDodge + defParry + defMiss

        local newArmor = (effectiveArmor or 0) + armorDiff
        local newHP    = maxHP + hpDiff
        local newAvoid = currentAvoid + (totalAvoidDiff / 100)

        local _, currentEHP = self:CalculateEHP(maxHP, effectiveArmor or 0, currentAvoid)
        local _, newEHP     = self:CalculateEHP(newHP, newArmor, newAvoid)
        local ehpDiff = newEHP - currentEHP

        if math.abs(ehpDiff) > 0.5 then
            tooltip:AddLine(" ")
            local ec = ehpDiff >= 0 and "|cff00ff00" or "|cffff0000"
            tooltip:AddDoubleLine("|cffffd700EHP Change:|r", string.format("%s%+.0f|r", ec, ehpDiff), 1,1,1)
        end
    end
end

-- Tooltip hook is in TooltipHook.lua
