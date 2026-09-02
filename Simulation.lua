-- ============================================================================
-- CharacterGearOptimizer: Simulation.lua
-- Multi-set simulation, comparative stat modeling, encounter diagnostics,
-- and predictive item upgrade engine with cap-impact analysis.
-- ============================================================================

local addonName, addon = ...
local addon = addon or _G.CharacterGearOptimizer or {}
_G.CharacterGearOptimizer = addon

addon.Sim = addon.Sim or {}
addon.Simulation = addon.Sim
addon.UpgradePredictor = addon.Sim
local Sim = addon.Sim

local BACKDROP_TEMPLATE = BackdropTemplateMixin and "BackdropTemplate" or nil

local function ApplyBackdrop(frame, backdrop, bgColor, borderColor)
    if not frame or not frame.SetBackdrop then return end
    frame:SetBackdrop(backdrop)
    if bgColor and frame.SetBackdropColor then
        frame:SetBackdropColor(unpack(bgColor))
    end
    if borderColor and frame.SetBackdropBorderColor then
        frame:SetBackdropBorderColor(unpack(borderColor))
    end
end

local function SafeColorTexture(tex, r, g, b, a)
    if not tex then return end
    if tex.SetColorTexture then
        tex:SetColorTexture(r, g, b, a)
    else
        tex:SetTexture(r, g, b, a)
    end
end

-- Human readable slot names
local SLOT_NAMES = {
    [1]  = "Head",      [2]  = "Neck",      [3]  = "Shoulder",
    [4]  = "Shirt",     [5]  = "Chest",     [6]  = "Waist",
    [7]  = "Legs",      [8]  = "Feet",      [9]  = "Wrist",
    [10] = "Hands",     [11] = "Ring 1",    [12] = "Ring 2",
    [13] = "Trinket 1", [14] = "Trinket 2", [15] = "Back",
    [16] = "Main Hand", [17] = "Off Hand",  [18] = "Ranged",
    [19] = "Tabard",
}
Sim.SLOT_NAMES = SLOT_NAMES

-- All relevant stats tracked during simulation
local TRACKED_STATS = {
    "STR", "AGI", "STA", "INT", "SPI",
    "AP", "FAP", "SP", "HEAL", "MP5",
    "HIT", "SPELLHIT", "SPELL_HIT_TOTAL",
    "CRIT", "SPELLCRIT", "MELEECRIT",
    "HASTE", "EXP", "DEF", "DODGE", "PARRY", "BLOCK_RATING", "BLOCK_VALUE",
    "RESIL", "ARP", "ARMOR", "SPELL_PEN",
    "SOCKET_RED", "SOCKET_YELLOW", "SOCKET_BLUE", "SOCKET_META", "SOCKET_PRISMATIC"
}
Sim.TRACKED_STATS = TRACKED_STATS

-- ============================================================================
-- SIMULATION CORE: Gear Set Aggregator & Stat Evaluator
-- ============================================================================

