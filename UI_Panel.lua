local addonName, addon = ...
_G.CharacterGearOptimizer = _G.CharacterGearOptimizer or {}

local PANEL_WIDTH, PANEL_HEIGHT = 340, 620
local SLOT_SIZE = 30
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

-- ============================================================================
-- SLOT NAMES (human-readable labels for each inventory slot ID)
-- ============================================================================
local SLOT_LABELS = {
    [1]  = "Head",      [2]  = "Neck",     [3]  = "Shoulder",
    [4]  = "Shirt",     [5]  = "Chest",    [6]  = "Waist",
    [7]  = "Legs",      [8]  = "Feet",     [9]  = "Wrist",
    [10] = "Hands",     [11] = "Ring 1",   [12] = "Ring 2",
    [13] = "Trinket 1", [14] = "Trinket 2",[15] = "Back",
    [16] = "Main Hand", [17] = "Off Hand", [18] = "Ranged",
    [19] = "Tabard",
}

-- ============================================================================
-- ITEM PICKER FLYOUT (shown when clicking a slot)
-- ============================================================================
local picker = CreateFrame("Frame", "CGOItemPicker", UIParent, BACKDROP_TEMPLATE)
picker:SetSize(280, 300)
picker:SetFrameStrata("TOOLTIP")
picker:SetFrameLevel(200)
picker:SetMovable(false)
picker:EnableMouse(true)
picker:Hide()
ApplyBackdrop(picker, {
    bgFile   = "Interface/DialogFrame/UI-DialogBox-Background",
    edgeFile = "Interface/DialogFrame/UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
}, { 0.06, 0.03, 0.03, 0.95 }, { 0.55, 0.45, 0.25, 1 })

local pickerTitle = picker:CreateFontString(nil, "OVERLAY", "GameFontNormal")
pickerTitle:SetPoint("TOP", picker, "TOP", 0, -10)

local pickerCloseBtn = CreateFrame("Button", nil, picker, "UIPanelCloseButton")
pickerCloseBtn:SetPoint("TOPRIGHT", picker, "TOPRIGHT", -2, -2)

-- Scrollable content area
local pickerClip = CreateFrame("Frame", nil, picker)
pickerClip:SetPoint("TOPLEFT", picker, "TOPLEFT", 8, -28)
pickerClip:SetPoint("BOTTOMRIGHT", picker, "BOTTOMRIGHT", -8, 8)
if pickerClip.SetClipsChildren then pickerClip:SetClipsChildren(true) end

local pickerContent = CreateFrame("Frame", nil, pickerClip)
pickerContent:SetPoint("TOPLEFT", pickerClip, "TOPLEFT")
pickerContent:SetWidth(264)
pickerContent:SetHeight(1)

local pickerRows = {}
local pickerScrollOffset = 0

picker:SetScript("OnMouseWheel", function(self, delta)
    local maxScroll = math.max(0, pickerContent:GetHeight() - pickerClip:GetHeight())
    pickerScrollOffset = math.max(0, math.min(maxScroll, pickerScrollOffset - delta * 28))
    pickerContent:SetPoint("TOPLEFT", pickerClip, "TOPLEFT", 0, pickerScrollOffset)
end)

-- Reset scroll on open
picker:SetScript("OnShow", function()
    pickerScrollOffset = 0
    pickerContent:SetPoint("TOPLEFT", pickerClip, "TOPLEFT", 0, 0)
end)

-- Auto-close picker when mouse leaves both the picker and all slot buttons
picker._autoCloseTimer = 0
picker:SetScript("OnUpdate", function(self, elapsed)
    if not self:IsShown() then return end
    if self:IsMouseOver() then self._autoCloseTimer = 0; return end
    for _, b in pairs(addon.equipSlots or {}) do
        if b:IsMouseOver() or (b.borderFrame and b.borderFrame:IsMouseOver()) then
            self._autoCloseTimer = 0
            return
        end
    end
    self._autoCloseTimer = self._autoCloseTimer + elapsed
    if self._autoCloseTimer > 0.5 then
        self:Hide()
        self._autoCloseTimer = 0
    end
end)

local function ShowItemPicker(slotID, anchorBtn)
    local specData = nil
    if addon.currentCustomProfile then
        specData = addon.currentCustomProfile
    elseif addon.currentClass and addon.currentSpecIdx and addon.currentSpecIdx > 0 then
        specData = addon.CLASS_SPECS[addon.currentClass][addon.currentSpecIdx]
    end
    if not specData then
        print("|cFFFFD700CharacterGearOptimizer:|r Select a Spec first to see item scores.")
        return
    end

    local items = addon:GetItemsForSlot(slotID, specData)

    pickerTitle:SetText("|cFFFFD700" .. (SLOT_LABELS[slotID] or ("Slot "..slotID)) .. "|r")
    picker:ClearAllPoints()
    picker:SetPoint("RIGHT", anchorBtn, "LEFT", -8, 0)

    -- Hide old rows
    for _, row in ipairs(pickerRows) do row:Hide() end

    local rowH = 30
    local yOff = 0

    for i, item in ipairs(items) do
        local row = pickerRows[i]
        if not row then
            row = CreateFrame("Button", nil, pickerContent)
            row:SetHeight(rowH)
            row:SetPoint("TOPLEFT", pickerContent, "TOPLEFT", 0, 0)
            row:SetPoint("TOPRIGHT", pickerContent, "TOPRIGHT", 0, 0)
            row:EnableMouse(true)

            row.icon = row:CreateTexture(nil, "ARTWORK")
            row.icon:SetSize(24, 24)
            row.icon:SetPoint("LEFT", row, "LEFT", 4, 0)

            row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.nameText:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
            row.nameText:SetWidth(170)
            row.nameText:SetJustifyH("LEFT")

            row.scoreText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.scoreText:SetPoint("RIGHT", row, "RIGHT", -6, 0)

            row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
            row.highlight:SetAllPoints()
            if row.highlight.SetColorTexture then row.highlight:SetColorTexture(0.55, 0.45, 0.25, 0.3) else row.highlight:SetTexture(0.55, 0.45, 0.25, 0.3) end

            row:SetScript("OnEnter", function(self)
                if self.itemLink then
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetHyperlink(self.itemLink)
                    GameTooltip:Show()
                end
            end)
            row:SetScript("OnLeave", function() GameTooltip:Hide() end)

            pickerRows[i] = row
        end

        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", pickerContent, "TOPLEFT", 0, -yOff)
        row:SetPoint("TOPRIGHT", pickerContent, "TOPRIGHT", 0, -yOff)

        local itemName, _, itemQuality, _, _, _, _, _, _, tex = GetItemInfo(item.link)
        local r, g, b = 1, 1, 1
        if itemQuality then
            r, g, b = GetItemQualityColor(itemQuality)
        end

        row.icon:SetTexture(tex or "Interface/Icons/INV_Misc_QuestionMark")
        row.nameText:SetText(itemName or "?")
        row.nameText:SetTextColor(r, g, b)
        row.scoreText:SetText(string.format("|cFFFFD700%.1f|r", item.score))
        row.itemLink = item.link
        row.slotID = slotID

        -- Click to assign this item to the slot
        row:SetScript("OnClick", function(self)
            if IsShiftKeyDown() and self.itemLink then
                HandleModifiedItemClick(self.itemLink)
                return
            end
            local btn = addon.equipSlots[self.slotID]
            if btn then
                local _, _, _, _, _, _, _, _, _, t = GetItemInfo(self.itemLink)
                SetItemButtonTexture(btn, t)
                btn.itemLink = self.itemLink

                -- Update the current working set
                addon.currentBestSet = addon.currentBestSet or {}
                addon.currentBestSet[self.slotID] = { link = self.itemLink, score = item.score }

                -- Equip the item now
                if not InCombatLockdown() then
                    local foundBag, foundSlot = addon:FindItemInBags(self.itemLink)
                    if foundBag and foundSlot then
                        ClearCursor()
                        PickupContainerItem(foundBag, foundSlot)
                        EquipCursorItem(self.slotID)
                        ClearCursor()
                    end
                end
            end
            picker:Hide()
        end)

        row:Show()
        yOff = yOff + rowH
    end

    pickerContent:SetHeight(math.max(1, yOff))

    -- Resize picker height to fit, up to max
    local visibleH = math.min(yOff + 40, 400)
    picker:SetHeight(visibleH)

    picker:Show()
end

-- ============================================================================
-- NAME INPUT DIALOG (for Save Set)
-- ============================================================================
local nameDialog = CreateFrame("Frame", "CGONameDialog", UIParent, BACKDROP_TEMPLATE)
nameDialog:SetSize(280, 120)
nameDialog:SetPoint("CENTER", UIParent, "CENTER", 0, 100)
nameDialog:SetFrameStrata("DIALOG")
nameDialog:EnableMouse(true)
nameDialog:Hide()
ApplyBackdrop(nameDialog, {
    bgFile   = "Interface/DialogFrame/UI-DialogBox-Background",
    edgeFile = "Interface/DialogFrame/UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
}, { 0.05, 0.02, 0.02, 0.95 }, { 0.55, 0.45, 0.25, 1 })

local nameDialogTitle = nameDialog:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
nameDialogTitle:SetPoint("TOP", nameDialog, "TOP", 0, -14)
nameDialogTitle:SetText("|cFFFFD700Name Your Set|r")

local nameInput = CreateFrame("EditBox", "CGONameInput", nameDialog, "InputBoxTemplate")
nameInput:SetSize(200, 22)
nameInput:SetPoint("CENTER", nameDialog, "CENTER", 0, 4)
nameInput:SetAutoFocus(true)
nameInput:SetMaxLetters(30)

local nameOK = CreateFrame("Button", nil, nameDialog, "UIPanelButtonTemplate")
nameOK:SetSize(80, 22)
nameOK:SetPoint("BOTTOMRIGHT", nameDialog, "BOTTOM", -4, 12)
nameOK:SetText("Save")
nameDialog.saveBtn = nameOK  -- expose so stat editor Save As can find it

local nameCancel = CreateFrame("Button", nil, nameDialog, "UIPanelButtonTemplate")
nameCancel:SetSize(80, 22)
nameCancel:SetPoint("BOTTOMLEFT", nameDialog, "BOTTOM", 4, 12)
nameCancel:SetText("Cancel")
nameCancel:SetScript("OnClick", function() nameDialog:Hide() end)

nameInput:SetScript("OnEscapePressed", function() nameDialog:Hide() end)
nameInput:SetScript("OnEnterPressed", function() nameOK:Click() end)

-- ============================================================================
-- STAT WEIGHT CUSTOMIZER (inline â€” replaces the 3D model when active)
-- ============================================================================
local statEditor = CreateFrame("Frame", "CGOStatEditor", UIParent)
statEditor:Hide()
statEditor:EnableMouse(true)

local seTitle = statEditor:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
seTitle:SetPoint("TOP", statEditor, "TOP", 0, -4)
seTitle:SetText("|cFFFFD700Stat Weights|r")

-- Scrollable stat list. Virtual list: rows are repositioned inside a fixed
-- clip window on scroll, so nothing ever renders outside the section
-- (3.3.5 has no SetClipsChildren).
local seClip = CreateFrame("Frame", nil, statEditor)
seClip:SetPoint("TOPLEFT", statEditor, "TOPLEFT", 6, -20)
seClip:SetPoint("BOTTOMRIGHT", statEditor, "BOTTOMRIGHT", -22, 30)

local ROW_HEIGHT = 22

