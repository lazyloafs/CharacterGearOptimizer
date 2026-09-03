local addonName, addon = ...
_G.CharacterGearOptimizer = _G.CharacterGearOptimizer or {}

-- ============================================================================
-- OPTIMIZER ENGINE
-- Scans equipped items and bags/bank to find the best item for each slot
-- based on the selected stat weights.
-- ============================================================================

-- Bag API helpers (Classic Anniversary only has C_Container)
local function GetNumSlots(bag)
    return GetContainerNumSlots(bag) or 0
end
local function GetItemLink(bag, slot)
    return GetContainerItemLink(bag, slot)
end

-- Helper: returns true if the player's class can wear this item.
-- Checks body-armor proficiency, weapon proficiency, shields, and relics.
local function CanPlayerWearItem(link, equipLoc)
    if not equipLoc then return true end
    local _, _, _, _, _, itemType, itemSubType = GetItemInfo(link)
    if not itemType then return true end -- data not cached yet, allow it
    local _, playerClass = UnitClass("player")

    -- 1. Body armor check (head/shoulders/chest/wrist/hands/waist/legs/feet)
    if addon.ARMOR_EQUIP_LOCS[equipLoc] then
        if itemType ~= "Armor" then return true end
        if itemSubType == "Miscellaneous" then return true end
        local preferred = addon.optimizePreferredArmor
        if not preferred then
            local spec = addon.GetActiveSpecData and addon:GetActiveSpecData()
            preferred = spec and spec.preferredArmor
        end
        if preferred then
            return preferred[itemSubType] == true
        end
        local proficiency = addon.CLASS_ARMOR_PROFICIENCY[playerClass]
        if not proficiency then return true end
        return proficiency[itemSubType] == true
    end

    -- 2. Shield check
    if equipLoc == "INVTYPE_SHIELD" then
        if addon.CLASS_SHIELD_PROFICIENCY[playerClass] then return true end
        -- Weapon Setup panel: an explicit Off Hand = Shield selection is a
        -- deliberate, specific choice, so it overrides the generic class
        -- table (which doesn't know about server-specific specs/talents
        -- that grant shield use outside the vanilla class list).
        local sel = addon.GetSelectedWeaponSubtypeMode and addon:GetSelectedWeaponSubtypeMode()
        if sel and sel.oh == "SHIELD" then return true end
        return false
    end

    -- 3. Weapon check
    if itemType == "Weapon" then
        local weaponProf = addon.CLASS_WEAPON_PROFICIENCY[playerClass]
        if not weaponProf then return true end
        return weaponProf[itemSubType] == true
    end

    -- 4. Relic check (Librams / Idols / Totems)
    if equipLoc == "INVTYPE_RELIC" then
        local relicProf = addon.CLASS_RELIC_PROFICIENCY[playerClass]
        if not relicProf then return false end
        return relicProf[itemSubType] == true
    end

    return true
end

-- Helper: returns false if the item requires a higher level or a class/race
-- the player doesn't have (e.g. a bow on a druid).
local function CanPlayerUseItem(link)
    -- Level check via GetItemInfo
    local _, _, _, _, minLevel = GetItemInfo(link)
    if minLevel and minLevel > UnitLevel("player") then return false end
    -- Class/proficiency check (covers weapon types, armor sub-types, etc.)
    if IsEquippableItem and not IsEquippableItem(link) then return false end
    return true
end

-- At level 60, heirlooms are leveling gear and should not be selected unless
-- the Not 60 preference is enabled. Keep currently equipped items available
-- as a fallback so optimization never leaves a slot unexpectedly empty.
local function ShouldIncludeForLevel(item)
    if item.isEquipped then return true end
    if UnitLevel("player") < 60 or addon:PreferHeirloomsEnabled() then return true end
    return not addon:IsHeirloomItem(item.link)
end

-- Helper: Get all available equippable items
function addon:GetAllAvailableItems()
    local items = {}
    
    -- 1. Scan equipped gear (slots 1-19 to include tabard)
    for slot = 1, 19 do
        local link = GetInventoryItemLink("player", slot)
        if link then
            table.insert(items, {
                link = link,
                bag = nil,
                slot = slot,
                isEquipped = true,
            })
        end
    end

    -- 2. Scan bags (0 = backpack, 1-4 = bags)
    for bag = 0, 4 do
        local numSlots = GetNumSlots(bag)
        for slot = 1, numSlots do
            local link = GetItemLink(bag, slot)
            if link then
                local name, _, _, _, _, _, _, _, equipLoc = GetItemInfo(link)
                if equipLoc and self.SLOT_MAP[equipLoc] and CanPlayerWearItem(link, equipLoc) and CanPlayerUseItem(link) then
                    table.insert(items, {
                        link = link,
                        bag = bag,
                        slot = slot,
                        equipLoc = equipLoc,
                        isEquipped = false
                    })
                end
            end
        end
    end

    -- 3. Scan bank bags when the bank frame is open
    --    Bag -1 = main bank (28 slots), bags 5-11 = bank bag slots
    if self.bankOpen then
        local bankBags = { -1, 5, 6, 7, 8, 9, 10, 11 }
        for _, bag in ipairs(bankBags) do
            local numSlots = GetNumSlots(bag)
            for slot = 1, numSlots do
                local link = GetItemLink(bag, slot)
                if link then
                    local name, _, _, _, _, _, _, _, equipLoc = GetItemInfo(link)
                    if equipLoc and self.SLOT_MAP[equipLoc] and CanPlayerWearItem(link, equipLoc) and CanPlayerUseItem(link) then
                        table.insert(items, {
                            link = link,
                            bag = bag,
                            slot = slot,
                            equipLoc = equipLoc,
                            isEquipped = false,
                            isBank = true,
                        })
                    end
                end
            end
        end
    end

    return items
end

-- Helper: detect whether an item is a two-hand weapon
local function IsStaffWeapon(item)
    if not item or not item.link then return false end
    local _, _, _, _, _, itemType, itemSubType = GetItemInfo(item.link)
    if not itemType and GetItemInfoInstant then
        _, itemType, itemSubType = GetItemInfoInstant(item.link)
    end
    return itemType == "Weapon" and (itemSubType == "Staves" or itemSubType == "Staff")
end

local function Is2HWeapon(item)
    if item.equipLoc == "INVTYPE_2HWEAPON" then return true end
    -- Ascension may expose some staff items with inconsistent equip-location
    -- metadata. Staves are inherently two-handed, so recognize the weapon
    -- subtype explicitly as well.
    if item.link then
        local _, _, _, _, _, _, _, _, eLoc = GetItemInfo(item.link)
        if eLoc == "INVTYPE_2HWEAPON" or IsStaffWeapon(item) then return true end
    end
    return false
end

local function GetResolvedEquipLoc(item)
    local eLoc = item and item.equipLoc
    if eLoc and eLoc ~= "" and eLoc ~= "EQUIPPED" then
        return eLoc
    end
    if item and item.link then
        local _, _, _, _, _, _, _, _, loc = GetItemInfo(item.link)
        return loc
    end
    return eLoc
end

local function IsShield(item)
    if GetResolvedEquipLoc(item) == "INVTYPE_SHIELD" then return true end
    if item and item.link then
        local _, _, _, _, _, itemType, itemSubType = GetItemInfo(item.link)
        if itemSubType == "Shields" or itemSubType == "Shield" then return true end
        if itemType == "Armor" and itemSubType == "Shields" then return true end
    end
    return false
end

local function IsOneHandWeapon(item)
    if Is2HWeapon(item) or IsShield(item) then return false end
    local eLoc = GetResolvedEquipLoc(item)
    return eLoc == "INVTYPE_WEAPON" or eLoc == "INVTYPE_WEAPONMAINHAND" or eLoc == "INVTYPE_WEAPONOFFHAND"
end

local function IsOffHandItem(item)
    if IsShield(item) then return true end
    if Is2HWeapon(item) then return false end
    local eLoc = GetResolvedEquipLoc(item)
    return eLoc == "INVTYPE_HOLDABLE" or eLoc == "INVTYPE_WEAPONOFFHAND" or eLoc == "INVTYPE_WEAPON"
end