--- Aggregate raw stats and calculate ratings, caps, EHP, and throughput score for a gear set.
-- @param gearSet table Mapping of slotID (1..19) to item table or item link
-- @param specData table Optional spec profile containing stat weights, role, caps
-- @return table Comprehensive simulation result object
function Sim:SimulateGearSet(gearSet, specData)
    specData = specData or (addon.GetActiveSpecData and addon:GetActiveSpecData())
    local result = {
        items = {},
        rawStats = {},
        score = 0,
        baseScore = 0,
        socketBonusScore = 0,
        emptySockets = 0,
        filledSockets = 0,
        totalSockets = 0,
        avgItemLevel = 0,
        totalItemLevel = 0,
        itemCount = 0,
        ehp = 0,
        ehpArmor = 0,
        armorDR = 0,
        ratings = {},
        caps = {},
        specName = specData and specData.name or "Default",
        role = specData and specData.role or "dps",
    }

    for _, statKey in ipairs(TRACKED_STATS) do
        result.rawStats[statKey] = 0
    end

    if not gearSet then return result end

    local R = addon.RATING or {
        HIT_PER_PCT = 8.0, SPELL_HIT_PER_PCT = 8.0, CRIT_PER_PCT = 45.91,
        HASTE_PER_PCT = 32.79, EXPERTISE_PER_SKILL = 8.1974, DEFENSE_PER_SKILL = 4.918,
        DODGE_PER_RATING = 39.35, PARRY_PER_RATING = 49.18, BLOCK_PER_RATING = 16.39,
        RESIL_PER_PCT = 81.97, AVOID_PER_DEF_SKILL = 0.16, DEFENSE_CAP = 540,
        UNCRUSHABLE_PCT = 102.4, MELEE_HIT_CAP_PCT = 8.0, SPELL_HIT_CAP_PCT = 17.0,
        EXPERTISE_SOFT_CAP = 26, BOSS_CRIT_PCT = 5.6,
    }

    -- 1. Extract and sum stats from every slot
    for slotID = 1, 19 do
        local slotData = gearSet[slotID]
        local link = nil
        local cachedStats = nil

        if type(slotData) == "string" then
            link = slotData
        elseif type(slotData) == "table" then
            link = slotData.link
            cachedStats = slotData.stats
        end

        if link and link ~= "" then
            local stats = cachedStats or addon:ExtractItemStats(link)
            local itemScore = addon:CalculateScore(stats, specData)
            local itemName, _, itemQuality, iLevel, _, _, _, _, equipLoc, itemTexture = GetItemInfo(link)

            local itemEntry = {
                slot = slotID,
                slotName = SLOT_NAMES[slotID] or ("Slot " .. slotID),
                link = link,
                name = itemName or link:match("%[(.-)%]") or "Unknown Item",
                quality = itemQuality or 1,
                iLevel = iLevel or 0,
                texture = itemTexture or "Interface/Icons/INV_Misc_QuestionMark",
                equipLoc = equipLoc,
                score = itemScore,
                stats = stats,
            }
            result.items[slotID] = itemEntry

            -- Accumulate raw stats
            for statKey, val in pairs(stats) do
                if type(val) == "number" and val > 0 then
                    result.rawStats[statKey] = (result.rawStats[statKey] or 0) + val
                end
            end

            -- Socket counting
            local coloredSockets = (stats["SOCKET_RED"] or 0) + (stats["SOCKET_YELLOW"] or 0) + (stats["SOCKET_BLUE"] or 0) + (stats["SOCKET_PRISMATIC"] or 0)
            local metaSockets = stats["SOCKET_META"] or 0
            local socketsOnItem = coloredSockets + metaSockets
            if socketsOnItem > 0 then
                result.totalSockets = result.totalSockets + socketsOnItem
                if addon.GetFilledSocketCounts then
                    local filledColored, filledMeta = addon:GetFilledSocketCounts(link)
                    local totalFilled = filledColored + filledMeta
                    result.filledSockets = result.filledSockets + totalFilled
                    result.emptySockets = result.emptySockets + math.max(0, socketsOnItem - totalFilled)
                end
            end

            result.score = result.score + itemScore
            if iLevel and iLevel > 0 then
                result.totalItemLevel = result.totalItemLevel + iLevel
                result.itemCount = result.itemCount + 1
            end
        end
    end

    result.baseScore = result.score
    if result.itemCount > 0 then
        result.avgItemLevel = math.floor((result.totalItemLevel / result.itemCount) * 10 + 0.5) / 10
    end

    -- Potential socket upgrade value (if open sockets are socketed)
    if result.emptySockets > 0 and specData then
        local gemVal = specData.gemValue or 20
        result.socketBonusScore = result.emptySockets * gemVal
    end

    -- 2. Derive Combat Ratings and Percentage Estimates
    local defRating   = result.rawStats["DEF"] or 0
    local dodgeRating = result.rawStats["DODGE"] or 0
    local parryRating = result.rawStats["PARRY"] or 0
    local blockRating = result.rawStats["BLOCK_RATING"] or 0
    local hitRating   = result.rawStats["HIT"] or 0
    local spellHitR   = result.rawStats["SPELLHIT"] or 0
    local critRating  = result.rawStats["CRIT"] or 0
    local hasteRating = result.rawStats["HASTE"] or 0
    local expRating   = result.rawStats["EXP"] or 0
    local resilRating = result.rawStats["RESIL"] or 0
    local armorVal    = result.rawStats["ARMOR"] or 0
    local stamVal     = result.rawStats["STA"] or 0

    local talentMeleeHit, talentRangedHit, talentSpellHit = 0, 0, 0
    if addon.GetTalentHitBonuses then
        talentMeleeHit, talentRangedHit, talentSpellHit = addon:GetTalentHitBonuses()
    end

    local ratings = {}
    ratings.defSkillBonus   = defRating / (R.DEFENSE_PER_SKILL or 4.918)
    ratings.dodgePctBonus   = dodgeRating / (R.DODGE_PER_RATING or 39.35)
    ratings.parryPctBonus   = parryRating / (R.PARRY_PER_RATING or 49.18)
    ratings.blockPctBonus   = blockRating / (R.BLOCK_PER_RATING or 16.39)
    ratings.meleeHitPct     = (hitRating / (R.HIT_PER_PCT or 8.0)) + talentMeleeHit
    ratings.spellHitPct     = ((hitRating + spellHitR) / (R.SPELL_HIT_PER_PCT or 8.0)) + talentSpellHit
    ratings.critPctBonus    = critRating / (R.CRIT_PER_PCT or 45.91)
    ratings.hastePctBonus   = hasteRating / (R.HASTE_PER_PCT or 32.79)
    ratings.expertiseSkill  = expRating / (R.EXPERTISE_PER_SKILL or 8.1974)
    ratings.resiliencePct   = resilRating / (R.RESIL_PER_PCT or 81.97)

    result.ratings = ratings

    -- 3. Armor DR and EHP Simulation
    local playerLevel = UnitLevel("player") or 80
    if addon.StatCalc and addon.StatCalc.GetArmorDR then
        result.armorDR = addon.StatCalc:GetArmorDR(armorVal, playerLevel)
    else
        local k = (playerLevel > 60) and (85 * playerLevel + 400) or 16635
        result.armorDR = math.min((armorVal / (armorVal + k)) * 100, 75)
    end

    local estimatedBaseHealth = (stamVal * 10) + (UnitHealthMax and UnitHealthMax("player") or 10000)
    local totalAvoidancePct = (ratings.dodgePctBonus + ratings.parryPctBonus + ratings.blockPctBonus + (ratings.defSkillBonus * 0.04) + 5.0)

    if addon.StatCalc and addon.StatCalc.CalculateEHP then
        result.ehp, result.ehpArmor = addon.StatCalc:CalculateEHP(estimatedBaseHealth, armorVal, totalAvoidancePct, playerLevel)
    else
        local armorMult = math.max(0.01, 1 - (result.armorDR / 100))
        result.ehpArmor = math.floor(estimatedBaseHealth / armorMult)
        local avoidMult = math.max(0.01, 1 - math.min(totalAvoidancePct / 100, 0.99))
        result.ehp = math.floor(result.ehpArmor / avoidMult)
    end

    -- 4. Cap Compliance Evaluation
    local caps = {}

    -- Melee Hit Cap (8% Special / Yellow attacks on raid bosses)
    local meleeHitTarget = R.MELEE_HIT_CAP_PCT or 8.0
    caps.meleeHit = {
        name = "Melee Hit Cap",
        target = meleeHitTarget,
        current = ratings.meleeHitPct,
        diff = ratings.meleeHitPct - meleeHitTarget,
        status = ratings.meleeHitPct >= meleeHitTarget and "CAPPED" or "UNDER",
        text = string.format("%.2f%% / %.1f%%", ratings.meleeHitPct, meleeHitTarget),
    }

    -- Spell Hit Cap (17% on raid bosses in WotLK / Classic)
    local spellHitTarget = R.SPELL_HIT_CAP_PCT or 17.0
    caps.spellHit = {
        name = "Spell Hit Cap",
        target = spellHitTarget,
        current = ratings.spellHitPct,
        diff = ratings.spellHitPct - spellHitTarget,
        status = ratings.spellHitPct >= spellHitTarget and "CAPPED" or "UNDER",
        text = string.format("%.2f%% / %.1f%%", ratings.spellHitPct, spellHitTarget),
    }

    -- Defense Cap (540 Defense Skill for level 83 boss crit immunity)
    local baseDef = 350
    if UnitDefense then
        local bDef = UnitDefense("player")
        if bDef and bDef > 0 then baseDef = bDef end
    end
    local totalDefSkill = baseDef + ratings.defSkillBonus
    local defTarget = R.DEFENSE_CAP or 540
    caps.defense = {
        name = "Defense Cap (Crit Immunity)",
        target = defTarget,
        current = totalDefSkill,
        diff = totalDefSkill - defTarget,
        status = totalDefSkill >= defTarget and "CAPPED" or "UNDER",
        text = string.format("%.1f / %d", totalDefSkill, defTarget),
    }

    -- Expertise Soft Cap (26 skill / 6.5% dodge reduction)
    local expTarget = R.EXPERTISE_SOFT_CAP or 26
    caps.expertise = {
        name = "Expertise Soft Cap",
        target = expTarget,
        current = ratings.expertiseSkill,
        diff = ratings.expertiseSkill - expTarget,
        status = ratings.expertiseSkill >= expTarget and "CAPPED" or "UNDER",
        text = string.format("%.1f / %d", ratings.expertiseSkill, expTarget),
    }

    -- Uncrushable Cap (102.4% Total Avoidance + Block + Miss for Level 83 Boss)
    local uncrushTarget = R.UNCRUSHABLE_PCT or 102.4
    caps.uncrushable = {
        name = "Uncrushable (Block Tank)",
        target = uncrushTarget,
        current = totalAvoidancePct,
        diff = totalAvoidancePct - uncrushTarget,
        status = totalAvoidancePct >= uncrushTarget and "CAPPED" or "UNDER",
        text = string.format("%.2f%% / %.1f%%", totalAvoidancePct, uncrushTarget),
    }

    -- Resilience Cap (5.6% Crit Reduction for PvP)
    local resilTarget = R.BOSS_CRIT_PCT or 5.6
    caps.resilience = {
        name = "Resilience (PvP)",
        target = resilTarget,
        current = ratings.resiliencePct,
        diff = ratings.resiliencePct - resilTarget,
        status = ratings.resiliencePct >= resilTarget and "CAPPED" or "UNDER",
        text = string.format("%.2f%% / %.1f%%", ratings.resiliencePct, resilTarget),
    }

    result.caps = caps
    return result
