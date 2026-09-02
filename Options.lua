-- ============================================================================
-- CharacterGearOptimizer: Options.lua
-- Dedicated AddOn Settings / Options Menu configuration panel
-- Cross-version compatibility: Retail (Settings API) & Classic (InterfaceOptions)
-- ============================================================================

local addonName, addon = ...
local addon = addon or _G.CharacterGearOptimizer or {}
_G.CharacterGearOptimizer = addon

addon.Options = addon.Options or {}
local Options = addon.Options

local BACKDROP_TEMPLATE = BackdropTemplateMixin and "BackdropTemplate" or nil

-- ============================================================================
-- Helper: Create Checkbutton
-- ============================================================================
local function CreateCheckbox(parent, label, getFunc, setFunc)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    cb.text = cb:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    cb.text:SetPoint("LEFT", cb, "RIGHT", 6, 1)
    cb.text:SetText(label)
    
    cb:SetScript("OnClick", function(self)
        local isChecked = self:GetChecked()
        if type(isChecked) == "number" then
            isChecked = (isChecked == 1)
        end
        setFunc(isChecked)
    end)
    
    cb.RefreshValue = function(self)
        local val = getFunc()
        self:SetChecked(val and true or false)
    end
    
    return cb
end

-- ============================================================================
-- Helper: Create Slider
-- ============================================================================
local function CreateSlider(parent, label, minVal, maxVal, step, getFunc, setFunc, formatFunc)
    local slider = CreateFrame("Slider", nil, parent, "OptionsSliderTemplate")
    slider:SetWidth(180)
    slider:SetHeight(16)
    slider:SetMinMaxValues(minVal, maxVal)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)

    slider.Low = _G[slider:GetName() .. "Low"] or slider:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    slider.High = _G[slider:GetName() .. "High"] or slider:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    slider.Text = _G[slider:GetName() .. "Text"] or slider:CreateFontString(nil, "ARTWORK", "GameFontNormal")

    slider.Low:SetPoint("TOPLEFT", slider, "BOTTOMLEFT", 2, -3)
    slider.High:SetPoint("TOPRIGHT", slider, "BOTTOMRIGHT", -2, -3)
    slider.Text:SetPoint("BOTTOM", slider, "TOP", 0, 4)

    slider.Low:SetText(tostring(minVal))
    slider.High:SetText(tostring(maxVal))
    slider.Text:SetText(label)

    local valText = slider:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    valText:SetPoint("TOP", slider, "BOTTOM", 0, -3)
    slider.ValueDisplay = valText

    slider:SetScript("OnValueChanged", function(self, value)
        setFunc(value)
        if formatFunc then
            valText:SetText(formatFunc(value))
        else
            valText:SetText(string.format("%.0f", value))
        end
    end)

    slider.RefreshValue = function(self)
        local val = getFunc() or minVal
        self:SetValue(val)
        if formatFunc then
            valText:SetText(formatFunc(val))
        else
            valText:SetText(string.format("%.0f", val))
        end
    end

    return slider
end

