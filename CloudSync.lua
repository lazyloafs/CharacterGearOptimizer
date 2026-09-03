-- ============================================================================
-- CharacterGearOptimizer: CloudSync.lua
-- Cloud Sync Profile Integration & Account-Wide Profile Store
-- Universal multi-version compatibility: Retail (The War Within / Midnight),
-- Classic Era, Season of Discovery, TBC Classic, Wrath Classic, and Cata Classic.
-- ============================================================================

local addonName, addon = ...
local addon = addon or _G.CharacterGearOptimizer or {}
_G.CharacterGearOptimizer = addon
_G.CGO = addon

addon.CloudSync = addon.CloudSync or {}
local CloudSync = addon.CloudSync

local BACKDROP_TEMPLATE = BackdropTemplateMixin and "BackdropTemplate" or nil

-- ============================================================================
-- BASE64 ENCODING & DECODING (Safe Pure Lua Implementation)
-- ============================================================================
local B64_CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local B64_LOOKUP = {}
for i = 1, #B64_CHARS do
    B64_LOOKUP[B64_CHARS:sub(i, i)] = i - 1
end

function CloudSync:Base64Encode(data)
    if not data or data == "" then return "" end
    local bytes = { string.byte(data, 1, -1) }
    local len = #bytes
    local out = {}
    local i = 1

    while i <= len do
        local b1 = bytes[i]
        local b2 = (i + 1 <= len) and bytes[i + 1] or 0
        local b3 = (i + 2 <= len) and bytes[i + 2] or 0

        local c1 = math.floor(b1 / 4)
        local c2 = (b1 % 4) * 16 + math.floor(b2 / 16)
        local c3 = (b2 % 16) * 4 + math.floor(b3 / 64)
        local c4 = b3 % 64

        table.insert(out, B64_CHARS:sub(c1 + 1, c1 + 1))
        table.insert(out, B64_CHARS:sub(c2 + 1, c2 + 1))

        if i + 1 <= len then
            table.insert(out, B64_CHARS:sub(c3 + 1, c3 + 1))
        else
            table.insert(out, "=")
        end

        if i + 2 <= len then
            table.insert(out, B64_CHARS:sub(c4 + 1, c4 + 1))
        else
            table.insert(out, "=")
        end

        i = i + 3
    end

    return table.concat(out)
end

function CloudSync:Base64Decode(data)
    if not data or data == "" then return "" end
    local clean = data:gsub("[^A-Za-z0-9%+/=]", "")
    local len = #clean
    if len % 4 ~= 0 then return nil, "Invalid base64 length" end

    local out = {}
    local i = 1

    while i <= len do
        local c1 = clean:sub(i, i)
        local c2 = clean:sub(i + 1, i + 1)
        local c3 = clean:sub(i + 2, i + 2)
        local c4 = clean:sub(i + 3, i + 3)

        local v1 = B64_LOOKUP[c1]
        local v2 = B64_LOOKUP[c2]
        local v3 = (c3 ~= "=") and B64_LOOKUP[c3] or 0
        local v4 = (c4 ~= "=") and B64_LOOKUP[c4] or 0

        if not v1 or not v2 then return nil, "Invalid base64 character" end

        local b1 = (v1 * 4) + math.floor(v2 / 16)
        local b2 = ((v2 % 16) * 16) + math.floor(v3 / 4)
        local b3 = ((v3 % 4) * 64) + v4

        table.insert(out, string.char(b1))
        if c3 ~= "=" then table.insert(out, string.char(b2)) end
        if c4 ~= "=" then table.insert(out, string.char(b3)) end

        i = i + 4
    end

    return table.concat(out)
end

-- ============================================================================
-- ADLER-32 CHECKSUM
-- ============================================================================
function CloudSync:CalculateChecksum(data)
    if not data then return "00000000" end
    local a = 1
    local b = 0
    local MOD_ADLER = 65521
    local len = #data

    for i = 1, len do
        local byte = string.byte(data, i)
        a = (a + byte) % MOD_ADLER
        b = (b + a) % MOD_ADLER
    end

    local sum = (b * 65536) + a
    return string.format("%08X", sum)
end