end

-- ============================================================================
-- CURRENT EQUIPPED & SAVED SETS RETRIEVAL
-- ============================================================================

--- Retrieve the player's currently equipped gear as a simulated set table.
-- @return table Gear set table indexed by slot ID 1..19
function Sim:GetCurrentlyEquippedSet()
    local set = {}
    for slot = 1, 19 do
        local link = GetInventoryItemLink("player", slot)
        if link then
            set[slot] = {
                link = link,
                slot = slot,
                isEquipped = true,
                stats = addon:ExtractItemStats(link),
            }
        end
    end
    return set
end

--- Retrieve all available sets (Equipped, Optimized from Bags, and Saved Sets).
-- @param specData table Optional spec profile
-- @return table Array of set descriptor tables { name = ..., set = ..., sim = ..., type = ... }
function Sim:GetAllSimulatedSets(specData)
    specData = specData or (addon.GetActiveSpecData and addon:GetActiveSpecData())
    local sets = {}

    -- 1. Currently Equipped
    local equippedSet = self:GetCurrentlyEquippedSet()
    local equippedSim = self:SimulateGearSet(equippedSet, specData)
    table.insert(sets, {
        id = "EQUIPPED",
        name = "Currently Equipped",
        type = "EQUIPPED",
        icon = "Interface/Icons/INV_Chest_Cloth_17",
        set = equippedSet,
        sim = equippedSim,
    })

    -- 2. Optimized (Best in Bags/Bank)
    local _, playerClass = UnitClass("player")
    local specIdx = addon.currentSpecIdx or addon.autoDetectedSpecIdx or 1
    local bestSet = addon:GetBestGearForSpec(playerClass, specIdx)
    if bestSet then
        local bagSim = self:SimulateGearSet(bestSet, specData)
        table.insert(sets, {
            id = "OPTIMIZED_BAGS",
            name = "Optimized (Bags & Bank)",
            type = "OPTIMIZED",
            icon = "Interface/Icons/Inv_misc_gear_01",
            set = bestSet,
            sim = bagSim,
        })
    end

    -- 3. User Saved Sets (CharacterGearOptimizerDB.sets)
    local saved = CharacterGearOptimizerDB and CharacterGearOptimizerDB.sets
    if saved then
        local sortedNames = {}
        for name in pairs(saved) do table.insert(sortedNames, name) end
        table.sort(sortedNames)

        for _, name in ipairs(sortedNames) do
            local setData = saved[name]
            if setData and setData.items then
                local sSet = {}
                for slotID, itemInfo in pairs(setData.items) do
                    sSet[tonumber(slotID) or slotID] = {
                        link = itemInfo.link,
                        slot = tonumber(slotID) or slotID,
                        score = itemInfo.score,
                    }
                end
                local sSim = self:SimulateGearSet(sSet, specData)
                table.insert(sets, {
                    id = "SAVED_" .. name,
                    name = name,
                    type = "SAVED",
                    icon = setData.icon or "Interface/Icons/INV_Misc_QuestionMark",
                    set = sSet,
                    sim = sSim,
                })
            end
        end
    end

    return sets
