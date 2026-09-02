-- ============================================================================
-- CharacterGearOptimizer: SpecHUD.lua
-- Draggable, scrollable floating stats HUD with cap breakpoints and
-- role-specific stat overview.  Only shows caps the user has checked.
-- ============================================================================

local addonName, addon = ...
local addon = addon or _G.CharacterGearOptimizer or {}
_G.CharacterGearOptimizer = addon

local R = addon.RATING or {}
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
-- FRAME (outer shell — title bar, border, close button)
-- ============================================================================
local frame = CreateFrame("Frame", "CGOSpecHUD", UIParent, BACKDROP_TEMPLATE)
frame:SetSize(260, 280)
frame:SetPoint("CENTER", UIParent, "CENTER", -300, 0)
frame:SetMovable(true)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")
frame:SetScript("OnDragStart", frame.StartMoving)
frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local p, _, rp, x, y = self:GetPoint()
    CharacterGearOptimizerDB = CharacterGearOptimizerDB or {}
    CharacterGearOptimizerDB.specHUD = CharacterGearOptimizerDB.specHUD or {}
    local s = CharacterGearOptimizerDB.specHUD
    s.point, s.relPoint, s.x, s.y = p, rp, x, y
end)

ApplyBackdrop(frame, {
    bgFile   = "Interface/DialogFrame/UI-DialogBox-Background",
    edgeFile = "Interface/DialogFrame/UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
}, { 0.06, 0.06, 0.06, 0.92 }, { 0.55, 0.45, 0.25, 1 })

local titleText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
titleText:SetPoint("TOP", frame, "TOP", 0, -8)

local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
closeBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, -2)
closeBtn:SetSize(20, 20)
closeBtn:SetScript("OnClick", function()
    frame:Hide()
    if CharacterGearOptimizerDB then CharacterGearOptimizerDB.specHUDHidden = true end
end)

-- ============================================================================
-- SCROLL FRAME (makes the content area scrollable via mouse wheel)
-- ============================================================================
local scrollClip = CreateFrame("Frame", nil, frame)
scrollClip:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -26)
scrollClip:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -8, 6)
if scrollClip.SetClipsChildren then scrollClip:SetClipsChildren(true) end

local scrollContent = CreateFrame("Frame", nil, scrollClip)
scrollContent:SetPoint("TOPLEFT", scrollClip, "TOPLEFT")
scrollContent:SetWidth(244)
scrollContent:SetHeight(1) -- will be resized

local statsText = scrollContent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
statsText:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", 4, 0)
statsText:SetJustifyH("LEFT")
statsText:SetWidth(236)

local scrollOffset = 0
frame:SetScript("OnMouseWheel", function(self, delta)
    local maxScroll = math.max(0, scrollContent:GetHeight() - scrollClip:GetHeight())
    scrollOffset = math.max(0, math.min(maxScroll, scrollOffset - delta * 20))
    scrollContent:SetPoint("TOPLEFT", scrollClip, "TOPLEFT", 0, scrollOffset)
end)

addon.specHUDFrame = frame

-- ============================================================================
-- HELPERS
-- ============================================================================
local function ArmorDR(armor)
    if armor <= 0 then return 0 end
    return armor / (armor + R.ARMOR_CONSTANT)
end

local SOTF_SPELLS = { [33853] = 1, [33855] = 2, [33856] = 3 }
local function GetSotFRank()
    for id, rank in pairs(SOTF_SPELLS) do
        if IsSpellKnown and IsSpellKnown(id) then return rank end
    end
    if not GetTalentInfo then return 0 end
    local nTabs = GetNumTalentTabs and GetNumTalentTabs() or 3
    for tab = 1, nTabs do
        for t = 1, (GetNumTalents and GetNumTalents(tab) or 0) do
            local name, _, _, _, rank = GetTalentInfo(tab, t)
            if name and name:find("Survival of the Fittest") then return rank or 0 end
        end
    end
    return 0
