local addonName, addon = ...
_G.CharacterGearOptimizer = _G.CharacterGearOptimizer or {}

-- ============================================================================
-- EQUIP MANAGER
-- Handles saving sets, loading sets, and equipping gear
-- ============================================================================

local equipQueue = {}
local isEquipping = false
local pullWaitTimer = 0        -- throttle after pulling from bank
local PULL_WAIT_SECONDS = 0.5  -- wait for bankâ†’bag transfer to settle
local equipFrame = CreateFrame("Frame")
local acceptBindUntil = 0

-- NOTE: "AUTOEQUIP_BIND_CONFIRM" is not a real Blizzard event (verified against
-- retail EventRouting.lua) -- only EQUIP_BIND_CONFIRM, EQUIP_BIND_TRADEABLE_CONFIRM,
-- and EQUIP_BIND_REFUNDABLE_CONFIRM exist. Registering it throws
-- "Attempt to register unknown event" on modern clients, so only the real
-- event is registered here.
equipFrame:RegisterEvent("EQUIP_BIND_CONFIRM")
equipFrame:RegisterEvent("EQUIP_BIND_TRADEABLE_CONFIRM")
equipFrame:RegisterEvent("EQUIP_BIND_REFUNDABLE_CONFIRM")
equipFrame:SetScript("OnEvent", function(self, event, slot)
    -- Accept binding only for items equipped by CGO's own queue. Keep a short
    -- grace window because the confirmation may dispatch one frame after the
    -- final queued item has been processed.
    if (isEquipping or GetTime() <= acceptBindUntil) and EquipPendingItem and slot then
        EquipPendingItem(slot)
        if StaticPopup_Hide then
            StaticPopup_Hide("EQUIP_BIND")
            StaticPopup_Hide("EQUIP_BIND_TRADEABLE")
            StaticPopup_Hide("EQUIP_BIND_REFUNDABLE")
        end
    end
end)

-- Simple frame update to throttle equipping (1 item per frame to avoid being blocked)
equipFrame:SetScript("OnUpdate", function(self, elapsed)
    if #equipQueue == 0 then
        isEquipping = false
        return
    end

    if InCombatLockdown() then
        print("|cFFFFD700CharacterGearOptimizer:|r Cannot equip gear while in combat!")
        equipQueue = {}
        isEquipping = false
        return
    end

    -- If we just pulled from bank, wait a moment for the transfer
    if pullWaitTimer > 0 then
        pullWaitTimer = pullWaitTimer - elapsed
        return
    end

    local task = equipQueue[1]

    if task.type == "PULL_FROM_BANK" then
        -- Move item from bank to bags using UseContainerItem (auto-transfers when bank is open)
        table.remove(equipQueue, 1)
        local bankBag, bankSlot = task.bankBag, task.bankSlot
        local link = GetContainerItemLink(bankBag, bankSlot)
        if link then
            ClearCursor()
            -- UseContainerItem auto-moves bank<->bag when bank frame is open
            if UseContainerItem then
                UseContainerItem(bankBag, bankSlot)
            else
                -- Fallback: pick up and place manually
                PickupContainerItem(bankBag, bankSlot)
                -- Try to put into any bag with space
                for b = 0, 4 do
                    local free = GetContainerNumFreeSlots(b)
                    if free and free > 0 then
                        PutItemInBag(ContainerIDToInventoryID(b))
                        break
                    end
                end
            end
            ClearCursor()
            pullWaitTimer = PULL_WAIT_SECONDS
        else
            print("|cFFFFD700CGO:|r Bank item no longer at expected slot.")
        end

    elseif task.type == "EQUIP" then
        table.remove(equipQueue, 1)
        -- Find the item in bags (regular bags only)
        local foundBag, foundSlot = addon:FindItemInBags(task.link)
        if foundBag and foundSlot then
            -- The Equip Set button is the user's authorization to equip the
            -- selected upgrade, including accepting its Bind-on-Equip prompt.
            acceptBindUntil = GetTime() + 2
            ClearCursor()
            PickupContainerItem(foundBag, foundSlot)
            EquipCursorItem(task.invSlot)
            ClearCursor()
        else
            -- Item might still be transferring; re-queue with a retry
            if not task.retries or task.retries < 5 then
                task.retries = (task.retries or 0) + 1
                table.insert(equipQueue, 1, task)
                pullWaitTimer = PULL_WAIT_SECONDS
            end
        end
    else
        table.remove(equipQueue, 1)
    end
end)

function addon:FindItemInBags(itemLink)
    -- Compare by exact string link or itemID. 
    -- Link matching is safer for enchants/gems if they match exactly.
    local searchID = tonumber(itemLink:match("item:(%d+)"))
    if not searchID then return nil, nil end

    -- Exact link match first (bags only)
    for bag = 0, 4 do
        local numSlots = GetContainerNumSlots(bag) or 0
        for slot = 1, numSlots do
            local link = GetContainerItemLink(bag, slot)
            if link then
                local id = tonumber(link:match("item:(%d+)"))
                if id == searchID then
                    if link == itemLink then
                        return bag, slot
                    end
                end
            end
        end
    end
    
    -- Fallback to ID match if exact enchant string changed (durability etc)
    for bag = 0, 4 do
        local numSlots = GetContainerNumSlots(bag) or 0
        for slot = 1, numSlots do
            local link = GetContainerItemLink(bag, slot)
            if link then
                local id = tonumber(link:match("item:(%d+)"))
                if id == searchID then
                    return bag, slot
                end
            end
        end
    end

    return nil, nil
end

