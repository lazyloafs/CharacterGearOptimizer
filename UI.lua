-- ============================================================================
-- CharacterGearOptimizer: UI.lua
-- UI Theme coordinator, safe texture styling, and frame helpers.
-- ============================================================================

local addonName, addon = ...
local addon = addon or _G.CharacterGearOptimizer or {}
_G.CharacterGearOptimizer = addon

addon.UI = addon.UI or {}
local UI = addon.UI

UI.BACKDROP_TEMPLATE = BackdropTemplateMixin and "BackdropTemplate" or nil

-- ============================================================================
-- WAR Dark Gold Theme Palette
-- ============================================================================
UI.THEME = {
    BG_COLOR        = { 0.05, 0.02, 0.02, 0.94 },
    BORDER_COLOR    = { 0.55, 0.45, 0.25, 1.00 },
    TITLE_BG        = { 0.14, 0.05, 0.03, 0.92 },
    HIGHLIGHT_GOLD  = { 0.95, 0.82, 0.35, 0.45 },
    ROW_HIGHLIGHT   = { 0.55, 0.45, 0.25, 0.25 },
    TEXT_GOLD       = "FFFFD700",
    TEXT_LIGHT_GOLD = "FFF0C060",
    TEXT_SUBTLE     = "FF8A7A60",
}

-- ============================================================================
-- Safe Backdrop Application
-- ============================================================================
function UI:ApplyBackdrop(frame, backdrop, bgColor, borderColor)
    if not frame or not frame.SetBackdrop then return end
    frame:SetBackdrop(backdrop)
    if bgColor and frame.SetBackdropColor then
        frame:SetBackdropColor(unpack(bgColor))
    end
    if borderColor and frame.SetBackdropBorderColor then
        frame:SetBackdropBorderColor(unpack(borderColor))
    end
end

-- ============================================================================
-- Safe Color Texture Setter
-- ============================================================================
function UI:SetColorTextureSafe(texture, r, g, b, a)
    if not texture then return end
    if texture.SetColorTexture then
        texture:SetColorTexture(r, g, b, a)
    else
        texture:SetTexture(r, g, b, a)
    end
end

-- ============================================================================
-- Dialog Box Backdrop Template
-- ============================================================================
UI.DIALOG_BACKDROP = {
    bgFile   = "Interface/DialogFrame/UI-DialogBox-Background",
    edgeFile = "Interface/DialogFrame/UI-DialogBox-Border",
    tile     = true,
    tileSize = 32,
    edgeSize = 16,
    insets   = { left = 4, right = 4, top = 4, bottom = 4 },
}

UI.TOOLTIP_BACKDROP = {
    bgFile   = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    tile     = true,
    tileSize = 16,
    edgeSize = 12,
    insets   = { left = 2, right = 2, top = 2, bottom = 2 },
}

-- ============================================================================
-- Frame Visibility Toggles
-- ============================================================================
function addon:ToggleMainPanel()
    if CharacterGearOptimizerFrame then
        if CharacterGearOptimizerFrame:IsShown() then
            CharacterGearOptimizerFrame:Hide()
        else
            CharacterGearOptimizerFrame:Show()
        end
    end
end

function addon:ToggleHUD()
    if addon.specHUDFrame then
        if addon.specHUDFrame:IsShown() then
            addon.specHUDFrame:Hide()
            CharacterGearOptimizerDB = CharacterGearOptimizerDB or {}
            CharacterGearOptimizerDB.specHUDHidden = true
        else
            addon.specHUDFrame:Show()
            CharacterGearOptimizerDB = CharacterGearOptimizerDB or {}
            CharacterGearOptimizerDB.specHUDHidden = false
            if addon.UpdateSpecHUD then addon:UpdateSpecHUD() end
        end
    end
end

addon.UI = UI
