-- ============================================================================
-- CharacterGearOptimizer: TooltipHook.lua
-- Hooks GameTooltip and ItemRefTooltip to show weighted stat comparison
-- vs currently equipped gear using the active spec/custom profile weights.
-- Handles dual-slot items (rings/trinkets), gems, and tank EHP.
-- ============================================================================

local addonName, addon = ...

-- ============================================================================
-- UTILITY: Get equipped item link for an item's equip slot
-- ============================================================================
function addon:GetEquippedItemForSlot(itemLink)
    if not itemLink then return nil, nil end
    local _, _, _, _, _, _, _, _, equipLoc = GetItemInfo(itemLink)
    if not equipLoc or equipLoc == "" then return nil, nil end
    local slotID = addon.SLOT_MAP[equipLoc]
    if not slotID then return nil, nil end
    return GetInventoryItemLink("player", slotID), slotID
end

-- ============================================================================
-- UTILITY: Check if item is a dual-slot equip (ring or trinket)
-- ============================================================================
function addon:GetDualSlots(itemLink)
    if not itemLink then return nil, nil end
    local _, _, _, _, _, _, _, _, equipLoc = GetItemInfo(itemLink)
    if equipLoc == "INVTYPE_FINGER" then
        return 11, 12
    elseif equipLoc == "INVTYPE_TRINKET" then
        return 13, 14
    end
    return nil, nil
end

-- ============================================================================
-- UTILITY: Check if item is a gem
-- ============================================================================
function addon:IsGem(itemLink)
    if not itemLink then return false end
    -- 3.3.5 GetItemInfo has no classID return; use the itemType string
    local _, _, _, _, _, itemType = GetItemInfo(itemLink)
    return itemType == "Gem"
end

local function IsTwoHandLink(link)
    if not link then return false end
    local _, _, _, _, _, itemType, itemSubType, _, equipLoc = GetItemInfo(link)
    if equipLoc == "INVTYPE_2HWEAPON" then return true end
    if itemType == "Weapon" and (itemSubType == "Staves" or itemSubType == "Staff") then
        return true
    end
    return false
end

local function ScoreLink(link, specData)
    if not link or not specData then return 0 end
    return addon:CalculateScore(addon:ExtractItemStats(link), specData)
end

-- Positive diff means the item is an upgrade for at least one valid slot.
function addon:GetUpgradeScoreDiff(itemLink, specData)
    if not itemLink or not specData then return 0 end
    if not IsEquippableItem or not IsEquippableItem(itemLink) then return 0 end

    local _, _, _, _, _, _, _, _, equipLoc = GetItemInfo(itemLink)
    if not equipLoc or equipLoc == "" then return 0 end
    if equipLoc == "INVTYPE_BODY" or equipLoc == "INVTYPE_TABARD" then return 0 end

    local newScore = ScoreLink(itemLink, specData)
    local slotA, slotB = addon:GetDualSlots(itemLink)
    if slotA and slotB then
        local scoreA = ScoreLink(GetInventoryItemLink("player", slotA), specData)
        local scoreB = ScoreLink(GetInventoryItemLink("player", slotB), specData)
        return newScore - math.min(scoreA, scoreB)
    end

    if equipLoc == "INVTYPE_2HWEAPON" then
        local mh = GetInventoryItemLink("player", 16)
        local oh = GetInventoryItemLink("player", 17)
        return newScore - (ScoreLink(mh, specData) + ScoreLink(oh, specData))
    end

    if equipLoc == "INVTYPE_WEAPON" then
        local mh = GetInventoryItemLink("player", 16)
        local oh = GetInventoryItemLink("player", 17)
        local mhDiff = newScore - ScoreLink(mh, specData)
        if oh and not IsTwoHandLink(GetInventoryItemLink("player", 16)) then
            local _, _, _, _, _, _, _, _, ohLoc = GetItemInfo(oh)
            if ohLoc == "INVTYPE_WEAPON" or ohLoc == "INVTYPE_WEAPONOFFHAND" then
                return math.max(mhDiff, newScore - ScoreLink(oh, specData))
            end
        end
        return mhDiff
    end

    local equippedLink, slotID = addon:GetEquippedItemForSlot(itemLink)
    if (equipLoc == "INVTYPE_SHIELD" or equipLoc == "INVTYPE_HOLDABLE" or equipLoc == "INVTYPE_WEAPONOFFHAND") then
        local mh = GetInventoryItemLink("player", 16)
        if mh and IsTwoHandLink(mh) and not (addon.ShouldForceShieldTank and addon:ShouldForceShieldTank(specData)) then
            return 0
        end
        equippedLink = GetInventoryItemLink("player", 17)
        slotID = 17
    end

    if not slotID then return 0 end
    return newScore - ScoreLink(equippedLink, specData)