-- ============================================================================
-- Options Panel Construction
-- ============================================================================
function Options:CreatePanel()
    if self.panel then return self.panel end

    local panel = CreateFrame("Frame", "CharacterGearOptimizerOptionsPanel", UIParent, BACKDROP_TEMPLATE)
    panel.name = "CharacterGearOptimizer"
    self.panel = panel

    -- Title
    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("|cFFFFD700CharacterGearOptimizer|r")

    -- Subtitle / Version
    local version = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    version:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    version:SetText("Version 1.0.0 | Dynamic Stat Weight Optimizer & Set Manager")

    -- Divider
    local line = panel:CreateTexture(nil, "ARTWORK")
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", version, "BOTTOMLEFT", 0, -10)
    line:SetPoint("RIGHT", panel, "RIGHT", -16, 0)
    if line.SetColorTexture then
        line:SetColorTexture(0.55, 0.45, 0.25, 0.6)
    else
        if line.SetColorTexture then line:SetColorTexture(0.55, 0.45, 0.25, 0.6) else line:SetTexture(0.55, 0.45, 0.25, 0.6) end
    end

    local checkboxes = {}
    local sliders = {}

    -- Checkboxes: General Options
    local cbTooltips = CreateCheckbox(panel, "Enable Tooltip Stat Comparisons & Upgrades",
        function() return CharacterGearOptimizerDB and CharacterGearOptimizerDB.enableTooltips ~= false end,
        function(val)
            CharacterGearOptimizerDB = CharacterGearOptimizerDB or {}
            CharacterGearOptimizerDB.enableTooltips = val
        end
    )
    cbTooltips:SetPoint("TOPLEFT", line, "BOTTOMLEFT", 0, -16)
    table.insert(checkboxes, cbTooltips)

    local cbSpecHUD = CreateCheckbox(panel, "Show Floating Spec HUD on Screen",
        function() return CharacterGearOptimizerDB and not CharacterGearOptimizerDB.specHUDHidden end,
        function(val)
            CharacterGearOptimizerDB = CharacterGearOptimizerDB or {}
            CharacterGearOptimizerDB.specHUDHidden = not val
            if addon.specHUDFrame then
                if val then addon.specHUDFrame:Show() else addon.specHUDFrame:Hide() end
            end
        end
    )
    cbSpecHUD:SetPoint("TOPLEFT", cbTooltips, "BOTTOMLEFT", 0, -8)
    table.insert(checkboxes, cbSpecHUD)

    local cbLockHUD = CreateCheckbox(panel, "Lock Spec HUD Position",
        function() return CharacterGearOptimizerDB and CharacterGearOptimizerDB.lockHUD == true end,
        function(val)
            CharacterGearOptimizerDB = CharacterGearOptimizerDB or {}
            CharacterGearOptimizerDB.lockHUD = val
        end
    )
    cbLockHUD:SetPoint("TOPLEFT", cbSpecHUD, "BOTTOMLEFT", 0, -8)
    table.insert(checkboxes, cbLockHUD)

    local cbAutoRoll = CreateCheckbox(panel, "Auto-Roll Greed / Disenchant on Unneeded Loot",
        function() return addon.IsAutoRollEnabled and addon:IsAutoRollEnabled() or (CharacterGearOptimizerDB and CharacterGearOptimizerDB.autoRoll ~= false) end,
        function(val)
            if addon.SetAutoRollEnabled then addon:SetAutoRollEnabled(val) end
            CharacterGearOptimizerDB = CharacterGearOptimizerDB or {}
            CharacterGearOptimizerDB.autoRoll = val
        end
    )
    cbAutoRoll:SetPoint("TOPLEFT", cbLockHUD, "BOTTOMLEFT", 0, -8)
    table.insert(checkboxes, cbAutoRoll)

    local cbMinimap = CreateCheckbox(panel, "Show Minimap Button",
        function() return CharacterGearOptimizerDB and CharacterGearOptimizerDB.minimap and not CharacterGearOptimizerDB.minimap.hide end,
        function(val)
            CharacterGearOptimizerDB = CharacterGearOptimizerDB or {}
            CharacterGearOptimizerDB.minimap = CharacterGearOptimizerDB.minimap or {}
            CharacterGearOptimizerDB.minimap.hide = not val
            local btn = _G["CharacterGearOptimizerMinimapButton"] or _G["CGOMinimapButton"]
            if btn then
                if val then btn:Show() else btn:Hide() end
            end
        end
    )
    cbMinimap:SetPoint("TOPLEFT", cbAutoRoll, "BOTTOMLEFT", 0, -8)
    table.insert(checkboxes, cbMinimap)

    local cbBank = CreateCheckbox(panel, "Include Bank Items When Optimizing Gear",
        function() return CharacterGearOptimizerDB and CharacterGearOptimizerDB.includeBank ~= false end,
        function(val)
            CharacterGearOptimizerDB = CharacterGearOptimizerDB or {}
            CharacterGearOptimizerDB.includeBank = val
        end
    )
    cbBank:SetPoint("TOPLEFT", cbMinimap, "BOTTOMLEFT", 0, -8)
    table.insert(checkboxes, cbBank)

    local cbSellomatic = CreateCheckbox(panel, "Enable Sell-O-Matic Merchant Auto-Sell & Protection",
        function() return CharacterGearOptimizerDB and CharacterGearOptimizerDB.enableSellomatic ~= false end,
        function(val)
            CharacterGearOptimizerDB = CharacterGearOptimizerDB or {}
            CharacterGearOptimizerDB.enableSellomatic = val
        end
    )
    cbSellomatic:SetPoint("TOPLEFT", cbBank, "BOTTOMLEFT", 0, -8)
    table.insert(checkboxes, cbSellomatic)

    -- Sliders: HUD Scale and Opacity
    local sliderScale = CreateSlider(panel, "Spec HUD Scale", 50, 150, 5,
        function() return CharacterGearOptimizerDB and CharacterGearOptimizerDB.hudScale or 100 end,
        function(val)
            CharacterGearOptimizerDB = CharacterGearOptimizerDB or {}
            CharacterGearOptimizerDB.hudScale = val
            if addon.specHUDFrame then
                addon.specHUDFrame:SetScale(val / 100)
            end
        end,
        function(val) return string.format("%d%%", val) end
    )
    sliderScale:SetPoint("TOPLEFT", cbSellomatic, "BOTTOMLEFT", 12, -28)
    table.insert(sliders, sliderScale)

    local sliderAlpha = CreateSlider(panel, "HUD Opacity", 20, 100, 5,
        function() return CharacterGearOptimizerDB and CharacterGearOptimizerDB.hudAlpha or 90 end,
        function(val)
            CharacterGearOptimizerDB = CharacterGearOptimizerDB or {}
            CharacterGearOptimizerDB.hudAlpha = val
            if addon.specHUDFrame then
                addon.specHUDFrame:SetAlpha(val / 100)
            end
        end,
        function(val) return string.format("%d%%", val) end
    )
    sliderAlpha:SetPoint("LEFT", sliderScale, "RIGHT", 36, 0)
    table.insert(sliders, sliderAlpha)

    -- Action Buttons
    local btnOpen = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    btnOpen:SetSize(160, 26)
    btnOpen:SetPoint("TOPLEFT", sliderScale, "BOTTOMLEFT", -12, -32)
    btnOpen:SetText("Open Gear Optimizer")
    btnOpen:SetScript("OnClick", function()
        if CharacterGearOptimizerFrame then
            CharacterGearOptimizerFrame:Show()
        end
    end)

    local btnResetHUD = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    btnResetHUD:SetSize(160, 26)
    btnResetHUD:SetPoint("LEFT", btnOpen, "RIGHT", 16, 0)
    btnResetHUD:SetText("Reset HUD Position")
    btnResetHUD:SetScript("OnClick", function()
        if addon.specHUDFrame then
            addon.specHUDFrame:ClearAllPoints()
            addon.specHUDFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        end
        CharacterGearOptimizerDB = CharacterGearOptimizerDB or {}
        CharacterGearOptimizerDB.specHUD = nil
        print("|cFFFFD700CGO:|r Spec HUD position reset to center.")
    end)

    panel:SetScript("OnShow", function()
        for _, cb in ipairs(checkboxes) do
            if cb.RefreshValue then cb:RefreshValue() end
        end
        for _, sl in ipairs(sliders) do
            if sl.RefreshValue then sl:RefreshValue() end
        end
    end)

    return panel