local seScrollOffset = 0
local UpdateStatEditorScroll -- forward declaration

-- Vertical scrollbar along the right edge of the editor
local seScrollbar = CreateFrame("Slider", "CGOStatEditorScrollBar", statEditor, "OptionsSliderTemplate")
seScrollbar:ClearAllPoints()
seScrollbar:SetPoint("TOPRIGHT", statEditor, "TOPRIGHT", -3, -26)
seScrollbar:SetPoint("BOTTOMRIGHT", statEditor, "BOTTOMRIGHT", -3, 34)
seScrollbar:SetWidth(10)
seScrollbar:SetOrientation("VERTICAL")
seScrollbar:SetValueStep(1)
seScrollbar:SetMinMaxValues(0, 1)
seScrollbar:SetScript("OnValueChanged", function(self, value)
    if self._syncing then return end
    seScrollOffset = tonumber(value) or 0
    UpdateStatEditorScroll(false)
end)

local statRows = {}
local customWeights = {} -- temp table while editing

local statRows = {}
local customWeights = {} -- temp table while editing

-- All possible stats in display order
local ALL_STATS = {
    "STR", "AGI", "STA", "INT", "SPI",
    "AP", "FAP", "SP", "HEAL", "MP5",
    "HIT", "CRIT", "SPELLCRIT", "MELEECRIT", "HASTE", "EXP",
    "DEF", "DODGE", "PARRY", "RESIL",
    "ARP", "BLOCK_RATING", "BLOCK_VALUE", "ARMOR", "SPELL_PEN",
}

local function PopulateStatEditor()
    for _, row in ipairs(statRows) do row:Hide() end

    local specData = nil
    if addon.currentCustomProfile then
        specData = addon.currentCustomProfile
    elseif addon.currentClass and addon.currentSpecIdx and addon.currentSpecIdx > 0 then
        specData = addon.CLASS_SPECS[addon.currentClass][addon.currentSpecIdx]
    end

    -- Seed customWeights from current spec or custom profile
    customWeights = {}
    if specData and specData.weights then
        for k, v in pairs(specData.weights) do
            customWeights[k] = v
        end
    end

    local yOff = 0
    local rowH = ROW_HEIGHT

    for idx, stat in ipairs(ALL_STATS) do
        local row = statRows[idx]
        if not row then
            row = CreateFrame("Frame", nil, seClip)
            row:SetHeight(rowH)

            row.label = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.label:SetPoint("LEFT", row, "LEFT", 4, 0)
            row.label:SetWidth(80)
            row.label:SetJustifyH("LEFT")

            row.editBox = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
            row.editBox:SetSize(60, 18)
            row.editBox:SetPoint("RIGHT", row, "RIGHT", -4, 0)
            row.editBox:SetAutoFocus(false)
            row.editBox:SetMaxLetters(8)
            row.editBox:SetJustifyH("CENTER")
            row.editBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

            statRows[idx] = row
        end

        -- Virtual list: rows are positioned by UpdateStatEditorScroll on
        -- every scroll; initial placement puts them in logical order.
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", seClip, "TOPLEFT", 0, -yOff)
        row:SetPoint("TOPRIGHT", seClip, "TOPRIGHT", 0, -yOff)

        local label = (addon.STAT_LABELS and addon.STAT_LABELS[stat]) or stat
        row.label:SetText("|cFFCCCCCC" .. label .. "|r")

        local val = customWeights[stat] or 0
        row.editBox:SetText(string.format("%.2f", val))
        row.stat = stat

        -- Update customWeights when the user changes it
        row.editBox:SetScript("OnEnterPressed", function(self)
            local num = tonumber(self:GetText()) or 0
            customWeights[row.stat] = num
            self:ClearFocus()
        end)
        row.editBox:SetScript("OnTabPressed", function(self)
            local num = tonumber(self:GetText()) or 0
            customWeights[row.stat] = num
            self:ClearFocus()
            -- Focus next row if possible
            if statRows[idx + 1] and statRows[idx + 1].editBox then
                statRows[idx + 1].editBox:SetFocus()
            end
        end)

        row:Show()
        yOff = yOff + rowH
    end

    seScrollOffset = 0
    UpdateStatEditorScroll(false)
end

-- Virtual list scroll: reposition rows within the fixed clip window and hide
-- any that fall outside it. updateSlider=false avoids slider feedback loops.
UpdateStatEditorScroll = function(updateSlider)
    local clipH = seClip:GetHeight() or 0
    local rowCount = #statRows
    local contentH = rowCount * ROW_HEIGHT
    -- Scroll in whole-row steps so rows never sit half-clipped
    local maxRow = math.max(0, rowCount - math.floor(clipH / ROW_HEIGHT))
    local rowOffset = math.floor(math.max(0, math.min(maxRow, seScrollOffset / ROW_HEIGHT)) + 0.5)
    seScrollOffset = rowOffset * ROW_HEIGHT

    for idx = 1, rowCount do
        local row = statRows[idx]
        if row then
            local rel = idx - 1 - rowOffset
            if rel >= 0 and rel * ROW_HEIGHT < clipH then
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", seClip, "TOPLEFT", 0, -rel * ROW_HEIGHT)
                row:SetPoint("TOPRIGHT", seClip, "TOPRIGHT", 0, -rel * ROW_HEIGHT)
                row:Show()
            else
                row:Hide()
            end
        end
    end

    if updateSlider ~= false then
        seScrollbar._syncing = true
        seScrollbar:SetMinMaxValues(0, math.max(1, maxRow))
        seScrollbar:SetValue(rowOffset)
        seScrollbar._syncing = false
    end

    if maxRow > 0 then
        seScrollbar:Show()
    else
        seScrollbar:Hide()
    end
end

-- Wheel anywhere over the editor scrolls the list (one row per notch)
statEditor:EnableMouseWheel(true)
statEditor:SetScript("OnMouseWheel", function(self, delta)
    seScrollOffset = seScrollOffset - delta * ROW_HEIGHT
    UpdateStatEditorScroll(true)
end)

-- ============================================================================
-- IMPORT & EXPORT STAT WEIGHTS (Pawn / SimC / JSON)
-- ============================================================================

local function ParseImportString(input)
    if not input or input == "" then return nil end
    if addon.ImportWeights then
        local weights, metadata = addon:ImportWeights(input)
        if weights and next(weights) then
            return weights, metadata
        end
    end
    if addon.StatCalc and addon.StatCalc.ImportWeights then
        local weights, metadata = addon.StatCalc:ImportWeights(input)
        if weights and next(weights) then
            return weights, metadata
        end
    end
    return nil
end

-- ----------------------------------------------------------------------------
-- Import Dialog
-- ----------------------------------------------------------------------------
local importDialog = CreateFrame("Frame", "CGOImportDialog", UIParent, BACKDROP_TEMPLATE)
importDialog:SetSize(360, 260)
importDialog:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
importDialog:SetFrameStrata("FULLSCREEN_DIALOG")
importDialog:SetMovable(true)
importDialog:EnableMouse(true)
importDialog:RegisterForDrag("LeftButton")
importDialog:SetScript("OnDragStart", importDialog.StartMoving)
importDialog:SetScript("OnDragStop", importDialog.StopMovingOrSizing)
importDialog:Hide()

ApplyBackdrop(importDialog, {
    bgFile   = "Interface/DialogFrame/UI-DialogBox-Background",
    edgeFile = "Interface/DialogFrame/UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
}, { 0.1, 0.1, 0.1, 0.95 }, nil)

local impTitle = importDialog:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
impTitle:SetPoint("TOP", importDialog, "TOP", 0, -14)
impTitle:SetText("|cFFFFD700Import Stat Weights|r")

local impHint = importDialog:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
impHint:SetPoint("TOP", impTitle, "BOTTOM", 0, -4)
impHint:SetText("|cFFAAAAAAPaste Pawn, SimC, or JSON string below|r")

local impScrollFrame = CreateFrame("ScrollFrame", "CGOImportScroll", importDialog, "UIPanelScrollFrameTemplate")
impScrollFrame:SetPoint("TOPLEFT", importDialog, "TOPLEFT", 14, -54)
impScrollFrame:SetPoint("BOTTOMRIGHT", importDialog, "BOTTOMRIGHT", -32, 54)

local impEditBox = CreateFrame("EditBox", "CGOImportEditBox", impScrollFrame)
impEditBox:SetMultiLine(true)
impEditBox:SetAutoFocus(false)
impEditBox:SetFontObject(ChatFontNormal)
impEditBox:SetWidth(290)
impEditBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
impScrollFrame:SetScrollChild(impEditBox)

local impStatusLine = importDialog:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
impStatusLine:SetPoint("BOTTOM", importDialog, "BOTTOM", 0, 36)
impStatusLine:SetJustifyH("CENTER")
impStatusLine:SetWidth(330)

local impOK = CreateFrame("Button", nil, importDialog, "UIPanelButtonTemplate")
impOK:SetSize(90, 22)
impOK:SetPoint("BOTTOMRIGHT", importDialog, "BOTTOM", -4, 8)
impOK:SetText("Import")
impOK:SetScript("OnClick", function()
    local text = impEditBox:GetText()
    local parsed, meta = ParseImportString(text)
    if not parsed or not next(parsed) then
        impStatusLine:SetText("|cFFFF4444Could not parse any stat weights.|r")
        return
    end

    local count = 0
    for _ in pairs(parsed) do count = count + 1 end

    -- Apply to customWeights and refresh stat editor rows
    customWeights = {}
    for k, v in pairs(parsed) do
        customWeights[k] = v
    end

    for _, row in ipairs(statRows) do
        if row:IsShown() and row.stat then
            local v = customWeights[row.stat] or 0
            row.editBox:SetText(string.format("%.2f", v))
        end
    end

    local scaleInfo = ""
    if meta and meta.scaleName then
        scaleInfo = string.format(" (\"%s\")", meta.scaleName)
    end
    impStatusLine:SetText(string.format("|cFF00FF00Imported %d stats%s!|r", count, scaleInfo))
end)

local impCancel = CreateFrame("Button", nil, importDialog, "UIPanelButtonTemplate")
impCancel:SetSize(90, 22)
impCancel:SetPoint("BOTTOMLEFT", importDialog, "BOTTOM", 4, 8)
impCancel:SetText("Close")
impCancel:SetScript("OnClick", function() importDialog:Hide() end)

importDialog:SetScript("OnShow", function()
    impEditBox:SetText("")
    impStatusLine:SetText("")
    impEditBox:SetFocus()
end)

-- ----------------------------------------------------------------------------
-- Export Dialog
-- ----------------------------------------------------------------------------
local exportDialog = CreateFrame("Frame", "CGOExportDialog", UIParent, BACKDROP_TEMPLATE)
exportDialog:SetSize(380, 280)
exportDialog:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
exportDialog:SetFrameStrata("FULLSCREEN_DIALOG")
exportDialog:SetMovable(true)
exportDialog:EnableMouse(true)
exportDialog:RegisterForDrag("LeftButton")
exportDialog:SetScript("OnDragStart", exportDialog.StartMoving)
exportDialog:SetScript("OnDragStop", exportDialog.StopMovingOrSizing)
exportDialog:Hide()

ApplyBackdrop(exportDialog, {
    bgFile   = "Interface/DialogFrame/UI-DialogBox-Background",
    edgeFile = "Interface/DialogFrame/UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
}, { 0.1, 0.1, 0.1, 0.95 }, nil)