-- Tank profiles that should always use a one-hander + shield (not 2H).
function addon:ShouldForceShieldTank(specData)
    -- Explicit weapon-mode selection wins over profile defaults.
    local mode = addon:GetSelectedWeaponMode()
    if mode then return mode == "1h_shield" end
    if not specData then return false end
    if specData.forceShieldTank == false then return false end
    if specData.forceShieldTank == true then return true end
    local role = specData.role
    if role == "tank_barrier" or role == "tank_druid" then return true end
    if role == "tank" then
        local _, playerClass = UnitClass("player")
        return playerClass ~= "DEATHKNIGHT"
    end
    return false
end

-- ============================================================================
-- WEAPON MODE SELECTION
-- User-selectable weapon loadout. Persisted per character; nil/"" = auto
-- (let the optimizer and spec decide). Split into two independent dropdowns:
--
-- MELEE (slots 16/17) — meleeMode:
--   one_1h      -> single one-hander, empty off-hand
--   one_dagger  -> single dagger, empty off-hand
--   dual_1h     -> two one-handers (daggers excluded; see dual_dagger)
--   dual_dagger -> two daggers
--   dual_2h     -> Titan's Grip style: a 2H in each hand
--   one_2h      -> single two-hander, empty off-hand
--   staff_shield -> staff in main hand plus shield in off-hand
--   wand        -> wand/held-in-off-hand only (casters)
--   1h_shield   -> one-hander plus shield
--   staff       -> staff in the main hand
--
-- RANGED (slot 18) — rangedMode:
--   thrown      -> thrown weapon in the ranged slot
--   ranged      -> bow / gun / crossbow in the ranged slot (wands excluded)
--   wand        -> wand in the ranged slot
-- ============================================================================
local WEAPON_MODES = {
    "one_1h", "one_dagger", "dual_1h", "dual_dagger", "dual_2h", "one_2h", "staff_shield", "wand", "thrown", "ranged", "1h_shield", "staff",
}

local function IsValidMode(mode)
    for _, m in ipairs(WEAPON_MODES) do
        if mode == m then return true end
    end
    return false
end

function addon:GetSelectedWeaponMode()
    local db = CharacterGearOptimizerDB
    local mode = db and db.weaponMode
    if not mode then return nil end
    -- Legacy value: derive the melee half from it.
    if mode == "thrown" or mode == "ranged" then return nil end
    return IsValidMode(mode) and mode or nil
end

function addon:GetSelectedRangedMode()
    local db = CharacterGearOptimizerDB
    local mode = db and db.rangedMode
    if mode == "thrown" or mode == "ranged" or mode == "wand" then return mode end
    -- Upgrade legacy: a stored combined mode implies the ranged half.
    local legacy = db and db.weaponMode
    if legacy == "thrown" or legacy == "ranged" then return legacy end
    return nil
end

function addon:SetSelectedWeaponMode(mode)
    CharacterGearOptimizerDB = CharacterGearOptimizerDB or {}
    if mode == "" or mode == nil then
        CharacterGearOptimizerDB.weaponMode = nil
    elseif IsValidMode(mode) and mode ~= "thrown" and mode ~= "ranged" then
        CharacterGearOptimizerDB.weaponMode = mode
    end
end

function addon:SetSelectedRangedMode(mode)
    CharacterGearOptimizerDB = CharacterGearOptimizerDB or {}
    if mode == "" or mode == nil then
        CharacterGearOptimizerDB.rangedMode = nil
    elseif mode == "thrown" or mode == "ranged" or mode == "wand" then
        CharacterGearOptimizerDB.rangedMode = mode
    end
end

local function IsWand(item)
    if Is2HWeapon(item) then return false end
    local eLoc = GetResolvedEquipLoc(item)
    return eLoc == "INVTYPE_WAND" or eLoc == "INVTYPE_HOLDABLE"
end

local function IsDagger(item)
    if Is2HWeapon(item) or IsShield(item) then return false end
    local eLoc = GetResolvedEquipLoc(item)
    if eLoc ~= "INVTYPE_WEAPON" and eLoc ~= "INVTYPE_WEAPONMAINHAND" and eLoc ~= "INVTYPE_WEAPONOFFHAND" then
        return false
    end
    local link = item and item.link
    if not link then return false end
    local _, _, _, _, _, itemType, itemSubType = GetItemInfo(link)
    return itemType == "Weapon" and itemSubType == "Daggers"
end

local function IsOneHandNonDagger(item)
    return IsOneHandWeapon(item) and not IsDagger(item)
end

local function IsThrownWeapon(item)
    local eLoc = GetResolvedEquipLoc(item)
    return eLoc == "INVTYPE_THROWN"
end

-- Wand detection for the ranged slot: wands normally use INVTYPE_WAND but
-- some servers expose them with the ranged equip-locs, so fall back to the
-- weapon subtype ("Wands") to tell them apart from bows/guns/crossbows.
local function IsRangedSlotWand(item)
    if GetResolvedEquipLoc(item) == "INVTYPE_WAND" then return true end
    local link = item and item.link
    if not link then return false end
    local _, _, _, _, _, itemType, itemSubType = GetItemInfo(link)
    return itemType == "Weapon" and (itemSubType == "Wands" or itemSubType == "Wand")
end

local function IsRangedWeapon(item)
    local eLoc = GetResolvedEquipLoc(item)
    return eLoc == "INVTYPE_RANGED" or eLoc == "INVTYPE_RANGEDRIGHT"
end

-- ============================================================================
-- WEAPON SETUP PANEL: exact weapon-subtype selection for Main Hand / Off Hand
-- Independent from the coarse WEAPON_MODES dropdown above. Persisted as
-- CharacterGearOptimizerDB.weaponSubtype = { mh = <subtype or nil>, oh = <choice or nil> }
--   mh: an itemSubType string from CLASS_WEAPON_PROFICIENCY (e.g. "One-Handed Swords"),
--       or nil for auto.
--   oh: "EMPTY", "SHIELD", "HOLDABLE", or an itemSubType string (including
--       Two-Handed / Staves subtypes for Titan's Grip-style dual
--       two-handers), or nil for auto.
-- Selecting a subtype clears the coarse dropdown mode and vice versa, so
-- only one weapon-selection system drives the optimizer at a time. Each
-- hand independently equips the highest-scoring item of the exact subtype
-- requested (scoredItems is already sorted best-to-worst by the caller).
-- ============================================================================

-- Melee weapon subtypes (excludes ranged-only subtypes handled by the
-- Ranged dropdown: Bows, Crossbows, Guns, Thrown, Wands).
addon.MELEE_WEAPON_SUBTYPES = {
    "One-Handed Swords", "Two-Handed Swords",
    "One-Handed Axes",   "Two-Handed Axes",
    "One-Handed Maces",  "Two-Handed Maces",
    "Daggers", "Fist Weapons", "Polearms", "Staves",
}

-- Returns the melee weapon subtypes usable by the given class, in display
-- order. Classes with no CLASS_WEAPON_PROFICIENCY entry (e.g. custom server
-- classes like HERO) are treated as unrestricted, matching CanPlayerWearItem.
function addon:GetClassMeleeWeaponSubtypes(class)
    local prof = self.CLASS_WEAPON_PROFICIENCY[class]
    local list = {}
    for _, subtype in ipairs(self.MELEE_WEAPON_SUBTYPES) do
        if not prof or prof[subtype] then
            table.insert(list, subtype)
        end
    end
    return list
end

-- Off-hand choices: Empty, Shield, Held-in-Off-hand, then every melee
-- weapon subtype the class can use. Shield is always offered -- this is an
-- explicit, specific choice from the panel, so it isn't gated behind the
-- CLASS_SHIELD_PROFICIENCY table (some specs/servers grant shield use that
-- table doesn't know about; if the item truly can't be worn, none will
-- score/equip). The full weapon-subtype list is offered too (not just 1H)
-- so Titan's Grip-style dual-two-hand combinations -- including dual
-- Staves -- can be built explicitly.
function addon:GetClassOffHandOptions(class)
    local options = { "EMPTY", "SHIELD", "HOLDABLE" }
    for _, subtype in ipairs(self:GetClassMeleeWeaponSubtypes(class)) do
        table.insert(options, subtype)
    end
    return options
end

local function GetItemWeaponSubType(item)
    if not item or not item.link then return nil end
    local _, _, _, _, _, itemType, itemSubType = GetItemInfo(item.link)
    if itemType ~= "Weapon" then return nil end
    return itemSubType
end