end

-- ============================================================================
-- MULTI-SET COMPARISON ENGINE
-- ============================================================================

--- Compare two simulated gear sets side-by-side with complete stat diffs and recommendation.
-- @param setA table First gear set
-- @param setB table Second gear set
-- @param specData table Optional spec profile
-- @param nameA string Name of set A (e.g. "Equipped")
-- @param nameB string Name of set B (e.g. "Optimized")
-- @return table Comprehensive comparison report
function Sim:CompareSets(setA, setB, specData, nameA, nameB)
    nameA = nameA or "Set A"
    nameB = nameB or "Set B"
    specData = specData or (addon.GetActiveSpecData and addon:GetActiveSpecData())

    local simA = self:SimulateGearSet(setA, specData)
    local simB = self:SimulateGearSet(setB, specData)

    local diff = {
        nameA = nameA,
        nameB = nameB,
        simA = simA,
        simB = simB,
        scoreDiff = simB.score - simA.score,
        scoreGainPct = simA.score > 0 and ((simB.score - simA.score) / simA.score) * 100 or 0,
        ehpDiff = simB.ehp - simA.ehp,
        ilvlDiff = simB.avgItemLevel - simA.avgItemLevel,
        slotDiffs = {},
        statDiffs = {},
        capDiffs = {},
        verdict = "",
        recommendation = "",
    }

    -- Stat Diffs (B minus A)
    for _, statKey in ipairs(TRACKED_STATS) do
        local valA = simA.rawStats[statKey] or 0
        local valB = simB.rawStats[statKey] or 0
        local delta = valB - valA
        if delta ~= 0 then
            diff.statDiffs[statKey] = {
                stat = statKey,
                valA = valA,
                valB = valB,
                delta = delta,
            }
        end
    end

    -- Slot Diffs
    for slotID = 1, 19 do
        local itemA = simA.items[slotID]
        local itemB = simB.items[slotID]
        local linkA = itemA and itemA.link
        local linkB = itemB and itemB.link

        if linkA ~= linkB then
            local scA = itemA and itemA.score or 0
            local scB = itemB and itemB.score or 0
            table.insert(diff.slotDiffs, {
                slot = slotID,
                slotName = SLOT_NAMES[slotID] or ("Slot " .. slotID),
                itemA = itemA,
                itemB = itemB,
                scoreA = scA,
                scoreB = scB,
                diff = scB - scA,
            })
        end
    end

    -- Cap Shift Diffs
    for capKey, capA in pairs(simA.caps) do
        local capB = simB.caps[capKey]
        if capB then
            diff.capDiffs[capKey] = {
                name = capA.name,
                statusA = capA.status,
                statusB = capB.status,
                diff = capB.current - capA.current,
                textA = capA.text,
                textB = capB.text,
            }
        end
    end

    -- Recommendation verdict
    if diff.scoreDiff > 0.5 then
        diff.verdict = string.format("|cFF00FF00%s is superior by +%.1f Score (+%.1f%%)|r", nameB, diff.scoreDiff, diff.scoreGainPct)
        diff.recommendation = "Equipping " .. nameB .. " will yield a net DPS / throughput improvement."
    elseif diff.scoreDiff < -0.5 then
        diff.verdict = string.format("|cFFFF4444%s is lower by %.1f Score (%.1f%%)|r", nameB, diff.scoreDiff, diff.scoreGainPct)
        diff.recommendation = nameA .. " remains the superior configuration for current weights."
    else
        diff.verdict = "|cFFFFFF00Both sets perform equally in score.|r"
        diff.recommendation = "Both sets are within ±0.5 score margin."
    end

    return diff
end

-- ============================================================================
-- ITEM UPGRADE PREDICTOR & ROADMAP ENGINE
-- ============================================================================