end

-- ============================================================================
-- Cross-Version Settings Registration
-- ============================================================================
function Options:Register()
    local panel = self:CreatePanel()

    if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
        -- Modern Retail (10.0+ / Mainline / The War Within / Midnight)
        local category = Settings.RegisterCanvasLayoutCategory(panel, "CharacterGearOptimizer")
        Settings.RegisterAddOnCategory(category)
        addon.settingsCategory = category
    elseif InterfaceOptions_AddCategory then
        -- Classic / Legacy (Wrath / TBC / Vanilla / Cata)
        panel.name = "CharacterGearOptimizer"
        InterfaceOptions_AddCategory(panel)
        addon.settingsCategory = panel
    end
end

-- ============================================================================
-- Open Options Helper
-- ============================================================================
function addon:OpenOptions()
    if not Options.panel then
        Options:CreatePanel()
    end

    if Settings and Settings.OpenToCategory and addon.settingsCategory then
        if type(addon.settingsCategory.GetID) == "function" then
            Settings.OpenToCategory(addon.settingsCategory:GetID())
        else
            Settings.OpenToCategory(addon.settingsCategory)
        end
    elseif InterfaceOptionsFrame_OpenToCategory and Options.panel then
        InterfaceOptionsFrame_OpenToCategory(Options.panel)
        InterfaceOptionsFrame_OpenToCategory(Options.panel)
    end
end

-- Auto-register on PLAYER_LOGIN or ADDON_LOADED
local optFrame = CreateFrame("Frame")
optFrame:RegisterEvent("PLAYER_LOGIN")
optFrame:SetScript("OnEvent", function(self)
    Options:Register()
    self:UnregisterEvent("PLAYER_LOGIN")
end)
