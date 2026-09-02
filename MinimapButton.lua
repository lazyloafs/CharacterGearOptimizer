local addonName, addon = ...

-- ============================================================================
-- HUD STAT DISPLAY MENU (shared by both fallback and LDB minimap buttons)
-- Per-stat checkboxes so the user picks exactly which stats appear on the HUD.
-- ============================================================================

-- Ordered list of every stat the HUD can show.  key = DB toggle key.
local HUD_STAT_OPTIONS = {
    -- Header: Attributes
    { header = "Attributes" },
    { key = "strength",    label = "Strength" },
    { key = "agility",     label = "Agility" },
    { key = "stamina",     label = "Stamina" },
    { key = "intellect",   label = "Intellect" },
    { key = "spirit",      label = "Spirit" },
    -- Header: Offensive
    { header = "Offensive" },
    { key = "attackPower",  label = "Attack Power" },
    { key = "spellPower",   label = "Spell Power" },
    { key = "healPower",    label = "Heal Power" },
    { key = "holyDamage",   label = "Holy Damage" },
    { key = "fireDamage",   label = "Fire Damage" },
    { key = "natureDamage", label = "Nature Damage" },
    { key = "frostDamage",  label = "Frost Damage" },
    { key = "shadowDamage", label = "Shadow Damage" },
    { key = "arcaneDamage", label = "Arcane Damage" },
    { key = "meleeCrit",    label = "Melee Crit" },
    { key = "spellCrit",    label = "Spell Crit" },
    { key = "meleeHaste",   label = "Melee Haste" },
    { key = "spellHaste",   label = "Spell Haste" },
    { key = "meleeHit",     label = "Melee Hit" },
    { key = "spellHit",     label = "Spell Hit" },
    { key = "expertise",    label = "Expertise" },
    { key = "armorPen",     label = "Armor Pen" },
    -- Header: Defensive
    { header = "Defensive" },
    { key = "hp",           label = "HP" },
    { key = "mana",         label = "Mana" },
    { key = "mp5",          label = "MP5 (casting)" },
    { key = "armor",        label = "Armor" },
    { key = "defense",      label = "Defense" },
    { key = "dodge",        label = "Dodge" },
    { key = "parry",        label = "Parry" },
    { key = "block",        label = "Block" },
    { key = "resilience",   label = "Resilience" },
    { key = "avoidance",    label = "Avoidance" },
    { key = "critImmune",   label = "Crit Immunity" },
    { key = "ehp",          label = "EHP" },
}

-- Expose the ordered list so SpecHUD.lua can read it
addon.HUD_STAT_OPTIONS = HUD_STAT_OPTIONS

local hudMenu = CreateFrame("Frame", "CGOHudStatsMenu", UIParent, "UIDropDownMenuTemplate")

local function InitHudStatsMenu(self, level)
    local db = addon.InitializeDatabase and addon:InitializeDatabase() or (CharacterGearOptimizerDB or {})
    db.hudStats = db.hudStats or {}
    local sel = db.hudStats

    for _, opt in ipairs(HUD_STAT_OPTIONS) do
        local info = UIDropDownMenu_CreateInfo()
        if opt.header then
            info.text = "|cFFFFD700" .. opt.header .. "|r"
            info.isTitle = true
            info.notCheckable = true
        else
            info.text = opt.label
            info.isNotRadio = true
            info.keepShownOnClick = true
            info.checked = sel[opt.key] and true or false
            info.func = function(btn)
                sel[opt.key] = not sel[opt.key] or nil
                if addon.UpdateSpecHUD then addon:UpdateSpecHUD() end
            end
        end
        UIDropDownMenu_AddButton(info, level)
    end

    -- Separator
    local info = UIDropDownMenu_CreateInfo()
    info.text = " "
    info.isTitle = true
    info.notCheckable = true
    UIDropDownMenu_AddButton(info, level)

    -- Clear All
    info = UIDropDownMenu_CreateInfo()
    info.text = "|cFFFF4444Clear All|r"
    info.notCheckable = true
    info.func = function()
        wipe(sel)
        if addon.UpdateSpecHUD then addon:UpdateSpecHUD() end
        CloseDropDownMenus()
    end
    UIDropDownMenu_AddButton(info, level)

    -- Toggle Gear Panel
    info = UIDropDownMenu_CreateInfo()
    info.text = "|cFFCCCCCCToggle Gear Panel|r"
    info.notCheckable = true
    info.func = function()
        if CharacterGearOptimizerFrame and CharacterGearOptimizerFrame:IsShown() then
            CharacterGearOptimizerFrame:Hide()
        else
            CharacterGearOptimizerFrame:Show()
        end
        CloseDropDownMenus()
    end
    UIDropDownMenu_AddButton(info, level)