-- Search bank containers for an item (bag -1 = main bank, 5-11 = bank bags)
function addon:FindItemInBank(itemLink)
    local searchID = tonumber(itemLink:match("item:(%d+)"))
    if not searchID then return nil, nil end

    local bankBags = { -1, 5, 6, 7, 8, 9, 10, 11 }

    -- Exact link first
    for _, bag in ipairs(bankBags) do
        local numSlots = GetContainerNumSlots(bag) or 0
        for slot = 1, numSlots do
            local link = GetContainerItemLink(bag, slot)
            if link and link == itemLink then
                return bag, slot
            end
        end
    end

    -- Fallback to item ID
    for _, bag in ipairs(bankBags) do
        local numSlots = GetContainerNumSlots(bag) or 0
        for slot = 1, numSlots do
            local link = GetContainerItemLink(bag, slot)
            if link then
                local id = tonumber(link:match("item:(%d+)"))
                if id == searchID then
                    return bag, slot
                end
            end
        end
    end

    return nil, nil
end

function addon:EquipSet(setName)
    if InCombatLockdown() then
        print("|cFFFFD700CharacterGearOptimizer:|r Cannot change sets in combat.")
        return
    end

    local set = CharacterGearOptimizerDB.sets and CharacterGearOptimizerDB.sets[setName]
    if not set then return end

    equipQueue = {}
    pullWaitTimer = 0
    print("|cFFFFD700CharacterGearOptimizer:|r Equipping set: " .. setName)

    local bankPulls = {}  -- items that need to come from bank first
    local directEquips = {}

    for slot, itemInfo in pairs(set.items) do
        local currentLink = GetInventoryItemLink("player", slot)
        if currentLink ~= itemInfo.link then
            -- Check bags first
            local foundBag, foundSlot = addon:FindItemInBags(itemInfo.link)
            if foundBag then
                table.insert(directEquips, {
                    type = "EQUIP",
                    link = itemInfo.link,
                    invSlot = slot,
                })
            elseif addon.bankOpen then
                -- Try the bank
                local bankBag, bankSlot = addon:FindItemInBank(itemInfo.link)
                if bankBag then
                    table.insert(bankPulls, {
                        link = itemInfo.link,
                        invSlot = slot,
                        bankBag = bankBag,
                        bankSlot = bankSlot,
                    })
                end
            end
        end
    end

    -- Queue bank pulls first, then the equip for that item
    for _, pull in ipairs(bankPulls) do
        table.insert(equipQueue, {
            type = "PULL_FROM_BANK",
            bankBag = pull.bankBag,
            bankSlot = pull.bankSlot,
        })
        table.insert(equipQueue, {
            type = "EQUIP",
            link = pull.link,
            invSlot = pull.invSlot,
        })
    end

    -- Then queue direct equips from bags
    for _, eq in ipairs(directEquips) do
        table.insert(equipQueue, eq)
    end
    
    if #equipQueue > 0 then
        isEquipping = true
    end
end

function addon:SaveSet(setName, bestSetData, icon)
    CharacterGearOptimizerDB.sets = CharacterGearOptimizerDB.sets or {}
    
    local itemsToSave = {}
    for slot, data in pairs(bestSetData) do
        itemsToSave[slot] = {
            link = data.link,
            score = data.score
        }
    end

    -- Use the helmet icon from the set if no explicit icon is provided
    if not icon or icon == "" then
        local headItem = itemsToSave[1]
        if headItem and headItem.link then
            local _, _, _, _, _, _, _, _, _, tex = GetItemInfo(headItem.link)
            if tex then icon = tex end
        end
    end

    CharacterGearOptimizerDB.sets[setName] = {
        icon = icon or "Interface/Icons/INV_Misc_QuestionMark",
        items = itemsToSave
    }

    print("|cFFFFD700CharacterGearOptimizer:|r Saved set: " .. setName)

    -- New set membership changes what Sell-O-Matic is allowed to sell.
    if _G.CGOMarkSellProtectionDirty then _G.CGOMarkSellProtectionDirty() end

    -- Notify the HUD to refresh
    if addon.RefreshHUD then
        addon:RefreshHUD()
    end
end

-- ============================================================================
-- BANK NON-EQUIPPED GEAR
-- Deposits all equippable items from bags into the bank.
-- Only works while the bank frame is open.
-- ============================================================================
function addon:BankNonEquipped()
    if not addon.bankOpen then
        print("|cFFFFD700CGO:|r Open the bank first!")
        return
    end
    if InCombatLockdown() then
        print("|cFFFFD700CGO:|r Cannot bank items in combat.")
        return
    end

    local UseItem = UseContainerItem
    if not UseItem then
        print("|cFFFFD700CGO:|r UseContainerItem API not available.")
        return
    end

    local count = 0
    -- Iterate bags in reverse so slot indices don't shift as items are removed
    for bag = 4, 0, -1 do
        local numSlots = GetContainerNumSlots(bag) or 0
        for slot = numSlots, 1, -1 do
            local link = GetContainerItemLink(bag, slot)
            if link then
                local _, _, _, _, _, _, _, _, equipLoc = GetItemInfo(link)
                if equipLoc and addon.SLOT_MAP and addon.SLOT_MAP[equipLoc] then
                    UseItem(bag, slot)
                    count = count + 1
                end
            end
        end
    end

    if count > 0 then
        print(string.format("|cFFFFD700CGO:|r Deposited %d gear item(s) to bank.", count))
    else
        print("|cFFFFD700CGO:|r No loose gear in bags to bank.")
    end
end