end

-- Color constants
local GRN  = "|cff00ff00"
local RED  = "|cffff4444"
local WHT  = "|cffffffff"
local DIM  = "|cff888888"
local GOLD = "|cffffd700"
local SEP  = GOLD .. "————————————————————|r"

-- ============================================================================
-- DURABILITY HELPER
-- ============================================================================
local function BuildDurability()
    local cur, mx = 0, 0
    for slot = 1, 18 do
        if slot ~= 4 then -- skip shirt
            local c, m = GetInventoryItemDurability(slot)
            if c and m and m > 0 then
                cur = cur + c
                mx  = mx  + m
            end
        end
    end
    if mx == 0 then return "" end
    local pct = (cur / mx) * 100
    local clr = pct > 50 and GRN or (pct > 25 and GOLD or RED)
    return clr .. string.format("Durability: %.0f%%", pct) .. "|r\n"
end

-- Cap line:  "CapName" in green/red,  values in white
local function CapLine(met, capName, valStr)
    local clr = met and GRN or RED
    return clr .. capName .. "|r  " .. WHT .. valStr .. "|r"
end

-- ============================================================================
-- BREAKPOINTS — only the caps the user has checked in Cap Priorities
-- ============================================================================
local function BuildBreakpoints(role)
    local caps = CharacterGearOptimizerDB and CharacterGearOptimizerDB.capPriorities or {}
    local pvp  = caps.pvpMode
    local lines = {}

    -- ── Crit Immune ──
    if caps.critImmune then
        local totalDef, defOver = 350, 0
        if UnitDefense then
            local b, m = UnitDefense("player")
            totalDef = (b or 0) + (m or 0)
            defOver  = totalDef - ((UnitLevel("player") or 80) * 5)
        end
        local critRed = defOver * 0.04 + (GetCombatRatingBonus(R.CR_RESILIENCE) or 0)
        local sotf = GetSotFRank()
        if sotf > 0 then critRed = critRed + sotf * 1.0 end
        local met = critRed >= R.BOSS_CRIT_PCT
        table.insert(lines, CapLine(met, "Crit Immune",
            string.format("%.2f%% / %.1f%%", critRed, R.BOSS_CRIT_PCT)))
    end

    -- ── Uncrushable ──
    if caps.uncrushable and (role == "tank" or role == "tank_barrier") then
        local dodge = GetDodgeChance() or 0
        local parry = GetParryChance() or 0
        local block = GetBlockChance() or 0
        local defOver = 0
        if UnitDefense then
            local b, m = UnitDefense("player")
            defOver = (b + m) - ((UnitLevel("player") or 80) * 5)
        end
        local miss = math.max(0, 5.0 - 0.6 + defOver * 0.04)
        local total = miss + dodge + parry + block
        table.insert(lines, CapLine(total >= 102.4, "Uncrushable",
            string.format("%.1f%% / 102.4%%", total)))
    end

    -- ── Armor Cap ──
    if caps.armorCapped then
        local _, armor = UnitArmor("player"); armor = armor or 0
        local armorConst = pvp and R.PVP_ARMOR_CONSTANT or R.ARMOR_CONSTANT
        local armorCap   = pvp and R.PVP_ARMOR_CAP_VALUE or R.ARMOR_CAP_VALUE
        local dr   = math.min(75, (armor / (armor + armorConst)) * 100)
        local met  = armor >= armorCap
        table.insert(lines, CapLine(met, "Armor Cap",
            string.format("%.1f%% / 75%%", dr)))
    end

    -- ── Melee Hit ──
    if caps.hitCapped then
        local hitCapPct = pvp and R.PVP_MELEE_HIT_CAP_PCT or R.MELEE_HIT_CAP_PCT
        local rating = GetCombatRating(R.CR_HIT_MELEE) or 0
        local pct    = addon:GetTotalHitChance(R.CR_HIT_MELEE)
        local cap    = math.ceil(hitCapPct * R.HIT_PER_PCT)
        local met    = pct >= hitCapPct
        table.insert(lines, CapLine(met, "Melee Hit",
            string.format("%.1f%% / %.0f%%", pct, hitCapPct)))
    end

    -- ── Spell Hit ──
    if caps.spellHitCapped then
        local shCapPct = pvp and R.PVP_SPELL_HIT_CAP_PCT or R.SPELL_HIT_CAP_PCT
        local rating = GetCombatRating(R.CR_HIT_SPELL) or 0
        local pct    = addon:GetTotalHitChance(R.CR_HIT_SPELL)
        local cap    = math.ceil(shCapPct * R.SPELL_HIT_PER_PCT)
        local met    = pct >= shCapPct
        table.insert(lines, CapLine(met, "Spell Hit",
            string.format("%.1f%% / %.0f%%", pct, shCapPct)))
    end

    -- ── Expertise ──
    if caps.expertiseCapped then
        local expCap = pvp and R.PVP_EXPERTISE_SOFT_CAP or R.EXPERTISE_SOFT_CAP
        local exp    = GetExpertise and GetExpertise() or 0
        local rating = GetCombatRating(R.CR_EXPERTISE) or 0
        local met    = exp >= expCap
        table.insert(lines, CapLine(met, "Expertise",
            string.format("%d / %d", exp, expCap)))
    end

    -- ── Resilience (PvP crit immune) ──
    if caps.resilCapped then
        local rating = GetCombatRating(R.CR_RESILIENCE) or 0
        local pct    = GetCombatRatingBonus(R.CR_RESILIENCE) or 0
        local met    = pct >= R.RESIL_CRIT_IMMUNE_PCT
        table.insert(lines, CapLine(met, "Resilience",
            string.format("%.1f%% / %.0f%%", pct, R.RESIL_CRIT_IMMUNE_PCT)))
    end

    -- ── Haste (GCD cap) ──
    if caps.hasteCapped then
        local isCaster = (role == "caster_dps" or role == "healer")
        local crID     = isCaster and R.CR_HASTE_SPELL or R.CR_HASTE_MELEE
        local rating   = GetCombatRating(crID) or 0
        local pct      = GetCombatRatingBonus(crID) or 0
        local capRating = R.HASTE_SPELL_CAP_RATING
        local met    = rating >= capRating
        table.insert(lines, CapLine(met, "Haste Cap",
            string.format("%.1f%% / %.0f%%", pct, R.HASTE_GCD_CAP_PCT)))
    end

    if #lines == 0 then return "" end
    return GOLD .. "Breakpoints|r\n" .. table.concat(lines, "\n") .. "\n"