-- ============================================================================
-- COMPACT JSON-COMPATIBLE SERIALIZER & DESERIALIZER
-- ============================================================================
function CloudSync:Serialize(val)
    local valType = type(val)
    if valType == "number" then
        if val == math.floor(val) then
            return string.format("%d", val)
        else
            return string.format("%.4f", val):gsub("%.?0+$", "")
        end
    elseif valType == "string" then
        local escaped = val:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n'):gsub('\r', '')
        return string.format('"%s"', escaped)
    elseif valType == "boolean" then
        return val and "true" or "false"
    elseif valType == "table" then
        local isArray = true
        local count = 0
        for k, _ in pairs(val) do
            count = count + 1
            if type(k) ~= "number" or k < 1 or k > count then
                isArray = false
            end
        end
        if count == 0 then isArray = false end

        if isArray then
            local items = {}
            for i = 1, #val do
                table.insert(items, self:Serialize(val[i]))
            end
            return "[" .. table.concat(items, ",") .. "]"
        else
            local items = {}
            -- Sort keys alphabetically for deterministic serialization
            local keys = {}
            for k, _ in pairs(val) do table.insert(keys, tostring(k)) end
            table.sort(keys)

            for _, k in ipairs(keys) do
                local rawKey = tonumber(k) or k
                local v = val[rawKey]
                if v ~= nil then
                    table.insert(items, string.format('"%s":%s', tostring(k), self:Serialize(v)))
                end
            end
            return "{" .. table.concat(items, ",") .. "}"
        end
    else
        return "null"
    end
end

function CloudSync:Deserialize(jsonStr)
    if not jsonStr or type(jsonStr) ~= "string" or jsonStr == "" then
        return nil, "Empty string"
    end

    local pos = 1
    local len = #jsonStr

    local function skipWhitespace()
        while pos <= len do
            local c = jsonStr:sub(pos, pos)
            if c == ' ' or c == '\t' or c == '\n' or c == '\r' then
                pos = pos + 1
            else
                break
            end
        end
    end

    local parseValue

    local function parseString()
        if jsonStr:sub(pos, pos) ~= '"' then return nil end
        pos = pos + 1
        local start = pos
        local chunks = {}
        while pos <= len do
            local c = jsonStr:sub(pos, pos)
            if c == '\\' then
                table.insert(chunks, jsonStr:sub(start, pos - 1))
                pos = pos + 1
                local esc = jsonStr:sub(pos, pos)
                if esc == 'n' then table.insert(chunks, '\n')
                elseif esc == 'r' then -- ignore
                elseif esc == 't' then table.insert(chunks, '\t')
                elseif esc == '"' then table.insert(chunks, '"')
                elseif esc == '\\' then table.insert(chunks, '\\')
                else table.insert(chunks, esc) end
                pos = pos + 1
                start = pos
            elseif c == '"' then
                table.insert(chunks, jsonStr:sub(start, pos - 1))
                pos = pos + 1
                return table.concat(chunks)
            else
                pos = pos + 1
            end
        end
        return table.concat(chunks)
    end

    local function parseNumber()
        local match = jsonStr:sub(pos):match("^([%-]?%d+%.?%d*)")
        if match then
            pos = pos + #match
            return tonumber(match)
        end
        return nil
    end

    local function parseObject()
        if jsonStr:sub(pos, pos) ~= '{' then return nil end
        pos = pos + 1
        local obj = {}
        skipWhitespace()
        if jsonStr:sub(pos, pos) == '}' then
            pos = pos + 1
            return obj
        end

        while pos <= len do
            skipWhitespace()
            local key = parseString()
            if not key then break end
            skipWhitespace()
            if jsonStr:sub(pos, pos) == ':' then
                pos = pos + 1
            end
            skipWhitespace()
            local val = parseValue()
            obj[key] = val
            skipWhitespace()
            local sep = jsonStr:sub(pos, pos)
            if sep == ',' then
                pos = pos + 1
            elseif sep == '}' then
                pos = pos + 1
                return obj
            else
                pos = pos + 1
            end
        end
        return obj
    end

    local function parseArray()
        if jsonStr:sub(pos, pos) ~= '[' then return nil end
        pos = pos + 1
        local arr = {}
        skipWhitespace()
        if jsonStr:sub(pos, pos) == ']' then
            pos = pos + 1
            return arr
        end

        while pos <= len do
            skipWhitespace()
            local val = parseValue()
            table.insert(arr, val)
            skipWhitespace()
            local sep = jsonStr:sub(pos, pos)
            if sep == ',' then
                pos = pos + 1
            elseif sep == ']' then
                pos = pos + 1
                return arr
            else
                pos = pos + 1
            end
        end
        return arr
    end

    parseValue = function()
        skipWhitespace()
        if pos > len then return nil end
        local c = jsonStr:sub(pos, pos)
        if c == '{' then
            return parseObject()
        elseif c == '[' then
            return parseArray()
        elseif c == '"' then
            return parseString()
        elseif c == 't' and jsonStr:sub(pos, pos + 3) == "true" then
            pos = pos + 4
            return true
        elseif c == 'f' and jsonStr:sub(pos, pos + 4) == "false" then
            pos = pos + 5
            return false
        elseif c == 'n' and jsonStr:sub(pos, pos + 3) == "null" then
            pos = pos + 4
            return nil
        else
            return parseNumber()
        end
    end

    local ok, res = pcall(parseValue)
    if ok and res ~= nil then
        return res
    else
        return nil, "JSON parse failure: " .. tostring(res)
    end
