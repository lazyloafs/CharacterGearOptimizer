local addonName, addon = ...
_G.CharacterGearOptimizer = _G.CharacterGearOptimizer or {}

-- ============================================================================
-- QUICK SETS HUD (ItemRack style draggable panel)
-- ============================================================================

local BUTTON_SIZE = 36
local BUTTON_PADDING = 4
local TITLE_HEIGHT = 18
local BACKDROP_TEMPLATE = BackdropTemplateMixin and "BackdropTemplate" or nil

local function ApplyBackdrop(frame, backdrop, bgColor, borderColor)
    if not frame or not frame.SetBackdrop then return end
    frame:SetBackdrop(backdrop)
    if bgColor then
        frame:SetBackdropColor(unpack(bgColor))
    end
    if borderColor then
        frame:SetBackdropBorderColor(unpack(borderColor))
    end
end

-- Main HUD Frame
local hud = CreateFrame("Frame", "CharacterGearOptimizerHUD", UIParent, BACKDROP_TEMPLATE)
hud:SetPoint("CENTER", UIParent, "CENTER", 200, 0)
hud:SetMovable(true)
hud:EnableMouse(true)
hud:Hide() -- Hidden by default, toggled via settings or command

-- WAR Theme Backdrop for the HUD
ApplyBackdrop(hud, {
    bgFile   = "Interface/DialogFrame/UI-DialogBox-Background",
    edgeFile = "Interface/DialogFrame/UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
}, { 0.05, 0.02, 0.02, 0.9 }, { 0.55, 0.45, 0.25, 1 })

-- HUD Title Bar
local titleBar = CreateFrame("Frame", nil, hud, BACKDROP_TEMPLATE)
titleBar:SetHeight(TITLE_HEIGHT)
titleBar:SetPoint("TOPLEFT", hud, "TOPLEFT", 4, -4)
titleBar:SetPoint("TOPRIGHT", hud, "TOPRIGHT", -4, -4)
titleBar:EnableMouse(true)
ApplyBackdrop(titleBar, {
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    tile = true, tileSize = 8, edgeSize = 8,
    insets = { left = 2, right = 2, top = 2, bottom = 2 }
}, { 0.2, 0.2, 0.3, 1 }, { 0.4, 0.4, 0.5, 1 })

local titleText = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
titleText:SetPoint("CENTER", titleBar, "CENTER", 0, 0)
titleText:SetText("LazySets")
titleText:SetTextColor(1, 0.82, 0, 1)

-- Drag movement
titleBar:SetScript("OnMouseDown", function(self, button)
    if button == "LeftButton" then
        hud:StartMoving()
    end
end)
titleBar:SetScript("OnMouseUp", function(self, button)
    hud:StopMovingOrSizing()
    local p, _, rp, x, y = hud:GetPoint()
    CharacterGearOptimizerDB.hudPoint = {p, rp, x, y}
end)

local setButtons = {}

-- ============================================================================
-- MANAGE SETS DROPDOWN (delete / new)
-- ============================================================================
local manageMenu = CreateFrame("Frame", "CGOManageSetsMenu", UIParent, "UIDropDownMenuTemplate")