end

-- ============================================================================
-- GET ACTIVE SPEC DATA (from dropdown selection or auto-detect)
-- Returns the specData table with .name, .role, .weights, .gemValue, .metaValue
-- ============================================================================
function addon:GetActiveSpecData()
    if addon.currentCustomProfile then
        return addon.currentCustomProfile
    elseif addon.currentClass and addon.currentSpecIdx and addon.currentSpecIdx > 0 then
        -- HERO weights are derived from the live Ascension character stats.
        -- Refresh them here as well as in the optimizer so tooltips never
        -- read the intentionally-empty profile templates after login/reload.
        if addon.currentClass == "HERO" and addon.RefreshAscensionHeroWeights then
            addon:RefreshAscensionHeroWeights(addon.currentSpecIdx)
        end
        return addon.CLASS_SPECS[addon.currentClass] and addon.CLASS_SPECS[addon.currentClass][addon.currentSpecIdx]
    elseif addon.autoDetectedSpec then
        if addon.currentClass == "HERO" and addon.autoDetectedSpecIdx and addon.RefreshAscensionHeroWeights then
            addon:RefreshAscensionHeroWeights(addon.autoDetectedSpecIdx)
            return addon.CLASS_SPECS.HERO and addon.CLASS_SPECS.HERO[addon.autoDetectedSpecIdx]
        end
        return addon.autoDetectedSpec
    end
    return nil
end

-- Return the rendered comparison tooltip for an equipped link. Ascension's
-- scaled items can report different values through GetItemStats(itemLink).
local function GetRenderedEquippedTooltip(equippedLink)
    if not equippedLink then return nil end
    local equippedID = tonumber(equippedLink:match("item:(%d+)"))
    for _, comparison in ipairs({ ShoppingTooltip1, ShoppingTooltip2 }) do
        if comparison then
            local _, comparisonLink = comparison:GetItem()
            local comparisonID = comparisonLink and tonumber(comparisonLink:match("item:(%d+)"))
            if comparisonID and comparisonID == equippedID then return comparison end
        end
    end
    return nil
end