end

-- ============================================================================
-- CUSTOM STAT BUILDER (driven by per-stat checkboxes in the minimap menu)
-- ============================================================================
local function BuildCustomStats(color, mobLevel)
    local sel = CharacterGearOptimizerDB and CharacterGearOptimizerDB.hudStats
    if not sel or not next(sel) then return nil end -- nothing selected, fall through to role

    local pvp = CharacterGearOptimizerDB.capPriorities and CharacterGearOptimizerDB.capPriorities.pvpMode

    local lines = {}
    -- Plain stat line (no cap)
    local function L(label, val)
        table.insert(lines, string.format("|cff%s%s|r  %s%s|r", color, label, WHT, val))
    end
    -- Capped stat line: name is green if met, red if not; shows "value / cap"
    local function C(label, val, cap, fmt, extra)
        local met = val >= cap
        local clr = met and GRN or RED
        local txt = string.format(fmt, val) .. " / " .. string.format(fmt, cap)
        if extra then txt = txt .. "  " .. extra end
        table.insert(lines, clr .. label .. "|r  " .. WHT .. txt .. "|r")
    end

    if sel.strength  then L("Strength",     tostring(UnitStat("player", 1) or 0)) end
    if sel.agility   then L("Agility",      tostring(UnitStat("player", 2) or 0)) end
    if sel.stamina   then L("Stamina",      tostring(UnitStat("player", 3) or 0)) end
    if sel.intellect then L("Intellect",    tostring(UnitStat("player", 4) or 0)) end
    if sel.spirit    then L("Spirit",       tostring(UnitStat("player", 5) or 0)) end

    if sel.attackPower then
        local b, p, n = UnitAttackPower("player")
        L("Attack Power", tostring((b or 0) + (p or 0) + (n or 0)))
    end
    if sel.spellPower then
        local maxDmg = 0
        if GetSpellBonusDamage then
            for school = 2, 7 do
                maxDmg = math.max(maxDmg, GetSpellBonusDamage(school) or 0)
            end
        end
        L("Spell Power", tostring(maxDmg))
    end
    if sel.healPower then
        L("Heal Power", tostring(GetSpellBonusHealing and GetSpellBonusHealing() or 0))
    end
    -- School indices for GetSpellBonusDamage: 2 Holy, 3 Fire, 4 Nature, 5 Frost, 6 Shadow, 7 Arcane
    if sel.holyDamage then
        L("Holy", tostring(GetSpellBonusDamage and GetSpellBonusDamage(2) or 0))
    end
    if sel.fireDamage then
        L("Fire", tostring(GetSpellBonusDamage and GetSpellBonusDamage(3) or 0))
    end
    if sel.natureDamage then
        L("Nature", tostring(GetSpellBonusDamage and GetSpellBonusDamage(4) or 0))
    end
    if sel.frostDamage then
        L("Frost", tostring(GetSpellBonusDamage and GetSpellBonusDamage(5) or 0))
    end
    if sel.shadowDamage then
        L("Shadow", tostring(GetSpellBonusDamage and GetSpellBonusDamage(6) or 0))
    end
    if sel.arcaneDamage then
        L("Arcane", tostring(GetSpellBonusDamage and GetSpellBonusDamage(7) or 0))
    end
    if sel.meleeCrit then
        L("Melee Crit", string.format("%.2f%%", GetCritChance() or 0))
    end
    if sel.spellCrit then
        L("Spell Crit", string.format("%.2f%%", GetSpellCritChance and GetSpellCritChance(2) or 0))
    end
    if sel.meleeHaste then
        local hr = GetCombatRating(R.CR_HASTE_MELEE) or 0
        L("Melee Haste", string.format("%.2f%%  %s(%d)|r", GetCombatRatingBonus(R.CR_HASTE_MELEE) or 0, DIM, hr))
    end
    if sel.spellHaste then
        local hr = GetCombatRating(R.CR_HASTE_SPELL) or 0
        L("Spell Haste", string.format("%.2f%%  %s(%d)|r", GetCombatRatingBonus(R.CR_HASTE_SPELL) or 0, DIM, hr))
    end
    if sel.meleeHit then
        local rating = GetCombatRating(R.CR_HIT_MELEE) or 0
        local pct    = addon:GetTotalHitChance(R.CR_HIT_MELEE)
        local cap    = pvp and R.PVP_MELEE_HIT_CAP_PCT or R.MELEE_HIT_CAP_PCT
        C("Melee Hit", pct, cap, "%.2f%%", DIM .. "(" .. rating .. ")|r")
    end
    if sel.spellHit then
        local rating = GetCombatRating(R.CR_HIT_SPELL) or 0
        local pct    = addon:GetTotalHitChance(R.CR_HIT_SPELL)
        local cap    = pvp and R.PVP_SPELL_HIT_CAP_PCT or R.SPELL_HIT_CAP_PCT
        C("Spell Hit", pct, cap, "%.2f%%", DIM .. "(" .. rating .. ")|r")
    end
    if sel.expertise then
        local exp = GetExpertise and GetExpertise() or 0
        local rating = GetCombatRating(R.CR_EXPERTISE) or 0
        local cap = pvp and R.PVP_EXPERTISE_SOFT_CAP or R.EXPERTISE_SOFT_CAP
        if cap > 0 then
            C("Expertise", exp, cap, "%d", DIM .. "(" .. rating .. " rating)|r")
        else
            L("Expertise", string.format("%d  %s(%d rating)|r", exp, DIM, rating))
        end
    end
    if sel.armorPen then
        local rating = GetCombatRating and GetCombatRating(25) or 0
        L("Armor Pen", string.format("%d rating", rating))
    end
    if sel.hp then
        L("HP", tostring(UnitHealthMax("player") or 0))
    end
    if sel.mana then
        L("Mana", tostring(UnitPowerMax("player", 0) or 0))
    end
    if sel.mp5 then
        local _, cmr = 0, 0
        if GetManaRegen then _, cmr = GetManaRegen() end
        L("MP5 (cast)", string.format("%.0f", (cmr or 0) * 5))
    end
    if sel.armor then
        local _, armor = UnitArmor("player"); armor = armor or 0
        local armorConst = pvp and R.PVP_ARMOR_CONSTANT or R.ARMOR_CONSTANT
        local dr = math.min(75, (armor / (armor + armorConst)) * 100)
        C("Armor", dr, R.ARMOR_DR_CAP_PCT, "%.1f%%", DIM .. "(" .. armor .. ")|r")
    end
    if sel.defense then
        if UnitDefense then
            local b, m = UnitDefense("player")
            local total = (b or 0) + (m or 0)
            C("Defense", total, R.DEFENSE_CAP, "%d")
        end
    end
    if sel.dodge then
        L("Dodge", string.format("%.2f%%", GetDodgeChance() or 0))
    end
    if sel.parry then
        L("Parry", string.format("%.2f%%", GetParryChance() or 0))
    end
    if sel.block then
        L("Block", string.format("%.2f%%", GetBlockChance() or 0))
    end
    if sel.resilience then
        local rating = GetCombatRating(R.CR_RESILIENCE) or 0
        local pct    = GetCombatRatingBonus(R.CR_RESILIENCE) or 0
        C("Resilience", pct, R.RESIL_CRIT_IMMUNE_PCT, "%.2f%%", DIM .. "(" .. rating .. ")|r")
    end
    if sel.avoidance then
        local dodge = GetDodgeChance() or 0
        local parry = GetParryChance() or 0
        local block = GetBlockChance() or 0
        local defOver = 0
        if UnitDefense then
            local b, m = UnitDefense("player")
            defOver = (b + m) - ((UnitLevel("player") or 80) * 5)
        end
        local miss = math.max(0, 5.0 - 0.6 + defOver * 0.04)
        local total = dodge + parry + block + miss
        C("Avoidance", total, R.UNCRUSHABLE_PCT, "%.1f%%", DIM .. string.format("(%.0fD/%.0fP/%.0fB/%.0fM)|r", dodge, parry, block, miss))
    end
    if sel.critImmune then
        local resilPct = GetCombatRatingBonus(R.CR_RESILIENCE) or 0
        local defOver = 0
        if UnitDefense then
            local b, m = UnitDefense("player")
            defOver = math.max(0, (b + m) - ((UnitLevel("player") or 80) * 5))
        end
        local defCritReduce = defOver * 0.04
        local sotf = GetSotFRank() * 1.0 -- 1%/2%/3% from talent
        local totalReduce = resilPct + defCritReduce + sotf
        local cap = R.BOSS_CRIT_PCT
        local extra = DIM .. string.format("(%.1fRes/%.1fDef", resilPct, defCritReduce)
        if sotf > 0 then extra = extra .. string.format("/%.0fSotF", sotf) end
        extra = extra .. ")|r"
        C("Crit Immunity", totalReduce, cap, "%.2f%%", extra)
    end
    if sel.ehp then
        local hp = UnitHealthMax("player") or 0
        local _, armor = UnitArmor("player"); armor = armor or 0
        local dodge = GetDodgeChance() or 0
        local parry = GetParryChance() or 0
        local defOver = 0
        if UnitDefense then
            local b, m = UnitDefense("player")
            defOver = (b + m) - ((UnitLevel("player") or 80) * 5)
        end
        local miss = math.max(0, 5.0 - 0.6 + defOver * 0.04)
        local avoid = (dodge + parry + miss) / 100
        local _, ehp = addon:CalculateEHP(hp, armor, avoid)
        table.insert(lines, GOLD .. "EHP|r  " .. WHT .. string.format("%.0f", ehp) .. "|r")
    end

    if #lines == 0 then return nil end
    return table.concat(lines, "\n") .. "\n"