end

-- ============================================================================
-- CLOUD SYNC STRING ENCODING & DECODING (!CGO1:Payload:Checksum!)
-- ============================================================================
function CloudSync:EncodeProfileToString(profileData)
    if not profileData or type(profileData) ~= "table" then return nil end

    local jsonStr = self:Serialize(profileData)
    local b64 = self:Base64Encode(jsonStr)
    local checksum = self:CalculateChecksum(b64)

    return string.format("!CGO1:%s:%s!", b64, checksum)
end

function CloudSync:DecodeProfileFromString(inputStr)
    if not inputStr or type(inputStr) ~= "string" then
        return nil, "Input is empty or not a string"
    end

    local clean = inputStr:match("^%s*(.-)%s*$")

    -- 1. Check for standard CGO Cloud Code: !CGO1:<b64>:<checksum>!
    local b64Payload, checksum = clean:match("!CGO1:([A-Za-z0-9%+/=]+):([A-Fa-f0-9]+)!")
    if b64Payload and checksum then
        local expectedChecksum = self:CalculateChecksum(b64Payload)
        if checksum:upper() ~= expectedChecksum:upper() then
            return nil, "Checksum mismatch! The profile string may be corrupted or truncated."
        end

        local jsonStr, decodeErr = self:Base64Decode(b64Payload)
        if not jsonStr then return nil, "Base64 decode error: " .. tostring(decodeErr) end

        local profile, parseErr = self:Deserialize(jsonStr)
        if not profile or type(profile) ~= "table" then
            return nil, "Failed to parse profile payload: " .. tostring(parseErr)
        end

        return profile, nil, "cloud"
    end

    -- 2. Fallback: Raw JSON string { ... }
    if clean:match("^{") and clean:match("}$") then
        local profile = self:Deserialize(clean)
        if profile and type(profile) == "table" and (profile.weights or profile.name) then
            return profile, nil, "json"
        end
    end

    -- 3. Fallback: Pawn string (Pawn: v1: ...)
    if clean:match("[Pp][Aa][Ww][Nn]:") or clean:match('^%(%s*"') then
        if addon.StatCalc and addon.StatCalc.ParsePawnString then
            local weights, meta, name = addon.StatCalc:ParsePawnString(clean)
            if weights and next(weights) then
                local profile = {
                    name = name or (meta and meta.scaleName) or "Imported Pawn Profile",
                    class = meta and meta.class or select(2, UnitClass("player")),
                    specName = meta and meta.spec or "Imported",
                    weights = weights,
                    timestamp = time(),
                    dateString = date("%Y-%m-%d %H:%M:%S"),
                    author = UnitName("player") or "Unknown",
                    realm = GetRealmName() or "",
                }
                return profile, nil, "pawn"
            end
        end
    end

    return nil, "Unrecognized profile format. Paste a valid !CGO1:...! string, JSON, or Pawn string."
end

-- ============================================================================
-- GLOBAL ACCOUNT-WIDE CLOUD STORAGE MANAGEMENT
-- ============================================================================
function CloudSync:InitializeDatabase()
    local globalDB = type(CharacterGearOptimizerGlobalDB) == "table" and CharacterGearOptimizerGlobalDB or {}
    
    globalDB.cloudProfiles = globalDB.cloudProfiles or {}
    globalDB.settings = globalDB.settings or {}
    if globalDB.settings.autoSync == nil then globalDB.settings.autoSync = true end
    if globalDB.settings.autoPushOnSave == nil then globalDB.settings.autoPushOnSave = true end
    globalDB.syncLog = globalDB.syncLog or {}
    globalDB.version = 1

    CharacterGearOptimizerGlobalDB = globalDB
    addon.globalDB = globalDB

    -- Check for initial cloud sync if autoSync is enabled
    if globalDB.settings.autoSync then
        self:AutoSync()
    end

    return globalDB
end

function CloudSync:GenerateProfileID(className, specName, profileName)
    local c = className or "ALL"
    local s = (specName or "Spec"):gsub("[%s_%-]", "")
    local p = (profileName or "Profile"):gsub("[%s_%-]", "_")
    return string.format("%s_%s_%s", c:upper(), s, p)