-- ============================================================================
-- MAIN TOOLTIP HOOK
-- ============================================================================
local function OnTooltipSetItem(tooltip)
    if CharacterGearOptimizerDB and CharacterGearOptimizerDB.enableTooltips == false then
        return
    end

    local specData = addon:GetActiveSpecData()
    if not specData then return end

    local _, itemLink = tooltip:GetItem()
    if not itemLink then return end

    local _, playerClass = UnitClass("player")
    local color = addon.CLASS_COLORS and addon.CLASS_COLORS[playerClass] or "FFFFFF"

    -- ---- Gem handling ----
    if addon:IsGem(itemLink) then
        local gemScore, gemBreakdown = addon:ScoreGem(itemLink, specData)
        if gemScore == 0 and #gemBreakdown == 0 then return end

        -- Prevent adding our lines twice
        local tName = tooltip:GetName()
        for i = 1, 30 do
            local line = _G[tName .. "TextLeft" .. i]
            if line and line:GetText() and line:GetText():find("%[CGO%]") then return end
        end

        tooltip:AddLine(" ")
        tooltip:AddLine(string.format("|cff%s[CGO] %s|r", color, specData.name))

        for _, entry in ipairs(gemBreakdown) do
            tooltip:AddDoubleLine(
                string.format("  %s (x%.2f):", entry.label, entry.weight),
                string.format("|cff00ff00%d|r = |cff00ff00%.1f|r", entry.raw, entry.weighted),
                0.7, 0.7, 0.7
            )
        end

        tooltip:AddLine(" ")
        tooltip:AddDoubleLine(
            "|cffffd700Gem Score:|r",
            string.format("|cff00ff00%.1f|r", gemScore),
            1, 1, 1
        )
        tooltip:Show()
        return
    end

    -- ---- Non-equippable items: skip ----
    if not IsEquippableItem(itemLink) then return end

    -- Prevent double-adding
    local tName = tooltip:GetName()
    for i = 1, 30 do
        local line = _G[tName .. "TextLeft" .. i]
        if line and line:GetText() and line:GetText():find("%[CGO%]") then return end
    end

    -- ---- Extract stats for the hovered item ----
    local newStats  = addon:ExtractItemStats(itemLink, tooltip)
    local newScore  = addon:CalculateScore(newStats, specData)
    local newBreak  = addon:BuildBreakdown(newStats, specData)

    -- Skip items with no extractable stats at all (cosmetic / quest items)
    if not newStats or not next(newStats) then return end

    -- ---- Dual-slot items (rings / trinkets): compare vs BOTH slots ----
    local slotA, slotB = addon:GetDualSlots(itemLink)
    if slotA and slotB then
        -- Hide the game's built-in "Currently Equipped" shopping tooltips
        if ShoppingTooltip1 then ShoppingTooltip1:Hide() end
        if ShoppingTooltip2 then ShoppingTooltip2:Hide() end

        local linkA = GetInventoryItemLink("player", slotA)
        local linkB = GetInventoryItemLink("player", slotB)

        local slotLabels = { [11] = "Ring 1", [12] = "Ring 2", [13] = "Trinket 1", [14] = "Trinket 2" }

        for idx, eqLink in ipairs({ linkA, linkB }) do
            local slotID    = idx == 1 and slotA or slotB
            local slotLabel = slotLabels[slotID] or ("Slot " .. slotID)
            local eqName    = ""
            if eqLink then
                eqName = GetItemInfo(eqLink) or "?"
            else
                eqName = "(empty)"
            end

            local eqStats  = addon:ExtractItemStats(eqLink)
            local eqScore  = addon:CalculateScore(eqStats, specData)
            local eqBreak  = addon:BuildBreakdown(eqStats, specData)
            local sDiff    = newScore - eqScore

            tooltip:AddLine(" ")
            tooltip:AddLine(string.format("|cff%s[CGO] %s|r  vs |cffffd700%s|r: %s",
                color, specData.name, slotLabel, eqName))

            addon:AddStatDiffs(tooltip, newStats, newBreak, eqStats, eqBreak, specData)
            addon:AddSocketDiffs(tooltip, newStats, eqStats, specData)

            local tc = sDiff >= 0 and "|cff00ff00" or "|cffff0000"
            tooltip:AddLine(" ")
            tooltip:AddDoubleLine(
                "|cffffd700Weighted Score:|r",
                string.format("%s%+.1f|r  (%.1f vs %.1f)", tc, sDiff, newScore, eqScore),
                1, 1, 1
            )

            addon:AddTankEHPTooltip(tooltip, newStats, eqStats, specData)
        end

        tooltip:Show()
        return
    end

    -- ---- Single-slot item comparison ----
    -- 2H weapons must be compared against MH + OH combined.
    local _, _, _, _, _, _, _, _, hoveredEquipLoc = GetItemInfo(itemLink)
    local is2H = (hoveredEquipLoc == "INVTYPE_2HWEAPON")

    if is2H then
        -- Compare 2H vs mainhand + offhand combined
        local mhLink = GetInventoryItemLink("player", 16)
        local ohLink = GetInventoryItemLink("player", 17)
        local mhStats = addon:ExtractItemStats(mhLink)
        local ohStats = addon:ExtractItemStats(ohLink)

        -- Combine MH + OH stats into one table
        local equippedStats = {}
        for k, v in pairs(mhStats) do equippedStats[k] = v end
        for k, v in pairs(ohStats) do equippedStats[k] = (equippedStats[k] or 0) + v end

        local equippedScore = addon:CalculateScore(mhStats, specData) + addon:CalculateScore(ohStats, specData)
        local equippedBreak = addon:BuildBreakdown(equippedStats, specData)
        local scoreDiff     = newScore - equippedScore

        local mhName = mhLink and (GetItemInfo(mhLink) or "?") or "(empty)"
        local ohName = ohLink and (GetItemInfo(ohLink) or "?") or "(empty)"

        tooltip:AddLine(" ")
        tooltip:AddLine(string.format("|cff%s[CGO] %s|r  vs |cffffd700MH+OH|r", color, specData.name))
        tooltip:AddLine(string.format("  |cffffd700MH:|r %s  +  |cffffd700OH:|r %s", mhName, ohName), 0.7, 0.7, 0.7)

        addon:AddStatDiffs(tooltip, newStats, newBreak, equippedStats, equippedBreak, specData)
        addon:AddSocketDiffs(tooltip, newStats, equippedStats, specData)

        tooltip:AddLine(" ")
        local totalColor = scoreDiff >= 0 and "|cff00ff00" or "|cffff0000"
        tooltip:AddDoubleLine(
            "|cffffd700Weighted Score:|r",
            string.format("%s%+.1f|r  (%.1f vs %.1f)", totalColor, scoreDiff, newScore, equippedScore),
            1, 1, 1
        )

        addon:AddTankEHPTooltip(tooltip, newStats, equippedStats, specData)
    else
        local equippedLink    = addon:GetEquippedItemForSlot(itemLink)
        local equippedStats   = addon:ExtractItemStats(equippedLink, GetRenderedEquippedTooltip(equippedLink))
        local equippedScore   = addon:CalculateScore(equippedStats, specData)
        local equippedBreak   = addon:BuildBreakdown(equippedStats, specData)
        local scoreDiff       = newScore - equippedScore

        -- Header
        tooltip:AddLine(" ")
        tooltip:AddLine(string.format("|cff%s[CGO] %s|r", color, specData.name))

        -- Per-stat diffs
        addon:AddStatDiffs(tooltip, newStats, newBreak, equippedStats, equippedBreak, specData)

        -- Socket diffs
        addon:AddSocketDiffs(tooltip, newStats, equippedStats, specData)

        -- Total weighted score
        tooltip:AddLine(" ")
        local totalColor = scoreDiff >= 0 and "|cff00ff00" or "|cffff0000"
        tooltip:AddDoubleLine(
            "|cffffd700Weighted Score:|r",
            string.format("%s%+.1f|r  (%.1f vs %.1f)", totalColor, scoreDiff, newScore, equippedScore),
            1, 1, 1
        )

        -- Tank EHP section
        addon:AddTankEHPTooltip(tooltip, newStats, equippedStats, specData)
    end

    tooltip:Show()
