-- File: SellOMatic.lua
-- Merged into CharacterGearOptimizer. All original Sell-O-Matic behavior is
-- preserved; the only addition is an upgrade-protection layer: items that are
-- an upgrade for ANY profile (or part of any saved/displayed set) are never
-- sold, even when their quality matches a sell rule.

local addonName, addon = ...

-- This function sells items of a specific quality.
-- Update the SellItems function to check against the blacklist
local categories = {"Cloth", "OresAndBars", "Righteous Orbs", "Herbs", "Highrisk"} -- Use this for consistency
local blacklist = {}

local itemsToSellByCategory = {
  Cloth = {
      "Runecloth",
      "Netherweave Cloth",
      "Frostweave Cloth",
      "Mageweave Cloth",
      "Silk Cloth",
      "Wool Cloth",
      "Linen Cloth",
      "Felcloth",
      "Shadow Silk",
      "Ebonweave",
      "Moonshroud",
      "Spellweave",
      "Iceweb Spider Silk",
      "Primal Mooncloth",
      "Shadoweave Cloth",
      "Spellfire Cloth",
      "Spellcloth",
      "Shadowcloth",
      "Soucloth",
      "Netherweb Spider Silk",
      "Mooncloth",
      "Ironweb Spider Silk"
  },
  OresAndBars = {
      "Titanium Ore",
      "Froststeel Bar",
      "Titansteel Bar",
      "Titanium Bar",
      "Saronite Bar",
      "Hardened Saronite Bar",
      "Saronite Ore",
      "Azurite Bar",
      "Cobalt Ore",
      "Cobalt Bar",
      "Khorium Ore",
      "Eternium Ore",
      "Eternium Bar",
      "Khorium Bar",
      "Hardened Khorium",
      "Adamantite Ore",
      "Adamantite Bar",
      "Hardened Adamantite Bar",
      "Elementium Bar",
      "Sulfuron Ingot",
      "Elementium Ore",
      "Guardian Stone",
      "Felsteel Bar",
      "Elemental Flux",
      "Fel Iron Ore",
      "Fel Iron Bar",
      "Arcanite Bar",
      "Enchanted Thorium Bar",
      "Truesilver Bar",
      "Dark Iron Ore",
      "Dark Iron Bar",
      "Thorium Bar",
      "Dense Stone",
      "Dense Grinding Stone",
      "Truesilver Ore",
      "Mithril Ore",
      "Mithril Bar",
      "Thorium Ore",
      "Steel Bar",
      "Solid Grinding Stone",
      "Gold Bar",
      "Iron Ore",
      "Iron Bar",
      "Coal",
      "Gold Ore",
      "Heavy Stone",
      "Heavy Grinding Stone",
      "Tin Ore",
      "Bronze Bar"
  },
      RighteousOrbs = { 
          "Righteous Orb" 
  },  -- This list contains only one item for the example
      Herbs = {
          "Peacebloom",
          "Silverleaf",
          "Earthroot",
          "Frost Lotus",
          "Lichbloom",
          "Icethorn",
          "Adder's Tongue",
          "Constrictor Grass",
          "Goldclover",
          "Tiger Lily",
          "Talandra's Rose",
          "Deadnettle",
          "Fel Lotus",
          "Netherbloom",
          "Nightmare Vine",
          "Mana Thistle",
          "Nightmare Seed",
          "Ancient Lichen",
          "Flame Cap",
          "Ragveil",
          "Blood Scythe",
          "Black Lotus",
          "Bloodvine",
          "Felweed",
          "Dreaming Glory",
          "Terocone",
          "Icecap",
          "Plaguebloom",
          "Mountain Silversage",
          "Dreamfoil",
          "Golden Sansam",
          "Gromsblood",
          "Blindweed",
          "Ghost Mushroom",
          "Sungrass",
          "Arthas' Tears",
          "Purple Lotus",
          "Firebloom",
          "Wildvine",
          "Wintersbite",
          "Khadgar's Whisker",
          "Goldthorn",
          "Fadeleaf",
          "Liferoot",
          "Kingsblood",
          "Wild Steelbloom",
          "Grave Moss",
          "Bruiseweed",
          "Stranglekelp",
          "Briarthorn",
          "Swiftthistle",
          "Mageroyal"
      },
      Highrisk = {
          "Scourge Tinged Meaty Limb",
          "Scourge Tinged Meat Chunks",
          "Sanguine Tinged Meat Chunks",
          "Nether Tinged Meat Chunks",
          "Dread Tinged Meaty Limb",
          "Dread Tinged Meat Chunks",
          "Demon Tinged Meaty Limb",
          "Demon Tinged Meat Chunks",
          "Core Tinged Meaty Limb",
          "Core Tinged Meat Chunks",
          "Void Tinged Trinket",
          "Twisted Tinged Trinket",
          "Scourge Tinged Trinket",
          "Dread Tinged Trinket",
          "Demon Tinged Trinket",
          "Core Tinged Trinket",
          "Frayed Winterweave",
          "Frayed Void Weave",
          "Frayed Twisted Weave",
          "Frayed Twilight Cloth",
          "Frayed Scourge Weave",
          "Frayed Scarlet Cloth",
          "Frayed Sanguine Weave",
          "Frayed Profane Cloth",
          "Frayed Plagueweave",
          "Frayed Nether Weave",
          "Frayed Infused Deadwind Cloth",
          "Frayed Dread Weave",
          "Frayed Dragonweave Cloth",
          "Frayed Demon Weave",
          "Frayed Core Weave",
          "Tainted Wintersteel",
          "Tainted Star Metal",
          "Tainted Plague Iron",
          "Tainted Meteorite Shards",
          "Tainted Living Irontree Bark",
          "Tainted Living Iron",
          "Tainted Fused Silithid Carapace",
          "Tainted Dragonsteel",
          "Tainted Chitin Alloy",
          "Tainted Beating Frostmaul Heart",
          "Tainted Abomination Chains",
          "Overwhelming Void Effigy",
          "Overwhelming Twisted Effigy",
          "Overwhelming Scourge Effigy",
          "Overwhelming Dread Effigy",
          "Overwhelming Demon Effigy",
          "Overwhelming Core Effigy"
      }
      }