end

function CloudSync:BuildProfileData(profileName, weights, extraMeta)
    local _, playerClass = UnitClass("player")
    local specIdx = addon.currentSpecIdx or addon.autoDetectedSpecIdx or 1
    local specData = addon.CLASS_SPECS and addon.CLASS_SPECS[playerClass] and addon.CLASS_SPECS[playerClass][specIdx]
    local specName = specData and specData.name or "Specialization"
    local role = specData and specData.role or "melee_dps"
    local pName = profileName or (specData and specData.name) or "Active Spec"

    local statWeights = {}
    if weights and type(weights) == "table" then
        for k, v in pairs(weights) do
            local num = tonumber(v)
            if num and num ~= 0 then statWeights[k] = num end
        end
    elseif specData and specData.weights then
        for k, v in pairs(specData.weights) do
            statWeights[k] = v
        end
    end

    local profileId = self:GenerateProfileID(playerClass, specName, pName)

    local profile = {
        id = profileId,
        name = pName,
        class = playerClass,
        specIdx = specIdx,
        specName = specName,
        role = role,
        author = UnitName("player") or "Unknown",
        realm = GetRealmName() or "",
        weights = statWeights,
        caps = (CharacterGearOptimizerDB and CharacterGearOptimizerDB.capPriorities) or {},
        clientFlavor = addon.isMainline and "Mainline" or (addon.isVanilla and "Vanilla" or (addon.isTBC and "TBC" or (addon.isWrath and "Wrath" or (addon.isCata and "Cata" or "Classic")))),
        clientVersion = addon.tocVersion or 0,
        timestamp = time(),
        dateString = date("%Y-%m-%d %H:%M:%S"),
        notes = (extraMeta and extraMeta.notes) or "",
        tags = (extraMeta and extraMeta.tags) or { "CGO", playerClass, specName },
    }

    return profile
end

function CloudSync:PushProfile(profileData)
    if not profileData or type(profileData) ~= "table" then return false, "Invalid profile data" end
    self:InitializeDatabase()

    local pId = profileData.id or self:GenerateProfileID(profileData.class, profileData.specName, profileData.name)
    profileData.id = pId
    profileData.timestamp = profileData.timestamp or time()
    profileData.dateString = profileData.dateString or date("%Y-%m-%d %H:%M:%S")

    CharacterGearOptimizerGlobalDB.cloudProfiles[pId] = profileData

    -- Add to sync log
    table.insert(CharacterGearOptimizerGlobalDB.syncLog, {
        action = "push",
        profileId = pId,
        profileName = profileData.name,
        timestamp = time(),
        date = date("%H:%M:%S"),
    })
    while #CharacterGearOptimizerGlobalDB.syncLog > 100 do
        table.remove(CharacterGearOptimizerGlobalDB.syncLog, 1)
    end

    print(string.format("|cFFFFD700CGO Cloud:|r Synced profile |cFF00FF00%s|r to Account Cloud Store.", profileData.name))

    if self.dialog and self.dialog:IsShown() and self.dialog.RefreshProfileList then
        self.dialog:RefreshProfileList()
    end

    return true, pId
end

function CloudSync:PushCurrentProfile(customName, customNotes)
    local weights = nil
    if addon.currentCustomProfile and addon.currentCustomProfile.weights then
        weights = addon.currentCustomProfile.weights
    elseif CharacterGearOptimizerDB and CharacterGearOptimizerDB.customStats and customName and CharacterGearOptimizerDB.customStats[customName] then
        weights = CharacterGearOptimizerDB.customStats[customName]
    end

    local profile = self:BuildProfileData(customName, weights, { notes = customNotes })
    return self:PushProfile(profile)
end

function CloudSync:PullProfile(profileId, localName, applyAsActive)
    self:InitializeDatabase()
    local profile = CharacterGearOptimizerGlobalDB.cloudProfiles[profileId]
    if not profile then
        return false, "Cloud profile not found: " .. tostring(profileId)
    end

    local targetName = localName or profile.name or "Cloud Profile"
    CharacterGearOptimizerDB = CharacterGearOptimizerDB or {}
    CharacterGearOptimizerDB.customStats = CharacterGearOptimizerDB.customStats or {}
    CharacterGearOptimizerDB.customStats[targetName] = {}

    for k, v in pairs(profile.weights or {}) do
        CharacterGearOptimizerDB.customStats[targetName][k] = v
    end

    if profile.caps and CharacterGearOptimizerDB.capPriorities then
        CharacterGearOptimizerDB.capPriorities[targetName] = profile.caps
    end

    if applyAsActive then
        addon.currentCustomProfile = {
            name = targetName,
            role = profile.role or "melee_dps",
            weights = CharacterGearOptimizerDB.customStats[targetName],
        }
        if addon.OptimizeForCustomProfile then
            addon:OptimizeForCustomProfile(addon.currentCustomProfile)
        end
        if addon.RefreshGearPanel then
            addon:RefreshGearPanel()
        end
    end

    print(string.format("|cFFFFD700CGO Cloud:|r Pulled profile |cFF00FF00%s|r into local character profiles.", targetName))
    return true, profile