local expTitle = exportDialog:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
expTitle:SetPoint("TOP", exportDialog, "TOP", 0, -14)
expTitle:SetText("|cFFFFD700Export Stat Weights|r")

local expHint = exportDialog:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
expHint:SetPoint("TOP", expTitle, "BOTTOM", 0, -4)
expHint:SetText("|cFFAAAAAAPress Ctrl+C to copy your stat weights|r")

local expCurrentFormat = "pawn"
local expWeights = nil
local expProfileName = nil

local expScrollFrame = CreateFrame("ScrollFrame", "CGOExportScroll", exportDialog, "UIPanelScrollFrameTemplate")
expScrollFrame:SetPoint("TOPLEFT", exportDialog, "TOPLEFT", 14, -64)
expScrollFrame:SetPoint("BOTTOMRIGHT", exportDialog, "BOTTOMRIGHT", -32, 46)

local expEditBox = CreateFrame("EditBox", "CGOExportEditBox", expScrollFrame)
expEditBox:SetMultiLine(true)
expEditBox:SetAutoFocus(false)
expEditBox:SetFontObject(ChatFontNormal)
expEditBox:SetWidth(310)
expEditBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
expScrollFrame:SetScrollChild(expEditBox)

local function RefreshExportText()
    local w = expWeights or customWeights or {}
    local name = expProfileName or "Current"
    local text = ""
    if addon.ExportWeights then
        text = addon:ExportWeights(w, expCurrentFormat, name, addon.currentClass, addon.currentSpecIdx)
    elseif addon.StatCalc and addon.StatCalc.ExportWeights then
        text = addon.StatCalc:ExportWeights(w, expCurrentFormat, name, addon.currentClass, addon.currentSpecIdx)
    end
    expEditBox:SetText(text or "")
    expEditBox:SetFocus()
    expEditBox:HighlightText()
end

local btnPawn = CreateFrame("Button", nil, exportDialog, "UIPanelButtonTemplate")
btnPawn:SetSize(60, 20)
btnPawn:SetPoint("TOPLEFT", exportDialog, "TOPLEFT", 14, -38)
btnPawn:SetText("Pawn")
btnPawn:SetScript("OnClick", function()
    expCurrentFormat = "pawn"
    RefreshExportText()
end)

local btnSimC = CreateFrame("Button", nil, exportDialog, "UIPanelButtonTemplate")
btnSimC:SetSize(60, 20)
btnSimC:SetPoint("LEFT", btnPawn, "RIGHT", 6, 0)
btnSimC:SetText("SimC")
btnSimC:SetScript("OnClick", function()
    expCurrentFormat = "simc"
    RefreshExportText()
end)

local btnJSON = CreateFrame("Button", nil, exportDialog, "UIPanelButtonTemplate")
btnJSON:SetSize(60, 20)
btnJSON:SetPoint("LEFT", btnSimC, "RIGHT", 6, 0)
btnJSON:SetText("JSON")
btnJSON:SetScript("OnClick", function()
    expCurrentFormat = "json"
    RefreshExportText()
end)

local expClose = CreateFrame("Button", nil, exportDialog, "UIPanelButtonTemplate")
expClose:SetSize(80, 22)
expClose:SetPoint("BOTTOM", exportDialog, "BOTTOM", 0, 10)
expClose:SetText("Close")
expClose:SetScript("OnClick", function() exportDialog:Hide() end)

function exportDialog:Open(profileName, weights, format)
    if format then expCurrentFormat = format end
    expProfileName = profileName
    expWeights = weights
    exportDialog:Show()
    RefreshExportText()
end

function addon:OpenExportDialog(profileName, weights, format)
    exportDialog:Open(profileName, weights, format)
end

function addon:OpenImportDialog()
    importDialog:Show()
end

-- ============================================================================
-- STAT EDITOR BUTTONS (Apply / Import / Export / Save Stats)
-- ============================================================================
local seApply = CreateFrame("Button", nil, statEditor, "UIPanelButtonTemplate")
seApply:SetSize(44, 20)
seApply:SetPoint("BOTTOMLEFT", statEditor, "BOTTOMLEFT", 4, 4)
seApply:SetText("Apply")
seApply:SetScript("OnClick", function()
    -- Commit editbox values
    for _, row in ipairs(statRows) do
        if row:IsShown() and row.stat then
            local num = tonumber(row.editBox:GetText()) or 0
            customWeights[row.stat] = num
        end
    end

    -- Apply custom weights to the current specData
    if addon.currentCustomProfile then
        addon.currentCustomProfile.weights = {}
        for k, v in pairs(customWeights) do
            if v ~= 0 then addon.currentCustomProfile.weights[k] = v end
        end
        local pName = addon.currentCustomProfile.name
        if pName and CharacterGearOptimizerDB and CharacterGearOptimizerDB.customStats then
            CharacterGearOptimizerDB.customStats[pName] = {}
            for k, v in pairs(addon.currentCustomProfile.weights) do
                CharacterGearOptimizerDB.customStats[pName][k] = v
            end
        end
        local bestSet = OptimizeForCustomProfile(addon.currentCustomProfile)
        addon.currentBestSet = bestSet
        addon:PopulateSlots(bestSet)
    elseif addon.currentClass and addon.currentSpecIdx and addon.currentSpecIdx > 0 then
        local specData = addon.CLASS_SPECS[addon.currentClass][addon.currentSpecIdx]
        if specData then
            specData.weights = {}
            for k, v in pairs(customWeights) do
                if v ~= 0 then
                    specData.weights[k] = v
                end
            end

            local bestSet = addon:GetBestGearForSpec(addon.currentClass, addon.currentSpecIdx)
            if bestSet then
                addon.currentBestSet = bestSet
                addon:PopulateSlots(bestSet)
            end
        end
    end
    statEditor:Hide()
end)

local seImport = CreateFrame("Button", nil, statEditor, "UIPanelButtonTemplate")
seImport:SetSize(44, 20)
seImport:SetPoint("LEFT", seApply, "RIGHT", 2, 0)
seImport:SetText("Import")
seImport:SetScript("OnClick", function()
    importDialog:Show()
end)

local seExport = CreateFrame("Button", nil, statEditor, "UIPanelButtonTemplate")
seExport:SetSize(44, 20)
seExport:SetPoint("LEFT", seImport, "RIGHT", 2, 0)
seExport:SetText("Export")
seExport:SetScript("OnClick", function()
    for _, row in ipairs(statRows) do
        if row:IsShown() and row.stat then
            local num = tonumber(row.editBox:GetText()) or 0
            customWeights[row.stat] = num
        end
    end
    local profileName = "Custom"
    if addon.currentCustomProfile and addon.currentCustomProfile.name then
        profileName = addon.currentCustomProfile.name
    elseif addon.currentClass and addon.currentSpecIdx and addon.CLASS_SPECS and addon.CLASS_SPECS[addon.currentClass] then
        local s = addon.CLASS_SPECS[addon.currentClass][addon.currentSpecIdx]
        if s and s.name then profileName = s.name end
    end
    exportDialog:Open(profileName, customWeights, "pawn")
end)

local seSaveAs = CreateFrame("Button", nil, statEditor, "UIPanelButtonTemplate")
seSaveAs:SetSize(48, 20)
seSaveAs:SetPoint("LEFT", seExport, "RIGHT", 2, 0)
seSaveAs:SetText("Save")
seSaveAs:SetScript("OnClick", function()
    for _, row in ipairs(statRows) do
        if row:IsShown() and row.stat then
            local num = tonumber(row.editBox:GetText()) or 0
            customWeights[row.stat] = num
        end
    end

    local dialog = _G["CGONameDialog"]
    local input  = _G["CGONameInput"]
    if not dialog or not input then return end

    input:SetText("My Custom Stats")
    dialog:Show()
    input:SetFocus()
    input:HighlightText()

    local nameOKBtn = dialog.saveBtn
    if nameOKBtn then
        nameOKBtn:SetScript("OnClick", function()
            local profileName = input:GetText()
            if not profileName or profileName == "" then return end
            dialog:Hide()

            CharacterGearOptimizerDB.customStats = CharacterGearOptimizerDB.customStats or {}

            local weights = {}
            for k, v in pairs(customWeights) do
                if v ~= 0 then weights[k] = v end
            end

            CharacterGearOptimizerDB.customStats[profileName] = weights
            print("|cFFFFD700CharacterGearOptimizer:|r Saved custom stats profile: |cFF00FF00" .. profileName .. "|r")

            addon:RestoreNameDialogSaveHook()
        end)
    end
end)

-- ============================================================================
-- MAIN PANEL
-- ============================================================================
local frame = CreateFrame("Frame", "CharacterGearOptimizerFrame", UIParent, BACKDROP_TEMPLATE)
frame:SetFrameStrata("DIALOG")
frame:SetSize(PANEL_WIDTH, PANEL_HEIGHT)
frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
frame:SetMovable(true)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")
frame:SetScript("OnDragStart", frame.StartMoving)
frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
frame:Hide()

ApplyBackdrop(frame, {
    bgFile   = "Interface/DialogFrame/UI-DialogBox-Background",
    edgeFile = "Interface/DialogFrame/UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
}, { 0.05, 0.02, 0.02, 0.75 }, { 0.55, 0.45, 0.25, 1 })

-- Title
local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
title:SetPoint("TOP", frame, "TOP", 0, -12)
title:SetText("|cFFFFD700Character Gear Optimizer|r")

-- Durability %
local function GetOverallDurability()
    local cur, mx = 0, 0
    for slot = 1, 18 do
        local c, m = GetInventoryItemDurability(slot)
        if c and m then cur = cur + c; mx = mx + m end
    end
    if mx == 0 then return 100 end
    return math.floor(cur / mx * 100 + 0.5)
end

local durabilityText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
durabilityText:SetPoint("TOP", title, "BOTTOM", 0, -2)

local function UpdateDurabilityText()
    local pct = GetOverallDurability()
    local col
    if pct > 50 then col = "00FF00"
    elseif pct > 25 then col = "FFFF00"
    else col = "FF3300" end
    durabilityText:SetText("|cFF" .. col .. "Durability: " .. pct .. "%%|r")
end

frame:HookScript("OnShow", UpdateDurabilityText)
frame:RegisterEvent("UPDATE_INVENTORY_DURABILITY")
frame:HookScript("OnEvent", function(self, event)
    if event == "UPDATE_INVENTORY_DURABILITY" and self:IsShown() then
        UpdateDurabilityText()
    end
end)

-- Close Button
local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
closeBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)

-- Close picker when main frame hides
frame:SetScript("OnHide", function()
    picker:Hide()
    statEditor:Hide()
    nameDialog:Hide()
end)

-- ============================================================================
-- REPLACE CHARACTER SHEET
-- Open CharacterGearOptimizer instead of the default PaperDollFrame when pressing C
-- or clicking the Character micro-button.
-- ============================================================================
local origToggleCharacter = ToggleCharacter
function ToggleCharacter(tab)
    if tab == "PaperDollFrame" then
        if frame:IsShown() then
            frame:Hide()
        else
            frame:Show()
        end
        return
    end
    origToggleCharacter(tab)
end
-- Let Escape close our frame via the built-in UISpecialFrames list
tinsert(UISpecialFrames, "CharacterGearOptimizerFrame")

-- 3D Model View
local model = CreateFrame("PlayerModel", nil, frame)
model:SetSize(150, 290)
model:SetPoint("TOP", frame, "TOP", 0, -42)
model:SetFrameStrata("TOOLTIP")
model:SetUnit("player")
model:SetRotation(0)