end

-- ============================================================================
-- STAT OVERVIEW (role-based fallback when no custom stats are selected)
-- ============================================================================
local function BuildStats(role, color, mobLevel)
    local lines = {}
    local function L(label, val)
        table.insert(lines, string.format("|cff%s%s|r  %s%s|r", color, label, WHT, val))
    end

    if role == "melee_dps" then
        local b, p, n = UnitAttackPower("player"); local ap = b + p + n
        L("Attack Power", tostring(ap))
        L("Strength",     tostring(UnitStat("player", 1) or 0))
        L("Agility",      tostring(UnitStat("player", 2) or 0))
        L("Crit",         string.format("%.2f%%", GetCritChance() or 0))
        local hr = GetCombatRating(R.CR_HASTE_MELEE) or 0
        L("Haste",        string.format("%.2f%%  %s(%d)|r", GetCombatRatingBonus(R.CR_HASTE_MELEE) or 0, DIM, hr))

    elseif role == "ranged_dps" then
        local b, p, n
        if UnitRangedAttackPower then b, p, n = UnitRangedAttackPower("player")
        else b, p, n = UnitAttackPower("player") end
        L("Attack Power", tostring((b or 0)+(p or 0)+(n or 0)))
        L("Agility",      tostring(UnitStat("player", 2) or 0))
        L("Crit",         string.format("%.2f%%", GetRangedCritChance and GetRangedCritChance() or (GetCritChance() or 0)))
        local hr = GetCombatRating(R.CR_HASTE_MELEE) or 0
        L("Haste",        string.format("%.2f%%  %s(%d)|r", GetCombatRatingBonus(R.CR_HASTE_MELEE) or 0, DIM, hr))

    elseif role == "caster_dps" then
        L("Spell Power",  tostring(GetSpellBonusDamage and GetSpellBonusDamage(2) or 0))
        L("Intellect",    tostring(UnitStat("player", 4) or 0))
        L("Mana",         tostring(UnitPowerMax("player", 0) or 0))
        L("Spell Crit",   string.format("%.2f%%", GetSpellCritChance and GetSpellCritChance(2) or 0))
        local hr = GetCombatRating(R.CR_HASTE_SPELL) or 0
        L("Haste",        string.format("%.2f%%  %s(%d)|r", GetCombatRatingBonus(R.CR_HASTE_SPELL) or 0, DIM, hr))

    elseif role == "healer" then
        L("Heal Power",   tostring(GetSpellBonusHealing and GetSpellBonusHealing() or 0))
        L("Spell Power",  tostring(GetSpellBonusDamage and GetSpellBonusDamage(2) or 0))
        L("Intellect",    tostring(UnitStat("player", 4) or 0))
        L("Spirit",       tostring(UnitStat("player", 5) or 0))
        L("Mana",         tostring(UnitPowerMax("player", 0) or 0))
        local _, cmr = 0, 0
        if GetManaRegen then _, cmr = GetManaRegen() end
        L("MP5 (cast)",   string.format("%.0f", (cmr or 0) * 5))
        L("Spell Crit",   string.format("%.2f%%", GetSpellCritChance and GetSpellCritChance(2) or 0))
        local hr = GetCombatRating(R.CR_HASTE_SPELL) or 0
        L("Haste",        string.format("%.2f%%  %s(%d)|r", GetCombatRatingBonus(R.CR_HASTE_SPELL) or 0, DIM, hr))

    elseif role == "tank" then
        local function DefInfo()
            if not UnitDefense then return 350, 0 end
            local b, m = UnitDefense("player"); local td = b + m
            return td, td - (UnitLevel("player") * 5)
        end
        local dodge = GetDodgeChance() or 0
        local parry = GetParryChance() or 0
        local block = GetBlockChance() or 0
        local _, defOver = DefInfo()
        local miss  = math.max(0, 5.0 - 0.6 + defOver * 0.04)
        local avoid = dodge + parry + miss
        local _, armor = UnitArmor("player")
        -- WotLK armor constant for attacker level >= 60: 467.5*L - 22167.5
        local armorDR = math.min(75, (armor / (armor + (467.5 * mobLevel - 22167.5))) * 100)
        local hp = UnitHealthMax("player") or 0
        local _, ehp = addon:CalculateEHP(hp, armor or 0, avoid / 100)

        L("Avoidance", string.format("%.1f%%  %s(%.0fD / %.0fP / %.0fM)|r", avoid, DIM, dodge, parry, miss))
        L("Armor",     string.format("%d  %s(%.1f%% DR)|r", armor, DIM, armorDR))
        L("Block",     string.format("%.1f%%", block))
        L("HP",        tostring(hp))
        table.insert(lines, GOLD .. "EHP|r  " .. WHT .. string.format("%.0f", ehp) .. "|r")

    elseif role == "tank_barrier" then
        local hp = UnitHealthMax("player") or 0
        local _, armor = UnitArmor("player"); armor = armor or 0
        local armorDR = math.min(75, (armor / (armor + (467.5 * mobLevel - 22167.5))) * 100)
        L("Intellect",    tostring(UnitStat("player", 4) or 0))
        L("Spell Power",  tostring(GetSpellBonusDamage and GetSpellBonusDamage(2) or 0))
        L("Mana",         tostring(UnitPowerMax("player", 0) or 0))
        L("HP",           tostring(hp))
        L("Armor",        string.format("%d  %s(%.1f%% DR)|r", armor, DIM, armorDR))

    elseif role == "tank_druid" then
        local hp = UnitHealthMax("player") or 0
        local _, armor = UnitArmor("player"); armor = armor or 0
        local dr = math.min(75, ArmorDR(armor) * 100)
        local dodge = GetDodgeChance() or 0
        local defOver = 0
        if UnitDefense then
            local b, m = UnitDefense("player")
            defOver = (b + m) - ((UnitLevel("player") or 80) * 5)
        end
        local miss  = math.max(0, 5.0 - 0.6 + defOver * 0.04)
        local avoid = dodge + miss
        local sotf  = GetSotFRank()
        local _, ehp = addon:CalculateEHP(hp, armor, avoid / 100)

        L("HP",        tostring(hp))
        L("Armor",     string.format("%d  %s(%.1f%% DR)|r", armor, DIM, dr))
        L("Avoidance", string.format("%.1f%%  %s(%.0fD / %.0fM)|r", avoid, DIM, dodge, miss))
        L("SotF",      string.format("%s%d/3|r  %s(%.1f%% crit red)|r", sotf > 0 and GRN or RED, sotf, DIM, sotf * 1.0))
        table.insert(lines, GOLD .. "EHP|r  " .. WHT .. string.format("%.0f", ehp) .. "|r")
    end

    if #lines == 0 then return "" end
    return table.concat(lines, "\n") .. "\n"