function addon:GetSelectedWeaponSubtypeMode()
    local db = CharacterGearOptimizerDB
    local sel = db and db.weaponSubtype
    if not sel or (not sel.mh and not sel.oh) then return nil end
    return sel
end

function addon:SetWeaponSubtypeMH(subtype)
    CharacterGearOptimizerDB = CharacterGearOptimizerDB or {}
    CharacterGearOptimizerDB.weaponSubtype = CharacterGearOptimizerDB.weaponSubtype or {}
    CharacterGearOptimizerDB.weaponSubtype.mh = (subtype ~= "" and subtype) or nil
    if CharacterGearOptimizerDB.weaponSubtype.mh or CharacterGearOptimizerDB.weaponSubtype.oh then
        CharacterGearOptimizerDB.weaponMode = nil
    end
end

function addon:SetWeaponSubtypeOH(choice)
    CharacterGearOptimizerDB = CharacterGearOptimizerDB or {}
    CharacterGearOptimizerDB.weaponSubtype = CharacterGearOptimizerDB.weaponSubtype or {}
    CharacterGearOptimizerDB.weaponSubtype.oh = (choice ~= "" and choice) or nil
    if CharacterGearOptimizerDB.weaponSubtype.mh or CharacterGearOptimizerDB.weaponSubtype.oh then
        CharacterGearOptimizerDB.weaponMode = nil
    end
end

function addon:ClearWeaponSubtypeMode()
    if CharacterGearOptimizerDB then
        CharacterGearOptimizerDB.weaponSubtype = nil
    end
end