-- Inline the stat editor over the model area
statEditor:SetParent(frame)
statEditor:ClearAllPoints()
statEditor:SetPoint("TOP", frame, "TOP", 0, -42)
statEditor:SetSize(200, 290)
statEditor:SetFrameLevel(model:GetFrameLevel() + 5)statEditor:SetScript("OnHide", function()
    model:Show()
    -- Restore weapon slot buttons
    for _, sid in ipairs({16, 17, 18}) do
        if addon.equipSlots and addon.equipSlots[sid] then
            addon.equipSlots[sid].borderFrame:Show()
        end
    end
end)

-- ============================================================================
-- EQUIPMENT SLOT BUTTONS (clickable -> opens item picker)
-- ============================================================================
addon.equipSlots = {}

local SLOT_BORDER = SLOT_SIZE + 8

local function CreateSlotButton(id, name, parent, anchor, x, y)
    -- WAR-themed border frame wrapping the slot
    local border = CreateFrame("Frame", nil, parent, BACKDROP_TEMPLATE)
    border:SetSize(SLOT_BORDER, SLOT_BORDER)
    border:SetPoint(anchor, parent, anchor, x, y)
    ApplyBackdrop(border, {
        bgFile   = "Interface/DialogFrame/UI-DialogBox-Background",
        edgeFile = "Interface/DialogFrame/UI-DialogBox-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    }, { 0.05, 0.02, 0.02, 0.8 }, { 0.55, 0.45, 0.25, 1 })

    local btn = CreateFrame("Button", "CGOSlot"..id, border, "ItemButtonTemplate")
    btn:SetSize(SLOT_SIZE, SLOT_SIZE)
    btn:SetPoint("CENTER", border, "CENTER", 0, 0)
    btn:SetID(id)
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    -- Strip the default ItemButtonTemplate border so only the WAR border shows
    local regions = { btn:GetRegions() }
    for _, region in ipairs(regions) do
        if region:IsObjectType("Texture") then
            local tex = region:GetTexture()
            local drawLayer = region:GetDrawLayer()
            -- Hide the default border/normal textures from the template
            if drawLayer == "OVERLAY" or drawLayer == "BORDER"
               or (tex and type(tex) == "string" and tex:find("UI%-Slot%-Background")) then
                region:SetTexture(nil)
                region:Hide()
            end
        end
    end
    if btn.IconBorder then btn.IconBorder:Hide() end
    if btn.NormalTexture then btn.NormalTexture:SetTexture(nil) end
    local nt = btn:GetNormalTexture()
    if nt then nt:SetTexture(nil) end

    local slotLabel = SLOT_LABELS[id] or name
    btn.slotName = name
    btn.invSlotID = id
    btn.borderFrame = border

    -- Hover-to-open item picker using OnUpdate elapsed timer
    btn._hoverElapsed = 0
    btn._hovering = false

    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self:GetParent(), "ANCHOR_RIGHT")
        if self.itemLink then
            GameTooltip:SetHyperlink(self.itemLink)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("|cff888888Shift-Right-Click: Socket Gems|r")
            GameTooltip:Show()
        else
            GameTooltip:AddLine(slotLabel)
            GameTooltip:Show()
        end
        self._hovering = true
        self._hoverElapsed = 0
    end)
    btn:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
        self._hovering = false
        self._hoverElapsed = 0
    end)
    btn:SetScript("OnUpdate", function(self, elapsed)
        if not self._hovering then return end
        self._hoverElapsed = self._hoverElapsed + elapsed
        if self._hoverElapsed >= 0.35 then
            self._hovering = false
            self._hoverElapsed = 0
            ShowItemPicker(self.invSlotID, self:GetParent())
        end
    end)

    btn:SetScript("OnClick", function(self, button)
        if button == "RightButton" and IsShiftKeyDown() then
            if self.invSlotID and GetInventoryItemLink("player", self.invSlotID) then
                SocketInventoryItem(self.invSlotID)
            end
        elseif button == "LeftButton" and IsShiftKeyDown() then
            local link = self.itemLink or GetInventoryItemLink("player", self.invSlotID)
            if link then
                HandleModifiedItemClick(link)
            end
        elseif button == "LeftButton" then
            ShowItemPicker(self.invSlotID, self:GetParent())
        end
    end)

    -- Allow drag-to-unequip: pick up the inventory item on drag start
    btn:RegisterForDrag("LeftButton")
    btn:SetScript("OnDragStart", function(self)
        PickupInventoryItem(self.invSlotID)
    end)
    -- Allow dropping an item onto a slot to equip it
    btn:SetScript("OnReceiveDrag", function(self)
        PickupInventoryItem(self.invSlotID)
    end)

    addon.equipSlots[id] = btn
    return btn
end

-- Left side (8 slots)
local lY = -38
local lIDs = {1, 2, 3, 15, 5, 4, 19, 9}
local lNames = {"INVTYPE_HEAD", "INVTYPE_NECK", "INVTYPE_SHOULDER", "INVTYPE_CLOAK", "INVTYPE_CHEST", "INVTYPE_BODY", "INVTYPE_TABARD", "INVTYPE_WRIST"}
for i, id in ipairs(lIDs) do
    CreateSlotButton(id, lNames[i], frame, "TOPLEFT", 8, lY)
    lY = lY - SLOT_BORDER
end

-- Right side (8 slots)
local rY = -38
local rIDs = {10, 6, 7, 8, 11, 12, 13, 14}
local rNames = {"INVTYPE_HAND", "INVTYPE_WAIST", "INVTYPE_LEGS", "INVTYPE_FEET", "INVTYPE_FINGER", "INVTYPE_FINGER", "INVTYPE_TRINKET", "INVTYPE_TRINKET"}
for i, id in ipairs(rIDs) do
    CreateSlotButton(id, rNames[i], frame, "TOPRIGHT", -8, rY)
    rY = rY - SLOT_BORDER
end

-- Bottom (weapons) â€” just above the dropdown row
CreateSlotButton(16, "INVTYPE_WEAPONMAINHAND", frame, "BOTTOM", -66, 318)
CreateSlotButton(17, "INVTYPE_WEAPONOFFHAND", frame, "BOTTOM", 0, 318)
CreateSlotButton(18, "INVTYPE_RANGED", frame, "BOTTOM", 66, 318)

-- ============================================================================
-- CUSTOM PROFILE OPTIMIZER (shared by checkbox handler + dropdown)
-- Uses the same two-pass MOO approach as GetBestGearForSpec but for an
-- arbitrary specData table (custom stat profiles).
-- When cap checkboxes are active, the optimizer first builds the best normal
-- set, then iteratively swaps items to meet caps (MOO: minimize score lost
-- per cap-stat gained).
-- ============================================================================
-- Helper: detect whether an item is a two-hand weapon
local function Is2HWeapon(item)
    if item.equipLoc == "INVTYPE_2HWEAPON" then return true end
    if item.link then
        local _, _, _, _, _, _, _, _, eLoc = GetItemInfo(item.link)
        if eLoc == "INVTYPE_2HWEAPON" then return true end
    end
    return false
end