end

function CloudSync:DeleteCloudProfile(profileId)
    self:InitializeDatabase()
    if CharacterGearOptimizerGlobalDB.cloudProfiles[profileId] then
        local name = CharacterGearOptimizerGlobalDB.cloudProfiles[profileId].name or profileId
        CharacterGearOptimizerGlobalDB.cloudProfiles[profileId] = nil
        print(string.format("|cFFFFD700CGO Cloud:|r Deleted profile |cFFFF5555%s|r from Account Cloud Store.", name))
        if self.dialog and self.dialog:IsShown() and self.dialog.RefreshProfileList then
            self.dialog:RefreshProfileList()
        end
        return true
    end
    return false
end

function CloudSync:GetAllCloudProfiles(filterClass)
    self:InitializeDatabase()
    local list = {}
    for id, profile in pairs(CharacterGearOptimizerGlobalDB.cloudProfiles or {}) do
        if not filterClass or profile.class == filterClass then
            table.insert(list, profile)
        end
    end

    table.sort(list, function(a, b)
        return (a.timestamp or 0) > (b.timestamp or 0)
    end)

    return list
end

function CloudSync:PushAllLocalProfiles()
    self:InitializeDatabase()
    local localStats = CharacterGearOptimizerDB and CharacterGearOptimizerDB.customStats or {}
    local pushedCount = 0

    for name, weights in pairs(localStats) do
        local profile = self:BuildProfileData(name, weights)
        self:PushProfile(profile)
        pushedCount = pushedCount + 1
    end

    print(string.format("|cFFFFD700CGO Cloud:|r Pushed %d local profile(s) to Account Cloud Store.", pushedCount))
    return pushedCount
end

function CloudSync:PullAllCloudProfiles()
    self:InitializeDatabase()
    local _, playerClass = UnitClass("player")
    local profiles = self:GetAllCloudProfiles(playerClass)
    local pulledCount = 0

    for _, p in ipairs(profiles) do
        self:PullProfile(p.id, p.name, false)
        pulledCount = pulledCount + 1
    end

    print(string.format("|cFFFFD700CGO Cloud:|r Pulled %d cloud profile(s) for class %s.", pulledCount, playerClass or "ALL"))
    return pulledCount
end

function CloudSync:AutoSync()
    -- NOTE: AutoSync is only ever invoked from InitializeDatabase() itself
    -- (when settings.autoSync is true). It must NOT call InitializeDatabase()
    -- again here -- that previously caused infinite mutual recursion
    -- (InitializeDatabase -> AutoSync -> InitializeDatabase -> ...) and a
    -- guaranteed stack overflow on every login/reload with autoSync enabled
    -- (the default). CharacterGearOptimizerGlobalDB is already guaranteed to
    -- exist by the caller before AutoSync runs.
    CharacterGearOptimizerGlobalDB = CharacterGearOptimizerGlobalDB or {}
    CharacterGearOptimizerGlobalDB.cloudProfiles = CharacterGearOptimizerGlobalDB.cloudProfiles or {}
    local localStats = CharacterGearOptimizerDB and CharacterGearOptimizerDB.customStats or {}
    
    -- Push local profiles that are missing in cloud
    for name, weights in pairs(localStats) do
        local _, playerClass = UnitClass("player")
        local specIdx = addon.currentSpecIdx or addon.autoDetectedSpecIdx or 1
        local specData = addon.CLASS_SPECS and addon.CLASS_SPECS[playerClass] and addon.CLASS_SPECS[playerClass][specIdx]
        local specName = specData and specData.name or "Spec"
        local pId = self:GenerateProfileID(playerClass, specName, name)

        if not CharacterGearOptimizerGlobalDB.cloudProfiles[pId] then
            local p = self:BuildProfileData(name, weights)
            CharacterGearOptimizerGlobalDB.cloudProfiles[pId] = p
        end
    end
end