-- add a print statement for how much gold you earned later

local itemsToBlacklist = {"Cloth", "OresAndBars", "Righteous Orbs", "Herbs", "Highrisk"}

-- ============================================================================
-- CGO UPGRADE PROTECTION
-- An item is protected (never sold) when ANY of the following is true:
--   1. Its name appears in any saved gear set
--   2. It is currently displayed in the optimizer panel's working set
--   3. It scores higher than the equipped item in the same slot under ANY
--      preset profile (class specs + HERO paths) or any custom stats profile
-- Protection is computed lazily per vendor visit and cached until bags,
-- equipment, or saved sets change.
-- ============================================================================
local protection = {
    byName = {},     -- itemName -> true
    dirty = true,    -- recompute on next query
}

local function MarkProtectionDirty()
    protection.dirty = true
end

-- Equipment changes can turn any bag item into (or out of) an upgrade.
local protListener = CreateFrame("Frame")
protListener:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
protListener:SetScript("OnEvent", MarkProtectionDirty)
-- Saving or deleting a set changes which names are protected.
hooksecurefunc(addon, "SaveSet", MarkProtectionDirty)

local function IsItemAnUpgradeForAnyProfile(link)
    if not link then return false end
    if not addon.ExtractItemStats or not addon.CalculateScore then return false end

    local _, _, _, _, _, _, _, _, equipLoc = GetItemInfo(link)
    if not equipLoc or not addon.SLOT_MAP[equipLoc] then return false end

    local itemStats = addon:ExtractItemStats(link)

    -- Collect every profile: class specs + HERO paths + custom stats profiles
    local profiles = {}
    local classSpecs = addon.CLASS_SPECS
    if classSpecs then
        for _, specs in pairs(classSpecs) do
            for _, specData in pairs(specs) do
                table.insert(profiles, specData)
            end
        end
    end
    local db = CharacterGearOptimizerDB
    if db and db.customStats then
        for _, weights in pairs(db.customStats) do
            table.insert(profiles, { role = "melee_dps", weights = weights })
        end
    end

    -- Slots this item could occupy (rings/trinkets/weapons fit two)
    local slotsToCheck
    if equipLoc == "INVTYPE_FINGER" then slotsToCheck = { 11, 12 }
    elseif equipLoc == "INVTYPE_TRINKET" then slotsToCheck = { 13, 14 }
    elseif equipLoc == "INVTYPE_WEAPON" then slotsToCheck = { 16, 17 }
    else slotsToCheck = { addon.SLOT_MAP[equipLoc] } end

    -- Pre-extract equipped stats once per slot (not per profile)
    local equipped = {}
    for _, invSlot in ipairs(slotsToCheck) do
        local eqLink = GetInventoryItemLink("player", invSlot)
        if eqLink then
            equipped[invSlot] = { score = nil, stats = addon:ExtractItemStats(eqLink) }
        end
    end

    for _, specData in ipairs(profiles) do
        if specData.weights then
            local score = addon:CalculateScore(itemStats, specData)
            if score > 0 then
                for _, invSlot in ipairs(slotsToCheck) do
                    local eq = equipped[invSlot]
                    -- Empty relevant slot: anything with positive score is an
                    -- upgrade. Filled slot: must strictly beat current score.
                    local eqScore = eq and addon:CalculateScore(eq.stats, specData) or -1
                    if score > eqScore then
                        return true
                    end
                end
            end
        end
    end
    return false