function OptimizeForCustomProfile(specData)
    addon.optimizePreferredArmor = specData and specData.preferredArmor
    if specData and specData.weights then
        addon:ApplyPowerCapWeights(specData.weights)
    end
    local allItems = addon:GetAllAvailableItems()

    -- Build scored item list
    local scoredItems = {}
    for _, item in ipairs(allItems) do
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
        -- Score-0 bag items are needed so cap swaps can find defense/hit/resil gear.
        if (item.isEquipped or item.equipLoc) and (item.isEquipped or UnitLevel("player") < 60 or addon:PreferHeirloomsEnabled() or not addon:IsHeirloomItem(item.link)) then
            local validSlots
            if item.isEquipped then
                local genericSlots = addon:GetValidSlotsForEquipLoc(nil, item.link)
                validSlots = { item.slot }
                for _, gs in ipairs(genericSlots) do
                    if gs ~= item.slot then table.insert(validSlots, gs) end
                end
            else
                validSlots = addon:GetValidSlotsForEquipLoc(item.equipLoc, item.link)
            end
            local resolvedLoc = item.equipLoc
            if not resolvedLoc or resolvedLoc == "EQUIPPED" then
                local _, _, _, _, _, _, _, _, eLoc = GetItemInfo(item.link)
                resolvedLoc = eLoc or item.equipLoc or "EQUIPPED"
            end
            table.insert(scoredItems, {
                link = item.link,
                bag = item.bag,
                slot = item.slot,
                isEquipped = item.isEquipped,
                equipLoc = resolvedLoc,
                score = score,
                slots = validSlots,
                stats = stats,
                isHeirloom = addon:IsHeirloomItem(item.link),
            })
        end
    end

    -- Greedy slot assignment helper
    local function AssignSlots(scored)
        local bestSet = {}
        local used = {}
        local blockedSlots = {}
        for _, it in ipairs(scored) do
            for _, s in ipairs(it.slots) do
                local key = it.isEquipped and ("EQ_"..it.slot) or ("BAG_"..(it.bag or 0).."_"..it.slot)
                -- Trinkets (13/14) are never auto-swapped by stat score --
                -- FillEquippedFallback below keeps whatever's already worn.
                if s ~= 13 and s ~= 14 and not bestSet[s] and not used[key] and not blockedSlots[s] then
                    bestSet[s] = it; used[key] = true
                    -- 2H weapon in MH blocks the OH slot
                    if s == 16 and Is2HWeapon(it) then
                        blockedSlots[17] = true
                        if bestSet[17] then
                            local ohKey = bestSet[17].isEquipped and ("EQ_"..bestSet[17].slot) or ("BAG_"..(bestSet[17].bag or 0).."_"..bestSet[17].slot)
                            used[ohKey] = nil
                            bestSet[17] = nil
                        end
                    end
                    if s == 17 and bestSet[16] and Is2HWeapon(bestSet[16]) then
                        bestSet[17] = nil; used[key] = nil
                    else
                        break
                    end
                end
            end
        end
        return bestSet
    end

    -- Fill equipped fallback
    local function FillEquippedFallback(bestSet)
        for _, item in ipairs(allItems) do
            if item.isEquipped and not bestSet[item.slot] then
                -- Don't fill OH if MH is a 2H weapon
                if item.slot == 17 and bestSet[16] and Is2HWeapon(bestSet[16]) then
                    -- skip offhand
                else
                    local st = addon:ExtractItemStats(item.link)
                    local sc = addon:CalculateScore(st, specData)
                    bestSet[item.slot] = {
                        link = item.link, bag = nil, slot = item.slot,
                        isEquipped = true, score = sc, slots = { item.slot }, stats = st,
                    }
                end
            end
        end
    end

    -- Sum a stat across all items in a gear set
    local function SumSetStat(gearSet, statKey)
        local total = 0
        for _, item in pairs(gearSet) do
            if item.stats then total = total + (item.stats[statKey] or 0) end
        end
        return total
    end

    -- STEP 1: Normal single-pass optimization
    table.sort(scoredItems, function(a, b) return addon:CompareOptimizerItems(a, b) end)
    local bestSet = AssignSlots(scoredItems)
    FillEquippedFallback(bestSet)

    local forceShieldTank = addon:ShouldForceShieldTank(specData)
    local selectedWeaponMode = addon:GetSelectedWeaponMode()
    local selectedSubtypeMode = addon:GetSelectedWeaponSubtypeMode()
    if selectedSubtypeMode then
        addon:EnforceWeaponSubtypeMode(bestSet, scoredItems)
    elseif selectedWeaponMode == "staff_shield" then
        addon:EnforceWeaponMode(bestSet, scoredItems)
    elseif not selectedWeaponMode and forceShieldTank then
        addon:EnforceShieldTankWeapons(bestSet, scoredItems)
    end

    -- 2H vs MH+OH check
    if not forceShieldTank and selectedWeaponMode ~= "staff_shield"
        and not selectedSubtypeMode
        and bestSet[16] and Is2HWeapon(bestSet[16]) then
        local twoHandScore = bestSet[16].score or 0
        local twoHandKey = bestSet[16].isEquipped and ("EQ_"..bestSet[16].slot)
                           or ("BAG_"..(bestSet[16].bag or 0).."_"..bestSet[16].slot)
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
                    if not bestMH and (isMH or eLoc == "INVTYPE_WEAPON") then
                        bestMH = item
                        usedKeys[item.isEquipped and ("EQ_"..item.slot) or ("BAG_"..(item.bag or 0).."_"..item.slot)] = true
                    elseif not bestOH and (isOH or (eLoc == "INVTYPE_WEAPON" and bestMH)) then
                        bestOH = item
                        usedKeys[item.isEquipped and ("EQ_"..item.slot) or ("BAG_"..(item.bag or 0).."_"..item.slot)] = true
                    end
                end
            end
            if bestMH and bestOH then break end
        end
        local dualScore = (bestMH and bestMH.score or 0) + (bestOH and bestOH.score or 0)
        if bestMH and dualScore > twoHandScore then
            bestSet[16] = bestMH
            bestSet[17] = bestOH
        end
    end

    -- STEP 2: MOO-style iterative cap swaps
    local caps = CharacterGearOptimizerDB and CharacterGearOptimizerDB.capPriorities or {}
    local anyCap = caps.critImmune or caps.hitCapped or caps.spellHitCapped or caps.expertiseCapped or caps.uncrushable or caps.armorCapped or caps.resilCapped or caps.hasteCapped

    if anyCap then
        local R = addon.RATING
        local role = specData.role or "melee_dps"

        -- Compute base (non-gear) contribution for each cap stat
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
            return totalDefSkill - (gearDefRating / R.DEFENSE_PER_SKILL)
        end

        local function GetBaseHitPct(crID)
            if not GetCombatRating then return 0 end
            local hitRating = GetCombatRating(crID) or 0
            local ratingPer = (crID == R.CR_HIT_SPELL) and R.SPELL_HIT_PER_PCT or R.HIT_PER_PCT
            local totalHitPct = addon:GetTotalHitChance(crID)
            return totalHitPct - (hitRating / ratingPer)
        end

        local function GetBaseExpertise()
            if not GetExpertise then return 0 end
            local totalExp = GetExpertise() or 0
            local expRating = GetCombatRating and (GetCombatRating(R.CR_EXPERTISE) or 0) or 0
            return totalExp - (expRating / R.EXPERTISE_PER_SKILL)
        end

        local function GetBaseResilPct()
            if not GetCombatRating then return 0 end
            local resilRating = GetCombatRating(R.CR_RESILIENCE) or 0
            local totalResilPct = GetCombatRatingBonus(R.CR_RESILIENCE) or 0
            return totalResilPct - (resilRating / R.RESIL_PER_PCT)
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
        if caps.critImmune then
            local baseDef = GetBaseDefense()
            if baseDef < R.DEFENSE_CAP then
                table.insert(capGoals, { stat = "DEF", totalRatingNeeded = (R.DEFENSE_CAP - baseDef) * R.DEFENSE_PER_SKILL, label = "Defense" })
            end
            local baseResil = GetBaseResilPct()
            if baseResil < R.BOSS_CRIT_PCT then
                table.insert(capGoals, { stat = "RESIL", totalRatingNeeded = (R.BOSS_CRIT_PCT - baseResil) * R.RESIL_PER_PCT, label = "Resilience" })
            end
        end
        local pvp = caps.pvpMode
        if caps.hitCapped then
            local hitCapPct = pvp and R.PVP_MELEE_HIT_CAP_PCT or R.MELEE_HIT_CAP_PCT
            local baseHit = GetBaseHitPct(R.CR_HIT_MELEE)
            if baseHit < hitCapPct then
                table.insert(capGoals, { stat = "HIT", totalRatingNeeded = (hitCapPct - baseHit) * R.HIT_PER_PCT, label = "Melee Hit" })
            end
        end
        if caps.spellHitCapped then
            local shCapPct = pvp and R.PVP_SPELL_HIT_CAP_PCT or R.SPELL_HIT_CAP_PCT
            local baseHit = GetBaseHitPct(R.CR_HIT_SPELL)
            if baseHit < shCapPct then
                table.insert(capGoals, { stat = "SPELL_HIT_TOTAL", totalRatingNeeded = (shCapPct - baseHit) * R.SPELL_HIT_PER_PCT, label = "Spell Hit" })
            end
        end
        if caps.expertiseCapped and (role == "melee_dps" or role == "tank") then
            local expCap = pvp and R.PVP_EXPERTISE_SOFT_CAP or R.EXPERTISE_SOFT_CAP
            local baseExp = GetBaseExpertise()
            if baseExp < expCap then
                table.insert(capGoals, { stat = "EXP", totalRatingNeeded = (expCap - baseExp) * R.EXPERTISE_PER_SKILL, label = "Expertise" })
            end
        end
        if caps.uncrushable then
            local baseAvoid = GetBaseAvoidance()
            if baseAvoid < R.UNCRUSHABLE_PCT then
                table.insert(capGoals, { stat = "AVOID", totalRatingNeeded = R.UNCRUSHABLE_PCT - baseAvoid, label = "Uncrushable" })
            end
        end
        if caps.armorCapped then
            -- Armor cap: need total armor >= cap for 75% DR
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

        -- Build per-slot candidate lookup. Trinkets (13/14) excluded --
        -- never auto-swapped, cap goals included.
        local slotCandidates = {}
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
        for _, statLists in pairs(slotCandidates) do
            for stat, list in pairs(statLists) do
                table.sort(list, function(a, b) return (a.stats[stat] or 0) > (b.stats[stat] or 0) end)
            end
        end

        -- Iterative swap loop
        for _, goal in ipairs(capGoals) do
            for _ = 1, 20 do
                local currentRating = SumSetStat(bestSet, goal.stat)
                if currentRating >= goal.totalRatingNeeded then break end

                local bestSwap = nil
                for slotID, item in pairs(bestSet) do
                    local currentCapVal = item.stats and (item.stats[goal.stat] or 0) or 0
                    local currentScore  = item.score or 0
                    local candidates = slotCandidates[slotID] and slotCandidates[slotID][goal.stat]
                    if candidates then
                        for _, cand in ipairs(candidates) do
                            local candKey = cand.isEquipped and ("EQ_"..cand.slot) or ("BAG_"..(cand.bag or 0).."_"..cand.slot)
                            local curKey  = item.isEquipped and ("EQ_"..item.slot) or ("BAG_"..(item.bag or 0).."_"..item.slot)
                            if candKey ~= curKey then
                                local alreadyUsed = false
                                for otherSlot, otherItem in pairs(bestSet) do
                                    if otherSlot ~= slotID then
                                        local otherKey = otherItem.isEquipped and ("EQ_"..otherItem.slot) or ("BAG_"..(otherItem.bag or 0).."_"..otherItem.slot)
                                        if otherKey == candKey then alreadyUsed = true; break end
                                    end
                                end
                                if not alreadyUsed then
                                    local capGained = (cand.stats[goal.stat] or 0) - currentCapVal
                                    if capGained > 0 then
                                        local scoreLost = currentScore - cand.score
                                        local eff = (scoreLost > 0) and (capGained / scoreLost) or (capGained * 1000)
                                        if not bestSwap or eff > bestSwap.efficiency then
                                            bestSwap = { slotID = slotID, newItem = cand, efficiency = eff }
                                        end
                                    end
                                    break  -- found usable candidate for this slot
                                end
                                -- candidate already used; try next best
                            end
                        end
                    end
                end

                if not bestSwap then break end
                bestSet[bestSwap.slotID] = bestSwap.newItem
                -- 2H/OH mutual exclusion after cap swap
                if bestSwap.slotID == 16 and Is2HWeapon(bestSwap.newItem) then
                    bestSet[17] = nil
                elseif bestSwap.slotID == 17 and bestSet[16] and Is2HWeapon(bestSet[16]) then
                    bestSet[bestSwap.slotID] = nil
                end
            end
        end
    end

    if addon:GetSelectedWeaponSubtypeMode() then
        addon:EnforceWeaponSubtypeMode(bestSet, scoredItems)
    elseif addon:GetSelectedWeaponMode() == "staff_shield" then
        addon:EnforceWeaponMode(bestSet, scoredItems)
    elseif not addon:GetSelectedWeaponMode() and forceShieldTank then
        addon:EnforceShieldTankWeapons(bestSet, scoredItems)
    end
    addon:EnforceRangedMode(bestSet, scoredItems)
    addon:EnforceHeirloomPreference(bestSet, scoredItems, specData, select(2, UnitClass("player")))

    return bestSet
end

-- ============================================================================
-- CAP PRIORITY CHECKBOXES
-- When checked, the optimizer boosts stat weights for uncapped breakpoints
-- so gear that reaches the cap is prioritised.
-- ============================================================================
local function CreateCapCheckbox(name, label, dbKey, yFromBottom, xOffset)
    local cb = CreateFrame("CheckButton", "CGOCap_" .. name, frame, "UICheckButtonTemplate")
    cb:SetSize(22, 22)
    cb:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", xOffset or 12, yFromBottom)

    cb.label = cb:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    cb.label:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    cb.label:SetText(label)

    cb:SetScript("OnClick", function(self)
        if not CharacterGearOptimizerDB then return end
        CharacterGearOptimizerDB.capPriorities = CharacterGearOptimizerDB.capPriorities or {}
        CharacterGearOptimizerDB.capPriorities[dbKey] = self:GetChecked() and true or false

        -- Re-run optimisation with updated caps
        if addon.currentClass and addon.currentSpecIdx and addon.currentSpecIdx > 0 then
            local bestSet = addon:GetBestGearForSpec(addon.currentClass, addon.currentSpecIdx)
            if bestSet then
                addon.currentBestSet = bestSet
                addon:PopulateSlots(bestSet)
            end
        elseif addon.currentCustomProfile then
            local bestSet = OptimizeForCustomProfile(addon.currentCustomProfile)
            addon.currentBestSet = bestSet
            addon:PopulateSlots(bestSet)
        end
        -- Refresh the SpecHUD so breakpoints reflect the new cap toggles
        if addon.UpdateSpecHUD then addon:UpdateSpecHUD() end
    end)

    return cb
end

-- Cap Priorities header
local capHeader = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
capHeader:SetPoint("BOTTOM", frame, "BOTTOM", 0, 282)
capHeader:SetText("|cFFFFD700Cap Priorities|r")

-- Two-column layout: left column x=12, right column x=172
local capColL, capColR = 12, 172
local capRow1, capRow2, capRow3, capRow4, capRow5 = 254, 236, 218, 200, 182
local capRow6, capRow7 = 164, 146