local function ShowManageMenu(anchorBtn)
    UIDropDownMenu_Initialize(manageMenu, function(self, level, menuList)
        local info = UIDropDownMenu_CreateInfo()

        -- Header
        info.text = "|cFFFFD700Manage Sets|r"
        info.isTitle = true
        info.notCheckable = true
        UIDropDownMenu_AddButton(info)

        -- Delete entries for each saved set
        local sets = CharacterGearOptimizerDB and CharacterGearOptimizerDB.sets
        if sets then
            local sorted = {}
            for name in pairs(sets) do table.insert(sorted, name) end
            table.sort(sorted)
            for _, setName in ipairs(sorted) do
                info = UIDropDownMenu_CreateInfo()
                info.text = "|cFFFF4444Delete:|r " .. setName
                info.notCheckable = true
                info.func = function()
                    -- Show confirmation dialog before deleting
                    StaticPopupDialogs["CGO_DELETE_SET_" .. setName] = {
                        text = "Delete gear set \"|cFFFFD700" .. setName .. "|r\"?",
                        button1 = "Delete",
                        button2 = "Cancel",
                        OnAccept = function()
                            CharacterGearOptimizerDB.sets[setName] = nil
                            print("|cFFFFD700CharacterGearOptimizer:|r Deleted set: |cFFFF4444" .. setName .. "|r")
                            if _G.CGOMarkSellProtectionDirty then _G.CGOMarkSellProtectionDirty() end
                            addon:RefreshHUD()
                        end,
                        timeout = 0,
                        whileDead = true,
                        hideOnEscape = true,
                        preferredIndex = 3,
                    }
                    StaticPopup_Show("CGO_DELETE_SET_" .. setName)
                end
                UIDropDownMenu_AddButton(info)
            end
        end

        -- Separator
        info = UIDropDownMenu_CreateInfo()
        info.text = " "
        info.isTitle = true
        info.notCheckable = true
        UIDropDownMenu_AddButton(info)

        -- New Set entry — opens the main panel so the user can Save Set
        info = UIDropDownMenu_CreateInfo()
        info.text = "|cFF00FF00+ New Set|r"
        info.notCheckable = true
        info.func = function()
            local mainFrame = _G["CharacterGearOptimizerFrame"]
            if mainFrame and not mainFrame:IsShown() then
                mainFrame:Show()
            end
        end
        UIDropDownMenu_AddButton(info)
    end, "MENU")
    ToggleDropDownMenu(1, nil, manageMenu, anchorBtn, 0, 0)
end

-- The "+" manage button (created once, repositioned each refresh)
local manageBtn = CreateFrame("Button", "CGOManageSetsBtn", hud, BACKDROP_TEMPLATE)
manageBtn:SetSize(BUTTON_SIZE, BUTTON_SIZE)
ApplyBackdrop(manageBtn, {
    bgFile   = "Interface/DialogFrame/UI-DialogBox-Background",
    edgeFile = "Interface/DialogFrame/UI-DialogBox-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
}, { 0.1, 0.1, 0.1, 0.9 }, { 0.55, 0.45, 0.25, 1 })
manageBtn:Hide()

local plusText = manageBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
plusText:SetPoint("CENTER", manageBtn, "CENTER", 0, 0)
plusText:SetText("|cFFFFD700+|r")

manageBtn:SetScript("OnClick", function(self)
    ShowManageMenu(self)
end)
manageBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine("|cFFFFD700Manage Sets|r")
    GameTooltip:AddLine("Delete or create gear sets", 0.7, 0.7, 0.7)
    GameTooltip:Show()
end)
manageBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

-- ============================================================================
-- "BANK ALL" BUTTON (deposits non-equipped gear to bank)
-- ============================================================================
local bankBtn = CreateFrame("Button", "CGOBankAllBtn", hud, BACKDROP_TEMPLATE)
bankBtn:SetSize(BUTTON_SIZE, BUTTON_SIZE)
ApplyBackdrop(bankBtn, {
    bgFile   = "Interface/DialogFrame/UI-DialogBox-Background",
    edgeFile = "Interface/DialogFrame/UI-DialogBox-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
}, { 0.1, 0.1, 0.1, 0.9 }, { 0.55, 0.45, 0.25, 1 })
bankBtn:Hide()

local bankIcon = bankBtn:CreateTexture(nil, "ARTWORK")
bankIcon:SetAllPoints(bankBtn)
bankIcon:SetTexture("Interface/Icons/INV_Misc_Coin_01")
bankIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

bankBtn:SetScript("OnClick", function()
    if addon.BankNonEquipped then
        addon:BankNonEquipped()
    end
end)
bankBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine("|cFFFFD700Bank All Gear|r")
    GameTooltip:AddLine("Deposit all equippable items", 0.7, 0.7, 0.7)
    GameTooltip:AddLine("from bags into the bank.", 0.7, 0.7, 0.7)
    GameTooltip:Show()
end)
bankBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