end

local function RebuildProtection()
    protection.byName = {}

    -- 1) Names referenced by any saved set
    local db = CharacterGearOptimizerDB
    if db and db.sets then
        for _, setData in pairs(db.sets) do
            if type(setData) == "table" and setData.items then
                for _, itemInfo in pairs(setData.items) do
                    local name = GetItemInfo(itemInfo.link)
                    if name then protection.byName[name] = true end
                end
            end
        end
    end

    -- 2) Currently displayed working set in the panel
    if addon.currentBestSet then
        for _, item in pairs(addon.currentBestSet) do
            if type(item) == "table" and item.link then
                local name = GetItemInfo(item.link)
                if name then protection.byName[name] = true end
            end
        end
    end

    -- 3) Upgrade detection across all profiles (bag items only)
    if addon.GetAllAvailableItems then
        for bag = 0, 4 do
            local numSlots = GetContainerNumSlots and GetContainerNumSlots(bag) or 0
            for slot = 1, numSlots do
                local link = GetContainerItemLink(bag, slot)
                if link then
                    local ok, isUpgrade = pcall(IsItemAnUpgradeForAnyProfile, link)
                    if ok and isUpgrade then
                        local name = GetItemInfo(link)
                        if name then protection.byName[name] = true end
                    end
                end
            end
        end
    end

    protection.dirty = false
end

local function IsProtectedFromSelling(itemName)
    if not itemName then return false end
    if protection.dirty then RebuildProtection() end
    return protection.byName[itemName] == true
end

-- Expose so other modules can invalidate the cache (equip changes, set saves).
_G.CGOMarkSellProtectionDirty = MarkProtectionDirty

local function UpdateBlacklist()
  blacklist = {} -- Reset the blacklist
  for _, category in ipairs(categories) do
      local checkbox = _G["SellOMatic_Checkbox" .. category]
      if checkbox and checkbox:GetChecked() then
          for _, item in ipairs(itemsToSellByCategory[category]) do
              blacklist[item] = true
          end
      end
  end
end


-- Function to check if an item is blacklisted
local function IsBlacklisted(itemName)
  if not itemName then return false end
  -- Prefix rules: never sell these item families.
  if string.find(itemName, "^Bloodforged") then return true end
  return blacklist[itemName] == true
end

-- Combined gate used by every sell path: blacklist OR upgrade protection.
-- byName covers set membership and cached upgrades; for anything else that is
-- a wearable weapon/armor (quality 2+), fall back to a direct upgrade check
-- so an uncached item can never slip through during a vendor session.
local function IsSellable(itemName)
  if IsBlacklisted(itemName) then return false end
  if IsProtectedFromSelling(itemName) then return false end
  return true
end

-- Custom blacklist entries (added via minimap menu), persisted in settings.
local function GetCustomBlacklist()
    SellOMatic_Settings = SellOMatic_Settings or {}
    SellOMatic_Settings.customBlacklist = SellOMatic_Settings.customBlacklist or {}
    return SellOMatic_Settings.customBlacklist
end

local function AddToCustomBlacklist(itemName)
    if not itemName or itemName == "" then return end
    local custom = GetCustomBlacklist()
    if custom[itemName] then
        print("|cFFFFD700Sell-O-Matic:|r " .. itemName .. " is already blacklisted.")
        return
    end
    custom[itemName] = true
    blacklist[itemName] = true
    print("|cFFFFD700Sell-O-Matic:|r blacklisted |cffffffff" .. itemName .. "|r.")
end

