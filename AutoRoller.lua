local addonName, addon = ...

local ONE_GOLD = 10000
local UPGRADE_EPSILON = 0.05
local ROLL_PASS, ROLL_NEED, ROLL_GREED = 0, 1, 2

local pendingRolls = {}

function addon:IsAutoRollEnabled()
    local db = CharacterGearOptimizerDB
    if not db then return true end
    if db.autoRoll == nil then return true end
    return db.autoRoll and true or false
end

function addon:SetAutoRollEnabled(enabled)
    CharacterGearOptimizerDB = CharacterGearOptimizerDB or {}
    CharacterGearOptimizerDB.autoRoll = enabled and true or false
    local cb = _G["CGOCap_AutoRoll"]
    if cb then cb:SetChecked(CharacterGearOptimizerDB.autoRoll) end
end

local function PlayerCanWear(link)
    if not link then return false end
    if IsEquippableItem and not IsEquippableItem(link) then return false end

    local _, _, _, _, minLevel, itemType, itemSubType, _, equipLoc = GetItemInfo(link)
    if minLevel and minLevel > UnitLevel("player") then return false end
    if not equipLoc or equipLoc == "" or not addon.SLOT_MAP[equipLoc] then return false end

    local _, playerClass = UnitClass("player")

    if addon.ARMOR_EQUIP_LOCS and addon.ARMOR_EQUIP_LOCS[equipLoc] then
        if itemType == "Armor" and itemSubType ~= "Miscellaneous" then
            local spec = addon.GetActiveSpecData and addon:GetActiveSpecData()
            local preferred = spec and spec.preferredArmor
            if preferred then
                return preferred[itemSubType] == true
            end
            local proficiency = addon.CLASS_ARMOR_PROFICIENCY and addon.CLASS_ARMOR_PROFICIENCY[playerClass]
            if proficiency then
                return proficiency[itemSubType] == true
            end
        end
    end

    if equipLoc == "INVTYPE_SHIELD" then
        return addon.CLASS_SHIELD_PROFICIENCY and addon.CLASS_SHIELD_PROFICIENCY[playerClass] == true
    end

    if itemType == "Weapon" then
        local weaponProf = addon.CLASS_WEAPON_PROFICIENCY and addon.CLASS_WEAPON_PROFICIENCY[playerClass]
        if weaponProf then
            return weaponProf[itemSubType] == true
        end
    end

    if equipLoc == "INVTYPE_RELIC" then
        local relicProf = addon.CLASS_RELIC_PROFICIENCY and addon.CLASS_RELIC_PROFICIENCY[playerClass]
        if not relicProf then return false end
        return relicProf[itemSubType] == true
    end

    return true
end