end

UIDropDownMenu_Initialize(hudMenu, InitHudStatsMenu, "MENU")

local function ShowHudMenu(anchorFrame)
    ToggleDropDownMenu(1, nil, hudMenu, anchorFrame or "cursor", 0, 0)
end

local LDB = LibStub and LibStub("LibDataBroker-1.1", true)
local icon = LibStub and LibStub("LibDBIcon-1.0", true)

if not LDB or not icon then
    -- Fallback simple minimap button if LibStub/LDB isn't available
    local dragFrame = CreateFrame("Button", "CharacterGearOptimizerMinimapButton", Minimap)
    dragFrame:SetSize(32, 32)
    dragFrame:SetFrameStrata("MEDIUM")
    dragFrame:SetFrameLevel(8)
    dragFrame:SetPoint("TOPLEFT", Minimap, "TOPLEFT", 5, -5)
    dragFrame:SetNormalTexture("Interface/Icons/Inv_misc_gear_01")
    dragFrame:SetPushedTexture("Interface/Icons/Inv_misc_gear_01")
    dragFrame:SetHighlightTexture("Interface/Minimap/UI-Minimap-ZoomButton-Highlight")
    
    local isDragging = false
    dragFrame:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    dragFrame:RegisterForDrag("LeftButton")
    
    dragFrame:SetScript("OnDragStart", function(self)
        isDragging = true
        self:LockHighlight()
        self:SetScript("OnUpdate", function(self)
            local xpos, ypos = GetCursorPosition()
            local xmin, ymin = Minimap:GetLeft(), Minimap:GetBottom()
            xpos = xmin - xpos / UIParent:GetScale() + 70
            ypos = ypos / UIParent:GetScale() - ymin - 70
            local angle = math.deg(math.atan2(ypos, xpos))
            local radius = 80
            self:SetPoint("TOPLEFT", Minimap, "TOPLEFT", 52 - (radius * math.cos(math.rad(angle))), (radius * math.sin(math.rad(angle))) - 52)
        end)
    end)
    
    dragFrame:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
        self:UnlockHighlight()
        isDragging = false
    end)
    
    dragFrame:SetScript("OnClick", function(self, button)
        if isDragging then return end
        if button == "LeftButton" then
            local hud = _G["CGOSpecHUD"]
            if hud then
                if hud:IsShown() then
                    hud:Hide()
                    if CharacterGearOptimizerDB then CharacterGearOptimizerDB.specHUDHidden = true end
                else
                    hud:Show()
                    if CharacterGearOptimizerDB then CharacterGearOptimizerDB.specHUDHidden = false end
                end
            end
        elseif button == "RightButton" then
            ShowHudMenu(self)
        end
    end)
    return
end

-- If LDB is available (common if Libs are packaged like in ItemRack)
local dataObject = LDB:NewDataObject("CharacterGearOptimizer", {
    type = "data source",
    text = "CharacterGearOptimizer",
    icon = "Interface/Icons/Inv_misc_gear_01",
    OnClick = function(self, button)
        if button == "LeftButton" then
            local hud = _G["CGOSpecHUD"]
            if hud then
                if hud:IsShown() then
                    hud:Hide()
                    if CharacterGearOptimizerDB then CharacterGearOptimizerDB.specHUDHidden = true end
                else
                    hud:Show()
                    if CharacterGearOptimizerDB then CharacterGearOptimizerDB.specHUDHidden = false end
                end
            end
        elseif button == "RightButton" then
            ShowHudMenu(self)
        end
    end,
    OnTooltipShow = function(tooltip)
        tooltip:AddLine("|cFFFFD700CharacterGearOptimizer|r")
        tooltip:AddLine("Left-click to toggle the Spec HUD.", 1, 1, 1)
        tooltip:AddLine("Right-click for HUD display options.", 1, 1, 1)
    end,
})

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:SetScript("OnEvent", function(self, event, arg1)
    if arg1 == addonName then
        local db = addon.InitializeDatabase and addon:InitializeDatabase() or (CharacterGearOptimizerDB or {})
        db.minimap = db.minimap or { hide = false }
        icon:Register("CharacterGearOptimizer", dataObject, db.minimap)
        self:UnregisterEvent("ADDON_LOADED")
    end
end)