local function RemoveFromCustomBlacklist(itemName)
    local custom = GetCustomBlacklist()
    if not custom[itemName] then return end
    custom[itemName] = nil
    blacklist[itemName] = nil
    print("|cFFFFD700Sell-O-Matic:|r removed |cffffffff" .. itemName .. "|r from the blacklist.")
end

local function LoadCustomBlacklist()
    local custom = GetCustomBlacklist()
    for name in pairs(custom) do
        blacklist[name] = true
    end
end

-- Updated SellItems function to sell items of a specific quality from the inventory to the vendor, excluding those in the blacklist.
local function SellItems(quality)
  if not MerchantFrame or not MerchantFrame:IsVisible() then return end
  if protection.dirty then RebuildProtection() end

  for bag = 0, 4 do
      for slot = 1, GetContainerNumSlots(bag) do
          local link = GetContainerItemLink(bag, slot)
          if link then
              local itemName, _, itemQuality = GetItemInfo(link)
              -- Name gate (blacklist + cached protections), then a live
              -- upgrade re-check by link so nothing slips through uncached.
              if itemQuality == quality and IsSellable(itemName) and not IsItemAnUpgradeForAnyProfile(link) then
                  UseContainerItem(bag, slot)
              end
          end
      end
  end
end

-- ============================================================================
-- AUTO-SELL GREYS (quality 0) whenever a vendor is opened. No button needed.
-- Sells one stack every 0.15s to avoid server action throttling, and re-scans
-- each tick so shifting bag slots never sell the wrong item.
-- ============================================================================
local function FormatMoney(copper)
    local gold = math.floor(copper / 10000)
    local silver = math.floor((copper % 10000) / 100)
    local rem = copper % 100
    if gold > 0 then return string.format("%dg %ds %dc", gold, silver, rem) end
    if silver > 0 then return string.format("%ds %dc", silver, rem) end
    return string.format("%dc", rem)
end

local function AutoSellEnabled()
    if not SellOMatic_Settings then return true end
    return SellOMatic_Settings.autoSellGreys ~= false
end

local autoSellFrame = CreateFrame("Frame")
local autoSellTimer = 0
local autoSellTotal = 0

local function ReportAutoSell()
    if autoSellTotal > 0 then
        print("|cFFFFD700Sell-O-Matic:|r sold grey items for " .. FormatMoney(autoSellTotal) .. ".")
    end
    autoSellTotal = 0
end

autoSellFrame:Hide()
autoSellFrame:SetScript("OnUpdate", function(self, elapsed)
    autoSellTimer = autoSellTimer - elapsed
    if autoSellTimer > 0 then return end
    autoSellTimer = 0.15

    if not MerchantFrame or not MerchantFrame:IsVisible() then
        self:Hide()
        ReportAutoSell()
        return
    end

    -- Sell the first sellable grey found, then re-scan next tick.
    for bag = 0, 4 do
        local sold = false
        for slot = 1, GetContainerNumSlots(bag) do
            local link = GetContainerItemLink(bag, slot)
            if link then
                local name, _, quality = GetItemInfo(link)
                if name and quality == 0 and IsSellable(name) and not IsItemAnUpgradeForAnyProfile(link) then
                    local price = select(11, GetItemInfo(link)) or 0
                    local count = select(2, GetContainerItemInfo(bag, slot)) or 1
                    autoSellTotal = autoSellTotal + (price * count)
                    UseContainerItem(bag, slot)
                    sold = true
                    break
                end
            end
        end
        if sold then return end
    end

    self:Hide()
    ReportAutoSell()
end)

local function StartAutoSellGreys()
    if not AutoSellEnabled() then return end
    if not MerchantFrame or not MerchantFrame:IsVisible() then return end
    autoSellTimer = 0.4 -- let the vendor UI settle before the first sale
    autoSellFrame:Show()
end
  