local capCritImmune    = CreateCapCheckbox("CritImmune",    "|cFFCCCCCCCrit Immune|r",    "critImmune",       capRow1, capColL)
local capUncrushable   = CreateCapCheckbox("Uncrushable",   "|cFFCCCCCCUncrushable|r",    "uncrushable",      capRow1, capColR)
local capHitCapped     = CreateCapCheckbox("HitCapped",     "|cFFCCCCCCMelee Hit|r",      "hitCapped",        capRow2, capColL)
local capSpellHit      = CreateCapCheckbox("SpellHitCapped","|cFFCCCCCCSpell Hit|r",      "spellHitCapped",   capRow2, capColR)
local capExpCapped     = CreateCapCheckbox("ExpCapped",     "|cFFCCCCCCExpertise|r",      "expertiseCapped",  capRow3, capColL)
local capArmorCapped   = CreateCapCheckbox("ArmorCapped",   "|cFFCCCCCCArmor Cap|r",      "armorCapped",      capRow3, capColR)
local capResilCapped   = CreateCapCheckbox("ResilCapped",   "|cFFCCCCCCResilience|r",     "resilCapped",      capRow4, capColL)
local capHasteCapped   = CreateCapCheckbox("HasteCapped",   "|cFFCCCCCCHaste Cap|r",      "hasteCapped",      capRow4, capColR)

-- Power priorities: maximize the checked power stat, ignore the unchecked one.
local capPvpPower      = CreateCapCheckbox("PvpPower",      "|cFF00CCFFPvP Power|r",      "pvpPower",         capRow5, capColL)
local capPvePower      = CreateCapCheckbox("PvePower",      "|cFF00CCFFPvE Power|r",      "pvePower",         capRow5, capColR)

local capPvpMode = CreateCapCheckbox("PvpMode", "|cFF00CCFFPvP Mode|r  |cFF888888(PvP caps)|r", "pvpMode", capRow6, capColL)

local capNot60 = CreateCapCheckbox("Not60", "|cFFCCCCCCNot 60|r  |cFF888888(prefer heirlooms)|r", "not60", capRow6, capColR)

local capAutoRoll = CreateFrame("CheckButton", "CGOCap_AutoRoll", frame, "UICheckButtonTemplate")
capAutoRoll:SetSize(22, 22)
capAutoRoll:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", capColL, capRow7)
capAutoRoll.label = capAutoRoll:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
capAutoRoll.label:SetPoint("LEFT", capAutoRoll, "RIGHT", 2, 0)
capAutoRoll.label:SetText("|cFF00CCFFAuto Roll|r")
capAutoRoll:SetScript("OnClick", function(self)
    CharacterGearOptimizerDB = CharacterGearOptimizerDB or {}
    CharacterGearOptimizerDB.autoRoll = self:GetChecked() and true or false
end)
capAutoRoll:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Auto Roll")
    GameTooltip:AddLine("Need on CGO upgrades.", 1, 1, 1)
    GameTooltip:AddLine("Greed if vendor value is over 1 gold.", 1, 1, 1)
    GameTooltip:AddLine("Pass on everything else.", 1, 1, 1)
    GameTooltip:AddLine("Does not roll on skill cards.", 1, 1, 1)
    GameTooltip:Show()
end)
capAutoRoll:SetScript("OnLeave", function() GameTooltip:Hide() end)

-- ============================================================================
-- WEAPON DROPDOWNS (melee hands + ranged slot, independent)
-- ============================================================================
local WEAPON_MODE_LABELS = {
    auto       = "Weapons: Auto",
    one_1h     = "1 x 1H",
    one_dagger = "1 x Dagger",
    dual_1h    = "Dual Wield 1H",
    dual_dagger = "Dual Wield Daggers",
    dual_2h    = "Dual Wield 2H",
    one_2h     = "1 x 2H",
    staff_shield = "2H Staff + Shield",
    wand       = "Wand",
    thrown     = "Thrown",
    ranged     = "Bow/Gun",
    ["1h_shield"] = "1H + Shield",
    staff      = "Staff",
}
local MELEE_MODE_ORDER = { "auto", "one_1h", "one_dagger", "dual_1h", "dual_dagger", "dual_2h", "one_2h", "staff_shield", "wand", "1h_shield", "staff" }
local RANGED_MODE_ORDER = { "auto", "thrown", "ranged", "wand" }

local function CurrentWeaponMode()
    return addon:GetSelectedWeaponMode() or "auto"
end

local function CurrentRangedMode()
    return addon:GetSelectedRangedMode() or "auto"
end

local function RefreshCurrentOptimization()
    if addon.currentCustomProfile then
        local bestSet = OptimizeForCustomProfile(addon.currentCustomProfile)
        if bestSet then
            addon.currentBestSet = bestSet
            addon:PopulateSlots(bestSet)
        end
    elseif addon.currentClass and addon.currentSpecIdx and addon.currentSpecIdx > 0 then
        local bestSet = addon:GetBestGearForSpec(addon.currentClass, addon.currentSpecIdx)
        if bestSet then
            addon.currentBestSet = bestSet
            addon:PopulateSlots(bestSet)
        end
    end
end

-- Melee dropdown: main hand / off hand loadout (slots 16-17)
local weaponDropdown = CreateFrame("Frame", "CGOWeaponDropdown", frame, "UIDropDownMenuTemplate")
weaponDropdown:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 10, 88)
UIDropDownMenu_SetWidth(weaponDropdown, 110)
weaponDropdown.label = weaponDropdown:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
weaponDropdown.label:SetPoint("TOPLEFT", weaponDropdown, "BOTTOMLEFT", -8, -2)
weaponDropdown.label:SetText("|cFFFFD700Main Hand / Off Hand|r")

local function UpdateWeaponDropdownText()
    UIDropDownMenu_SetText(weaponDropdown, WEAPON_MODE_LABELS[CurrentWeaponMode()] or "Weapons: Auto")
end

UIDropDownMenu_Initialize(weaponDropdown, function(self, level)
    for _, mode in ipairs(MELEE_MODE_ORDER) do
        local info = UIDropDownMenu_CreateInfo()
        info.text = WEAPON_MODE_LABELS[mode]
        info.value = mode
        info.func = function()
            addon:SetSelectedWeaponMode(mode == "auto" and nil or mode)
            UpdateWeaponDropdownText()
            RefreshCurrentOptimization()
        end
        info.checked = (CurrentWeaponMode() == mode)
        UIDropDownMenu_AddButton(info)
    end
end)

-- Ranged dropdown: thrown vs bow/gun/crossbow (slot 18)
local rangedDropdown = CreateFrame("Frame", "CGORangedDropdown", frame, "UIDropDownMenuTemplate")
rangedDropdown:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 8, 88)
UIDropDownMenu_SetWidth(rangedDropdown, 100)
rangedDropdown.label = rangedDropdown:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
rangedDropdown.label:SetPoint("TOPLEFT", rangedDropdown, "BOTTOMLEFT", -8, -2)
rangedDropdown.label:SetText("|cFFFFD700Ranged|r")

local function UpdateRangedDropdownText()
    UIDropDownMenu_SetText(rangedDropdown, WEAPON_MODE_LABELS[CurrentRangedMode()] or "Ranged: Auto")
end

UIDropDownMenu_Initialize(rangedDropdown, function(self, level)
    for _, mode in ipairs(RANGED_MODE_ORDER) do
        local info = UIDropDownMenu_CreateInfo()
        info.text = mode == "auto" and "Ranged: Auto" or WEAPON_MODE_LABELS[mode]
        info.value = mode
        info.func = function()
            addon:SetSelectedRangedMode(mode == "auto" and nil or mode)
            UpdateRangedDropdownText()
            RefreshCurrentOptimization()
        end
        info.checked = (CurrentRangedMode() == mode)
        UIDropDownMenu_AddButton(info)
    end
end)

