-- ============================================================================
-- CharacterGearOptimizer: Options.lua
-- Dedicated AddOn Settings / Options Menu configuration panel
-- Cross-version compatibility: Retail (Settings API) & Classic (InterfaceOptions)
-- Features: Checkboxes, Sliders, Dropdowns, Action Buttons, and Cloud Integration
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
-- Running counter so every slider gets a unique global name -- OptionsSliderTemplate's
-- XML-defined Low/High/Text FontStrings are only auto-created (and reachable via
-- _G[name.."Low"] etc.) when the frame itself has a real name; an anonymous frame
-- (name = nil) makes slider:GetName() return nil, and nil .. "Low" throws
-- "attempt to concatenate a nil value".
local sliderNameCounter = 0
local function CreateSlider(parent, label, minVal, maxVal, step, getFunc, setFunc, formatFunc)
    sliderNameCounter = sliderNameCounter + 1
    local slider = CreateFrame("Slider", "CGOOptionsSlider" .. sliderNameCounter, parent, "OptionsSliderTemplate")
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
-- Helper: Create Dropdown
-- ============================================================================
local dropdownCounter = 0
local function CreateDropdown(parent, label, width, getOptionsFunc, getFunc, setFunc)
    dropdownCounter = dropdownCounter + 1
    local frameName = "CGODropdownMenu_" .. dropdownCounter

    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(width + 24, 44)

    local lbl = container:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    lbl:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
    lbl:SetText(label)

    local dd = CreateFrame("Frame", frameName, container, "UIDropDownMenuTemplate")
    dd:SetPoint("TOPLEFT", lbl, "BOTTOMLEFT", -16, -2)
    if UIDropDownMenu_SetWidth then
        UIDropDownMenu_SetWidth(dd, width)
    end

    local function InitializeMenu(self, level)
        if not getOptionsFunc then return end
        local options = getOptionsFunc() or {}
        local currentVal = getFunc and getFunc() or nil

        for _, opt in ipairs(options) do
            local info = UIDropDownMenu_CreateInfo and UIDropDownMenu_CreateInfo() or {}
            info.text = opt.text
            info.value = opt.value
            info.checked = (opt.value == currentVal)
            info.func = function()
                if setFunc then
                    setFunc(opt.value, opt.text)
                end
                if UIDropDownMenu_SetText then
                    UIDropDownMenu_SetText(dd, opt.text)
                end
                if UIDropDownMenu_SetSelectedValue then
                    UIDropDownMenu_SetSelectedValue(dd, opt.value)
                end
            end
            if UIDropDownMenu_AddButton then
                UIDropDownMenu_AddButton(info)
            end
        end
    end

    if UIDropDownMenu_Initialize then
        UIDropDownMenu_Initialize(dd, InitializeMenu)
    end

    local function Refresh()
        local currentVal, currentText = nil, nil
        if getFunc then
            currentVal, currentText = getFunc()
        end

        if not currentText and getOptionsFunc then
            local options = getOptionsFunc() or {}
            for _, opt in ipairs(options) do
                if opt.value == currentVal then
                    currentText = opt.text
                    break
                end
            end
        end

        if UIDropDownMenu_SetText then
            UIDropDownMenu_SetText(dd, currentText or tostring(currentVal or "Select..."))
        end
        if UIDropDownMenu_SetSelectedValue and currentVal ~= nil then
            UIDropDownMenu_SetSelectedValue(dd, currentVal)
        end
    end

    container.dropdown = dd
    container.RefreshValue = Refresh

    return container
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
    version:SetText("Version 1.1.0 | Dynamic Stat Weight Optimizer & Set Manager")

    -- Divider Line
    local line = panel:CreateTexture(nil, "ARTWORK")
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", version, "BOTTOMLEFT", 0, -10)
    line:SetPoint("RIGHT", panel, "RIGHT", -16, 0)
    if line.SetColorTexture then
        line:SetColorTexture(0.55, 0.45, 0.25, 0.6)
    else
        line:SetTexture(0.55, 0.45, 0.25, 0.6)
    end

    local checkboxes = {}
    local sliders = {}
    local dropdowns = {}

    -- ========================================================================
    -- COLUMN 1: General Options & Checkboxes
    -- ========================================================================
    local cbTooltips = CreateCheckbox(panel, "Enable Tooltip Stat Comparisons & Upgrades",
        function() return CharacterGearOptimizerDB and CharacterGearOptimizerDB.enableTooltips ~= false end,
        function(val)
            CharacterGearOptimizerDB = CharacterGearOptimizerDB or {}
            CharacterGearOptimizerDB.enableTooltips = val
        end
    )
    cbTooltips:SetPoint("TOPLEFT", line, "BOTTOMLEFT", 0, -14)
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
    cbSpecHUD:SetPoint("TOPLEFT", cbTooltips, "BOTTOMLEFT", 0, -6)
    table.insert(checkboxes, cbSpecHUD)

    local cbLockHUD = CreateCheckbox(panel, "Lock Spec HUD Position",
        function() return CharacterGearOptimizerDB and CharacterGearOptimizerDB.lockHUD == true end,
        function(val)
            CharacterGearOptimizerDB = CharacterGearOptimizerDB or {}
            CharacterGearOptimizerDB.lockHUD = val
        end
    )
    cbLockHUD:SetPoint("TOPLEFT", cbSpecHUD, "BOTTOMLEFT", 0, -6)
    table.insert(checkboxes, cbLockHUD)

    local cbAutoRoll = CreateCheckbox(panel, "Auto-Roll Greed / Disenchant on Unneeded Loot",
        function() return addon.IsAutoRollEnabled and addon:IsAutoRollEnabled() or (CharacterGearOptimizerDB and CharacterGearOptimizerDB.autoRoll ~= false) end,
        function(val)
            if addon.SetAutoRollEnabled then addon:SetAutoRollEnabled(val) end
            CharacterGearOptimizerDB = CharacterGearOptimizerDB or {}
            CharacterGearOptimizerDB.autoRoll = val
        end
    )
    cbAutoRoll:SetPoint("TOPLEFT", cbLockHUD, "BOTTOMLEFT", 0, -6)
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
    cbMinimap:SetPoint("TOPLEFT", cbAutoRoll, "BOTTOMLEFT", 0, -6)
    table.insert(checkboxes, cbMinimap)

    local cbBank = CreateCheckbox(panel, "Include Bank Items When Optimizing Gear",
        function() return CharacterGearOptimizerDB and CharacterGearOptimizerDB.includeBank ~= false end,
        function(val)
            CharacterGearOptimizerDB = CharacterGearOptimizerDB or {}
            CharacterGearOptimizerDB.includeBank = val
        end
    )
    cbBank:SetPoint("TOPLEFT", cbMinimap, "BOTTOMLEFT", 0, -6)
    table.insert(checkboxes, cbBank)

    local cbSellomatic = CreateCheckbox(panel, "Enable Sell-O-Matic Merchant Auto-Sell & Repair",
        function() return CharacterGearOptimizerDB and CharacterGearOptimizerDB.enableSellomatic ~= false end,
        function(val)
            CharacterGearOptimizerDB = CharacterGearOptimizerDB or {}
            CharacterGearOptimizerDB.enableSellomatic = val
        end
    )
    cbSellomatic:SetPoint("TOPLEFT", cbBank, "BOTTOMLEFT", 0, -6)
    table.insert(checkboxes, cbSellomatic)

    local cbCloudSync = CreateCheckbox(panel, "Enable Account-Wide Cloud Auto-Sync for Profiles",
        function()
            local gdb = CharacterGearOptimizerGlobalDB or {}
            return gdb.settings and gdb.settings.autoSync ~= false
        end,
        function(val)
            if addon.CloudSync and addon.CloudSync.InitializeDatabase then
                addon.CloudSync:InitializeDatabase()
            end
            CharacterGearOptimizerGlobalDB = CharacterGearOptimizerGlobalDB or {}
            CharacterGearOptimizerGlobalDB.settings = CharacterGearOptimizerGlobalDB.settings or {}
            CharacterGearOptimizerGlobalDB.settings.autoSync = val
        end
    )
    cbCloudSync:SetPoint("TOPLEFT", cbSellomatic, "BOTTOMLEFT", 0, -6)
    table.insert(checkboxes, cbCloudSync)

    local cbCloudAutoPush = CreateCheckbox(panel, "Auto-Push Custom Profiles to Cloud on Save",
        function()
            local gdb = CharacterGearOptimizerGlobalDB or {}
            return gdb.settings and gdb.settings.autoPushOnSave ~= false
        end,
        function(val)
            if addon.CloudSync and addon.CloudSync.InitializeDatabase then
                addon.CloudSync:InitializeDatabase()
            end
            CharacterGearOptimizerGlobalDB = CharacterGearOptimizerGlobalDB or {}
            CharacterGearOptimizerGlobalDB.settings = CharacterGearOptimizerGlobalDB.settings or {}
            CharacterGearOptimizerGlobalDB.settings.autoPushOnSave = val
        end
    )
    cbCloudAutoPush:SetPoint("TOPLEFT", cbCloudSync, "BOTTOMLEFT", 0, -6)
    table.insert(checkboxes, cbCloudAutoPush)

    -- ========================================================================
    -- COLUMN 2: Dropdown Selectors
    -- ========================================================================

    -- Dropdown 1: Active Optimization Profile / Spec
    local ddSpec = CreateDropdown(panel, "Active Spec / Optimization Preset", 200,
        function()
            local opts = {}
            table.insert(opts, { value = 0, text = "Auto-Detect Spec" })
            local _, playerClass = UnitClass("player")
            local classSpecs = addon.CLASS_SPECS and addon.CLASS_SPECS[playerClass]
            if classSpecs then
                local indices = {}
                for idx, _ in pairs(classSpecs) do table.insert(indices, idx) end
                table.sort(indices)
                for _, idx in ipairs(indices) do
                    local spec = classSpecs[idx]
                    table.insert(opts, { value = idx, text = spec.name or ("Spec " .. idx) })
                end
            end
            -- Custom Profiles
            local db = CharacterGearOptimizerDB or {}
            local custom = db.customProfiles or db.profiles or {}
            for name, _ in pairs(custom) do
                table.insert(opts, { value = "custom:" .. name, text = "[Custom] " .. name })
            end
            return opts
        end,
        function()
            local db = CharacterGearOptimizerDB or {}
            if db.specOverride then
                local _, playerClass = UnitClass("player")
                local classSpecs = addon.CLASS_SPECS and addon.CLASS_SPECS[playerClass]
                local sName = classSpecs and classSpecs[db.specOverride] and classSpecs[db.specOverride].name
                return db.specOverride, sName or ("Spec " .. db.specOverride)
            end
            if addon.currentCustomProfile then
                return "custom:" .. (addon.currentCustomProfile.name or "Custom"), "[Custom] " .. (addon.currentCustomProfile.name or "Custom")
            end
            local autoName = addon.autoDetectedSpec and addon.autoDetectedSpec.name or "Auto-Detect"
            return 0, "Auto: " .. autoName
        end,
        function(val, text)
            if val == 0 then
                addon:ClearSpecOverride()
            elseif type(val) == "string" and val:match("^custom:(.+)") then
                local pName = val:match("^custom:(.+)")
                local db = CharacterGearOptimizerDB or {}
                local custom = db.customProfiles or db.profiles or {}
                if custom[pName] then
                    addon.currentCustomProfile = { name = pName, weights = custom[pName] }
                    if addon.UpdateSpecHUD then addon:UpdateSpecHUD() end
                end
            elseif type(val) == "number" then
                addon:SetSpecOverride(val)
            end
        end
    )
    ddSpec:SetPoint("TOPLEFT", line, "BOTTOMLEFT", 380, -14)
    table.insert(dropdowns, ddSpec)

    -- Dropdown 2: Auto-Roll Loot Policy
    local ddAutoRoll = CreateDropdown(panel, "Auto-Roll Loot Policy", 200,
        function()
            return {
                { value = "smart", text = "Smart (Greed/DE unneeded)" },
                { value = "greed", text = "Always Greed" },
                { value = "de", text = "Always Disenchant" },
                { value = "need_upgrade", text = "Need Upgrades, Greed Rest" },
                { value = "disabled", text = "Disabled" },
            }
        end,
        function()
            local db = CharacterGearOptimizerDB or {}
            local policy = db.autoRollPolicy or "smart"
            local labels = {
                smart = "Smart (Greed/DE unneeded)",
                greed = "Always Greed",
                de = "Always Disenchant",
                need_upgrade = "Need Upgrades, Greed Rest",
                disabled = "Disabled",
            }
            return policy, labels[policy] or "Smart (Greed/DE unneeded)"
        end,
        function(val)
            CharacterGearOptimizerDB = CharacterGearOptimizerDB or {}
            CharacterGearOptimizerDB.autoRollPolicy = val
            if val == "disabled" then
                if addon.SetAutoRollEnabled then addon:SetAutoRollEnabled(false) end
            else
                if addon.SetAutoRollEnabled then addon:SetAutoRollEnabled(true) end
            end
        end
    )
    ddAutoRoll:SetPoint("TOPLEFT", ddSpec, "BOTTOMLEFT", 0, -10)
    table.insert(dropdowns, ddAutoRoll)

    -- Dropdown 3: Weapon Optimization Preference
    local ddWeapon = CreateDropdown(panel, "Preferred Weapon Mode", 200,
        function()
            return {
                { value = "auto", text = "Auto / Any Best Weapons" },
                { value = "2h", text = "Two-Handed Preferred" },
                { value = "dw", text = "Dual-Wield Preferred" },
                { value = "shield", text = "1H + Shield Preferred" },
            }
        end,
        function()
            local db = CharacterGearOptimizerDB or {}
            local mode = db.weaponMode or "auto"
            local labels = {
                auto = "Auto / Any Best Weapons",
                ["2h"] = "Two-Handed Preferred",
                dw = "Dual-Wield Preferred",
                shield = "1H + Shield Preferred",
            }
            return mode, labels[mode] or "Auto / Any Best Weapons"
        end,
        function(val)
            CharacterGearOptimizerDB = CharacterGearOptimizerDB or {}
            CharacterGearOptimizerDB.weaponMode = val
        end
    )
    ddWeapon:SetPoint("TOPLEFT", ddAutoRoll, "BOTTOMLEFT", 0, -10)
    table.insert(dropdowns, ddWeapon)

    -- Dropdown 4: Cloud Sync Conflict Strategy
    local ddCloudStrategy = CreateDropdown(panel, "Cloud Sync Conflict Strategy", 200,
        function()
            return {
                { value = "newer", text = "Keep Newer (Timestamp)" },
                { value = "prefer_local", text = "Prefer Local Profiles" },
                { value = "prefer_cloud", text = "Prefer Cloud Profiles" },
                { value = "prompt", text = "Prompt on Conflict" },
            }
        end,
        function()
            local gdb = CharacterGearOptimizerGlobalDB or {}
            local strat = (gdb.settings and gdb.settings.conflictStrategy) or "newer"
            local labels = {
                newer = "Keep Newer (Timestamp)",
                prefer_local = "Prefer Local Profiles",
                prefer_cloud = "Prefer Cloud Profiles",
                prompt = "Prompt on Conflict",
            }
            return strat, labels[strat] or "Keep Newer (Timestamp)"
        end,
        function(val)
            CharacterGearOptimizerGlobalDB = CharacterGearOptimizerGlobalDB or {}
            CharacterGearOptimizerGlobalDB.settings = CharacterGearOptimizerGlobalDB.settings or {}
            CharacterGearOptimizerGlobalDB.settings.conflictStrategy = val
        end
    )
    ddCloudStrategy:SetPoint("TOPLEFT", ddWeapon, "BOTTOMLEFT", 0, -10)
    table.insert(dropdowns, ddCloudStrategy)

    -- ========================================================================
    -- SLIDERS: HUD Scale and Opacity
    -- ========================================================================
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
    sliderScale:SetPoint("TOPLEFT", cbCloudAutoPush, "BOTTOMLEFT", 12, -26)
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

    -- ========================================================================
    -- ACTION BUTTONS
    -- ========================================================================
    local btnOpen = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    btnOpen:SetSize(160, 26)
    btnOpen:SetPoint("TOPLEFT", sliderScale, "BOTTOMLEFT", -12, -28)
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

    local btnCloud = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    btnCloud:SetSize(160, 26)
    btnCloud:SetPoint("TOPLEFT", btnOpen, "BOTTOMLEFT", 0, -8)
    btnCloud:SetText("Cloud Profile Manager")
    btnCloud:SetScript("OnClick", function()
        if addon.OpenCloudSync then
            addon:OpenCloudSync()
        elseif addon.CloudSync and addon.CloudSync.OpenDialog then
            addon.CloudSync:OpenDialog()
        end
    end)

    local btnSyncNow = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    btnSyncNow:SetSize(160, 26)
    btnSyncNow:SetPoint("LEFT", btnCloud, "RIGHT", 16, 0)
    btnSyncNow:SetText("Sync to Cloud Now")
    btnSyncNow:SetScript("OnClick", function()
        if addon.CloudSync then
            addon.CloudSync:PushAllLocalProfiles()
            addon.CloudSync:PullAllCloudProfiles()
        end
    end)

    panel:SetScript("OnShow", function()
        for _, cb in ipairs(checkboxes) do
            if cb.RefreshValue then cb:RefreshValue() end
        end
        for _, sl in ipairs(sliders) do
            if sl.RefreshValue then sl:RefreshValue() end
        end
        for _, dd in ipairs(dropdowns) do
            if dd.RefreshValue then dd:RefreshValue() end
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