-- Creates the sell buttons and attaches them to the MerchantFrame.
function CreateSellButtons()
    if SellomaticSellWhiteItemsButton and SellomaticSellGreenItemsButton and SellomaticSellBlueItemsButton and SellomaticSellEpicItemsButton then
        return -- Buttons already exist, ensure they are not recreated
    end

    local buttonWidth = 100
    local buttonHeight = 16
    local spacing = 10

    local merchantFrameLevel = MerchantFrame:GetFrameLevel()

    -- Create 'Sell White Items' button
    local SellomaticSellWhiteItemsButton = CreateFrame("Button", nil, MerchantFrame, "OptionsButtonTemplate")
    SellomaticSellWhiteItemsButton:SetText("Sell Whites")
    SellomaticSellWhiteItemsButton:SetSize(buttonWidth, buttonHeight)
    SellomaticSellWhiteItemsButton:SetPoint("TOPLEFT", MerchantFrame, "TOPLEFT", 80, -37.5)
    SellomaticSellWhiteItemsButton:SetFrameLevel(merchantFrameLevel + 1)
    SellomaticSellWhiteItemsButton:SetScript("OnClick", function() SellItems(1) end)

    -- Create 'Sell Green Items' button
    local SellomaticSellGreenItemsButton = CreateFrame("Button", nil, MerchantFrame, "OptionsButtonTemplate")
    SellomaticSellGreenItemsButton:SetText("Sell Greens")
    SellomaticSellGreenItemsButton:SetSize(buttonWidth, buttonHeight)
    SellomaticSellGreenItemsButton:SetPoint("LEFT", SellomaticSellWhiteItemsButton, "RIGHT", spacing, 0)
    SellomaticSellGreenItemsButton:SetFrameLevel(merchantFrameLevel + 1)
    SellomaticSellGreenItemsButton:SetScript("OnClick", function() SellItems(2) end)

    -- Create 'Sell Blue Items' button
    local SellomaticSellBlueItemsButton = CreateFrame("Button", nil, MerchantFrame, "OptionsButtonTemplate")
    SellomaticSellBlueItemsButton:SetText("Sell Blues")
    SellomaticSellBlueItemsButton:SetSize(buttonWidth, buttonHeight)
    SellomaticSellBlueItemsButton:SetPoint("TOPLEFT", SellomaticSellWhiteItemsButton, "BOTTOMLEFT", 0, -1.5)
    SellomaticSellBlueItemsButton:SetFrameLevel(merchantFrameLevel + 1)
    SellomaticSellBlueItemsButton:SetScript("OnClick", function() SellItems(3) end)

    -- Create 'Sell Epic Items' button
    local SellomaticSellEpicItemsButton = CreateFrame("Button", nil, MerchantFrame, "OptionsButtonTemplate")
    SellomaticSellEpicItemsButton:SetText("Sell Epics")
    SellomaticSellEpicItemsButton:SetSize(buttonWidth, buttonHeight)
    SellomaticSellEpicItemsButton:SetPoint("LEFT", SellomaticSellBlueItemsButton, "RIGHT", spacing, 0)
    SellomaticSellEpicItemsButton:SetFrameLevel(merchantFrameLevel + 1)
    SellomaticSellEpicItemsButton:SetScript("OnClick", function() SellItems(4) end)

end

  
  


  
  

-- Main event frame.
local frame = CreateFrame("Frame")
frame:RegisterEvent("MERCHANT_SHOW")
frame:SetScript("OnEvent", function(self, event)
  if event == "MERCHANT_SHOW" then
      CreateSellButtons()
      UpdateBlacklist() -- Ensure the blacklist is up-to-date
      LoadCustomBlacklist()
      StartAutoSellGreys()
  end
end)

-- ============================================================================
-- MINIMAP BUTTON + BLACKLIST MENU
-- Left click: open options. Right click: blacklist menu (add hovered/bag
-- items, remove existing entries).
-- ============================================================================
local minimapButton = CreateFrame("Button", "SellOMaticMinimapButton", Minimap)
minimapButton:SetFrameStrata("MEDIUM")
minimapButton:SetSize(31, 31)
minimapButton:RegisterForClicks("AnyUp")
minimapButton:SetHighlightTexture(136477) -- Interface\\Minimap\\UI-MapZoom-Highlight
minimapButton:SetMovable(true)
minimapButton:EnableMouse(true)

local icon = minimapButton:CreateTexture(nil, "BACKGROUND")
icon:SetSize(18, 18)
icon:SetTexture(133739) -- Interface\\Icons\\INV_Misc_Coin_01 (gold coin)
icon:SetPoint("CENTER")
minimapButton.icon = icon

local overlay = minimapButton:CreateTexture(nil, "OVERLAY")
overlay:SetSize(53, 53)
overlay:SetTexture(136430) -- Interface\\Minimap\\MiniMap-TrackingBorder
overlay:SetPoint("TOPLEFT")

local function UpdateMinimapPosition(angle)
    local x, y = math.cos(angle) * 80, math.sin(angle) * 80
    minimapButton:ClearAllPoints()
    minimapButton:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