-- ============================================================================
-- WEAPON SETUP PANEL (inline -- replaces the 3D model when active, like the
-- Stat Weights editor). Exact Main Hand / Off Hand weapon-subtype selectors:
-- every combination (1H Sword + Shield, 1H Mace + Shield, Dual 1H Maces,
-- Staff + Shield, Titan's Grip 2H/2H, dual Staves, etc.) is reachable by
-- combining the two dropdowns. The optimizer equips the highest-scoring
-- item of each exact subtype chosen -- see Optimizer.lua:
-- EnforceWeaponSubtypeMode. This is independent from -- and takes priority
-- over -- the quick Main Hand / Off Hand dropdown above.
-- ============================================================================
local WEAPON_SUBTYPE_LABELS = {
    ["One-Handed Swords"] = "1H Sword",
    ["Two-Handed Swords"] = "2H Sword",
    ["One-Handed Axes"]   = "1H Axe",
    ["Two-Handed Axes"]   = "2H Axe",
    ["One-Handed Maces"]  = "1H Mace",
    ["Two-Handed Maces"]  = "2H Mace",
    ["Daggers"]           = "Dagger",
    ["Fist Weapons"]      = "Fist Weapon",
    ["Polearms"]          = "Polearm",
    ["Staves"]            = "Staff",
    EMPTY                  = "Empty",
    SHIELD                 = "Shield",
    HOLDABLE               = "Held In Off-hand",
}

local weaponSetup = CreateFrame("Frame", "CGOWeaponSetup", UIParent)
weaponSetup:Hide()
weaponSetup:EnableMouse(true)

local wsTitle = weaponSetup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
wsTitle:SetPoint("TOP", weaponSetup, "TOP", 0, -4)
wsTitle:SetText("|cFFFFD700Weapon Setup|r")

local wsDesc = weaponSetup:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
wsDesc:SetPoint("TOP", wsTitle, "BOTTOM", 0, -6)
wsDesc:SetWidth(190)
wsDesc:SetJustifyH("CENTER")
wsDesc:SetText("Pick an exact subtype per hand. Your best item of that type gets equipped.")

-- Main Hand dropdown
local wsMHDropdown = CreateFrame("Frame", "CGOWeaponSetupMH", weaponSetup, "UIDropDownMenuTemplate")
wsMHDropdown:SetPoint("TOP", wsDesc, "BOTTOM", -8, -34)
UIDropDownMenu_SetWidth(wsMHDropdown, 170)
wsMHDropdown.label = wsMHDropdown:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
wsMHDropdown.label:SetPoint("BOTTOMLEFT", wsMHDropdown, "TOPLEFT", 14, 0)
wsMHDropdown.label:SetText("|cFFFFD700Main Hand|r")

-- Off Hand dropdown
local wsOHDropdown = CreateFrame("Frame", "CGOWeaponSetupOH", weaponSetup, "UIDropDownMenuTemplate")
wsOHDropdown:SetPoint("TOP", wsMHDropdown, "BOTTOM", 0, -30)
UIDropDownMenu_SetWidth(wsOHDropdown, 170)
wsOHDropdown.label = wsOHDropdown:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
wsOHDropdown.label:SetPoint("BOTTOMLEFT", wsOHDropdown, "TOPLEFT", 14, 0)
wsOHDropdown.label:SetText("|cFFFFD700Off Hand|r")

local wsClearBtn = CreateFrame("Button", nil, weaponSetup, "UIPanelButtonTemplate")
wsClearBtn:SetSize(120, 20)
wsClearBtn:SetPoint("TOP", wsOHDropdown, "BOTTOM", 0, -26)
wsClearBtn:SetText("Clear (Auto)")

local function WeaponSetupClass()
    return select(2, UnitClass("player"))
end

local function UpdateWeaponSetupText()
    local sel = CharacterGearOptimizerDB and CharacterGearOptimizerDB.weaponSubtype
    UIDropDownMenu_SetText(wsMHDropdown, (sel and sel.mh and (WEAPON_SUBTYPE_LABELS[sel.mh] or sel.mh)) or "Auto")
    UIDropDownMenu_SetText(wsOHDropdown, (sel and sel.oh and (WEAPON_SUBTYPE_LABELS[sel.oh] or sel.oh)) or "Auto")
end

UIDropDownMenu_Initialize(wsMHDropdown, function(self, level)
    local class = WeaponSetupClass()
    local sel = CharacterGearOptimizerDB and CharacterGearOptimizerDB.weaponSubtype

    local info = UIDropDownMenu_CreateInfo()
    info.text = "Auto"
    info.func = function()
        addon:SetWeaponSubtypeMH(nil)
        UpdateWeaponSetupText()
        UpdateWeaponDropdownText()
        RefreshCurrentOptimization()
    end
    info.checked = not (sel and sel.mh)
    UIDropDownMenu_AddButton(info)

    for _, subtype in ipairs(addon:GetClassMeleeWeaponSubtypes(class)) do
        local row = UIDropDownMenu_CreateInfo()
        row.text = WEAPON_SUBTYPE_LABELS[subtype] or subtype
        row.func = function()
            addon:SetWeaponSubtypeMH(subtype)
            UpdateWeaponSetupText()
            UpdateWeaponDropdownText()
            RefreshCurrentOptimization()
        end
        row.checked = (sel and sel.mh == subtype)
        UIDropDownMenu_AddButton(row)
    end
end)

UIDropDownMenu_Initialize(wsOHDropdown, function(self, level)
    local class = WeaponSetupClass()
    local sel = CharacterGearOptimizerDB and CharacterGearOptimizerDB.weaponSubtype

    local info = UIDropDownMenu_CreateInfo()
    info.text = "Auto"
    info.func = function()
        addon:SetWeaponSubtypeOH(nil)
        UpdateWeaponSetupText()
        UpdateWeaponDropdownText()
        RefreshCurrentOptimization()
    end
    info.checked = not (sel and sel.oh)
    UIDropDownMenu_AddButton(info)

    for _, choice in ipairs(addon:GetClassOffHandOptions(class)) do
        local row = UIDropDownMenu_CreateInfo()
        row.text = WEAPON_SUBTYPE_LABELS[choice] or choice
        row.func = function()
            addon:SetWeaponSubtypeOH(choice)
            UpdateWeaponSetupText()
            UpdateWeaponDropdownText()
            RefreshCurrentOptimization()
        end
        row.checked = (sel and sel.oh == choice)
        UIDropDownMenu_AddButton(row)
    end
end)

wsClearBtn:SetScript("OnClick", function()
    addon:ClearWeaponSubtypeMode()
    UpdateWeaponSetupText()
    UpdateWeaponDropdownText()
    RefreshCurrentOptimization()
end)

-- Inline the weapon setup panel over the model area (shares the space with
-- the stat editor and the default 3D model view -- only one is shown at a time).
weaponSetup:SetParent(frame)
weaponSetup:ClearAllPoints()
weaponSetup:SetPoint("TOP", frame, "TOP", 0, -42)
weaponSetup:SetSize(200, 290)
weaponSetup:SetFrameLevel(model:GetFrameLevel() + 5)
weaponSetup:SetScript("OnShow", function()
    UpdateWeaponSetupText()
end)
weaponSetup:SetScript("OnHide", function()
    if not statEditor:IsShown() then
        model:Show()
        for _, sid in ipairs({16, 17, 18}) do
            if addon.equipSlots and addon.equipSlots[sid] then
                addon.equipSlots[sid].borderFrame:Show()
            end
        end
    end
end)

-- ============================================================================
-- SPEC DROPDOWN
-- ============================================================================
local specDropdown = CreateFrame("Frame", "CGOSpecDropdown", frame, "UIDropDownMenuTemplate")
specDropdown:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 8, 56)
UIDropDownMenu_SetWidth(specDropdown, 145)
UIDropDownMenu_SetText(specDropdown, "Select Stats")

-- WAR-theme the dropdown button / left / middle / right textures
do
    local dd = specDropdown
    local left   = _G[dd:GetName().."Left"]
    local middle = _G[dd:GetName().."Middle"]
    local right  = _G[dd:GetName().."Right"]
    if left   then left:Hide()   end
    if middle then middle:Hide() end
    if right  then right:Hide()  end

    -- Add a WAR-themed backdrop behind the dropdown text area
    local ddBG = CreateFrame("Frame", nil, dd, BACKDROP_TEMPLATE)
    ddBG:SetPoint("TOPLEFT", dd, "TOPLEFT", 16, -2)
    ddBG:SetPoint("BOTTOMRIGHT", dd, "BOTTOMRIGHT", -16, 5)
    ddBG:SetFrameLevel(dd:GetFrameLevel())
    ApplyBackdrop(ddBG, {
        bgFile   = "Interface/DialogFrame/UI-DialogBox-Background",
        edgeFile = "Interface/DialogFrame/UI-DialogBox-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    }, { 0.05, 0.02, 0.02, 0.9 }, { 0.55, 0.45, 0.25, 1 })
end

local function OnSpecSelected(self)
    local selType = self.value  -- "spec_N" or "custom_Name"
    if not selType then return end

    local class = select(2, UnitClass("player"))

    if selType:sub(1, 5) == "spec_" then
        local specIndex = tonumber(selType:sub(6))
        addon.currentClass = class
        addon.currentSpecIdx = specIndex
        addon.currentCustomProfile = nil

        local bestSet, specData = addon:GetBestGearForSpec(class, specIndex)
        if bestSet then
            addon.currentBestSet = bestSet
            addon:PopulateSlots(bestSet)
        end
        UIDropDownMenu_SetText(specDropdown, specData and specData.name or ("Spec " .. specIndex))

        -- Persist selection
        if CharacterGearOptimizerDB then CharacterGearOptimizerDB.lastSelection = "spec_" .. specIndex end

    elseif selType:sub(1, 7) == "custom_" then
        local profileName = selType:sub(8)
        local weights = CharacterGearOptimizerDB.customStats and CharacterGearOptimizerDB.customStats[profileName]
        if not weights then return end

        -- Build a temporary specData from the custom profile
        local specData = { name = profileName, role = "melee_dps", weights = weights }
        -- Use spec index 0 as sentinel for custom
        addon.currentClass = class
        addon.currentSpecIdx = 0
        addon.currentCustomProfile = specData

        -- Run optimization using shared helper
        local bestSet = OptimizeForCustomProfile(specData)
        addon.currentBestSet = bestSet
        addon:PopulateSlots(bestSet)
        UIDropDownMenu_SetText(specDropdown, "|cFF00FF00" .. profileName .. "|r")

        -- Persist selection
        if CharacterGearOptimizerDB then CharacterGearOptimizerDB.lastSelection = "custom_" .. profileName end
    end
end

UIDropDownMenu_Initialize(specDropdown, function(self, level, menuList)
    local info = UIDropDownMenu_CreateInfo()
    local class = select(2, UnitClass("player"))

    -- Built-in class specs
    local specs = addon.CLASS_SPECS and addon.CLASS_SPECS[class]
    if specs then
        for i, spec in ipairs(specs) do
            info.text = spec.name or ("Spec " .. i)
            info.value = "spec_" .. i
            info.func = OnSpecSelected
            info.checked = (addon.currentSpecIdx == i and not addon.currentCustomProfile)
            UIDropDownMenu_AddButton(info)
        end
    end

    -- Separator
    local customProfiles = CharacterGearOptimizerDB and CharacterGearOptimizerDB.customStats
    if customProfiles and next(customProfiles) then
        info = UIDropDownMenu_CreateInfo()
        info.text = " "
        info.isTitle = true
        info.notCheckable = true
        UIDropDownMenu_AddButton(info)

        info = UIDropDownMenu_CreateInfo()
        info.text = "|cFFFFD700â€” Custom Stats â€”|r"
        info.isTitle = true
        info.notCheckable = true
        UIDropDownMenu_AddButton(info)

        for profileName, _ in pairs(customProfiles) do
            info = UIDropDownMenu_CreateInfo()
            info.text = "|cFF00FF00" .. profileName .. "|r"
            info.value = "custom_" .. profileName
            info.func = OnSpecSelected
            info.checked = (addon.currentCustomProfile and addon.currentCustomProfile.name == profileName)
            UIDropDownMenu_AddButton(info)
        end
    end
end)

-- ============================================================================
-- POPULATE SLOTS
-- ============================================================================
function addon:PopulateSlots(bestSet)
    -- Save displayed gear to DB for session persistence
    local saved = {}
    for slot, item in pairs(bestSet) do
        if item and item.link then
            saved[slot] = { link = item.link, score = item.score or 0 }
        end
    end
    if CharacterGearOptimizerDB then
        CharacterGearOptimizerDB.lastGear = saved
    end

    for slot, btn in pairs(self.equipSlots) do
        local item = bestSet[slot]
        if item then
            local _, _, _, _, _, _, _, _, _, texture = GetItemInfo(item.link)
            SetItemButtonTexture(btn, texture)
            btn.itemLink = item.link
        else
            SetItemButtonTexture(btn, nil)
            btn.itemLink = nil
        end
    end
end

local function BuildSetFromVisibleSlots()
    if not addon.equipSlots then return nil end

    local built = {}
    local current = addon.currentBestSet or {}

    for slot, btn in pairs(addon.equipSlots) do
        if btn.itemLink then
            local score = 0
            if current[slot] and current[slot].link == btn.itemLink then
                score = current[slot].score or 0
            end
            built[slot] = { link = btn.itemLink, score = score }
        end
    end

    return next(built) and built or nil
end

-- ============================================================================
-- SHOW CURRENTLY EQUIPPED GEAR  (default view when opening the panel)
-- ============================================================================
function addon:ShowEquippedGear()
    local shownSet = {}
    for slot, btn in pairs(self.equipSlots) do
        local link = GetInventoryItemLink("player", slot)
        local tex  = GetInventoryItemTexture("player", slot)
        if link then
            SetItemButtonTexture(btn, tex)
            btn.itemLink = link
            local score = 0
            if self.currentBestSet and self.currentBestSet[slot] and self.currentBestSet[slot].link == link then
                score = self.currentBestSet[slot].score or 0
            end
            shownSet[slot] = { link = link, score = score }
        else
            SetItemButtonTexture(btn, nil)
            btn.itemLink = nil
        end
    end
    self.currentBestSet = next(shownSet) and shownSet or nil
end

-- Always show currently equipped gear when the frame opens.
-- Optimized gear replaces this only when the user clicks Re-Scan or changes spec.
frame:HookScript("OnShow", function()
    addon:ShowEquippedGear()
end)

-- Update individual slot icons as gear changes (e.g. after EquipSet or manual swap).
frame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
frame:HookScript("OnEvent", function(self, event, slotID)
    if event ~= "PLAYER_EQUIPMENT_CHANGED" then return end
    if not self:IsShown() then return end
    local btn = addon.equipSlots and addon.equipSlots[slotID]
    if not btn then return end
    local link = GetInventoryItemLink("player", slotID)
    local tex  = GetInventoryItemTexture("player", slotID)
    if link then
        SetItemButtonTexture(btn, tex)
        btn.itemLink = link
        addon.currentBestSet = addon.currentBestSet or {}
        local score = 0
        if addon.currentBestSet[slotID] and addon.currentBestSet[slotID].link == link then
            score = addon.currentBestSet[slotID].score or 0
        end
        addon.currentBestSet[slotID] = { link = link, score = score }
    else
        SetItemButtonTexture(btn, nil)
        btn.itemLink = nil
        if addon.currentBestSet then
            addon.currentBestSet[slotID] = nil
            if not next(addon.currentBestSet) then
                addon.currentBestSet = nil
            end
        end
    end
end)

-- ============================================================================
-- BOTTOM BUTTONS
-- ============================================================================

-- [Stat Weights] button
local statsBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
statsBtn:SetSize(68, 22)
statsBtn:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -8, 8)
statsBtn:SetText("Weights")
statsBtn:SetScript("OnClick", function()
    if statEditor:IsShown() then
        statEditor:Hide()
    else
        weaponSetup:Hide()
        PopulateStatEditor()
        model:Hide()
        -- Hide weapon slots so they don't overlap the stat editor
        for _, sid in ipairs({16, 17, 18}) do
            if addon.equipSlots and addon.equipSlots[sid] then
                addon.equipSlots[sid].borderFrame:Hide()
            end
        end
        statEditor:Show()
    end
end)

-- [Weapon Setup] button -- opens the exact Main Hand / Off Hand
-- subtype picker in the same character/model area used by Stat Weights.
local weaponSetupBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
weaponSetupBtn:SetSize(90, 22)
weaponSetupBtn:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 10, 34)
weaponSetupBtn:SetText("Weapon Setup")
weaponSetupBtn:SetScript("OnClick", function()
    if weaponSetup:IsShown() then
        weaponSetup:Hide()
    else
        statEditor:Hide()
        model:Hide()
        -- Hide weapon slots so they don't overlap the weapon setup panel
        for _, sid in ipairs({16, 17, 18}) do
            if addon.equipSlots and addon.equipSlots[sid] then
                addon.equipSlots[sid].borderFrame:Hide()
            end
        end
        weaponSetup:Show()
    end
end)