-- ============================================================================
-- INTERACTIVE CLOUD SYNC & PROFILE SHARING UI PANEL
-- ============================================================================
function CloudSync:CreateDialog()
    if self.dialog then return self.dialog end

    local dialog = CreateFrame("Frame", "CGOCloudSyncDialog", UIParent, BACKDROP_TEMPLATE)
    dialog:SetSize(460, 480)
    dialog:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    dialog:SetFrameStrata("DIALOG")
    dialog:SetFrameLevel(150)
    dialog:SetMovable(true)
    dialog:EnableMouse(true)
    dialog:RegisterForDrag("LeftButton")
    dialog:SetScript("OnDragStart", dialog.StartMoving)
    dialog:SetScript("OnDragStop", dialog.StopMovingOrSizing)
    dialog:SetClampedToScreen(true)

    if dialog.SetBackdrop then
        dialog:SetBackdrop({
            bgFile   = "Interface/DialogFrame/UI-DialogBox-Background",
            edgeFile = "Interface/DialogFrame/UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 },
        })
        dialog:SetBackdropColor(0.06, 0.05, 0.08, 0.96)
        dialog:SetBackdropBorderColor(0.7, 0.55, 0.25, 1)
    end

    self.dialog = dialog

    -- Header Title
    local title = dialog:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -14)
    title:SetText("|cFFFFD700CGO Cloud Sync & Profile Sharing|r")

    -- Subtitle
    local subtitle = dialog:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    subtitle:SetText("Account-Wide Cloud Profiles & Cross-Realm Sharing")

    -- Close Button
    local closeBtn = CreateFrame("Button", nil, dialog, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", dialog, "TOPRIGHT", -4, -4)
    closeBtn:SetScript("OnClick", function() dialog:Hide() end)

    -- Divider Line
    local line = dialog:CreateTexture(nil, "ARTWORK")
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -8)
    line:SetPoint("RIGHT", dialog, "RIGHT", -16, 0)
    if line.SetColorTexture then
        line:SetColorTexture(0.55, 0.45, 0.25, 0.6)
    end

    -- Tab / Section Buttons
    local tabLib = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
    tabLib:SetSize(130, 22)
    tabLib:SetPoint("TOPLEFT", line, "BOTTOMLEFT", 0, -8)
    tabLib:SetText("Cloud Library")

    local tabCode = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
    tabCode:SetSize(130, 22)
    tabCode:SetPoint("LEFT", tabLib, "RIGHT", 6, 0)
    tabCode:SetText("Share / Code")

    -- Content Containers
    local libFrame = CreateFrame("Frame", nil, dialog)
    libFrame:SetPoint("TOPLEFT", tabLib, "BOTTOMLEFT", 0, -8)
    libFrame:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -16, 44)

    local codeFrame = CreateFrame("Frame", nil, dialog)
    codeFrame:SetPoint("TOPLEFT", tabLib, "BOTTOMLEFT", 0, -8)
    codeFrame:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -16, 44)
    codeFrame:Hide()

    local function SwitchTab(tab)
        if tab == "lib" then
            libFrame:Show()
            codeFrame:Hide()
            tabLib:Disable()
            tabCode:Enable()
            dialog:RefreshProfileList()
        else
            libFrame:Hide()
            codeFrame:Show()
            tabLib:Enable()
            tabCode:Disable()
        end
    end

    tabLib:SetScript("OnClick", function() SwitchTab("lib") end)
    tabCode:SetScript("OnClick", function() SwitchTab("code") end)

    -- ========================================================================
    -- TAB 1: CLOUD LIBRARY VIEW
    -- ========================================================================
    local scrollFrame = CreateFrame("ScrollFrame", "CGOCloudScrollFrame", libFrame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", libFrame, "TOPLEFT", 0, 0)
    scrollFrame:SetPoint("BOTTOMRIGHT", libFrame, "BOTTOMRIGHT", -24, 38)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize(400, 1)
    scrollFrame:SetScrollChild(scrollChild)

    local profileRows = {}

    function dialog:RefreshProfileList()
        for _, row in ipairs(profileRows) do row:Hide() end

        local _, playerClass = UnitClass("player")
        local profiles = CloudSync:GetAllCloudProfiles()
        local yOffset = 0

        for i, p in ipairs(profiles) do
            local row = profileRows[i]
            if not row then
                row = CreateFrame("Frame", nil, scrollChild, BACKDROP_TEMPLATE)
                row:SetSize(396, 52)
                if row.SetBackdrop then
                    row:SetBackdrop({
                        bgFile   = "Interface/DialogFrame/UI-DialogBox-Background",
                        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
                        tile = true, tileSize = 16, edgeSize = 10,
                        insets = { left = 2, right = 2, top = 2, bottom = 2 },
                    })
                    row:SetBackdropColor(0.1, 0.1, 0.14, 0.85)
                    row:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.6)
                end

                row.nameText = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
                row.nameText:SetPoint("TOPLEFT", 8, -6)

                row.metaText = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
                row.metaText:SetPoint("TOPLEFT", row.nameText, "BOTTOMLEFT", 0, -3)

                row.statsText = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
                row.statsText:SetPoint("TOPLEFT", row.metaText, "BOTTOMLEFT", 0, -2)

                -- Action Buttons
                row.btnPull = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
                row.btnPull:SetSize(56, 20)
                row.btnPull:SetPoint("TOPRIGHT", -8, -6)
                row.btnPull:SetText("Pull")

                row.btnCode = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
                row.btnCode:SetSize(56, 20)
                row.btnCode:SetPoint("TOPRIGHT", row.btnPull, "TOPLEFT", -4, 0)
                row.btnCode:SetText("Code")

                row.btnDel = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
                row.btnDel:SetSize(40, 20)
                row.btnDel:SetPoint("TOPRIGHT", -8, -28)
                row.btnDel:SetText("X")

                profileRows[i] = row
            end

            row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, yOffset)
            row:Show()

            local color = (addon.CLASS_COLORS and addon.CLASS_COLORS[p.class]) or "FFFFFF"
            row.nameText:SetText(string.format("|cFF%s%s|r (|cFFFFD700%s|r)", color, p.name or "Profile", p.specName or p.class or "All"))
            row.metaText:SetText(string.format("By %s (%s) • %s", p.author or "Unknown", p.realm or "Realm", p.dateString or "Recently"))

            -- Top stats preview
            local topStats = {}
            for sKey, sVal in pairs(p.weights or {}) do
                table.insert(topStats, string.format("%s: %.1f", sKey, sVal))
                if #topStats >= 3 then break end
            end
            row.statsText:SetText(table.concat(topStats, ", "))

            row.btnPull:SetScript("OnClick", function()
                CloudSync:PullProfile(p.id, p.name, true)
            end)

            row.btnCode:SetScript("OnClick", function()
                local codeStr = CloudSync:EncodeProfileToString(p)
                SwitchTab("code")
                if dialog.expBox then
                    dialog.expBox:SetText(codeStr)
                    dialog.expBox:HighlightText()
                    dialog.expBox:SetFocus()
                end
            end)

            row.btnDel:SetScript("OnClick", function()
                CloudSync:DeleteCloudProfile(p.id)
            end)

            yOffset = yOffset - 56
        end

        scrollChild:SetHeight(math.max(1, math.abs(yOffset)))
    end

    -- Bottom Library Buttons
    local btnPushActive = CreateFrame("Button", nil, libFrame, "UIPanelButtonTemplate")
    btnPushActive:SetSize(130, 24)
    btnPushActive:SetPoint("BOTTOMLEFT", libFrame, "BOTTOMLEFT", 0, 4)
    btnPushActive:SetText("Push Active Spec")
    btnPushActive:SetScript("OnClick", function()
        CloudSync:PushCurrentProfile()
    end)

    local btnSyncAll = CreateFrame("Button", nil, libFrame, "UIPanelButtonTemplate")
    btnSyncAll:SetSize(130, 24)
    btnSyncAll:SetPoint("LEFT", btnPushActive, "RIGHT", 8, 0)
    btnSyncAll:SetText("Sync All to Cloud")
    btnSyncAll:SetScript("OnClick", function()
        CloudSync:PushAllLocalProfiles()
    end)

    local btnPullAll = CreateFrame("Button", nil, libFrame, "UIPanelButtonTemplate")
    btnPullAll:SetSize(130, 24)
    btnPullAll:SetPoint("LEFT", btnSyncAll, "RIGHT", 8, 0)
    btnPullAll:SetText("Pull All for Class")
    btnPullAll:SetScript("OnClick", function()
        CloudSync:PullAllCloudProfiles()
    end)

    -- ========================================================================
    -- TAB 2: SHARE / CODE VIEW (Export & Import)
    -- ========================================================================
    local expLabel = codeFrame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    expLabel:SetPoint("TOPLEFT", codeFrame, "TOPLEFT", 0, -4)
    expLabel:SetText("|cFFFFD700Export Cloud String (Copy & Share)|r")

    local expScroll = CreateFrame("ScrollFrame", "CGOCloudExpScroll", codeFrame, "UIPanelScrollFrameTemplate")
    expScroll:SetSize(400, 110)
    expScroll:SetPoint("TOPLEFT", expLabel, "BOTTOMLEFT", 0, -6)

    local expBox = CreateFrame("EditBox", "CGOCloudExpBox", expScroll)
    expBox:SetMultiLine(true)
    expBox:SetAutoFocus(false)
    expBox:SetFontObject(GameFontHighlightSmall)
    expBox:SetWidth(380)
    expBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    expScroll:SetScrollChild(expBox)
    dialog.expBox = expBox

    local btnGenActive = CreateFrame("Button", nil, codeFrame, "UIPanelButtonTemplate")
    btnGenActive:SetSize(140, 22)
    btnGenActive:SetPoint("TOPLEFT", expScroll, "BOTTOMLEFT", 0, -8)
    btnGenActive:SetText("Generate for Active")
    btnGenActive:SetScript("OnClick", function()
        local prof = CloudSync:BuildProfileData()
        local codeStr = CloudSync:EncodeProfileToString(prof)
        expBox:SetText(codeStr)
        expBox:HighlightText()
        expBox:SetFocus()
    end)

    -- Import Section
    local impLabel = codeFrame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    impLabel:SetPoint("TOPLEFT", btnGenActive, "BOTTOMLEFT", 0, -14)
    impLabel:SetText("|cFFFFD700Import Profile String (Paste Cloud Code / Pawn / JSON)|r")

    local impScroll = CreateFrame("ScrollFrame", "CGOCloudImpScroll", codeFrame, "UIPanelScrollFrameTemplate")
    impScroll:SetSize(400, 90)
    impScroll:SetPoint("TOPLEFT", impLabel, "BOTTOMLEFT", 0, -6)

    local impBox = CreateFrame("EditBox", "CGOCloudImpBox", impScroll)
    impBox:SetMultiLine(true)
    impBox:SetAutoFocus(false)
    impBox:SetFontObject(GameFontHighlightSmall)
    impBox:SetWidth(380)
    impBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    impScroll:SetScrollChild(impBox)

    local impStatus = codeFrame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    impStatus:SetPoint("TOPLEFT", impScroll, "BOTTOMLEFT", 0, -6)
    impStatus:SetText("|cFFAAAAAAPaste code above and click Import Profile|r")

    local btnDoImport = CreateFrame("Button", nil, codeFrame, "UIPanelButtonTemplate")
    btnDoImport:SetSize(140, 24)
    btnDoImport:SetPoint("TOPLEFT", impStatus, "BOTTOMLEFT", 0, -6)
    btnDoImport:SetText("Import & Save")
    btnDoImport:SetScript("OnClick", function()
        local text = impBox:GetText()
        local profile, err, fmt = CloudSync:DecodeProfileFromString(text)
        if profile then
            CloudSync:PushProfile(profile)
            CloudSync:PullProfile(profile.id, profile.name, true)
            impStatus:SetText(string.format("|cFF00FF00Successfully imported '%s' (%s format)!|r", profile.name, fmt or "cloud"))
            impBox:SetText("")
        else
            impStatus:SetText(string.format("|cFFFF5555Error: %s|r", err or "Invalid format"))
        end
    end)

    -- Bottom Close
    local btnBottomClose = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
    btnBottomClose:SetSize(100, 24)
    btnBottomClose:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -16, 12)
    btnBottomClose:SetText("Close")
    btnBottomClose:SetScript("OnClick", function() dialog:Hide() end)

    dialog:SetScript("OnShow", function()
        SwitchTab("lib")
    end)

    return dialog
end

function CloudSync:OpenDialog()
    local dialog = self:CreateDialog()
    dialog:Show()
    dialog:RefreshProfileList()
end

-- ============================================================================
-- GLOBAL ADDON CONVENIENCE BINDINGS
-- ============================================================================
addon.OpenCloudSync = function(self)
    CloudSync:OpenDialog()
end

addon.PushProfileToCloud = function(self, name, notes)
    return CloudSync:PushCurrentProfile(name, notes)
end

addon.PullProfileFromCloud = function(self, id, name, apply)
    return CloudSync:PullProfile(id, name, apply)
end

addon.ExportCloudProfile = function(self, profile)
    return CloudSync:EncodeProfileToString(profile)
end

addon.ImportCloudProfile = function(self, str)
    return CloudSync:DecodeProfileFromString(str)
end

-- Auto-register on PLAYER_LOGIN
local csInitFrame = CreateFrame("Frame")
csInitFrame:RegisterEvent("PLAYER_LOGIN")
csInitFrame:SetScript("OnEvent", function(self)
    CloudSync:InitializeDatabase()
    self:UnregisterEvent("PLAYER_LOGIN")
end)