minimapButton:SetScript("OnMouseDown", function(self, button)
    if IsShiftKeyDown() then
        self:SetScript("OnUpdate", function(frame)
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            local angle = math.atan2(cy / scale - my, cx / scale - mx)
            self.angle = angle
            UpdateMinimapPosition(angle)
        end)
    end
end)

minimapButton:SetScript("OnMouseUp", function(self)
    self:SetScript("OnUpdate", nil)
    SellOMatic_Settings = SellOMatic_Settings or {}
    SellOMatic_Settings.minimapAngle = self.angle or SellOMatic_Settings.minimapAngle
end)

minimapButton:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
    GameTooltip:SetText("Sell-O-Matic")
    GameTooltip:AddLine("Left click: options", 1, 1, 1)
    GameTooltip:AddLine("Right click: blacklist menu", 1, 1, 1)
    GameTooltip:AddLine("Shift+drag: move button", 0.8, 0.8, 0.8)
    GameTooltip:Show()
end)
minimapButton:SetScript("OnLeave", GameTooltip_Hide)

-- ---------------------------------------------------------------------------
-- Dropdown menu
-- ---------------------------------------------------------------------------
local menuFrame = CreateFrame("Frame", "SellOMaticMenuFrame", UIParent, "UIDropDownMenuTemplate")

local function MenuAddBagItem(owner, itemName)
    AddToCustomBlacklist(itemName)
    CloseDropDownMenus()
end

local function MenuRemoveItem(owner, itemName)
    RemoveFromCustomBlacklist(itemName)
    CloseDropDownMenus()
end

local function BuildMenu(level)
    if level ~= 1 then return end
    local info

    info = UIDropDownMenu_CreateInfo()
    info.notCheckable = true
    info.isTitle = true
    info.text = "Blacklist an item"
    UIDropDownMenu_AddButton(info, level)

    -- Add every grey/white item found in bags as a one-click entry.
    local seen = {}
    for bag = 0, 4 do
        for slot = 1, GetContainerNumSlots(bag) do
            local link = GetContainerItemLink(bag, slot)
            if link then
                local name, _, quality = GetItemInfo(link)
                if name and quality and quality <= 1 and not seen[name] then
                    seen[name] = true
                    info = UIDropDownMenu_CreateInfo()
                    info.notCheckable = true
                    info.text = "Add: " .. name
                    info.func = MenuAddBagItem
                    info.arg1 = name
                    info.colorCode = quality == 0 and "|cff9d9d9d" or "|cffffffff"
                    UIDropDownMenu_AddButton(info, level)
                end
            end
        end
    end

    info = UIDropDownMenu_CreateInfo()
    info.notCheckable = true
    info.isTitle = true
    info.text = "Custom blacklist entries"
    UIDropDownMenu_AddButton(info, level)

    local custom = GetCustomBlacklist()
    local any = false
    for name in pairs(custom) do
        any = true
        info = UIDropDownMenu_CreateInfo()
        info.notCheckable = true
        info.text = "Remove: " .. name
        info.func = MenuRemoveItem
        info.arg1 = name
        UIDropDownMenu_AddButton(info, level)
    end
    if not any then
        info = UIDropDownMenu_CreateInfo()
        info.notCheckable = true
        info.disabled = true
        info.text = "(none yet)"
        UIDropDownMenu_AddButton(info, level)
    end

    info = UIDropDownMenu_CreateInfo()
    info.notCheckable = true
    info.isTitle = true
    info.text = "Built-in rules"
    UIDropDownMenu_AddButton(info, level)

    info = UIDropDownMenu_CreateInfo()
    info.notCheckable = true
    info.disabled = true
    info.text = "Bloodforged items (always protected)"
    UIDropDownMenu_AddButton(info, level)
end

UIDropDownMenu_Initialize(menuFrame, BuildMenu, "MENU")

minimapButton:SetScript("OnClick", function(self, button)
    if button == "LeftButton" then
        if SellOMatic_InterfacePanel then
            InterfaceOptionsFrame_OpenToCategory(SellOMatic_InterfacePanel)
            InterfaceOptionsFrame_OpenToCategory(SellOMatic_InterfacePanel)
        end
    else
        ToggleDropDownMenu(1, nil, menuFrame, self, 0, -5)
    end
end)