end

-- ============================================================================
-- WEIGHTS FOOTER
-- ============================================================================
local function BuildWeightsFooter(weights)
    local parts = {}
    for stat, w in pairs(weights) do
        if w > 0 then
            table.insert(parts, string.format("%s:%.1f", addon.STAT_LABELS[stat] or stat, w))
        end
    end
    if #parts == 0 then return "" end
    return "\n" .. DIM .. "Weights: " .. table.concat(parts, "  ") .. "|r"
end

-- ============================================================================
-- MAIN UPDATE
-- ============================================================================
function addon:UpdateSpecHUD()
    if not frame:IsShown() then return end

    local specData = addon:GetActiveSpecData()
    if not specData then
        statsText:SetText(DIM .. "Select a spec to display stats.|r")
        titleText:SetText(GOLD .. "CGO|r")
        return
    end

    local role  = specData.role
    local _, cls = UnitClass("player")
    local color = addon.CLASS_COLORS[cls] or "FFFFFF"
    local mobLevel = (UnitLevel("player") or 80) + 3

    titleText:SetText(string.format("|cff%s%s|r", color, specData.name))

    local caps = CharacterGearOptimizerDB and CharacterGearOptimizerDB.capPriorities or {}
    local pvp  = caps.pvpMode

    local text = BuildDurability()
    if pvp then
        text = text .. GOLD .. "PvP Mode|r  " .. DIM .. string.format("vs Level %d Player", (UnitLevel("player") or 80)) .. "|r\n\n"
    else
        text = text .. DIM .. string.format("vs Level %d Boss (+3)", mobLevel) .. "|r\n\n"
    end

    -- Breakpoints (only selected caps)
    local bpText = BuildBreakpoints(role)
    if bpText ~= "" then
        text = text .. bpText .. "\n" .. GOLD .. "Spec Info|r" .. "\n"
    end

    -- Stats overview (custom checkboxes take priority over role-based)
    local customText = BuildCustomStats(color, mobLevel)
    if customText then
        text = text .. customText
    else
        text = text .. BuildStats(role, color, mobLevel)
    end

    -- Weights footer (skip for tanks)
    if role ~= "tank" and role ~= "tank_druid" and role ~= "tank_barrier" and specData.weights then
        text = text .. BuildWeightsFooter(specData.weights)
    end

    statsText:SetText(text)

    -- Resize scroll content to fit text, reset scroll
    local h = statsText:GetStringHeight() or 200
    scrollContent:SetHeight(h + 8)

    -- Auto-size frame: cap at 400px, use scroll if taller
    local maxH = 400
    local desiredH = h + 40
    frame:SetHeight(math.min(desiredH, maxH))

    -- Reset scroll position on update
    scrollOffset = 0
    scrollContent:SetPoint("TOPLEFT", scrollClip, "TOPLEFT", 0, 0)
