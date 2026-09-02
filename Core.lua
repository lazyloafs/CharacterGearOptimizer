local addonName, addon = ...
local addon = addon or _G.CharacterGearOptimizer or {}
_G.CharacterGearOptimizer = addon
_G.CGO = addon

addon.db = {}

-- ============================================================================
-- RUNTIME FLAVOR DETECTION
-- ============================================================================
local _, _, _, tocVersion = GetBuildInfo()
addon.tocVersion = tocVersion or 0
addon.projectID = WOW_PROJECT_ID

addon.isMainline = (WOW_PROJECT_ID == WOW_PROJECT_MAINLINE) or (tocVersion and tocVersion >= 100000)
addon.isVanilla = (WOW_PROJECT_ID == WOW_PROJECT_CLASSIC) or (tocVersion and tocVersion < 20000)
addon.isTBC = (WOW_PROJECT_ID == (WOW_PROJECT_BURNING_CRUSADE_CLASSIC or 5)) or (tocVersion and tocVersion >= 20000 and tocVersion < 30000)
addon.isWrath = (WOW_PROJECT_ID == (WOW_PROJECT_WRATH_CLASSIC or 11)) or (tocVersion and tocVersion >= 30000 and tocVersion < 40000)
addon.isCata = (WOW_PROJECT_ID == (WOW_PROJECT_CATACLYSM_CLASSIC or 14)) or (tocVersion and tocVersion >= 40000 and tocVersion < 50000)
addon.isClassic = not addon.isMainline

-- ============================================================================
-- C_Timer shim for legacy clients without native C_Timer
-- ============================================================================
if not C_Timer then
    local timerFrame = CreateFrame("Frame")
    local timers = {}
    timerFrame:SetScript("OnUpdate", function(self, elapsed)
        for i = #timers, 1, -1 do
            local t = timers[i]
            t.remaining = t.remaining - elapsed
            if t.remaining <= 0 then
                table.remove(timers, i)
                local ok, err = pcall(t.callback)
                if not ok then
                    print("|cFFFFD700CGO:|r timer error: " .. tostring(err))
                end
            end
        end
        if #timers == 0 then self:Hide() end
    end)
    timerFrame:Hide()

    C_Timer = {}
    function C_Timer.After(delay, callback)
        table.insert(timers, { remaining = delay or 0, callback = callback })
        timerFrame:Show()
    end
end

local function DeepMergeMissing(target, source)
    if type(target) ~= "table" or type(source) ~= "table" then return target end

    for key, value in pairs(source) do
        if target[key] == nil then
            if type(value) == "table" then
                target[key] = {}
                DeepMergeMissing(target[key], value)
            else
                target[key] = value
            end
        elseif type(target[key]) == "table" and type(value) == "table" then
            DeepMergeMissing(target[key], value)
        end
    end

    return target
end

local function EnsureTableField(tbl, key)
    if type(tbl[key]) ~= "table" then
        tbl[key] = {}
    end
    return tbl[key]
end

function addon:InitializeDatabase()
    local db = type(CharacterGearOptimizerDB) == "table" and CharacterGearOptimizerDB or {}
    local legacy = type(LazyOptimizerDB) == "table" and LazyOptimizerDB or nil

    if legacy then
        DeepMergeMissing(db, legacy)
    end

    EnsureTableField(db, "profiles")
    EnsureTableField(db, "sets")
    EnsureTableField(db, "customStats")
    EnsureTableField(db, "capPriorities")
    EnsureTableField(db, "specHUD")
    EnsureTableField(db, "minimap")
    EnsureTableField(db, "hudStats")

    if db.minimap.hide == nil then
        db.minimap.hide = false
    end
    if db.autoRoll == nil then
        db.autoRoll = true
    end
    if db.enableTooltips == nil then
        db.enableTooltips = true
    end
    if db.includeBank == nil then
        db.includeBank = true
    end
    if db.enableSellomatic == nil then
        db.enableSellomatic = true
    end

    CharacterGearOptimizerDB = db
    LazyOptimizerDB = nil
    addon.db = db

    return db