-- Slash command setup
SLASH_SELLOMATIC1 = "/sellomatic"
SlashCmdList["SELLOMATIC"] = function(msg)
    msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if msg == "greys on" then
        SellOMatic_Settings = SellOMatic_Settings or {}
        SellOMatic_Settings.autoSellGreys = true
        local cb = _G["SellOMatic_CheckboxAutoSellGreys"]
        if cb then cb:SetChecked(true) end
        print("|cFFFFD700Sell-O-Matic:|r auto-sell greys |cff00ff00enabled|r.")
    elseif msg == "greys off" then
        SellOMatic_Settings = SellOMatic_Settings or {}
        SellOMatic_Settings.autoSellGreys = false
        local cb = _G["SellOMatic_CheckboxAutoSellGreys"]
        if cb then cb:SetChecked(false) end
        print("|cFFFFD700Sell-O-Matic:|r auto-sell greys |cffff0000disabled|r.")
    elseif msg == "protect" then
        MarkProtectionDirty()
        RebuildProtection()
        local n = 0
        for _ in pairs(protection.byName) do n = n + 1 end
        print("|cFFFFD700Sell-O-Matic:|r protecting |cffffd700" .. n .. "|r items (set members + upgrades across all profiles).")
    else
        if SellOMatic_InterfacePanel then
            InterfaceOptionsFrame_OpenToCategory(SellOMatic_InterfacePanel)
            InterfaceOptionsFrame_OpenToCategory(SellOMatic_InterfacePanel)
        end
    end
end

-- Interface panel
SellOMatic_InterfacePanel = CreateFrame("Frame", "SellOMatic_InterfacePanel", InterfaceOptionsFramePanelContainer)
SellOMatic_InterfacePanel.name = "Sell-O-Matic"
InterfaceOptions_AddCategory(SellOMatic_InterfacePanel)

-- Panel title
SellOMatic_InterfacePanel.title = SellOMatic_InterfacePanel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
SellOMatic_InterfacePanel.title:SetPoint("TOPLEFT", 16, -16)
SellOMatic_InterfacePanel.title:SetText("Sell-O-Matic Options")

-- Checkboxes
local itemsToBlacklist = {"Cloth", "Righteous Orbs", "OresAndBars", "Herbs", "Highrisk"} -- Corrected category names

local function CreateCheckboxesForBlacklist()
  local prevCheckbox -- For positioning checkboxes below one another
  for i, category in ipairs(categories) do
      local checkbox = CreateFrame("CheckButton", "SellOMatic_Checkbox" .. category, SellOMatic_InterfacePanel, "UICheckButtonTemplate")
      checkbox:SetPoint("TOPLEFT", prevCheckbox or SellOMatic_InterfacePanel.title, "BOTTOMLEFT", 0, prevCheckbox and -30 or -10)
      local checkboxLabel = _G[checkbox:GetName() .. "Text"] or checkbox:CreateFontString(nil, "ARTWORK", "GameFontNormal")
      checkboxLabel:SetPoint("LEFT", checkbox, "RIGHT", 0, 0)
      checkboxLabel:SetText("Blacklist " .. category)
      checkbox.tooltipText = "Prevents selling of " .. category .. " if checked"
      checkbox:SetScript("OnClick", function()
          UpdateBlacklist()
          -- Optionally, sync with selling logic here if immediate action is required
      end)
      prevCheckbox = checkbox
  end
end



-- Function to update the blacklist based on checkbox selections
local function UpdateBlacklist()
  blacklist = {} -- Reset the blacklist
  for _, category in ipairs(categories) do
      local checkbox = _G["SellOMatic_Checkbox" .. category]
      if checkbox and checkbox:GetChecked() then
          for _, item in ipairs(itemsToSellByCategory[category]) do
              blacklist[item] = true
          end
      end
  end
end


-- Save and restore functionality
SellOMatic_InterfacePanel.default = function() -- Set defaults
    SellOMatic_Settings = SellOMatic_Settings or {}
    for _, cat in ipairs(categories) do
        SellOMatic_Settings[cat] = true -- Default to all checked
    end
    SellOMatic_Settings.autoSellGreys = true
end

SellOMatic_InterfacePanel.refresh = function() -- Refresh UI from saved settings
    for _, cat in ipairs(categories) do
        local checkbox = _G["SellOMatic_Checkbox" .. cat]
        if checkbox then
            checkbox:SetChecked(SellOMatic_Settings[cat] or false)
        end
    end
    local autoCb = _G["SellOMatic_CheckboxAutoSellGreys"]
    if autoCb then
        autoCb:SetChecked(SellOMatic_Settings.autoSellGreys ~= false)
    end