-- Enforce an exact Main Hand / Off Hand subtype selection from the Weapon
-- Setup panel. Returns true if a subtype selection was active (handled),
-- false otherwise (caller should fall back to the coarse dropdown / auto
-- logic).
function addon:EnforceWeaponSubtypeMode(bestSet, scoredItems)
    local sel = self:GetSelectedWeaponSubtypeMode()
    if not sel then return false end

    local function ItemKey(item)
        return item.isEquipped and ("EQ_"..item.slot) or ("BAG_"..(item.bag or 0).."_"..item.slot)
    end

    local mhItem, mhKey
    if sel.mh then
        for _, item in ipairs(scoredItems) do
            if GetItemWeaponSubType(item) == sel.mh then
                mhItem = item
                mhKey = ItemKey(item)
                break
            end
        end
        bestSet[16] = mhItem
        -- A real 2H weapon inherently blocks the off-hand unless the user
        -- explicitly chose an Off Hand pairing (e.g. Staff + Shield, or a
        -- Titan's Grip dual two-hander), in which case the branch below
        -- assigns slot 17 itself.
        if mhItem and Is2HWeapon(mhItem) and not sel.oh then
            bestSet[17] = nil
        end
    end

    if sel.oh then
        local ohItem
        if sel.oh == "EMPTY" then
            bestSet[17] = nil
        elseif sel.oh == "SHIELD" then
            for _, item in ipairs(scoredItems) do
                if IsShield(item) and ItemKey(item) ~= mhKey then
                    ohItem = item
                    break
                end
            end
            bestSet[17] = ohItem
        elseif sel.oh == "HOLDABLE" then
            for _, item in ipairs(scoredItems) do
                if GetResolvedEquipLoc(item) == "INVTYPE_HOLDABLE" and not IsShield(item)
                    and ItemKey(item) ~= mhKey then
                    ohItem = item
                    break
                end
            end
            bestSet[17] = ohItem
        else
            -- Exact weapon subtype: may be a 1H subtype (dual wield) or a
            -- 2H / Staves subtype (Titan's Grip-style dual two-hander),
            -- and may match the Main Hand subtype (e.g. Dual 1H Maces).
            for _, item in ipairs(scoredItems) do
                if GetItemWeaponSubType(item) == sel.oh and ItemKey(item) ~= mhKey then
                    ohItem = item
                    break
                end
            end
            bestSet[17] = ohItem
        end
    end

    return true
end


-- Enforce the selected weapon mode on a finished best set.
-- Melee dropdown only (slots 16/17); ranged is handled by EnforceRangedMode.
function addon:EnforceWeaponMode(bestSet, scoredItems)
    local mode = self:GetSelectedWeaponMode()
    if not mode then return false end

    local function BestMatch(predicate)
        for _, item in ipairs(scoredItems) do
            if predicate(item) then return item end
        end
        return nil
    end

    if mode == "one_1h" or mode == "one_dagger" then
        local predicate = mode == "one_dagger" and IsDagger or IsOneHandWeapon
        bestSet[16] = BestMatch(predicate)
        bestSet[17] = nil
        return true

    elseif mode == "dual_dagger" then
        -- Two daggers: best dagger main hand, second-best dagger off hand.
        local first, second
        for _, item in ipairs(scoredItems) do
            if IsDagger(item) then
                if not first then
                    first = item
                elseif not second then
                    second = item
                    break
                end
            end
        end
        if first then bestSet[16] = first end
        if second then
            bestSet[17] = second
        else
            bestSet[17] = nil
        end
        return true

    elseif mode == "dual_1h" or mode == "1h_shield" or mode == "wand" then
        -- Main hand is always a one-hander; off-hand differs by mode.
        -- dual_1h excludes daggers (use dual_dagger for those).
        local mhPredicate = (mode == "dual_1h") and IsOneHandNonDagger or IsOneHandWeapon
        local ohPredicate
        if mode == "1h_shield" then
            ohPredicate = IsShield
        elseif mode == "wand" then
            ohPredicate = IsWand
        elseif mode == "dual_1h" then
            ohPredicate = IsOneHandNonDagger
        else
            ohPredicate = IsOneHandWeapon
        end
        local mh = BestMatch(mhPredicate)
        local oh
        for _, item in ipairs(scoredItems) do
            if item ~= mh and ohPredicate(item) then
                oh = item
                break
            end
        end
        if mh then bestSet[16] = mh end
        if oh then
            bestSet[17] = oh
        elseif mode == "dual_1h" and mh and GetResolvedEquipLoc(mh) == "INVTYPE_WEAPON" then
            -- Same 1H can't be duplicated; leave OH empty if no second 1H exists.
            bestSet[17] = nil
        end
        return true

    elseif mode == "staff_shield" then
        local staff
        for _, item in ipairs(scoredItems) do
            if Is2HWeapon(item) and IsStaffWeapon(item) then
                staff = item
                break
            end
        end
        local shield = BestMatch(IsShield)
        bestSet[16] = staff
        if shield then bestSet[17] = shield else bestSet[17] = nil end
        return true

    elseif mode == "one_2h" then
        local th = BestMatch(Is2HWeapon)
        if th then
            bestSet[16] = th
        end
        bestSet[17] = nil
        return true

    elseif mode == "staff" then
        -- Staves are 2H weapons; prefer an actual staff subtype if present.
        local staff
        for _, item in ipairs(scoredItems) do
            if Is2HWeapon(item) and IsStaffWeapon(item) then
                staff = item
                break
            end
        end
        bestSet[16] = staff
        bestSet[17] = nil
        return true

    elseif mode == "dual_2h" then
        -- Titan's Grip: highest-scored 2H main hand, second-best 2H off hand.
        local first, second
        for _, item in ipairs(scoredItems) do
            if Is2HWeapon(item) then
                if not first then
                    first = item
                elseif not second then
                    second = item
                    break
                end
            end
        end
        if first then bestSet[16] = first end
        if second then
            bestSet[17] = second
        else
            bestSet[17] = nil
        end
        return true

    elseif mode == "thrown" or mode == "ranged" then
        -- Legacy combined mode reaching this path: delegate the ranged half.
        return self:EnforceRangedMode(bestSet, scoredItems)
    end

    return false
end

-- Enforce the ranged-slot dropdown (slot 18 only). MH/OH untouched.
function addon:EnforceRangedMode(bestSet, scoredItems)
    local mode = self:GetSelectedRangedMode()
    if not mode then return false end

    local pick
    for _, item in ipairs(scoredItems) do
        local ok = false
        for _, s in ipairs(item.slots or {}) do
            if s == 18 then ok = true break end
        end
        if ok then
            if mode == "thrown" and IsThrownWeapon(item) then
                pick = item
            elseif mode == "ranged" and IsRangedWeapon(item) and not IsRangedSlotWand(item) then
                pick = item
            elseif mode == "wand" and IsRangedSlotWand(item) then
                pick = item
            end
        end
        if pick then break end
    end
    if pick then
        bestSet[18] = pick
        return true
    end
    return false
end

function addon:EnforceShieldTankWeapons(bestSet, scoredItems)
    local preferHeirlooms = self:PreferHeirloomsEnabled()
    local bestMH, bestShield, heirloomMH, heirloomShield
    for _, item in ipairs(scoredItems) do
        if IsOneHandWeapon(item) then
            if not bestMH then bestMH = item end
            if item.isHeirloom and not heirloomMH then heirloomMH = item end
        elseif IsShield(item) then
            if not bestShield then bestShield = item end
            if item.isHeirloom and not heirloomShield then heirloomShield = item end
        end
        if bestMH and bestShield and (not preferHeirlooms or (heirloomMH and heirloomShield)) then
            break
        end
    end
    if preferHeirlooms then
        bestMH = heirloomMH or bestMH
        bestShield = heirloomShield or bestShield
    end
    if bestMH then bestSet[16] = bestMH end
    if bestShield then bestSet[17] = bestShield end
end

local function ScanTooltipForHeirloom(link)
    if not link then return false, false end
    local tip = addon.scanTooltip
    if not tip then
        addon.scanTooltip = CreateFrame("GameTooltip", "CGOScanTooltip", nil, "GameTooltipTemplate")
        tip = addon.scanTooltip
    end
    tip:SetOwner(WorldFrame, "ANCHOR_NONE")
    tip:ClearLines()
    tip:SetHyperlink(link)
    local lineCount = tip:NumLines() or 0
    if lineCount == 0 then
        return false, false
    end
    for i = 1, lineCount do
        local left = _G["CGOScanTooltipTextLeft" .. i]
        if left then
            local text = string.lower(left:GetText() or "")
            if text ~= "" then
                if text:find("heirloom", 1, true)
                    or text:find("experience gained", 1, true)
                    or text:find("increases your experience", 1, true)
                    or text:find("increases experience", 1, true)
                    or text:find("bind on account", 1, true)
                    or text:find("binds to account", 1, true)
                    or text:find("account bound", 1, true)
                    or text:find("scales to your level", 1, true)
                    or text:find("scales with your level", 1, true) then
                    return true, true
                end
            end
        end
    end
    return false, true
end

function addon:IsHeirloomItem(link)
    if not link then return false end
    self._heirloomCache = self._heirloomCache or {}
    if self._heirloomCache[link] == true then
        return true
    end
    local _, _, quality, _, _, itemClass, itemSubClass = GetItemInfo(link)
    local isHeirloom = quality == 7
        or quality == LE_ITEM_QUALITY_HEIRLOOM
        or itemClass == "Heirloom"
        or itemSubClass == "Heirloom"
        or itemSubClass == "Heirlooms"
    local scanned, tooltipReady = false, false
    if not isHeirloom then
        scanned, tooltipReady = ScanTooltipForHeirloom(link)
        isHeirloom = scanned
    end
    -- Only cache confirmed heirlooms, or confirmed non-heirlooms once the
    -- tooltip actually populated. Empty tooltips are item-cache misses.
    if isHeirloom or tooltipReady then
        self._heirloomCache[link] = isHeirloom
    end
    return isHeirloom
end

function addon:PreferHeirloomsEnabled()
    local caps = CharacterGearOptimizerDB and CharacterGearOptimizerDB.capPriorities
    return caps and caps.not60 == true
end

function addon:CompareOptimizerItems(a, b)
    -- NOTE: PvP Power / PvE Power priority comparisons were removed along
    -- with the rest of that feature -- those stats only existed on the
    -- Ascension private server and have no equivalent on any real client.
    if self:PreferHeirloomsEnabled() then
        local ah = a.isHeirloom and 1 or 0
        local bh = b.isHeirloom and 1 or 0
        if ah ~= bh then return ah > bh end
    end
    return (a.score or 0) > (b.score or 0)
end

function addon:EnforceHeirloomPreference(bestSet, scoredItems, specData, class)
    if not self:PreferHeirloomsEnabled() then return end

    local heirloomsBySlot = {}
    for _, item in ipairs(scoredItems) do
        if item.isHeirloom then
            for _, s in ipairs(item.slots) do
                heirloomsBySlot[s] = heirloomsBySlot[s] or {}
                table.insert(heirloomsBySlot[s], item)
            end
        end
    end

    local usedKeys = {}
    local function ItemKey(item)
        return item.isEquipped and ("EQ_" .. item.slot) or ("BAG_" .. (item.bag or 0) .. "_" .. item.slot)
    end
    local function IsUsed(item)
        return usedKeys[ItemKey(item)] == true
    end
    local function ItemAllowedForSlot(item, slot)
        if slot == 16 then
            if class == "HERO" and specData and specData.path == "strength" then
                return Is2HWeapon(item)
            end
            if self:ShouldForceShieldTank(specData) then
                return IsOneHandWeapon(item)
            end
        elseif slot == 17 then
            if class == "HERO" and specData and specData.path == "strength" then
                return false
            end
            if bestSet[16] and Is2HWeapon(bestSet[16]) then
                return false
            end
            -- Not 60: any heirloom that can sit in the off-hand wins, including
            -- holdables. Shield-tank specs still prefer a shield when one exists.
            return IsOffHandItem(item)
        end
        return true
    end

    for slot = 1, 19 do
        -- Trinkets (13/14) are never auto-swapped, including for heirloom
        -- preference: their value is usually in on-use/proc effects that
        -- can't be judged by score or "is it an heirloom" alone.
        local candidates = (slot ~= 13 and slot ~= 14) and heirloomsBySlot[slot]
        if candidates then
            local chosen
            if slot == 17 then
                for _, item in ipairs(candidates) do
                    if not IsUsed(item) and ItemAllowedForSlot(item, slot) and IsShield(item) then
                        chosen = item
                        break
                    end
                end
            end
            if not chosen then
                for _, item in ipairs(candidates) do
                    if not IsUsed(item) and ItemAllowedForSlot(item, slot) then
                        chosen = item
                        break
                    end
                end
            end
            if chosen then
                if slot == 16 and Is2HWeapon(chosen) then
                    bestSet[17] = nil
                end
                bestSet[slot] = chosen
                usedKeys[ItemKey(chosen)] = true
            end
        end
    end
end

-- Refresh HERO DPS profiles from Ascension's live character stats.
-- Tank profiles keep their static mitigation weights.
function addon:RefreshAscensionHeroWeights(specIndex)
    local spec = self.CLASS_SPECS.HERO and self.CLASS_SPECS.HERO[specIndex]
    if not spec then return end
    -- Attack Power Healer: Path of Healing converts AP and Agility into
    -- Healing Power, so the profile is computed from live stats below.
    if spec.path == "healer_ap" then
        return self:RefreshHealerApWeights(spec)
    end
    if spec.role ~= "melee_dps" then return end
    local level = math.max(UnitLevel("player") or 1, 1)
    local apBase, apPos, apNeg = UnitAttackPower("player")
    local ap = math.max((apBase or 0) + (apPos or 0) + (apNeg or 0), 0)
    local low, high = UnitDamage("player")
    local speed = UnitAttackSpeed("player") or 2
    local weaponDPS = speed > 0 and (((low or 0) + (high or 0)) * 0.5 / speed) or 0
    local spellPower = 0
    if GetSpellBonusDamage then
        for school = 2, 7 do
            spellPower = math.max(spellPower, GetSpellBonusDamage(school) or 0)
        end
    end
    -- Ascension weapon attacks, including Sinister Strike, use whichever
    -- offensive power is higher when constructing normalized weapon damage.
    local dominantPower = math.max(ap, spellPower)
    local baseDPS = math.max(weaponDPS + dominantPower / 14, 1)
    local critPct = GetCritChance and (GetCritChance() or 0) or 0
    local apMarginal = math.max((1 + critPct / 100) / 14, 0.01)
    local function RatingEP(id, fallbackPerPoint)
        local rating = GetCombatRating and (GetCombatRating(id) or 0) or 0
        local bonus = GetCombatRatingBonus and (GetCombatRatingBonus(id) or 0) or 0
        local pctPerPoint = rating > 0 and bonus / rating or fallbackPerPoint
        return (baseDPS * pctPerPoint / 100) / apMarginal
    end
    local critEP = RatingEP(self.RATING.CR_CRIT_MELEE, 1 / self.RATING.CRIT_PER_PCT)
    local hasteEP = RatingEP(self.RATING.CR_HASTE_MELEE, 1 / self.RATING.HASTE_PER_PCT)
    local hitEP = RatingEP(self.RATING.CR_HIT_MELEE, 1 / self.RATING.HIT_PER_PCT)
    local agiPerCrit = level >= 70 and 40 or level >= 60 and 33 or math.max(10, 33 * level / 60)
    local agiCritEP = critEP * self.RATING.CRIT_PER_PCT / agiPerCrit
    local path = spec.path
    spec.weights.STR = path == "strength" and 2 or 1
    spec.weights.AGI = (path == "agility" and 1 or 0) + agiCritEP
    if path == "duality" then spec.weights.AGI = 1 + agiCritEP end
    spec.weights.AP = 1
    spec.weights.FAP = 1
    -- Sinister Strike deals 100% normalized weapon damage. Ascension calculates
    -- weapon damage from AP or SP (whichever is higher), so SP is a full
    -- alternative power path for this profile: one SP has the same marginal
    -- weapon-damage value as one AP once SP is the dominant power.
    spec.weights.SP = 1
    spec.weights.WEAPON_DPS = 14
    spec.weights.HIT = math.max(hitEP, 0.25)
    spec.weights.SPELLHIT = spec.weights.HIT
    spec.weights.CRIT = math.max(critEP, 0.15)
    spec.weights.MELEECRIT = spec.weights.CRIT
    spec.weights.HASTE = math.max(hasteEP, 0.15)
    spec.weights.ARP = 0.35
        self:ApplyPowerCapWeights(spec.weights)
    end

-- Attack Power Healer (Path of Healing). Ascension talents convert primary
-- stats into Healing Power:
--   Hippocratic Oath:      +20% healing power of attack power
--   Grove Ranger's Agility: +120% AP of Agility, +20% healing power of Agility
-- Path of Healing also grants Intellect, Spirit, and SP->healing scaling,
-- with SP converting to Healing Power at the same rate as the Spell Power
-- Healer (user constraint): 1 SP = 1 Healing Power.
--
-- Marginal Healing Power per stat point is constant, so exact EP ratios are:
--   HEAL 1.0 | SP 1.0 | AP/FAP 0.20 | AGI 0.44 | INT 0.30 | SPI 0.15
-- Normalized to an AP = 1.00 anchor:
--   HEAL 5.0 | SP 5.0 | AGI 2.2 | AP/FAP 1.0 | INT 1.5 | SPI 0.75
-- Secondary-stat weights come from an NSGA-II search (throughput/sustain/
-- survival objectives over a slot-competitive gear pool); see
-- scripts/healer-ap-nsga.js in the repo.
function addon:RefreshHealerApWeights(spec)
    local w = spec.weights

    -- Power stats: exact Path-of-Healing ratios (AP anchor = 1.00).
    w.AP   = 1.0
    w.FAP  = 1.0
    w.AGI  = 2.2   -- 0.24 HP via Grove Ranger AP + 0.20 HP direct
    w.HEAL = 5.0
    w.SP   = 5.0   -- equals the Spell Power Healer's SP valuation
    w.INT  = 1.5
    w.SPI  = 0.75

    -- Secondaries: NSGA-II knee values (hps-optimal front, gen 220).
    -- Crits heal bigger (150% avg multiplier); haste scales cast throughput.
    w.CRIT = 0.45
    w.MELEECRIT = w.CRIT
    w.SPELLCRIT = w.CRIT
    w.HASTE = 0.5
    w.HIT = 0.05       -- heals can't miss; only relevant for offensive casts
    w.SPELLHIT = w.HIT
    -- GA explored MP5 up to 5.4 under pure-sustain pressure; 1.8 preserves
    -- long-fight value without outbidding actual Healing Power points.
    w.MP5 = 1.8
    -- Survivability floor so the healer doesn't die to splash damage.
    w.STA = 0.5
    w.ARMOR = 0.03

    -- Gems: best common gem is +18 Healing => 18 x 5.0 weighted points.
    spec.gemValue = 18 * w.HEAL
    spec.metaValue = 36

    self:ApplyPowerCapWeights(w)
end

-- ============================================================================
-- Main Optimization Function
function addon:GetBestGearForSpec(class, specIndex)
    if class == "HERO" then self:RefreshAscensionHeroWeights(specIndex) end
    local specData = self.CLASS_SPECS[class] and self.CLASS_SPECS[class][specIndex]
    if not specData then return nil end

    self.activeCapBoosts = nil
    self.optimizePreferredArmor = specData.preferredArmor
    -- PvP/PvE Power cap checkboxes apply to every profile.
    self:ApplyPowerCapWeights(specData.weights)

    local allItems = self:GetAllAvailableItems()

    -- ====================================================================
    -- HELPER: build scored+slotted item list from allItems (also extracts
    --         and stores raw stats per item for the cap system to use).
    -- ====================================================================
    local function BuildScoredItems(itemList)
        local scored = {}
        for _, item in ipairs(itemList) do
            local stats = addon:ExtractItemStats(item.link)
            -- Synthetic avoidance % for uncrushable cap
            do
                local R = addon.RATING
                local defR  = stats["DEF"] or 0
                local dodR  = stats["DODGE"] or 0
                local parR  = stats["PARRY"] or 0
                local blkR  = stats["BLOCK_RATING"] or 0
                if defR > 0 or dodR > 0 or parR > 0 or blkR > 0 then
                    stats["AVOID"] = (defR / R.DEFENSE_PER_SKILL) * R.AVOID_PER_DEF_SKILL
                                   + dodR / R.DODGE_PER_RATING
                                   + parR / R.PARRY_PER_RATING
                                   + blkR / R.BLOCK_PER_RATING
                end
            end
            -- Synthetic spell hit total: HIT + SPELLHIT (both contribute to spell hit)
            do
                local hitR  = stats["HIT"] or 0
                local shR   = stats["SPELLHIT"] or 0
                if hitR > 0 or shR > 0 then
                    stats["SPELL_HIT_TOTAL"] = hitR + shR
                end
            end
            local score = addon:CalculateScore(stats, specData)

            -- Always include equipped items AND all equippable bag items.
            -- Score-0 bag items are needed so the cap swap system can find
            -- defense / hit / resil gear that the normal weights don't value.
            if (item.isEquipped or item.equipLoc) and ShouldIncludeForLevel(item) then
                local validSlots
                if item.isEquipped then
                    local genericSlots = addon:GetValidSlotsForEquipLoc(nil, item.link)
                    validSlots = { item.slot }
                    for _, gs in ipairs(genericSlots) do
                        if gs ~= item.slot then
                            table.insert(validSlots, gs)
                        end
                    end
                else
                    validSlots = addon:GetValidSlotsForEquipLoc(item.equipLoc, item.link)
                end
                local resolvedLoc = item.equipLoc
                if not resolvedLoc or resolvedLoc == "EQUIPPED" then
                    local _, _, _, _, _, _, _, _, eLoc = GetItemInfo(item.link)
                    resolvedLoc = eLoc or item.equipLoc or "EQUIPPED"
                end
                table.insert(scored, {
                    link = item.link,
                    bag = item.bag,
                    slot = item.slot,
                    isEquipped = item.isEquipped,
                    isBank = item.isBank,
                    equipLoc = resolvedLoc,
                    score = score,
                    slots = validSlots,
                    stats = stats,
                    isHeirloom = addon:IsHeirloomItem(item.link),
                })
            end
        end
        return scored
    end

    -- ====================================================================
    -- HELPER: greedy slot assignment
    -- ====================================================================
    local function AssignSlots(scoredItems)
        local bestSet = {}
        local usedItems = {}
        local blockedSlots = {}
        for _, item in ipairs(scoredItems) do
            for _, s in ipairs(item.slots) do
                local itemKey = item.isEquipped and ("EQ_"..item.slot) or ("BAG_"..(item.bag or 0).."_"..item.slot)
                -- Trinkets (13/14) are never auto-swapped by stat score --
                -- their value is usually in on-use/proc effects the weight
                -- system can't judge. FillEquippedFallback below keeps
                -- whatever trinkets are already equipped; use the item
                -- picker to change them manually.
                if s ~= 13 and s ~= 14 and not bestSet[s] and not usedItems[itemKey] and not blockedSlots[s] then
                    bestSet[s] = item
                    usedItems[itemKey] = true
                    -- 2H weapon in MH blocks the OH slot
                    if s == 16 and Is2HWeapon(item) then
                        blockedSlots[17] = true
                        if bestSet[17] then
                            local ohKey = bestSet[17].isEquipped and ("EQ_"..bestSet[17].slot) or ("BAG_"..(bestSet[17].bag or 0).."_"..bestSet[17].slot)
                            usedItems[ohKey] = nil
                            bestSet[17] = nil
                        end
                    end
                    -- OH assigned: if MH is a 2H, skip this assignment
                    if s == 17 and bestSet[16] and Is2HWeapon(bestSet[16]) then
                        bestSet[17] = nil
                        usedItems[itemKey] = nil
                    else
                        break
                    end
                end
            end
        end
        return bestSet
    end

    -- ====================================================================
    -- HELPER: ensure every currently-equipped slot is populated
    -- ====================================================================
    local function FillEquippedFallback(bestSet)
        for _, item in ipairs(allItems) do
            if item.isEquipped and not bestSet[item.slot] then
                -- Don't fill OH if MH is a 2H weapon
                if item.slot == 17 and bestSet[16] and Is2HWeapon(bestSet[16]) then
                    -- skip offhand
                else
                    local stats = addon:ExtractItemStats(item.link)
                    local score = addon:CalculateScore(stats, specData)
                    bestSet[item.slot] = {
                        link = item.link, bag = nil, slot = item.slot,
                        isEquipped = true, score = score, slots = { item.slot }, stats = stats,
                    }
                end
            end
        end
    end

    -- ====================================================================
    -- HELPER: Sum a specific stat across all items in a gear set
    -- ====================================================================
    local function SumSetStat(gearSet, statKey)
        local total = 0
        for _, item in pairs(gearSet) do
            if item.stats then
                total = total + (item.stats[statKey] or 0)
            end
        end
        return total
    end

    -- ====================================================================
    -- STEP 1: Normal single-pass optimization (best DPS/throughput)
    -- ====================================================================
    local scoredItems = BuildScoredItems(allItems)
    table.sort(scoredItems, function(a, b) return self:CompareOptimizerItems(a, b) end)
    local bestSet = AssignSlots(scoredItems)
    FillEquippedFallback(bestSet)
    -- Ascension Strength path is always a two-handed build. Pick the
    -- highest-scoring usable 2H weapon and leave the off-hand empty.
    -- If the player owns no usable 2H weapon, retain the normal fallback
    -- so the generated set never removes their only weapon.
    local forceStrengthTwoHander = class == "HERO" and specData.path == "strength"
    local forceShieldTank = self:ShouldForceShieldTank(specData)
    local function EnforceStrengthTwoHander()
        if not forceStrengthTwoHander then return end
        for _, item in ipairs(scoredItems) do
            if Is2HWeapon(item) then
                bestSet[16] = item
                bestSet[17] = nil
                return
            end
        end
    end

    EnforceStrengthTwoHander()
    if not self:EnforceWeaponSubtypeMode(bestSet, scoredItems) then
        if not self:EnforceWeaponMode(bestSet, scoredItems) then
            if forceShieldTank then
                self:EnforceShieldTankWeapons(bestSet, scoredItems)
            end
        end
    end
    self:EnforceRangedMode(bestSet, scoredItems)

    -- ====================================================================
    -- 2H vs MH+OH CHECK
    -- If a 2H weapon won slot 16, see if the best 1H + best OH would
    -- score higher combined.  If so, swap them in.
    -- ====================================================================
    if not forceStrengthTwoHander and not forceShieldTank
        and self:GetSelectedWeaponMode() ~= "staff_shield"
        and not self:GetSelectedWeaponSubtypeMode()
        and bestSet[16] and Is2HWeapon(bestSet[16]) then
        local twoHandScore = bestSet[16].score or 0
        local twoHandKey = bestSet[16].isEquipped and ("EQ_"..bestSet[16].slot)
                           or ("BAG_"..(bestSet[16].bag or 0).."_"..bestSet[16].slot)

        -- Find best 1H mainhand and best offhand from scored items
        local bestMH, bestOH
        local usedKeys = {}
        for slotID, item in pairs(bestSet) do
            if slotID ~= 16 and slotID ~= 17 then
                local k = item.isEquipped and ("EQ_"..item.slot) or ("BAG_"..(item.bag or 0).."_"..item.slot)
                usedKeys[k] = true
            end
        end

        for _, item in ipairs(scoredItems) do
            local eLoc = item.equipLoc
            if eLoc and eLoc ~= "INVTYPE_2HWEAPON" then
                local k = item.isEquipped and ("EQ_"..item.slot) or ("BAG_"..(item.bag or 0).."_"..item.slot)
                if k ~= twoHandKey and not usedKeys[k] then
                    local isMH = (eLoc == "INVTYPE_WEAPON" or eLoc == "INVTYPE_WEAPONMAINHAND")
                    local isOH = (eLoc == "INVTYPE_WEAPONOFFHAND" or eLoc == "INVTYPE_HOLDABLE" or eLoc == "INVTYPE_SHIELD")
                    -- INVTYPE_WEAPON can go in either hand
                    if not bestMH and (isMH or eLoc == "INVTYPE_WEAPON") then
                        bestMH = item
                        local mk = item.isEquipped and ("EQ_"..item.slot) or ("BAG_"..(item.bag or 0).."_"..item.slot)
                        usedKeys[mk] = true
                    elseif not bestOH and (isOH or (eLoc == "INVTYPE_WEAPON" and bestMH)) then
                        bestOH = item
                        local ok = item.isEquipped and ("EQ_"..item.slot) or ("BAG_"..(item.bag or 0).."_"..item.slot)
                        usedKeys[ok] = true
                    end
                end
            end
            if bestMH and bestOH then break end
        end

        local dualScore = (bestMH and bestMH.score or 0) + (bestOH and bestOH.score or 0)
        if bestMH and dualScore > twoHandScore then
            bestSet[16] = bestMH
            bestSet[17] = bestOH  -- may be nil if no OH found, that's fine
        end
    end

    -- ====================================================================
    -- STEP 2: MOO-STYLE ITERATIVE CAP SWAPS
    -- Check each active cap against the ACTUAL items in the set. If a cap
    -- is not met, iteratively swap a slot's item for the best cap-stat
    -- alternative, choosing the swap with the best cap-gained per
    -- score-lost ratio. Repeat until the cap is met or no swaps help.
    -- ====================================================================
    local caps = CharacterGearOptimizerDB and CharacterGearOptimizerDB.capPriorities or {}
    local anyCap = caps.critImmune or caps.hitCapped or caps.spellHitCapped or caps.expertiseCapped or caps.uncrushable or caps.armorCapped or caps.resilCapped or caps.hasteCapped

    if anyCap then
        local R = self.RATING
        local role = specData.role or "melee_dps"

        -- Compute the base (non-gear) contribution for each cap stat.
        -- base = playerTotal - sumFromCurrentlyEquippedItems
        -- This captures talents, buffs, racial, etc. that are independent
        -- of which gear we choose.
        local function GetBaseDefense()
            if not UnitDefense then return 350 end
            local baseDef, modDef = UnitDefense("player")
            local totalDefSkill = (baseDef or 0) + (modDef or 0)
            local gearDefRating = 0
            for slot = 1, 19 do
                local link = GetInventoryItemLink("player", slot)
                if link then
                    local st = addon:ExtractItemStats(link)
                    gearDefRating = gearDefRating + (st["DEF"] or 0)
                end
            end
            local gearDefSkill = gearDefRating / R.DEFENSE_PER_SKILL
            return totalDefSkill - gearDefSkill  -- base + talent defense skill
        end

        local function GetBaseHitPct(crID)
            if not GetCombatRating then return 0 end
            local hitRating = GetCombatRating(crID) or 0
            local ratingPer = (crID == R.CR_HIT_SPELL) and R.SPELL_HIT_PER_PCT or R.HIT_PER_PCT
            local hitPctFromGear = hitRating / ratingPer
            local totalHitPct = self:GetTotalHitChance(crID)
            return totalHitPct - hitPctFromGear  -- talent + racial hit
        end

        local function GetBaseExpertise()
            if not GetExpertise then return 0 end
            local totalExp = GetExpertise() or 0
            local expRating = 0
            if GetCombatRating then
                expRating = GetCombatRating(R.CR_EXPERTISE) or 0
            end
            local expFromGear = expRating / R.EXPERTISE_PER_SKILL
            return totalExp - expFromGear  -- base + talent expertise
        end

        local function GetBaseResilPct()
            if not GetCombatRating then return 0 end
            local resilRating = GetCombatRating(R.CR_RESILIENCE) or 0
            local resilPctFromGear = resilRating / R.RESIL_PER_PCT
            local totalResilPct = GetCombatRatingBonus(R.CR_RESILIENCE) or 0
            return totalResilPct - resilPctFromGear
        end

        local function GetBaseAvoidance()
            local totalDefSkill = 350
            if UnitDefense then
                local baseDef, modDef = UnitDefense("player")
                totalDefSkill = (baseDef or 0) + (modDef or 0)
            end
            local missPct  = R.BASE_MISS_PCT + (totalDefSkill - 350) * 0.04
            local dodgePct = GetDodgeChance and GetDodgeChance() or 0
            local parryPct = GetParryChance and GetParryChance() or 0
            local blockPct = GetBlockChance and GetBlockChance() or 0
            local totalAvoid = missPct + dodgePct + parryPct + blockPct
            local gearAvoid = 0
            for slot = 1, 19 do
                local link = GetInventoryItemLink("player", slot)
                if link then
                    local st = addon:ExtractItemStats(link)
                    local dR = st["DEF"] or 0
                    local doR = st["DODGE"] or 0
                    local pR = st["PARRY"] or 0
                    local bR = st["BLOCK_RATING"] or 0
                    gearAvoid = gearAvoid
                        + (dR / R.DEFENSE_PER_SKILL) * R.AVOID_PER_DEF_SKILL
                        + doR / R.DODGE_PER_RATING
                        + pR / R.PARRY_PER_RATING
                        + bR / R.BLOCK_PER_RATING
                end
            end
            return totalAvoid - gearAvoid
        end

        -- Build cap goals with TOTAL rating needed from gear
        local capGoals = {}
        local pvp = caps.pvpMode

        if caps.critImmune then
            local baseDef = GetBaseDefense()
            if baseDef < R.DEFENSE_CAP then
                local defSkillFromGear = R.DEFENSE_CAP - baseDef
                local totalDefRatingNeeded = defSkillFromGear * R.DEFENSE_PER_SKILL
                table.insert(capGoals, {
                    stat = "DEF",
                    totalRatingNeeded = totalDefRatingNeeded,
                    ratingPerUnit = R.DEFENSE_PER_SKILL,
                    label = "Defense",
                })
            end
            local baseResil = GetBaseResilPct()
            if baseResil < R.BOSS_CRIT_PCT then
                local resilPctFromGear = R.BOSS_CRIT_PCT - baseResil
                local totalResilRatingNeeded = resilPctFromGear * R.RESIL_PER_PCT
                table.insert(capGoals, {
                    stat = "RESIL",
                    totalRatingNeeded = totalResilRatingNeeded,
                    ratingPerUnit = R.RESIL_PER_PCT,
                    label = "Resilience",
                })
            end
        end

        if caps.hitCapped then
            local hitCapPct = pvp and R.PVP_MELEE_HIT_CAP_PCT or R.MELEE_HIT_CAP_PCT
            local baseHit = GetBaseHitPct(R.CR_HIT_MELEE)
            if baseHit < hitCapPct then
                local hitPctFromGear = hitCapPct - baseHit
                table.insert(capGoals, {
                    stat = "HIT",
                    totalRatingNeeded = hitPctFromGear * R.HIT_PER_PCT,
                    ratingPerUnit = R.HIT_PER_PCT,
                    label = "Melee Hit",
                })
            end
        end

        if caps.spellHitCapped then
            local shCapPct = pvp and R.PVP_SPELL_HIT_CAP_PCT or R.SPELL_HIT_CAP_PCT
            local baseHit = GetBaseHitPct(R.CR_HIT_SPELL)
            if baseHit < shCapPct then
                local hitPctFromGear = shCapPct - baseHit
                -- Use synthetic SPELL_HIT_TOTAL so both HIT and SPELLHIT items count
                table.insert(capGoals, {
                    stat = "SPELL_HIT_TOTAL",
                    totalRatingNeeded = hitPctFromGear * R.SPELL_HIT_PER_PCT,
                    ratingPerUnit = R.SPELL_HIT_PER_PCT,
                    label = "Spell Hit",
                })
            end
        end

        if caps.expertiseCapped then
            if role == "melee_dps" or role == "tank" then
                local expCap = pvp and R.PVP_EXPERTISE_SOFT_CAP or R.EXPERTISE_SOFT_CAP
                local baseExp = GetBaseExpertise()
                if baseExp < expCap then
                    local expFromGear = expCap - baseExp
                    table.insert(capGoals, {
                        stat = "EXP",
                        totalRatingNeeded = expFromGear * R.EXPERTISE_PER_SKILL,
                        ratingPerUnit = R.EXPERTISE_PER_SKILL,
                        label = "Expertise",
                    })
                end
            end
        end

        if caps.uncrushable then
            local baseAvoid = GetBaseAvoidance()
            if baseAvoid < R.UNCRUSHABLE_PCT then
                table.insert(capGoals, {
                    stat = "AVOID",
                    totalRatingNeeded = R.UNCRUSHABLE_PCT - baseAvoid,
                    label = "Uncrushable",
                })
            end
        end

        if caps.armorCapped then
            local armorCapVal = pvp and R.PVP_ARMOR_CAP_VALUE or R.ARMOR_CAP_VALUE
            local _, currentArmor = UnitArmor("player")
            local gearArmor = 0
            for slot = 1, 19 do
                local link = GetInventoryItemLink("player", slot)
                if link then
                    local st = addon:ExtractItemStats(link)
                    gearArmor = gearArmor + (st["ARMOR"] or 0)
                end
            end
            local baseArmor = (currentArmor or 0) - gearArmor
            if baseArmor < armorCapVal then
                table.insert(capGoals, { stat = "ARMOR", totalRatingNeeded = armorCapVal - baseArmor, label = "Armor Cap" })
            end
        end

        if caps.resilCapped then
            local baseResil = GetBaseResilPct()
            if baseResil < R.RESIL_CRIT_IMMUNE_PCT then
                table.insert(capGoals, { stat = "RESIL", totalRatingNeeded = (R.RESIL_CRIT_IMMUNE_PCT - baseResil) * R.RESIL_PER_PCT, label = "Resilience" })
            end
        end

        if caps.hasteCapped then
            local hasteID = (role == "caster_dps" or role == "healer") and R.CR_HASTE_SPELL or R.CR_HASTE_MELEE
            local hasteRating = GetCombatRating and GetCombatRating(hasteID) or 0
            local hastePer = R.HASTE_PER_PCT
            local totalHastePct = GetCombatRatingBonus and GetCombatRatingBonus(hasteID) or 0
            local baseHaste = totalHastePct - (hasteRating / hastePer)
            if baseHaste < R.HASTE_GCD_CAP_PCT then
                table.insert(capGoals, { stat = "HASTE", totalRatingNeeded = (R.HASTE_GCD_CAP_PCT - baseHaste) * hastePer, label = "Haste" })
            end
        end

        -- Build a lookup: for each slot, what's the best alternative item
        -- with cap stat X? Pre-sort per-slot candidates by cap stat value.
        -- Trinkets (13/14) are excluded: they're never auto-swapped, cap
        -- goals included, since their value is usually in on-use/proc
        -- effects the weight and cap systems can't judge.
        local slotCandidates = {}  -- [slotID][statKey] = sorted list of items
        for _, item in ipairs(scoredItems) do
            for _, s in ipairs(item.slots) do
                if s ~= 13 and s ~= 14 then
                    slotCandidates[s] = slotCandidates[s] or {}
                    for _, goal in ipairs(capGoals) do
                        local capVal = item.stats[goal.stat] or 0
                        if capVal > 0 then
                            slotCandidates[s][goal.stat] = slotCandidates[s][goal.stat] or {}
                            table.insert(slotCandidates[s][goal.stat], item)
                        end
                    end
                end
            end
        end

        -- Sort each candidate list by cap stat descending
        for slotID, statLists in pairs(slotCandidates) do
            for stat, list in pairs(statLists) do
                table.sort(list, function(a, b)
                    return (a.stats[stat] or 0) > (b.stats[stat] or 0)
                end)
            end
        end

        -- Iterative swap loop for each cap goal
        for _, goal in ipairs(capGoals) do
            local MAX_SWAPS = 20  -- safety limit
            for _ = 1, MAX_SWAPS do
                -- How much of this stat does the current set provide?
                local currentRating = SumSetStat(bestSet, goal.stat)
                local deficit = goal.totalRatingNeeded - currentRating
                if deficit <= 0 then break end  -- cap met!

                -- Find the best swap across all slots
                local bestSwap = nil  -- { slotID, newItem, capGained, scoreLost, efficiency }

                for slotID, item in pairs(bestSet) do
                    local currentCapVal = item.stats and (item.stats[goal.stat] or 0) or 0
                    local currentScore  = item.score or 0
                    local candidates = slotCandidates[slotID] and slotCandidates[slotID][goal.stat]
                    if candidates then
                        for _, cand in ipairs(candidates) do
                            -- Don't swap with itself
                            local candKey = cand.isEquipped and ("EQ_"..cand.slot) or ("BAG_"..(cand.bag or 0).."_"..cand.slot)
                            local curKey  = item.isEquipped and ("EQ_"..item.slot) or ("BAG_"..(item.bag or 0).."_"..item.slot)
                            if candKey ~= curKey then
                                -- Check this candidate isn't already used in another slot
                                local alreadyUsed = false
                                for otherSlot, otherItem in pairs(bestSet) do
                                    if otherSlot ~= slotID then
                                        local otherKey = otherItem.isEquipped and ("EQ_"..otherItem.slot) or ("BAG_"..(otherItem.bag or 0).."_"..otherItem.slot)
                                        if otherKey == candKey then
                                            alreadyUsed = true
                                            break
                                        end
                                    end
                                end

                                if not alreadyUsed then
                                    local candCapVal = cand.stats[goal.stat] or 0
                                    local capGained = candCapVal - currentCapVal
                                    if capGained > 0 then
                                        local scoreLost = currentScore - cand.score
                                        -- efficiency = cap gained per point of score lost
                                        -- If scoreLost <= 0 (swap is free or an upgrade), efficiency is infinite
                                        local eff = (scoreLost > 0) and (capGained / scoreLost) or (capGained * 1000)
                                        if not bestSwap or eff > bestSwap.efficiency then
                                            bestSwap = {
                                                slotID = slotID,
                                                newItem = cand,
                                                capGained = capGained,
                                                scoreLost = scoreLost,
                                                efficiency = eff,
                                            }
                                        end
                                    end
                                    break  -- found a usable candidate for this slot
                                end
                                -- candidate was already used; try next best
                            end
                        end
                    end
                end

                if not bestSwap then break end  -- no beneficial swap found
                bestSet[bestSwap.slotID] = bestSwap.newItem
                -- 2H/OH mutual exclusion after cap swap
                if bestSwap.slotID == 16 and Is2HWeapon(bestSwap.newItem) then
                    bestSet[17] = nil
                elseif bestSwap.slotID == 17 and bestSet[16] and Is2HWeapon(bestSet[16]) then
                    bestSet[bestSwap.slotID] = nil  -- can't put OH with 2H
                end
            end
        end
    end

    -- Cap swaps can reconsider weapon slots, so apply hard weapon rules once
    -- more to the finished set.
    EnforceStrengthTwoHander()
    if not self:EnforceWeaponSubtypeMode(bestSet, scoredItems) then
        if not self:EnforceWeaponMode(bestSet, scoredItems) then
            if forceShieldTank then
                self:EnforceShieldTankWeapons(bestSet, scoredItems)
            end
        end
    end
    self:EnforceRangedMode(bestSet, scoredItems)
    self:EnforceHeirloomPreference(bestSet, scoredItems, specData, class)
    return bestSet, specData
end

-- Helper matching equipLoc to Inventory Slot IDs
-- Returns a table of possible slots (e.g. Finger can go to 11 or 12)
function addon:GetValidSlotsForEquipLoc(equipLoc, link)
    if not equipLoc or equipLoc == "EQUIPPED" then 
        -- If it's already equipped and we don't have its raw equipLoc, we cheat by using its current slot.
        -- But really we should always have equipLoc from GetItemInfo.
        local _, _, _, _, _, _, _, _, eLoc = GetItemInfo(link)
        equipLoc = eLoc
    end

    if equipLoc == "INVTYPE_FINGER" then return {11, 12} end
    if equipLoc == "INVTYPE_TRINKET" then return {13, 14} end
    if equipLoc == "INVTYPE_WEAPON" then return {16, 17} end
    
    local defaultSlot = self.SLOT_MAP[equipLoc]
    if defaultSlot then return {defaultSlot} end
    
    return {}
end

-- ============================================================================
-- Get all scored items that can go into a specific inventory slot
-- Returns a sorted list (highest score first) for the slot picker dropdown
-- ============================================================================
function addon:GetItemsForSlot(invSlot, specData)
    if not specData then return {} end

    -- Build reverse lookup: which equipLocs map to this invSlot
    local validEquipLocs = {}
    for loc, s in pairs(self.SLOT_MAP) do
        if s == invSlot then
            validEquipLocs[loc] = true
        end
    end
    -- Rings and trinkets have dual slots
    if invSlot == 12 then validEquipLocs["INVTYPE_FINGER"] = true end
    if invSlot == 14 then validEquipLocs["INVTYPE_TRINKET"] = true end
    if invSlot == 17 then
        validEquipLocs["INVTYPE_WEAPON"] = true
        validEquipLocs["INVTYPE_WEAPONOFFHAND"] = true
        validEquipLocs["INVTYPE_HOLDABLE"] = true
        validEquipLocs["INVTYPE_SHIELD"] = true
    end

    local results = {}

    -- Currently equipped item in this slot
    local eqLink = GetInventoryItemLink("player", invSlot)
    if eqLink then
        local stats = self:ExtractItemStats(eqLink)
        local score = self:CalculateScore(stats, specData)
        table.insert(results, { link = eqLink, score = score, source = "Equipped" })
    end

    -- Scan bags
    for bag = 0, 4 do
        local numSlots = GetNumSlots(bag)
        for slot = 1, numSlots do
            local link = GetItemLink(bag, slot)
            if link then
                local name, _, _, _, _, _, _, _, equipLoc = GetItemInfo(link)
                if equipLoc and validEquipLocs[equipLoc] then
                    local stats = self:ExtractItemStats(link)
                    local score = self:CalculateScore(stats, specData)
                    table.insert(results, { link = link, score = score, source = "Bag", bag = bag, slot = slot })
                end
            end
        end
    end

    -- Scan bank bags when the bank frame is open
    if self.bankOpen then
        local bankBags = { -1, 5, 6, 7, 8, 9, 10, 11 }
        for _, bag in ipairs(bankBags) do
            local numSlots = GetNumSlots(bag)
            for slot = 1, numSlots do
                local link = GetItemLink(bag, slot)
                if link then
                    local name, _, _, _, _, _, _, _, equipLoc = GetItemInfo(link)
                    if equipLoc and validEquipLocs[equipLoc] then
                        local stats = self:ExtractItemStats(link)
                        local score = self:CalculateScore(stats, specData)
                        table.insert(results, { link = link, score = score, source = "Bank", bag = bag, slot = slot })
                    end
                end
            end
        end
    end

    -- Sort descending by score (heirlooms first when Not 60 is checked)
    table.sort(results, function(a, b)
        return self:CompareOptimizerItems(
            { score = a.score, isHeirloom = self:IsHeirloomItem(a.link) },
            { score = b.score, isHeirloom = self:IsHeirloomItem(b.link) }
        )
    end)

    return results
end

-- ComputeCapBoosts is a no-op stub kept for backward compat with UI_Panel calls.
-- The real cap logic now lives in the two-pass MOO algorithm inside GetBestGearForSpec.
function addon:ComputeCapBoosts(specData)
    self.activeCapBoosts = nil
end