end

-- ============================================================================
-- SPEC AUTO-DETECTION
-- ============================================================================
function addon:DetectSpec()
    local _, playerClass = UnitClass("player")
    if not playerClass then return end

    local classSpecs = addon.CLASS_SPECS and addon.CLASS_SPECS[playerClass]
    if not classSpecs then return end

    -- Check for saved spec override
    local db = CharacterGearOptimizerDB or {}
    if db.specOverride and classSpecs[db.specOverride] then
        addon.autoDetectedSpec = classSpecs[db.specOverride]
        addon.autoDetectedSpecIdx = db.specOverride
        return
    end

    -- Modern Retail / Mainline Specialization
    if addon.isMainline and GetSpecialization then
        local specIdx = GetSpecialization()
        if specIdx and specIdx > 0 and classSpecs[specIdx] then
            addon.autoDetectedSpec = classSpecs[specIdx]
            addon.autoDetectedSpecIdx = specIdx
            return
        end
    end

    -- Ascension Wildcard Primary Stat Check
    if playerClass == "HERO" and C_PrimaryStat and C_PrimaryStat.GetActivePrimaryStat then
        local ok, primaryID = pcall(C_PrimaryStat.GetActivePrimaryStat, C_PrimaryStat)
        if not ok then ok, primaryID = pcall(C_PrimaryStat.GetActivePrimaryStat) end
        local heroSpec = ok and ({ [1] = 1, [2] = 2, [6] = 3 })[primaryID]
        if heroSpec and classSpecs[heroSpec] then
            addon.autoDetectedSpec = classSpecs[heroSpec]
            addon.autoDetectedSpecIdx = heroSpec
            return
        end
    end

    -- Classic / WotLK / TBC Talent Tree Scanning
    local maxTab, maxPoints = 1, 0
    local numTabs = GetNumTalentTabs and GetNumTalentTabs() or 3

    for tab = 1, numTabs do
        local tabPoints = 0
        local numTalents = GetNumTalents and GetNumTalents(tab) or 0
        for t = 1, numTalents do
            local rank
            if GetTalentInfo then
                _, _, _, _, rank = GetTalentInfo(tab, t)
            end
            if rank and type(rank) == "number" then
                tabPoints = tabPoints + rank
            else
                tabPoints = tabPoints + (tonumber(rank) or 0)
            end
        end
        if tabPoints > maxPoints then
            maxTab = tab
            maxPoints = tabPoints
        end
    end

    addon.autoDetectedSpec = classSpecs[maxTab] or classSpecs[1]
    addon.autoDetectedSpecIdx = maxTab
end

-- ============================================================================
-- SET SPEC OVERRIDE
-- ============================================================================
function addon:SetSpecOverride(specIdx)
    local _, playerClass = UnitClass("player")
    local classSpecs = addon.CLASS_SPECS and addon.CLASS_SPECS[playerClass]
    if not classSpecs or not classSpecs[specIdx] then
        print("|cFFFFD700CGO:|r Invalid spec index: " .. tostring(specIdx))
        return
    end

    addon.autoDetectedSpec = classSpecs[specIdx]
    addon.autoDetectedSpecIdx = specIdx

    CharacterGearOptimizerDB = CharacterGearOptimizerDB or {}
    CharacterGearOptimizerDB.specOverride = specIdx

    local color = addon.CLASS_COLORS and addon.CLASS_COLORS[playerClass] or "FFFFFF"
    print(string.format("|cFFFFD700CGO:|r Spec set to |cff%s%s|r", color, classSpecs[specIdx].name))

    if addon.UpdateSpecHUD then addon:UpdateSpecHUD() end
end