end

-- Function to save checkbox states
local function SaveCheckboxStates()
  for i, category in ipairs(categories) do
      local checkbox = _G["SellOMatic_Checkbox".. category]
      -- Checkboxes are only created lazily when the options panel is shown
      -- (CreateCheckboxesForBlacklist runs on OnShow), so this can run before
      -- they exist (e.g. during ADDON_LOADED). Guard against nil.
      if checkbox then
          SellOMatic_Settings[category] = checkbox:GetChecked()
      end
  end
end

-- Function to load checkbox states
local function LoadCheckboxStates()
  SellOMatic_Settings = SellOMatic_Settings or {}
  for i, category in ipairs(categories) do
      local checkbox = _G["SellOMatic_Checkbox".. category]
      -- Same lazy-creation caveat as SaveCheckboxStates above.
      if checkbox then
          checkbox:SetChecked(SellOMatic_Settings[category] or false)
      end
  end
  UpdateBlacklist() -- Ensure blacklist is updated based on loaded settings
end

SellOMatic_InterfacePanel:SetScript("OnShow", function()
  CreateCheckboxesForBlacklist()
  LoadCheckboxStates() -- Assuming this adjusts checkbox states based on saved settings
end)

local function SyncCheckboxesWithBlacklist()
  for _, category in ipairs(categories) do
    local isCategoryBlacklisted = false
    for _, item in ipairs(itemsToSellByCategory[category]) do
      if blacklist[item] then
        isCategoryBlacklisted = true
        break -- If any item in the category is blacklisted, mark the category as blacklisted and stop checking further
      end
    end
    local checkbox = _G["SellOMatic_Checkbox" .. category]
    if checkbox then
      checkbox:SetChecked(isCategoryBlacklisted)
    end
  end
end

-- Add saving functionality to the interface panel's okay button
SellOMatic_InterfacePanel.okay = function()
    SaveCheckboxStates()
end

SellOMatic_InterfacePanel.cancel = SellOMatic_InterfacePanel.default -- Revert to last saved

-- Auto-sell greys toggle
local autoSellCheckbox = CreateFrame("CheckButton", "SellOMatic_CheckboxAutoSellGreys", SellOMatic_InterfacePanel, "UICheckButtonTemplate")
local autoLabel = _G[autoSellCheckbox:GetName() .. "Text"]
autoLabel:SetText("Auto-sell grey items on vendor open")
autoSellCheckbox.tooltipText = "Automatically sells all grey vendor trash when you open a merchant window"
autoSellCheckbox:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(self.tooltipText, nil, nil, nil, nil, true)
end)
autoSellCheckbox:SetScript("OnLeave", GameTooltip_Hide)
autoSellCheckbox:SetScript("OnClick", function(self)
    SellOMatic_Settings = SellOMatic_Settings or {}
    SellOMatic_Settings.autoSellGreys = self:GetChecked() and true or false
end)

SellOMatic_InterfacePanel:HookScript("OnShow", function()
    local prev = SellOMatic_InterfacePanel.title
    for _, cat in ipairs(categories) do
        local cb = _G["SellOMatic_Checkbox" .. cat]
        if cb then prev = cb end
    end
    autoSellCheckbox:ClearAllPoints()
    autoSellCheckbox:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -10)
    if autoSellCheckbox:GetChecked() == nil then
        autoSellCheckbox:SetChecked(SellOMatic_Settings.autoSellGreys ~= false)
    end
end)


-- Combined event handler frame
local eventHandler = CreateFrame("Frame")
eventHandler:RegisterEvent("ADDON_LOADED")
eventHandler:SetScript("OnEvent", function(self, event, arg1)
  if event == "ADDON_LOADED" and arg1 == addonName then
    SellOMatic_Settings = SellOMatic_Settings or {}
    LoadCheckboxStates() -- Load saved checkbox states if any
    LoadCustomBlacklist()
    UpdateMinimapPosition(SellOMatic_Settings.minimapAngle or -math.pi / 4)
    self:UnregisterEvent("ADDON_LOADED")
  end
end)

-- ============================================================================
-- SELL-O-MATIC OPTIONS ENTRY
-- Options are reachable via /sellomatic or the minimap coin button. No panel
-- button: it overlapped the Save Set button in the main frame.
-- ============================================================================