local function ScanTooltipText(link)
    if not link then return "" end
    local tip = addon.scanTooltip
    if not tip then return "" end
    tip:SetOwner(WorldFrame, "ANCHOR_NONE")
    tip:ClearLines()
    tip:SetHyperlink(link)
    local parts = {}
    for i = 1, tip:NumLines() do
        local left = _G["CGOScanTooltipTextLeft" .. i]
        if left then
            parts[#parts + 1] = left:GetText() or ""
        end
    end
    return table.concat(parts, "\n"):lower()
end

local function IsSkillCard(link)
    if not link then return false end
    local name, _, _, _, _, itemType, itemSubType = GetItemInfo(link)
    local haystack = string.lower(table.concat({
        name or "",
        itemType or "",
        itemSubType or "",
    }, " "))
    if haystack:find("skill card", 1, true) or haystack:find("skillcard", 1, true) then
        return true
    end
    local tooltip = ScanTooltipText(link)
    if tooltip:find("skill card", 1, true) or tooltip:find("skillcard", 1, true) then
        return true
    end
    return false
end

local function VendorPrice(link)
    local sellPrice = select(11, GetItemInfo(link))
    return tonumber(sellPrice) or 0
end

local function IsHeirloom(link)
    if not link then return false end
    if addon.IsHeirloomItem then
        return addon:IsHeirloomItem(link)
    end
    local _, _, quality = GetItemInfo(link)
    return quality == 7
end

-- ---------------------------------------------------------------------------
-- WEAPON-MODE AWARENESS
-- When the user has pinned a melee mode (dual wield etc.) and/or a ranged
-- mode (thrown/bow-gun), loot that cannot fit those slots is never an
-- upgrade: pass instead of Need. Wands and any other off-hand filler are
-- auto-passed too when a melee mode owns both hands.
-- ---------------------------------------------------------------------------
local MELEE_SLOT_EQUIPLOCS = {
    INVTYPE_WEAPON        = true,
    INVTYPE_WEAPONMAINHAND= true,
    INVTYPE_WEAPONOFFHAND = true,
    INVTYPE_2HWEAPON      = true,
    INVTYPE_SHIELD        = true,
    INVTYPE_HOLDABLE      = true,
}

local RANGED_MODE_EQUIPLOCS = {
    thrown = { INVTYPE_THROWN = true },
    ranged = { INVTYPE_RANGED = true, INVTYPE_RANGEDRIGHT = true },
}

-- Wands share the ranged equip-locs with bows/guns on some servers; identify
-- them by weapon subtype so the two can be told apart.
local function IsWandLink(link)
    if not link then return false end
    local _, _, _, _, _, itemType, itemSubType, _, equipLoc = GetItemInfo(link)
    if equipLoc == "INVTYPE_WAND" then return true end
    return itemType == "Weapon" and (itemSubType == "Wands" or itemSubType == "Wand")
end

local function ItemEquipLoc(link)
    local _, _, _, _, _, _, _, _, equipLoc = GetItemInfo(link)
    return equipLoc
end

local function IsDaggerLink(link)
    local equipLoc = ItemEquipLoc(link)
    if equipLoc ~= "INVTYPE_WEAPON" and equipLoc ~= "INVTYPE_WEAPONMAINHAND" and equipLoc ~= "INVTYPE_WEAPONOFFHAND" then
        return false
    end

    local function IsStaffLink(link)
        if not link then return false end
        local _, _, _, _, _, itemType, itemSubType = GetItemInfo(link)
        return itemType == "Weapon" and (itemSubType == "Staves" or itemSubType == "Staff")
    end
    local _, _, _, _, _, itemType, itemSubType = GetItemInfo(link)
    return itemType == "Weapon" and itemSubType == "Daggers"
end

-- Returns true when this item's slot is governed by a pinned weapon mode.
local function WeaponModeExcludes(link)
    if not link then return false end
    local equipLoc = ItemEquipLoc(link)
    if not equipLoc then return false end

    -- Ranged-slot items: only relevant when no ranged mode pinned, or pinned mode matches
    if equipLoc == "INVTYPE_THROWN" or equipLoc == "INVTYPE_RANGED" or equipLoc == "INVTYPE_RANGEDRIGHT" then
        local rangedMode = addon.GetSelectedRangedMode and addon:GetSelectedRangedMode()
        local isWand = IsWandLink(link)
        if rangedMode then
            if rangedMode == "wand" then
                -- Wand mode: wands fit, bows/guns don't.
                return not isWand
            end
            if isWand then
                return true -- wand while bow/gun (or thrown) pinned: pass
            end
            local okMap = RANGED_MODE_EQUIPLOCS[rangedMode]
            return not (okMap and okMap[equipLoc])
        end
        return false -- ranged auto: let upgrade logic decide
    end

    -- Wand items that report a dedicated wand equipLoc
    if equipLoc == "INVTYPE_WAND" then
        local meleeMode = addon.GetSelectedWeaponMode and addon:GetSelectedWeaponMode()
        local rangedMode = addon.GetSelectedRangedMode and addon:GetSelectedRangedMode()
        if rangedMode then
            return rangedMode ~= "wand"
        end
        if meleeMode then
            return meleeMode ~= "wand"
        end
        return false
    end

    -- Melee-hand items
    if MELEE_SLOT_EQUIPLOCS[equipLoc] or equipLoc == "INVTYPE_WAND" then
        local meleeMode = addon.GetSelectedWeaponMode and addon:GetSelectedWeaponMode()
        if not meleeMode then
            -- Auto melee mode: keep normal upgrade behavior.
            return false
        end

        if meleeMode == "staff_shield" then
            if equipLoc == "INVTYPE_SHIELD" then return false end
            if equipLoc == "INVTYPE_2HWEAPON" then return not IsStaffLink(link) end
            return true
        end

        if equipLoc == "INVTYPE_WAND" or equipLoc == "INVTYPE_HOLDABLE" then
            -- Wand/held-in-offhand only fits when the pinned mode is wand.
            return meleeMode ~= "wand"
        end

        if meleeMode == "dual_1h" then
            -- Only plain one-handers fit; daggers excluded by design.
            if IsDaggerLink(link) then return true end
            return equipLoc ~= "INVTYPE_WEAPON"
                and equipLoc ~= "INVTYPE_WEAPONMAINHAND"
                and equipLoc ~= "INVTYPE_WEAPONOFFHAND"
        elseif meleeMode == "dual_dagger" then
            return not IsDaggerLink(link)
        elseif meleeMode == "one_2h" or meleeMode == "staff" or meleeMode == "dual_2h" then
            -- Only two-handers fit; everything else passes.
            return equipLoc ~= "INVTYPE_2HWEAPON"
        elseif meleeMode == "1h_shield" then
            -- One-hander + shield; wands already handled above.
            local fitsMH = equipLoc == "INVTYPE_WEAPON"
                or equipLoc == "INVTYPE_WEAPONMAINHAND"
                or equipLoc == "INVTYPE_WEAPONOFFHAND"
            local fitsOH = equipLoc == "INVTYPE_SHIELD"
            return not (fitsMH or fitsOH)
        end
    end

    return false
end

local function DecideRoll(link, canNeed, canGreed)
    local specData = addon.GetActiveSpecData and addon:GetActiveSpecData()

    -- Heirlooms are always wanted while leveling: Need them, never pass.
    if IsHeirloom(link) then
        if canNeed ~= false then
            return ROLL_NEED, "heirloom"
        end
        if canGreed ~= false then
            return ROLL_GREED, "heirloom (need not allowed)"
        end
        return ROLL_PASS, "heirloom but roll not allowed"
    end

    -- Pinned weapon modes: loot that can't fit the selected melee/ranged
    -- loadout is never an upgrade. Wands and other filler weapons are
    -- auto-passed when a dual-wield mode owns both hands.
    if WeaponModeExcludes(link) then
        return ROLL_PASS, "excluded by weapon mode"
    end

    local isUpgrade = false
    local diff = 0
    if specData and PlayerCanWear(link) and addon.GetUpgradeScoreDiff then
        diff = addon:GetUpgradeScoreDiff(link, specData) or 0
        isUpgrade = diff > UPGRADE_EPSILON
    end

    if isUpgrade then
        if canNeed ~= false then
            return ROLL_NEED, string.format("upgrade %+.1f", diff)
        end
        if canGreed ~= false then
            return ROLL_GREED, string.format("upgrade %+.1f (need not allowed)", diff)
        end
        return ROLL_PASS, "upgrade but roll not allowed"
    end

    if VendorPrice(link) > ONE_GOLD then
        if canGreed ~= false then
            return ROLL_GREED, "vendor value > 1g"
        end
        return ROLL_PASS, "over 1g but greed not allowed"
    end

    return ROLL_PASS, "not an upgrade"
end

local function DoRoll(rollID, rollType)
    RollOnLoot(rollID, rollType)
    if ConfirmLootRoll then
        ConfirmLootRoll(rollID, rollType)
    end
    if StaticPopup_Hide then
        StaticPopup_Hide("CONFIRM_LOOT_ROLL")
        StaticPopup_Hide("CONFIRM_DISENCHANT_ROLL")
    end
end

local function RollName(rollType)
    if rollType == ROLL_NEED then return "|cff00ff00Need|r" end
    if rollType == ROLL_GREED then return "|cffffff00Greed|r" end
    return "|cffaaaaaaPass|r"
end

local function ProcessRoll(rollID, attempts)
    if not addon:IsAutoRollEnabled() then return end
    if pendingRolls[rollID] == false then return end

    attempts = attempts or 1
    local link = GetLootRollItemLink(rollID)
    if not link then
        if attempts < 8 then
            C_Timer.After(0.2, function() ProcessRoll(rollID, attempts + 1) end)
        end
        return
    end

    local name = GetItemInfo(link)
    if not name then
        if attempts < 8 then
            C_Timer.After(0.2, function() ProcessRoll(rollID, attempts + 1) end)
        end
        return
    end

    if IsSkillCard(link) then
        pendingRolls[rollID] = nil
        print(string.format("|cFFFFD700CGO:|r skipped Auto Roll on %s |cff888888(skill card)|r", link))
        return
    end

    local _, _, _, _, _, canNeed, canGreed = GetLootRollItemInfo(rollID)
    local rollType, reason = DecideRoll(link, canNeed, canGreed)
    pendingRolls[rollID] = false
    DoRoll(rollID, rollType)
    print(string.format("|cFFFFD700CGO:|r %s on %s |cff888888(%s)|r", RollName(rollType), link, reason))
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("START_LOOT_ROLL")
frame:RegisterEvent("CANCEL_LOOT_ROLL")
frame:RegisterEvent("CONFIRM_LOOT_ROLL")
frame:SetScript("OnEvent", function(_, event, rollID, arg2)
    if event == "START_LOOT_ROLL" then
        if not addon:IsAutoRollEnabled() then return end
        pendingRolls[rollID] = true
        C_Timer.After(0.35, function() ProcessRoll(rollID, 1) end)
    elseif event == "CANCEL_LOOT_ROLL" then
        pendingRolls[rollID] = nil
    elseif event == "CONFIRM_LOOT_ROLL" then
        if not addon:IsAutoRollEnabled() then return end
        if ConfirmLootRoll then
            ConfirmLootRoll(rollID, arg2)
        end
        if StaticPopup_Hide then
            StaticPopup_Hide("CONFIRM_LOOT_ROLL")
        end
    end
end)