end

-- ============================================================================
-- HOOK TOOLTIPS (on PLAYER_LOGIN so frames exist)
-- ============================================================================
addon._isDualSlotHover = false

local hookFrame = CreateFrame("Frame")
hookFrame:RegisterEvent("PLAYER_LOGIN")
hookFrame:SetScript("OnEvent", function(self)
    -- Modern Retail TooltipDataProcessor (10.0.2+ / The War Within / Midnight)
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
            if not tooltip or (tooltip.IsForbidden and tooltip:IsForbidden()) then return end
            OnTooltipSetItem(tooltip)
        end)
    else
        -- Classic / Legacy HookScript
        if GameTooltip then
            GameTooltip:HookScript("OnTooltipSetItem", function(self)
                local _, link = self:GetItem()
                if link then
                    local sA, sB = addon:GetDualSlots(link)
                    addon._isDualSlotHover = (sA ~= nil)
                else
                    addon._isDualSlotHover = false
                end
                OnTooltipSetItem(self)
            end)

            GameTooltip:HookScript("OnTooltipCleared", function()
                addon._isDualSlotHover = false
            end)
        end

        if ItemRefTooltip then
            ItemRefTooltip:HookScript("OnTooltipSetItem", OnTooltipSetItem)
        end
    end

    -- Hide shopping (comparison) tooltips for dual-slot items
    if ShoppingTooltip1 then
        ShoppingTooltip1:HookScript("OnShow", function(self)
            if addon._isDualSlotHover then self:Hide() end
        end)
    end
    if ShoppingTooltip2 then
        ShoppingTooltip2:HookScript("OnShow", function(self)
            if addon._isDualSlotHover then self:Hide() end
        end)
    end
    self:UnregisterEvent("PLAYER_LOGIN")
end)