--- Predict the exact impact of equipping a specific item into a target set.
-- @param itemLink string Item hyperlink or ID
-- @param targetSet table Optional target gear set (defaults to currently equipped)
-- @param specData table Optional spec profile
-- @return table Upgrade prediction analysis
function Sim:PredictUpgrade(itemLink, targetSet, specData)
    if not itemLink or itemLink == "" then return nil end
    specData = specData or (addon.GetActiveSpecData and addon:GetActiveSpecData())
    targetSet = targetSet or self:GetCurrentlyEquippedSet()

    local _, _, _, _, _, _, _, _, equipLoc = GetItemInfo(itemLink)
    if not equipLoc or equipLoc == "" or equipLoc == "INVTYPE_TABARD" or equipLoc == "INVTYPE_BODY" then
        return nil
    end

    local validSlots = addon:GetValidSlotsForEquipLoc(equipLoc, itemLink)
    if not validSlots or #validSlots == 0 then return nil end

    local baseSim = self:SimulateGearSet(targetSet, specData)
    local bestOutcome = nil

    -- Test replacing each candidate slot
    for _, slotID in ipairs(validSlots) do
        local simulatedSet = {}
        for s, it in pairs(targetSet) do simulatedSet[s] = it end

        -- Handle 2H weapon replacing MH + OH
        if equipLoc == "INVTYPE_2HWEAPON" and slotID == 16 then
            simulatedSet[16] = { link = itemLink, slot = 16 }
            simulatedSet[17] = nil
        else
            simulatedSet[slotID] = { link = itemLink, slot = slotID }
        end

        local newSim = self:SimulateGearSet(simulatedSet, specData)
        local scoreDelta = newSim.score - baseSim.score
        local replacedItem = targetSet[slotID]

        if not bestOutcome or scoreDelta > bestOutcome.scoreDiff then
            local capWarnings = {}
            local capGains = {}

            -- Cap impact inspection
            for capKey, oldCap in pairs(baseSim.caps) do
                local newCap = newSim.caps[capKey]
                if newCap then
                    if oldCap.status == "CAPPED" and newCap.status == "UNDER" then
                        table.insert(capWarnings, string.format("WARNING: Equipping this breaks %s (drops from %s to %s)!", oldCap.name, oldCap.text, newCap.text))
                    elseif oldCap.status == "UNDER" and newCap.status == "CAPPED" then
                        table.insert(capGains, string.format("SUCCESS: Reaches %s (%s)!", newCap.name, newCap.text))
                    end
                end
            end

            -- Potential socket upgrade value
            local newStats = addon:ExtractItemStats(itemLink)
            local sockets = (newStats["SOCKET_RED"] or 0) + (newStats["SOCKET_YELLOW"] or 0) + (newStats["SOCKET_BLUE"] or 0) + (newStats["SOCKET_META"] or 0) + (newStats["SOCKET_PRISMATIC"] or 0)

            bestOutcome = {
                itemLink = itemLink,
                slot = slotID,
                slotName = SLOT_NAMES[slotID] or ("Slot " .. slotID),
                isUpgrade = scoreDelta > 0.05,
                scoreDiff = scoreDelta,
                pctGain = baseSim.score > 0 and (scoreDelta / baseSim.score) * 100 or 0,
                oldSetScore = baseSim.score,
                newSetScore = newSim.score,
                oldEHP = baseSim.ehp,
                newEHP = newSim.ehp,
                ehpDiff = newSim.ehp - baseSim.ehp,
                replacedItem = replacedItem,
                replacedLink = replacedItem and (type(replacedItem) == "table" and replacedItem.link or replacedItem) or nil,
                capWarnings = capWarnings,
                capGains = capGains,
                sockets = sockets,
                newSim = newSim,
                baseSim = baseSim,
            }
        end
    end

    return bestOutcome
end

--- Scan all bags and bank (if open) to find all items that are upgrades over the target set.
-- @param specData table Optional spec profile
-- @param targetSet table Optional target gear set
-- @return table Sorted list of upgrade predictions
function Sim:PredictAllUpgradesInBags(specData, targetSet)
    specData = specData or (addon.GetActiveSpecData and addon:GetActiveSpecData())
    targetSet = targetSet or self:GetCurrentlyEquippedSet()

    local availableItems = addon:GetAllAvailableItems()
    local upgrades = {}
    local seenLinks = {}

    for _, item in ipairs(availableItems) do
        if item.link and not item.isEquipped and not seenLinks[item.link] then
            seenLinks[item.link] = true
            local pred = self:PredictUpgrade(item.link, targetSet, specData)
            if pred and pred.isUpgrade and pred.scoreDiff >= 0.5 then
                table.insert(upgrades, pred)
            end
        end
    end

    table.sort(upgrades, function(a, b)
        return a.scoreDiff > b.scoreDiff
    end)

    return upgrades
end

--- Identify the weakest gear slots in a set to highlight upgrade priorities.
-- @param gearSet table Gear set table (defaults to equipped)
-- @param specData table Optional spec profile
-- @return table Sorted array of slots with lowest score or item level
function Sim:FindWeakestSlots(gearSet, specData)
    specData = specData or (addon.GetActiveSpecData and addon:GetActiveSpecData())
    gearSet = gearSet or self:GetCurrentlyEquippedSet()

    local sim = self:SimulateGearSet(gearSet, specData)
    local slotsAnalysis = {}

    for slotID = 1, 18 do
        -- Skip shirts and tabards
        if slotID ~= 4 and slotID ~= 19 then
            local item = sim.items[slotID]
            local sc = item and item.score or 0
            local ilvl = item and item.iLevel or 0
            table.insert(slotsAnalysis, {
                slot = slotID,
                slotName = SLOT_NAMES[slotID] or ("Slot " .. slotID),
                item = item,
                score = sc,
                iLevel = ilvl,
                link = item and item.link or nil,
                isEmpty = (item == nil),
            })
        end
    end

    -- Sort by lowest score first
    table.sort(slotsAnalysis, function(a, b)
        if a.isEmpty ~= b.isEmpty then return a.isEmpty end
        return a.score < b.score
    end)

    return slotsAnalysis
end

-- ============================================================================
-- ENCOUNTER PROFILE SIMULATION
-- ============================================================================