-- [Re-Scan] button
local reloadBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
reloadBtn:SetSize(72, 22)
reloadBtn:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 8, 8)
reloadBtn:SetText("Re-Scan")
reloadBtn:SetScript("OnClick", function()
    RefreshCurrentOptimization()
end)

-- [Simulate] button -- opens Multi-Set Simulation & Upgrade Prediction panel
local simBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
simBtn:SetSize(72, 22)
simBtn:SetPoint("LEFT", reloadBtn, "RIGHT", 5, 0)
simBtn:SetText("Simulate")
simBtn:SetScript("OnClick", function()
    if addon.OpenSimulationPanel then
        addon:OpenSimulationPanel()
    end
end)

-- [Update Set] button — dropdown to overwrite an existing saved set
local updateSetBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
updateSetBtn:SetSize(86, 22)
updateSetBtn:SetPoint("BOTTOM", frame, "BOTTOM", 0, 32)
updateSetBtn:SetText("Update Set")

local updateSetMenu = CreateFrame("Frame", "CGOUpdateSetMenu", UIParent, "UIDropDownMenuTemplate")
UIDropDownMenu_Initialize(updateSetMenu, function(self, level)
    local sets = CharacterGearOptimizerDB and CharacterGearOptimizerDB.sets or {}
    local hasAny = false
    for setName, setData in pairs(sets) do
        hasAny = true
        local info = UIDropDownMenu_CreateInfo()
        info.text = setName
        info.icon = setData.icon
        info.notCheckable = true
        info.func = function()
            local bestSet = BuildSetFromVisibleSlots() or addon.currentBestSet
            if not bestSet then return end
            addon:SaveSet(setName, bestSet, nil)
        end
        UIDropDownMenu_AddButton(info, level)
    end
    if not hasAny then
        local info = UIDropDownMenu_CreateInfo()
        info.text = "No saved sets"
        info.disabled = true
        info.notCheckable = true
        UIDropDownMenu_AddButton(info, level)
    end
end, "MENU")

updateSetBtn:SetScript("OnClick", function(self)
    ToggleDropDownMenu(1, nil, updateSetMenu, self, 0, 0)
end)

-- [Save Set] button (prompts for name)
local equipBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
equipBtn:SetSize(76, 22)
equipBtn:SetPoint("LEFT", simBtn, "RIGHT", 5, 0)
equipBtn:SetText("Save Set")
equipBtn:SetScript("OnClick", function()
    if not addon.currentClass or not addon.currentSpecIdx then
        print("|cFFFFD700CharacterGearOptimizer:|r Select a Spec first.")
        return
    end

    local specData = addon.CLASS_SPECS[addon.currentClass][addon.currentSpecIdx]
    local defaultName = specData and specData.name or "My Set"

    nameInput:SetText(defaultName)
    nameDialog:Show()
    nameInput:SetFocus()
    nameInput:HighlightText()
end)

-- [Equip Set] button â€“ equips the currently displayed gear
local equipGearBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
equipGearBtn:SetSize(86, 22)
equipGearBtn:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -10, 34)
equipGearBtn:SetText("Equip Set")
equipGearBtn:SetScript("OnClick", function()
    if InCombatLockdown() then
        print("|cFFFFD700CharacterGearOptimizer:|r Cannot equip gear in combat.")
        return
    end
    local bestSet = BuildSetFromVisibleSlots() or addon.currentBestSet
    if not bestSet then
        print("|cFFFFD700CharacterGearOptimizer:|r No gear set to equip.")
        return
    end
    -- Build a temporary set table matching EquipSet format and equip directly
    local tempName = "_cgo_temp_equip"
    CharacterGearOptimizerDB.sets = CharacterGearOptimizerDB.sets or {}
    local items = {}
    for slot, data in pairs(bestSet) do
        if data and data.link then
            items[slot] = { link = data.link, score = data.score or 0 }
        end
    end
    CharacterGearOptimizerDB.sets[tempName] = { icon = "", items = items }
    addon:EquipSet(tempName)
    CharacterGearOptimizerDB.sets[tempName] = nil
end)

-- Hook Save dialog OK to actually perform the save
local function NameDialog_SaveSetHandler()
    local setName = nameInput:GetText()
    if not setName or setName == "" then return end
    nameDialog:Hide()

    local bestSet = BuildSetFromVisibleSlots() or addon.currentBestSet
    if not bestSet then
        -- Build from current slot contents
        bestSet = {}
        for slot, btn in pairs(addon.equipSlots) do
            if btn.itemLink then
                bestSet[slot] = { link = btn.itemLink, score = 0 }
            end
        end
    end

    local class = addon.currentClass or select(2, UnitClass("player"))
    local baseIcon = nil  -- let SaveSet resolve from helmet

    addon:SaveSet(setName, bestSet, baseIcon)
end

nameOK:SetScript("OnClick", NameDialog_SaveSetHandler)

-- Utility: restore the name dialog Save button to its default Save-Set behaviour
function addon:RestoreNameDialogSaveHook()
    nameOK:SetScript("OnClick", NameDialog_SaveSetHandler)
end

-- Expose to global
_G.CharacterGearOptimizerFrame = frame

-- ============================================================================
-- SESSION RESTORE (called from Core.lua after PLAYER_LOGIN)
-- ============================================================================
function addon:RestoreSession()
    if not CharacterGearOptimizerDB then return end

    -- Restore weapon mode dropdown texts
    UpdateWeaponDropdownText()
    UpdateRangedDropdownText()
    UpdateWeaponSetupText()

    -- Restore cap priority checkbox states
    local caps = CharacterGearOptimizerDB.capPriorities or {}
    local cbCrit     = _G["CGOCap_CritImmune"]
    local cbUncrush  = _G["CGOCap_Uncrushable"]
    local cbHit      = _G["CGOCap_HitCapped"]
    local cbSpellHit = _G["CGOCap_SpellHitCapped"]
    local cbExp      = _G["CGOCap_ExpCapped"]
    local cbArmor    = _G["CGOCap_ArmorCapped"]
    local cbResil    = _G["CGOCap_ResilCapped"]
    local cbHaste    = _G["CGOCap_HasteCapped"]
    if cbCrit     then cbCrit:SetChecked(caps.critImmune or false) end
    if cbUncrush  then cbUncrush:SetChecked(caps.uncrushable or false) end
    if cbHit      then cbHit:SetChecked(caps.hitCapped or false) end
    if cbSpellHit then cbSpellHit:SetChecked(caps.spellHitCapped or false) end
    if cbExp      then cbExp:SetChecked(caps.expertiseCapped or false) end
    if cbArmor    then cbArmor:SetChecked(caps.armorCapped or false) end
    if cbResil    then cbResil:SetChecked(caps.resilCapped or false) end
    if cbHaste    then cbHaste:SetChecked(caps.hasteCapped or false) end
    local cbPvpPower = _G["CGOCap_PvpPower"]
    if cbPvpPower then cbPvpPower:SetChecked(caps.pvpPower or false) end
    local cbPvePower = _G["CGOCap_PvePower"]
    if cbPvePower then cbPvePower:SetChecked(caps.pvePower or false) end
    local cbPvp = _G["CGOCap_PvpMode"]
    if cbPvp then cbPvp:SetChecked(caps.pvpMode or false) end
    local cbNot60 = _G["CGOCap_Not60"]
    if cbNot60 then cbNot60:SetChecked(caps.not60 or false) end
    local cbAutoRoll = _G["CGOCap_AutoRoll"]
    if cbAutoRoll then
        local enabled = true
        if CharacterGearOptimizerDB.autoRoll == false then enabled = false end
        cbAutoRoll:SetChecked(enabled)
    end

    local sel = CharacterGearOptimizerDB.lastSelection
    local gear = CharacterGearOptimizerDB.lastGear

    -- Restore selection state
    if sel then
        local class = select(2, UnitClass("player"))

        if sel:sub(1, 5) == "spec_" then
            local idx = tonumber(sel:sub(6))
            if idx and addon.CLASS_SPECS and addon.CLASS_SPECS[class] and addon.CLASS_SPECS[class][idx] then
                addon.currentClass = class
                addon.currentSpecIdx = idx
                addon.currentCustomProfile = nil
                local specData = addon.CLASS_SPECS[class][idx]
                UIDropDownMenu_SetText(specDropdown, specData.name or ("Spec " .. idx))
            end
        elseif sel:sub(1, 7) == "custom_" then
            local profileName = sel:sub(8)
            local weights = CharacterGearOptimizerDB.customStats and CharacterGearOptimizerDB.customStats[profileName]
            if weights then
                addon.currentClass = class
                addon.currentSpecIdx = 0
                addon.currentCustomProfile = { name = profileName, role = "melee_dps", weights = weights }
                UIDropDownMenu_SetText(specDropdown, "|cFF00FF00" .. profileName .. "|r")
            end
        end
    end

    -- Restore displayed gear
    if gear and addon.equipSlots then
        addon.currentBestSet = nil
        for slot, btn in pairs(addon.equipSlots) do
            local item = gear[slot]
            if item and item.link then
                local _, _, _, _, _, _, _, _, _, texture = GetItemInfo(item.link)
                if texture then
                    SetItemButtonTexture(btn, texture)
                    btn.itemLink = item.link
                else
                    -- Item info might not be cached yet; retry after a short delay
                    local link = item.link
                    C_Timer.After(1, function()
                        local _, _, _, _, _, _, _, _, _, tex = GetItemInfo(link)
                        SetItemButtonTexture(btn, tex)
                        btn.itemLink = link
                    end)
                end
            end
        end
    end
end