-- ============================================================================
-- CLEAR SPEC OVERRIDE
-- ============================================================================
function addon:ClearSpecOverride()
    CharacterGearOptimizerDB = CharacterGearOptimizerDB or {}
    CharacterGearOptimizerDB.specOverride = nil
    addon:DetectSpec()

    local _, playerClass = UnitClass("player")
    local color = addon.CLASS_COLORS and addon.CLASS_COLORS[playerClass] or "FFFFFF"
    local name = addon.autoDetectedSpec and addon.autoDetectedSpec.name or "Unknown"
    print(string.format("|cFFFFD700CGO:|r Auto-detected spec: |cff%s%s|r", color, name))

    if addon.UpdateSpecHUD then addon:UpdateSpecHUD() end
end

-- ============================================================================
-- LIST SPECS
-- ============================================================================
function addon:ListSpecs()
    local _, playerClass = UnitClass("player")
    local classSpecs = addon.CLASS_SPECS and addon.CLASS_SPECS[playerClass]
    if not classSpecs then
        print("|cFFFFD700CGO:|r No specs found for your class.")
        return
    end

    local color = addon.CLASS_COLORS and addon.CLASS_COLORS[playerClass] or "FFFFFF"
    print("|cFFFFD700CGO:|r Available specs:")

    local indices = {}
    for idx, _ in pairs(classSpecs) do table.insert(indices, idx) end
    table.sort(indices)

    for _, idx in ipairs(indices) do
        local spec = classSpecs[idx]
        local marker = (idx == addon.autoDetectedSpecIdx) and " |cff00ff00<< active|r" or ""
        print(string.format("  |cff%s%d|r - %s (%s)%s", color, idx, spec.name, spec.role, marker))
    end
    print("  Use |cff69ccf0/cgo spec <number>|r to switch.")
end

-- ============================================================================
-- CHAT & SLASH COMMANDS
-- ============================================================================
function addon:DebugLog(message)
    CharacterGearOptimizerDB = CharacterGearOptimizerDB or {}
    CharacterGearOptimizerDB.debugLog = CharacterGearOptimizerDB.debugLog or {}
    table.insert(CharacterGearOptimizerDB.debugLog, date("%H:%M:%S") .. " " .. tostring(message))
    while #CharacterGearOptimizerDB.debugLog > 300 do table.remove(CharacterGearOptimizerDB.debugLog, 1) end
end