--- Simulate a gear set's viability against specific PvE/PvP encounter archetypes.
-- @param gearSet table Gear set table
-- @param encounterType string "RAID_BOSS" | "DUNGEON_HEROIC" | "SURVIVAL_TANK" | "PVP_ARENA"
-- @param specData table Optional spec profile
-- @return table Encounter simulation diagnostic result
function Sim:SimulateEncounter(gearSet, encounterType, specData)
    encounterType = encounterType or "RAID_BOSS"
    specData = specData or (addon.GetActiveSpecData and addon:GetActiveSpecData())
    local sim = self:SimulateGearSet(gearSet, specData)

    local report = {
        encounterType = encounterType,
        sim = sim,
        passed = true,
        checks = {},
        summary = "",
    }

    if encounterType == "RAID_BOSS" then
        report.title = "Level 83 Raid Boss Encounter"
        local hitCheck = {
            name = "Hit Cap (Melee 8% / Spell 17%)",
            required = (sim.role == "caster" or sim.role == "healer") and 17.0 or 8.0,
            actual = (sim.role == "caster" or sim.role == "healer") and sim.ratings.spellHitPct or sim.ratings.meleeHitPct,
        }
        hitCheck.met = hitCheck.actual >= hitCheck.required
        table.insert(report.checks, hitCheck)

        if sim.role == "tank" or sim.role == "tank_barrier" or sim.role == "tank_druid" then
            local defCheck = {
                name = "Crit Immunity (540 Defense Skill)",
                required = 540,
                actual = sim.caps.defense.current,
                met = sim.caps.defense.status == "CAPPED",
            }
            table.insert(report.checks, defCheck)
            if not defCheck.met then report.passed = false end
        end

        if not hitCheck.met then report.passed = false end

    elseif encounterType == "SURVIVAL_TANK" then
        report.title = "High Physical Mitigation / Survival"
        local defCheck = {
            name = "Defense Cap (540)",
            required = 540,
            actual = sim.caps.defense.current,
            met = sim.caps.defense.status == "CAPPED",
        }
        local armorCheck = {
            name = "Armor Damage Reduction (60%+)",
            required = 60.0,
            actual = sim.armorDR,
            met = sim.armorDR >= 60.0,
        }
        table.insert(report.checks, defCheck)
        table.insert(report.checks, armorCheck)
        report.passed = defCheck.met and armorCheck.met

    elseif encounterType == "PVP_ARENA" then
        report.title = "PvP Arena / Battleground (Crit Reduction)"
        local resilCheck = {
            name = "Resilience Crit Reduction (5.6%+)",
            required = 5.6,
            actual = sim.ratings.resiliencePct,
            met = sim.ratings.resiliencePct >= 5.6,
        }
        table.insert(report.checks, resilCheck)
        report.passed = resilCheck.met
    end

    report.summary = report.passed
        and "|cFF00FF00Ready for " .. report.title .. "! All critical thresholds met.|r"
        or "|cFFFF4444Deficiencies detected for " .. report.title .. ". Review cap requirements below.|r"

    return report
end

-- ============================================================================
-- DEVTOOL DIAGNOSTICS & GLOBAL EXPOSURE
-- ============================================================================

--- Run comprehensive self-diagnostics and benchmark suite for DevTool inspection.
-- @return table Diagnostics result table
function Sim:RunDiagnostics()
    local diag = {
        timestamp = date and date("%Y-%m-%d %H:%M:%S") or "now",
        version = addon.version or "1.1.0",
        equippedSim = self:SimulateGearSet(self:GetCurrentlyEquippedSet()),
        availableSets = self:GetAllSimulatedSets(),
        bagUpgrades = self:PredictAllUpgradesInBags(),
        weakestSlots = self:FindWeakestSlots(),
        bossEncounter = self:SimulateEncounter(self:GetCurrentlyEquippedSet(), "RAID_BOSS"),
        pvpEncounter = self:SimulateEncounter(self:GetCurrentlyEquippedSet(), "PVP_ARENA"),
    }
    return diag
end

-- ============================================================================
-- IN-GAME SIMULATION & UPGRADE PREDICTION UI PANEL
-- ============================================================================

local simFrame = nil