-- ============================================================================
-- REFRESH HUD
-- ============================================================================
function addon:RefreshHUD()
    if not CharacterGearOptimizerDB or not CharacterGearOptimizerDB.sets then return end
    
    local sets = {}
    for name, data in pairs(CharacterGearOptimizerDB.sets) do
        table.insert(sets, name)
    end
    table.sort(sets)
    
    local numSets = #sets
    if numSets == 0 then
        hud:Hide()
        manageBtn:Hide()
        return
    end

    -- Keep HUD shown if there are sets
    hud:Show()

    -- Hide old buttons
    for _, btn in pairs(setButtons) do
        btn:Hide()
    end

    -- +1 for manage, +1 if bank is open
    local totalBtns = numSets + 1 + (addon.bankOpen and 1 or 0)
    local width = totalBtns * BUTTON_SIZE + (totalBtns + 1) * BUTTON_PADDING + 8
    local height = BUTTON_SIZE + TITLE_HEIGHT + (BUTTON_PADDING * 2) + 8
    hud:SetSize(width, height)

    local xOffset = BUTTON_PADDING + 4
    local yOffset = -TITLE_HEIGHT - BUTTON_PADDING - 4

    for i, setName in ipairs(sets) do
        local btn = setButtons[i]
        if not btn then
            btn = CreateFrame("Button", "CharacterGearOptimizerHUDButton"..i, hud, BACKDROP_TEMPLATE)
            btn:SetSize(BUTTON_SIZE, BUTTON_SIZE)
            ApplyBackdrop(btn, {
                bgFile   = "Interface/DialogFrame/UI-DialogBox-Background",
                edgeFile = "Interface/DialogFrame/UI-DialogBox-Border",
                tile = true, tileSize = 16, edgeSize = 12,
                insets = { left = 2, right = 2, top = 2, bottom = 2 },
            }, { 0.05, 0.02, 0.02, 0.8 }, { 0.55, 0.45, 0.25, 1 })

            -- Own icon texture: ActionButtonTemplate does not provide a
            -- .icon field on 3.3.5, which left the bar rendering empty.
            btn.icon = btn:CreateTexture(nil, "ARTWORK")
            btn.icon:SetAllPoints(btn)
            btn.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

            -- Both clicks equip the set
            btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            btn:SetScript("OnClick", function(self, button)
                addon:EquipSet(self.setName)
            end)

            -- Tooltip
            btn:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine("|cFFFFD700" .. (self.setName or "?") .. "|r")
                GameTooltip:AddLine("Click to Equip", 0.7, 0.7, 0.7)
                GameTooltip:Show()
            end)
            btn:SetScript("OnLeave", function(self) GameTooltip:Hide() end)

            setButtons[i] = btn
        end

        local setInfo = CharacterGearOptimizerDB.sets[setName]
        if setInfo then
            btn.setName = setName
            btn.icon:SetTexture(setInfo.icon or "Interface/Icons/INV_Misc_QuestionMark")
            btn:SetPoint("TOPLEFT", hud, "TOPLEFT", xOffset, yOffset)
            btn:Show()

            xOffset = xOffset + BUTTON_SIZE + BUTTON_PADDING
        else
            -- Malformed entry: hide the button and don't advance the row.
            btn:Hide()
        end
    end

    -- Position the "+" manage button at the end of the row
    manageBtn:ClearAllPoints()
    manageBtn:SetPoint("TOPLEFT", hud, "TOPLEFT", xOffset, yOffset)
    manageBtn:Show()
    xOffset = xOffset + BUTTON_SIZE + BUTTON_PADDING

    -- Show the "Bank All" button only when the bank frame is open
    if addon.bankOpen then
        bankBtn:ClearAllPoints()
        bankBtn:SetPoint("TOPLEFT", hud, "TOPLEFT", xOffset, yOffset)
        bankBtn:Show()
        xOffset = xOffset + BUTTON_SIZE + BUTTON_PADDING
    else
        bankBtn:Hide()
    end

    -- Recalculate HUD width to include all visible buttons
    hud:SetSize(xOffset + 4, height)
end