local function HandleSlashCommand(msg)
    local command, rest = msg:match("^(%S*)%s*(.-)$")
    command = command and command:lower() or ""

    if command == "debug" then
        local log = CharacterGearOptimizerDB and CharacterGearOptimizerDB.debugLog or {}
        print("|cFFFFD700CGO debug log (last 40):|r")
        for i = math.max(1, #log - 39), #log do print(log[i]) end
        return
    end

    if command == "config" or command == "options" or command == "opt" or command == "settings" then
        if addon.OpenOptions then
            addon:OpenOptions()
        else
            print("|cFFFFD700CGO:|r Options panel initializing...")
        end
        return
    end

    if command == "show" or command == "panel" or command == "ui" then
        if addon.ToggleMainPanel then
            addon:ToggleMainPanel()
        elseif CharacterGearOptimizerFrame then
            if CharacterGearOptimizerFrame:IsShown() then
                CharacterGearOptimizerFrame:Hide()
            else
                CharacterGearOptimizerFrame:Show()
            end
        end
        return
    end

    if command == "hud" then
        if addon.ToggleHUD then
            addon:ToggleHUD()
        elseif addon.specHUDFrame then
            if addon.specHUDFrame:IsShown() then
                addon.specHUDFrame:Hide()
                CharacterGearOptimizerDB = CharacterGearOptimizerDB or {}
                CharacterGearOptimizerDB.specHUDHidden = true
            else
                addon.specHUDFrame:Show()
                CharacterGearOptimizerDB = CharacterGearOptimizerDB or {}
                CharacterGearOptimizerDB.specHUDHidden = false
            end
        end
        return
    end

    if command == "hudreset" then
        if addon.specHUDFrame then
            addon.specHUDFrame:ClearAllPoints()
            addon.specHUDFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        end
        CharacterGearOptimizerDB = CharacterGearOptimizerDB or {}
        CharacterGearOptimizerDB.specHUD = nil
        print("|cFFFFD700CGO:|r HUD position reset.")
        return
    end

    if command == "spec" then
        local idx = tonumber(rest)
        if idx then
            addon:SetSpecOverride(idx)
        else
            addon:ListSpecs()
        end
        return
    end

    if command == "auto" then
        addon:ClearSpecOverride()
        return
    end

    if command == "cat" then
        local _, playerClass = UnitClass("player")
        if playerClass == "DRUID" then
            addon:SetSpecOverride(2)
        else
            print("|cFFFFD700CGO:|r Cat mode is for Druids only.")
        end
        return
    end

    if command == "bear" then
        local _, playerClass = UnitClass("player")
        if playerClass == "DRUID" then
            addon:SetSpecOverride(4)
        else
            print("|cFFFFD700CGO:|r Bear mode is for Druids only.")
        end
        return
    end

    if command == "import" then
        if addon.OpenImportDialog then
            addon:OpenImportDialog()
        elseif _G["CGOImportDialog"] then
            _G["CGOImportDialog"]:Show()
        else
            print("|cFFFFD700CGO:|r Import dialog not available. Open the gear panel first.")
        end
        return
    end

    if command == "export" or command == "pawn" then
        local format = (command == "pawn") and "pawn" or (rest ~= "" and rest:lower() or "pawn")
        local _, class = UnitClass("player")
        local specIdx = addon.currentSpecIdx or addon.autoDetectedSpecIdx or 1
        local specData = addon.CLASS_SPECS and addon.CLASS_SPECS[class] and addon.CLASS_SPECS[class][specIdx]
        local profileName = specData and specData.name or "Active Spec"
        local weights = specData and specData.weights or {}
        if addon.currentCustomProfile then
            profileName = addon.currentCustomProfile.name or profileName
            weights = addon.currentCustomProfile.weights or weights
        end

        if addon.OpenExportDialog then
            addon:OpenExportDialog(profileName, weights, format)
        elseif _G["CGOExportDialog"] and _G["CGOExportDialog"].Open then
            _G["CGOExportDialog"]:Open(profileName, weights, format)
        else
            -- Fallback: print to chat if UI dialog isn't loaded
            local exported = addon.ExportWeights and addon:ExportWeights(weights, format, profileName, class, specIdx)
            if exported then
                print("|cFFFFD700CGO Export (" .. format:upper() .. "):|r")
                print(exported)
            else
                print("|cFFFFD700CGO:|r Export dialog not available. Open the gear panel first.")
            end
        end
        return
    end

    if command == "best" then
        print("|cFFFFD700CGO:|r Scanning bags for optimized gear...")
        local _, class = UnitClass("player")
        local bestSet, specData = addon:GetBestGearForSpec(class, addon.autoDetectedSpecIdx or 1)
        if bestSet then
            print("Optimized for: " .. (specData and specData.name or "Active Spec"))
            for slot = 1, 18 do
                if bestSet[slot] then
                    print(string.format("Slot %d: %s (Score: %.1f)", slot, bestSet[slot].link or "?", bestSet[slot].score or 0))
                end
            end
        else
            print("Failed to optimize.")
        end
        return
    end

    if command == "autoroll" then
        local enabled = not (addon.IsAutoRollEnabled and addon:IsAutoRollEnabled())
        if rest == "on" then enabled = true end
        if rest == "off" then enabled = false end
        if addon.SetAutoRollEnabled then addon:SetAutoRollEnabled(enabled) end
        print("|cFFFFD700CGO:|r Auto Roll " .. (enabled and "|cff00ff00enabled|r" or "|cffff0000disabled|r") .. ".")
        return
    end

    if command == "sim" or command == "simulate" then
        if addon.OpenSimulationPanel then
            addon:OpenSimulationPanel()
        else
            print("|cFFFFD700CGO:|r Simulation module initializing...")
        end
        return
    end

    if command == "upgrade" or command == "upgrades" then
        if addon.Sim and addon.Sim.PredictAllUpgradesInBags then
            local upgrades = addon.Sim:PredictAllUpgradesInBags()
            if #upgrades == 0 then
                print("|cFFFFD700CGO:|r No item upgrades found in your bags.")
            else
                print(string.format("|cFFFFD700CGO:|r Found |cff00ff00%d|r upgrade(s) in your bags:", #upgrades))
                for i = 1, math.min(#upgrades, 5) do
                    local u = upgrades[i]
                    print(string.format("  #%d: %s for |cffffd700%s|r (+%.1f / |cff00ff00+%.1f%%|r)",
                        i, u.link or "?", u.slotName or tostring(u.slot), u.delta, u.pctGain))
                end
            end
        else
            print("|cFFFFD700CGO:|r Simulation module not loaded.")
        end
        return
    end

    if command == "weak" or command == "weakest" then
        if addon.Sim and addon.Sim.FindWeakestSlots then
            local slots = addon.Sim:FindWeakestSlots()
            if #slots == 0 then
                print("|cFFFFD700CGO:|r No equipped gear found.")
            else
                print("|cFFFFD700CGO:|r Weakest equipped slots (highest upgrade priority):")
                for i = 1, math.min(#slots, 5) do
                    local s = slots[i]
                    print(string.format("  #%d: |cffffd700%s|r - %s (Score: %.1f, Avg: %.1f, |cffff4444-%.1f%%|r)",
                        i, s.slotName, s.link or "Empty", s.score, s.avgScore, s.pctBelowAvg))
                end
            end
        else
            print("|cFFFFD700CGO:|r Simulation module not loaded.")
        end
        return
    end

    if command == "dev" then
        if _G.DevTool and _G.DevTool.AddData then
            _G.DevTool:AddData(addon, "CharacterGearOptimizer")
            print("|cFFFFD700CGO:|r Added addon table to DevTool under 'CharacterGearOptimizer'.")
        else
            print("|cFFFFD700CGO:|r DevTool is not loaded. To inspect, run: /dev CharacterGearOptimizer")
        end
        return
    end

    if command == "help" or command == "?" then
        print("|cFFFFD700CharacterGearOptimizer|r commands:")
        print("  |cff69ccf0/cgo|r or |cff69ccf0/cgo show|r - Toggle main gear panel")
        print("  |cff69ccf0/cgo config|r or |cff69ccf0/cgo opt|r - Open AddOn Settings menu")
        print("  |cff69ccf0/cgo sim|r - Open Multi-Set Simulation & Upgrade Prediction UI")
        print("  |cff69ccf0/cgo upgrade|r - Find top item upgrades in your bags")
        print("  |cff69ccf0/cgo weak|r - List weakest equipped gear slots")
        print("  |cff69ccf0/cgo hud|r - Toggle floating spec HUD")
        print("  |cff69ccf0/cgo hudreset|r - Reset HUD position to center")
        print("  |cff69ccf0/cgo spec|r - List available specs")
        print("  |cff69ccf0/cgo spec <#>|r - Switch to spec by number")
        print("  |cff69ccf0/cgo auto|r - Revert to auto-detect spec")
        print("  |cff69ccf0/cgo best|r - Scan bags for best gear")
        print("  |cff69ccf0/cgo import|r - Open stat weights import dialog")
        print("  |cff69ccf0/cgo export [pawn|simc|json]|r - Open stat weights export dialog")
        print("  |cff69ccf0/cgo pawn|r - Quick export weights in Pawn format")
        print("  |cff69ccf0/cgo autoroll|r - Toggle auto loot rolls")
        print("  |cff69ccf0/cgo dev|r - Register table in DevTool")
        local _, playerClass = UnitClass("player")
        if playerClass == "DRUID" then
            print("  |cff69ccf0/cgo cat|r / |cff69ccf0/cgo bear|r - Quick toggle Feral mode")
        end
        return
    end

    -- Default: toggle main panel
    if addon.ToggleMainPanel then
        addon:ToggleMainPanel()
    elseif CharacterGearOptimizerFrame then
        if CharacterGearOptimizerFrame:IsShown() then
            CharacterGearOptimizerFrame:Hide()
        else
            CharacterGearOptimizerFrame:Show()
        end
    end
end

SLASH_CHARACTERGEAROPTIMIZER1 = "/cgo"
SLASH_CHARACTERGEAROPTIMIZER2 = "/cgopt"
SLASH_CHARACTERGEAROPTIMIZER3 = "/chargear"
SLASH_CHARACTERGEAROPTIMIZER4 = "/charactergear"

SlashCmdList["CHARACTERGEAROPTIMIZER"] = HandleSlashCommand

-- ============================================================================
-- INITIALIZATION & EVENT DISPATCH
-- ============================================================================
local eventFrame = CreateFrame("Frame")

-- Hidden tooltip for scanning gear
addon.scanTooltip = CreateFrame("GameTooltip", "CGOScanTooltip", nil, "GameTooltipTemplate")
addon.scanTooltip:SetOwner(WorldFrame, "ANCHOR_NONE")

-- Talent hit tooltip scanner
addon.talentHitTooltip = CreateFrame("GameTooltip", "CGOTalentHitTooltip", nil, "GameTooltipTemplate")
addon.talentHitTooltip:SetOwner(WorldFrame, "ANCHOR_NONE")

function addon:InvalidateTalentHitCache()
    self.talentHitCache = nil
end

function addon:GetTalentHitBonuses()
    if self.talentHitCache then
        return self.talentHitCache.melee, self.talentHitCache.ranged, self.talentHitCache.spell
    end
    local melee, ranged, spell = 0, 0, 0
    local tooltip = self.talentHitTooltip
    local numTabs = GetNumTalentTabs and GetNumTalentTabs() or 0
    if numTabs == 0 then return 0, 0, 0 end
    for tab = 1, numTabs do
        local numTalents = GetNumTalents and GetNumTalents(tab) or 0
        for talent = 1, numTalents do
            local name, rank
            if GetTalentInfo then
                name, _, _, _, rank = GetTalentInfo(tab, talent)
            end
            if name and (rank or 0) > 0 then
                tooltip:ClearLines()
                if tooltip.SetTalent then
                    tooltip:SetTalent(tab, talent)
                    local description = ""
                    for line = 2, tooltip:NumLines() do
                        local region = _G["CGOTalentHitTooltipTextLeft" .. line]
                        local lineText = region and region:GetText()
                        if lineText then description = description .. " " .. string.lower(lineText) end
                    end
                    local universal = tonumber(description:match("increases? your hit chance by ([%d%.]+)%%"))
                        or tonumber(description:match("increases? your chance to hit by ([%d%.]+)%%"))
                    local spellOnly = tonumber(description:match("spell hit chance by ([%d%.]+)%%"))
                        or tonumber(description:match("chance to hit with spells by ([%d%.]+)%%"))
                    local meleeOnly = tonumber(description:match("melee hit chance by ([%d%.]+)%%"))
                        or tonumber(description:match("chance to hit with melee attacks by ([%d%.]+)%%"))
                    local rangedOnly = tonumber(description:match("ranged hit chance by ([%d%.]+)%%"))
                        or tonumber(description:match("chance to hit with ranged attacks by ([%d%.]+)%%"))
                    if name == "Balance of Power" and not universal then universal = 4 end
                    if universal then
                        melee, ranged, spell = melee + universal, ranged + universal, spell + universal
                    else
                        melee = melee + (meleeOnly or 0)
                        ranged = ranged + (rangedOnly or 0)
                        spell = spell + (spellOnly or 0)
                    end
                end
            end
        end
    end
    self.talentHitCache = { melee = melee, ranged = ranged, spell = spell }
    return melee, ranged, spell
end

function addon:GetTotalHitChance(crID)
    local ratingHit = GetCombatRatingBonus and (GetCombatRatingBonus(crID) or 0) or 0
    local melee, ranged, spell = self:GetTalentHitBonuses()
    local CR = addon.RATING or {}
    if crID == CR.CR_HIT_SPELL then return ratingHit + spell end
    if crID == CR.CR_HIT_RANGED then return ratingHit + ranged end
    return ratingHit + melee
end

eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_TALENT_UPDATE")
if addon.isMainline then
    pcall(eventFrame.RegisterEvent, eventFrame, "PLAYER_SPECIALIZATION_CHANGED")
    pcall(eventFrame.RegisterEvent, eventFrame, "TRAIT_CONFIG_UPDATED")
else
    pcall(eventFrame.RegisterEvent, eventFrame, "ACTIVE_TALENT_GROUP_CHANGED")
    pcall(eventFrame.RegisterEvent, eventFrame, "CHARACTER_POINTS_CHANGED")
end
eventFrame:RegisterEvent("BANKFRAME_OPENED")
eventFrame:RegisterEvent("BANKFRAME_CLOSED")

eventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == addonName then
        local db = addon:InitializeDatabase()
        
        if db.hudPoint and CharacterGearOptimizerHUD then
            local p = db.hudPoint
            CharacterGearOptimizerHUD:ClearAllPoints()
            CharacterGearOptimizerHUD:SetPoint(p[1], UIParent, p[2], p[3], p[4])
        end

        if addon.RefreshHUD then
            addon:RefreshHUD()
        end
        
        -- Auto register to DevTool if available
        if _G.DevTool and _G.DevTool.AddData then
            _G.DevTool:AddData(addon, "CharacterGearOptimizer")
        end
        
        print("|cFFFFD700CharacterGearOptimizer|r loaded! Type |cff69ccf0/cgo help|r or |cff69ccf0/cgo config|r.")
        self:UnregisterEvent("ADDON_LOADED")

    elseif event == "PLAYER_LOGIN" then
        addon:InvalidateTalentHitCache()
        addon:DetectSpec()

        if not addon.currentSpecIdx and addon.autoDetectedSpecIdx then
            local _, playerClass = UnitClass("player")
            addon.currentClass = playerClass
            addon.currentSpecIdx = addon.autoDetectedSpecIdx

            local dd = _G["CGOSpecDropdown"]
            if dd and addon.autoDetectedSpec and UIDropDownMenu_SetText then
                UIDropDownMenu_SetText(dd, addon.autoDetectedSpec.name)
            end
        end

        if addon.RestoreSession then
            addon:RestoreSession()
        end

        -- Register DevTool on login
        if _G.DevTool and _G.DevTool.AddData then
            _G.DevTool:AddData(addon, "CharacterGearOptimizer")
        end

        local _, playerClass = UnitClass("player")
        local color = addon.CLASS_COLORS and addon.CLASS_COLORS[playerClass] or "FFFFFF"
        local specName = addon.autoDetectedSpec and addon.autoDetectedSpec.name or "Unknown"
        print(string.format("|cFFFFD700CGO:|r Detected |cff%s%s|r. Type |cff69ccf0/cgo hud|r to show spec HUD.", color, specName))

        self:UnregisterEvent("PLAYER_LOGIN")

    elseif event == "PLAYER_TALENT_UPDATE" or event == "ACTIVE_TALENT_GROUP_CHANGED"
           or event == "CHARACTER_POINTS_CHANGED" or event == "PLAYER_SPECIALIZATION_CHANGED"
           or event == "TRAIT_CONFIG_UPDATED" then
        addon:InvalidateTalentHitCache()
        local db = CharacterGearOptimizerDB or {}
        if not db.specOverride then
            addon:DetectSpec()
            if addon.UpdateSpecHUD then addon:UpdateSpecHUD() end
        end

    elseif event == "BANKFRAME_OPENED" then
        addon.bankOpen = true
        if addon.RefreshHUD then addon:RefreshHUD() end

    elseif event == "BANKFRAME_CLOSED" then
        addon.bankOpen = false
        if addon.RefreshHUD then addon:RefreshHUD() end
    end
end)