function Sim:CreateUI()
    if simFrame then return simFrame end

    local FRAME_WIDTH, FRAME_HEIGHT = 580, 520
    simFrame = CreateFrame("Frame", "CharacterGearOptimizerSimFrame", UIParent, BACKDROP_TEMPLATE)
    simFrame:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
    simFrame:SetPoint("CENTER", UIParent, "CENTER", 40, 20)
    simFrame:SetFrameStrata("DIALOG")
    simFrame:SetMovable(true)
    simFrame:EnableMouse(true)
    simFrame:RegisterForDrag("LeftButton")
    simFrame:SetScript("OnDragStart", simFrame.StartMoving)
    simFrame:SetScript("OnDragStop", simFrame.StopMovingOrSizing)
    simFrame:Hide()

    ApplyBackdrop(simFrame, {
        bgFile   = "Interface/DialogFrame/UI-DialogBox-Background",
        edgeFile = "Interface/DialogFrame/UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    }, { 0.05, 0.02, 0.02, 0.96 }, { 0.55, 0.45, 0.25, 1 })

    -- Title
    local title = simFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -14)
    title:SetText("|cFFFFD700Multi-Set Simulation & Upgrade Predictor|r")

    local subtitle = simFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
    subtitle:SetText("Compare gear sets side-by-side, predict item upgrades, and diagnose cap compliance.")

    local closeBtn = CreateFrame("Button", nil, simFrame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", simFrame, "TOPRIGHT", -4, -4)

    -- Tabs: [1] Set Comparison, [2] Bag Upgrades & Weak Slots, [3] Encounter Diagnostics
    local currentTab = 1
    local tabButtons = {}

    local function SetTab(tabIdx)
        currentTab = tabIdx
        for idx, btn in ipairs(tabButtons) do
            if idx == tabIdx then
                btn:LockHighlight()
            else
                btn:UnlockHighlight()
            end
        end
        if simFrame.RefreshView then simFrame:RefreshView() end
    end

    local tabNames = { "Set Comparison", "Upgrade Predictor", "Encounter Diagnostics" }
    for idx, tName in ipairs(tabNames) do
        local btn = CreateFrame("Button", nil, simFrame, "UIPanelButtonTemplate")
        btn:SetSize(150, 22)
        btn:SetPoint("TOPLEFT", simFrame, "TOPLEFT", 16 + (idx - 1) * 156, -42)
        btn:SetText(tName)
        btn:SetScript("OnClick", function() SetTab(idx) end)
        tabButtons[idx] = btn
    end

    -- Scrollable Content Area
    local scrollFrame = CreateFrame("ScrollFrame", "CGOSimScrollFrame", simFrame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", simFrame, "TOPLEFT", 14, -72)
    scrollFrame:SetPoint("BOTTOMRIGHT", simFrame, "BOTTOMRIGHT", -32, 14)

    local content = CreateFrame("Frame", "CGOSimScrollContent", scrollFrame)
    content:SetWidth(FRAME_WIDTH - 50)
    content:SetHeight(1)
    scrollFrame:SetScrollChild(content)

    simFrame.content = content
    simFrame.scrollFrame = scrollFrame

    -- Dynamic view renderer
    function simFrame:RefreshView()
        -- Clear old child widgets in content
        local children = { content:GetChildren() }
        for _, child in ipairs(children) do
            child:Hide()
            child:SetParent(nil)
        end
        local regions = { content:GetRegions() }
        for _, region in ipairs(regions) do
            if region:IsObjectType("FontString") or region:IsObjectType("Texture") then
                region:Hide()
            end
        end

        local y = 0
        local specData = addon:GetActiveSpecData()
        local sets = Sim:GetAllSimulatedSets(specData)

        if currentTab == 1 then
            -- ================================================================
            -- TAB 1: SET COMPARISON MATRIX
            -- ================================================================
            local header = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            header:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
            header:SetText("|cFFFFD700All Available Gear Sets (Ranked by Score):|r")
            y = y + 22

            table.sort(sets, function(a, b) return a.sim.score > b.sim.score end)

            for rank, sInfo in ipairs(sets) do
                local row = CreateFrame("Frame", nil, content, BACKDROP_TEMPLATE)
                row:SetSize(FRAME_WIDTH - 52, 44)
                row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
                ApplyBackdrop(row, {
                    bgFile = "Interface/Buttons/WHITE8x8",
                    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
                    edgeSize = 8,
                    insets = { left = 2, right = 2, top = 2, bottom = 2 },
                }, { 0.08, 0.04, 0.04, 0.8 }, { 0.55, 0.45, 0.25, 0.8 })

                local icon = row:CreateTexture(nil, "ARTWORK")
                icon:SetSize(32, 32)
                icon:SetPoint("LEFT", row, "LEFT", 6, 0)
                icon:SetTexture(sInfo.icon)

                local nameFS = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                nameFS:SetPoint("TOPLEFT", icon, "TOPRIGHT", 8, -2)
                nameFS:SetText(string.format("#%d %s", rank, sInfo.name))

                local statsFS = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                statsFS:SetPoint("BOTTOMLEFT", icon, "TOPRIGHT", 8, -26)
                statsFS:SetText(string.format("Score: |cFFFFD700%.1f|r | Avg iLvl: |cFFFFFFFF%.1f|r | EHP: |cFF00FF00%s|r | Armor DR: %.1f%%",
                    sInfo.sim.score, sInfo.sim.avgItemLevel, BreakUpLargeNumbers and BreakUpLargeNumbers(sInfo.sim.ehp) or sInfo.sim.ehp, sInfo.sim.armorDR))

                local equipBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
                equipBtn:SetSize(70, 20)
                equipBtn:SetPoint("RIGHT", row, "RIGHT", -6, 0)
                equipBtn:SetText("Equip")
                equipBtn:SetScript("OnClick", function()
                    if sInfo.type == "SAVED" then
                        addon:EquipSet(sInfo.name)
                    elseif sInfo.type == "OPTIMIZED" then
                        if addon.PopulateSlots then addon:PopulateSlots(sInfo.set) end
                        print("|cFFFFD700CGO:|r Loaded optimized set into gear panel.")
                    end
                end)
                if sInfo.type == "EQUIPPED" then equipBtn:Disable() end

                y = y + 48
            end

            -- Side-by-side comparison between Top Set and Equipped
            local equippedSet = Sim:GetCurrentlyEquippedSet()
            local bestSet = sets[1] and sets[1].set
            if bestSet then
                y = y + 10
                local compHeader = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                compHeader:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
                compHeader:SetText(string.format("|cFFFFD700Comparison: Equipped vs Best Set (%s)|r", sets[1].name))
                y = y + 20

                local comp = Sim:CompareSets(equippedSet, bestSet, specData, "Equipped", sets[1].name)
                local verdictFS = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                verdictFS:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
                verdictFS:SetText(comp.verdict .. "\n|cFFCCCCCC" .. comp.recommendation .. "|r")
                y = y + 36

                -- Slot differences list
                if #comp.slotDiffs > 0 then
                    for _, sd in ipairs(comp.slotDiffs) do
                        local sLine = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                        sLine:SetPoint("TOPLEFT", content, "TOPLEFT", 10, -y)
                        local linkA = sd.itemA and sd.itemA.link or "(Empty)"
                        local linkB = sd.itemB and sd.itemB.link or "(Empty)"
                        local diffCol = sd.diff >= 0 and "|cFF00FF00+" or "|cFFFF4444"
                        sLine:SetText(string.format("• |cFFFFD700%s:|r %s -> %s (%s%.1f Score|r)", sd.slotName, linkA, linkB, diffCol, sd.diff))
                        y = y + 16
                    end
                else
                    local sLine = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                    sLine:SetPoint("TOPLEFT", content, "TOPLEFT", 10, -y)
                    sLine:SetText("No item differences. Equipped set is already optimal!")
                    y = y + 16
                end
            end

        elseif currentTab == 2 then
            -- ================================================================
            -- TAB 2: UPGRADE PREDICTOR & ROADMAP
            -- ================================================================
            local upHeader = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            upHeader:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
            upHeader:SetText("|cFFFFD700Available Upgrades in Bags & Bank (Ranked by Gain):|r")
            y = y + 22

            local upgrades = Sim:PredictAllUpgradesInBags(specData)
            if #upgrades > 0 then
                for idx, up in ipairs(upgrades) do
                    local row = CreateFrame("Frame", nil, content, BACKDROP_TEMPLATE)
                    row:SetSize(FRAME_WIDTH - 52, 40)
                    row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
                    ApplyBackdrop(row, {
                        bgFile = "Interface/Buttons/WHITE8x8",
                        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
                        edgeSize = 8,
                        insets = { left = 2, right = 2, top = 2, bottom = 2 },
                    }, { 0.08, 0.04, 0.04, 0.8 }, { 0.25, 0.55, 0.25, 0.8 })

                    local itemName, _, _, _, _, _, _, _, _, tex = GetItemInfo(up.itemLink)
                    local icon = row:CreateTexture(nil, "ARTWORK")
                    icon:SetSize(28, 28)
                    icon:SetPoint("LEFT", row, "LEFT", 6, 0)
                    icon:SetTexture(tex or "Interface/Icons/INV_Misc_QuestionMark")

                    local titleFS = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                    titleFS:SetPoint("TOPLEFT", icon, "TOPRIGHT", 8, -2)
                    titleFS:SetText(string.format("%s for |cFFFFD700%s|r (|cFF00FF00+%.1f Score / +%.1f%%|r)",
                        up.itemLink, up.slotName, up.scoreDiff, up.pctGain))

                    local repFS = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                    repFS:SetPoint("BOTTOMLEFT", icon, "TOPRIGHT", 8, -22)
                    local repName = up.replacedLink or "(Empty)"
                    repFS:SetText(string.format("Replaces: %s | EHP Gain: |cFF00FF00%+d|r", repName, up.ehpDiff))

                    y = y + 44
                end
            else
                local noneFS = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                noneFS:SetPoint("TOPLEFT", content, "TOPLEFT", 10, -y)
                noneFS:SetText("No direct item upgrades found in current bags or bank.")
                y = y + 20
            end

            -- Weakest Slots Roadmap
            y = y + 10
            local weakHeader = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            weakHeader:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
            weakHeader:SetText("|cFFFFD700Weakest Equipped Slots (Upgrade Bottlenecks):|r")
            y = y + 22

            local weakSlots = Sim:FindWeakestSlots(nil, specData)
            for idx = 1, math.min(5, #weakSlots) do
                local ws = weakSlots[idx]
                local line = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                line:SetPoint("TOPLEFT", content, "TOPLEFT", 10, -y)
                local itText = ws.link or "|cFFFF0000(Empty Slot)|r"
                line:SetText(string.format("%d. |cFFFFD700%s:|r %s (Score: %.1f | iLvl: %d)", idx, ws.slotName, itText, ws.score, ws.iLevel))
                y = y + 18
            end

        elseif currentTab == 3 then
            -- ================================================================
            -- TAB 3: ENCOUNTER PROFILE DIAGNOSTICS
            -- ================================================================
            local encs = { "RAID_BOSS", "SURVIVAL_TANK", "PVP_ARENA" }
            for _, encType in ipairs(encs) do
                local report = Sim:SimulateEncounter(nil, encType, specData)
                local box = CreateFrame("Frame", nil, content, BACKDROP_TEMPLATE)
                box:SetSize(FRAME_WIDTH - 52, 90)
                box:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
                ApplyBackdrop(box, {
                    bgFile = "Interface/Buttons/WHITE8x8",
                    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
                    edgeSize = 8,
                    insets = { left = 2, right = 2, top = 2, bottom = 2 },
                }, { 0.08, 0.04, 0.04, 0.8 }, { 0.55, 0.45, 0.25, 0.8 })

                local tFS = box:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                tFS:SetPoint("TOPLEFT", 8, -6)
                tFS:SetText(report.title)

                local sFS = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                sFS:SetPoint("TOPLEFT", tFS, "BOTTOMLEFT", 0, -4)
                sFS:SetText(report.summary)

                local byOff = 44
                for _, chk in ipairs(report.checks) do
                    local cFS = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                    cFS:SetPoint("TOPLEFT", box, "TOPLEFT", 16, -byOff)
                    local iconStr = chk.met and "|cFF00FF00[PASS]|r" or "|cFFFF4444[FAIL]|r"
                    cFS:SetText(string.format("%s %s: Current |cFFFFD700%.1f|r (Required %.1f)", iconStr, chk.name, chk.actual, chk.required))
                    byOff = byOff + 16
                end

                y = y + 98
            end
        end

        content:SetHeight(math.max(y + 20, 300))
    end

    simFrame:SetScript("OnShow", function(self)
        SetTab(currentTab)
    end)

    return simFrame
end

function addon:OpenSimulationPanel()
    local frame = Sim:CreateUI()
    if frame then
        if frame:IsShown() then frame:Hide() else frame:Show() end
    end
end