end

-- ============================================================================
-- EVENTS
-- ============================================================================
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("UNIT_STATS")
frame:RegisterEvent("UNIT_AURA")
frame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
frame:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
frame:RegisterEvent("PLAYER_LEVEL_UP")
frame:RegisterEvent("COMBAT_RATING_UPDATE")
frame:RegisterEvent("PLAYER_TALENT_UPDATE")
frame:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
frame:RegisterEvent("CHARACTER_POINTS_CHANGED")
frame:RegisterEvent("UNIT_MAXHEALTH")
frame:RegisterEvent("UPDATE_INVENTORY_DURABILITY")
if UnitDefense then pcall(frame.RegisterEvent, frame, "UNIT_DEFENSE") end

frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
        local db = CharacterGearOptimizerDB and CharacterGearOptimizerDB.specHUD
        if db and db.point then
            self:ClearAllPoints()
            self:SetPoint(db.point, UIParent, db.relPoint, db.x, db.y)
        end
        if CharacterGearOptimizerDB and CharacterGearOptimizerDB.specHUDHidden then
            self:Hide()
        else
            self:Show()
        end
        addon:UpdateSpecHUD()
    elseif arg1 == "player" or arg1 == nil then
        addon:UpdateSpecHUD()
    end
end)

frame:SetScript("OnShow", function()
    addon:UpdateSpecHUD()
end)
