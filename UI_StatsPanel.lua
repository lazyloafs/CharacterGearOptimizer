-- ============================================================================
-- UI_StatsPanel.lua
-- Scrollable character-stats panel anchored to the right of CharacterGearOptimizerFrame.
-- Shows live Primary / Melee / Ranged / Spell / Defence statistics with
-- rating breakdowns, updated automatically on relevant game events.
-- Modelled after DejaClassicStats.
-- ============================================================================
local addonName, addon = ...

local STATS_WIDTH   = 200
local LINE_HEIGHT   = 15
local HEADER_HEIGHT = 18
local SECTION_GAP   = 6
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

local statsPanel, statsClip, statsContent
local statWidgets   = {}
local scrollOffset  = 0

local RESISTANCE_ROWS = {
    { label = "Arcane", key = "arcane_res", school = 6 },
    { label = "Fire",   key = "fire_res",   school = 2 },
    { label = "Frost",  key = "frost_res",  school = 4 },
    { label = "Nature", key = "nature_res", school = 3 },
    { label = "Shadow", key = "shadow_res", school = 5 },
    { label = "Holy",   key = "holy_res",   school = 1 },
}

-- ============================================================================
-- BUILD THE PANEL  (called once after CharacterGearOptimizerFrame exists)
-- ============================================================================
local function BuildStatsPanel()
    local parent = _G["CharacterGearOptimizerFrame"]
    if not parent or statsPanel then return end

    -- Main frame — child of CharacterGearOptimizerFrame so it auto-shows / hides
    statsPanel = CreateFrame("Frame", "CharacterGearOptimizerStatsPanel", parent,
                              BACKDROP_TEMPLATE)
    statsPanel:SetSize(STATS_WIDTH, parent:GetHeight())
    statsPanel:SetPoint("TOPLEFT", parent, "TOPRIGHT", -2, 0)
    statsPanel:SetFrameStrata("DIALOG")
    ApplyBackdrop(statsPanel, {
        bgFile   = "Interface/DialogFrame/UI-DialogBox-Background",
        edgeFile = "Interface/DialogFrame/UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    }, { 0.05, 0.02, 0.02, 1.0 }, { 0.55, 0.45, 0.25, 1 })
    statsPanel:EnableMouse(true)

    -- Title
    local titleFS = statsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleFS:SetPoint("TOP", statsPanel, "TOP", 0, -10)
    titleFS:SetText("|cFFFFD700Character Stats|r")

    -- Real 3.3.5 ScrollFrame: SetClipsChildren is unavailable on Ascension,
    -- so a plain Frame allowed the stat rows to draw below the panel.
    statsClip = CreateFrame("ScrollFrame", "CGOStatsScrollFrame", statsPanel, "UIPanelScrollFrameTemplate")
    statsClip:SetPoint("TOPLEFT", statsPanel, "TOPLEFT", 6, -28)
    statsClip:SetPoint("BOTTOMRIGHT", statsPanel, "BOTTOMRIGHT", -27, 8)
    statsClip:EnableMouseWheel(true)

    statsContent = CreateFrame("Frame", "CGOStatsScrollContent", statsClip)
    statsContent:SetWidth(STATS_WIDTH - 35)
    statsContent:SetHeight(1)
    statsClip:SetScrollChild(statsContent)

    local function SetStatsScroll(offset)
        local maxScroll = math.max(0, statsContent:GetHeight() - statsClip:GetHeight())
        scrollOffset = math.max(0, math.min(maxScroll, offset or 0))
        statsClip:SetVerticalScroll(scrollOffset)
    end

    statsClip:SetScript("OnMouseWheel", function(_, delta)
        SetStatsScroll(scrollOffset - delta * (LINE_HEIGHT * 3))
    end)

    statsClip:SetScript("OnSizeChanged", function()
        SetStatsScroll(scrollOffset)
    end)

    -- -----------------------------------------------------------------
    -- Layout helpers
    -- -----------------------------------------------------------------
    local y = 0

    local function AddHeader(text)
        local bg = CreateFrame("Frame", nil, statsContent, BACKDROP_TEMPLATE)
        bg:SetHeight(HEADER_HEIGHT)
        bg:SetPoint("TOPLEFT",  statsContent, "TOPLEFT",  0, -y)
        bg:SetPoint("TOPRIGHT", statsContent, "TOPRIGHT", 0, -y)
        ApplyBackdrop(bg, {
            bgFile = "Interface/Buttons/WHITE8x8",
            edgeFile = "Interface/DialogFrame/UI-DialogBox-Border",
            tile = false,
            edgeSize = 8,
            insets = { left = 2, right = 2, top = 2, bottom = 2 },
        }, { 0.05, 0.02, 0.02, 0.88 }, { 0.55, 0.45, 0.25, 1 })

        local fill = bg:CreateTexture(nil, "BACKGROUND")
        fill:SetPoint("TOPLEFT", 3, -3)
        fill:SetPoint("BOTTOMRIGHT", -3, 3)
        if fill.SetColorTexture then fill:SetColorTexture(0.14, 0.05, 0.03, 0.92) else fill:SetTexture(0.14, 0.05, 0.03, 0.92) end

        local highlight = bg:CreateTexture(nil, "BORDER")
        highlight:SetPoint("TOPLEFT", 4, -3)
        highlight:SetPoint("TOPRIGHT", -4, -3)
        highlight:SetHeight(1)
        if highlight.SetColorTexture then highlight:SetColorTexture(0.95, 0.82, 0.35, 0.45) else highlight:SetTexture(0.95, 0.82, 0.35, 0.45) end

        local shadow = bg:CreateTexture(nil, "BORDER")
        shadow:SetPoint("BOTTOMLEFT", 4, 3)
        shadow:SetPoint("BOTTOMRIGHT", -4, 3)
        shadow:SetHeight(1)
        if shadow.SetColorTexture then shadow:SetColorTexture(0, 0, 0, 0.45) else shadow:SetTexture(0, 0, 0, 0.45) end

        local fs = bg:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetAllPoints()
        fs:SetText("|cFFFFD700" .. text .. "|r")
        fs:SetJustifyH("CENTER")
        fs:SetShadowOffset(1, -1)
        fs:SetShadowColor(0, 0, 0, 0.9)
        y = y + HEADER_HEIGHT
    end

    local function AddStat(label, key)
        local line = CreateFrame("Frame", nil, statsContent)
        line:SetHeight(LINE_HEIGHT)
        line:SetPoint("TOPLEFT",  statsContent, "TOPLEFT",  0, -y)
        line:SetPoint("TOPRIGHT", statsContent, "TOPRIGHT", 0, -y)

        line.label = line:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        line.label:SetPoint("LEFT", 4, 0)
        line.label:SetText("|cFFCCCCCC" .. label .. "|r")

        line.value = line:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        line.value:SetPoint("RIGHT", -4, 0)
        line.value:SetJustifyH("RIGHT")

        -- hover highlight
        local hl = line:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        if hl.SetColorTexture then hl:SetColorTexture(0.55, 0.45, 0.25, 0.15) else hl:SetTexture(0.55, 0.45, 0.25, 0.15) end

        -- tooltip
        line:EnableMouse(true)
        line:SetScript("OnEnter", function(self)
            if self.tipTitle then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine(self.tipTitle, 1, 0.82, 0)
                if self.tipLines then
                    for _, tl in ipairs(self.tipLines) do
                        GameTooltip:AddLine(tl, 1, 1, 1, true)
                    end
                end
                GameTooltip:Show()
            end
        end)
        line:SetScript("OnLeave", function() GameTooltip:Hide() end)

        statWidgets[key] = line
        y = y + LINE_HEIGHT
    end

    local function AddGap() y = y + SECTION_GAP end

    -- -----------------------------------------------------------------
    -- Sections
    -- -----------------------------------------------------------------
    AddHeader("Primary")
    AddStat("Strength",  "str")
    AddStat("Agility",   "agi")
    AddStat("Stamina",   "sta")
    AddStat("Intellect", "int")
    AddStat("Spirit",    "spi")
    AddStat("Armor",     "armor")
    AddGap()

    AddHeader("Melee")
    AddStat("Attack Power", "melee_ap")
    AddStat("MH Damage",    "mh_dmg")
    AddStat("MH DPS",       "mh_dps")
    AddStat("OH Damage",    "oh_dmg")
    AddStat("Crit",         "melee_crit")
    AddStat("Hit",          "melee_hit")
    AddStat("Haste",        "melee_haste")
    AddStat("Expertise",    "expertise")
    AddGap()

    AddHeader("Ranged")
    AddStat("Ranged AP",  "ranged_ap")
    AddStat("Crit",       "ranged_crit")
    AddStat("Hit",        "ranged_hit")
    AddStat("Haste",      "ranged_haste")
    AddGap()

    AddHeader("Spell")
    AddStat("Spell Damage", "spell_dmg")
    AddStat("+ Healing",    "healing")
    AddStat("Crit",         "spell_crit")
    AddStat("Hit",          "spell_hit")
    AddStat("Haste",        "spell_haste")
    AddStat("MP5 (casting)","mp5")
    AddGap()

    AddHeader("Defense")
    AddStat("Defense",     "defense")
    AddStat("Dodge",       "dodge")
    AddStat("Parry",       "parry")
    AddStat("Block",       "block")
    AddStat("Block Value", "block_val")
    AddStat("Resilience",  "resil")
    AddStat("Avoidance",   "avoidance")
    AddGap()

    AddHeader("Resistances")
    for _, resistance in ipairs(RESISTANCE_ROWS) do
        AddStat(resistance.label, resistance.key)
    end

    statsContent:SetHeight(y + 10)
    addon.statsPanel = statsPanel
end

-- ============================================================================
-- UPDATE ALL STAT VALUES
-- ============================================================================
local function UpdateStats_Inner()
    local w = statWidgets
    local fmt = format

    ---------- PRIMARY ----------
    for idx, key in ipairs({"str","agi","sta","int","spi"}) do
        local line = w[key]
        if line then
            local base, eff, pos, neg = UnitStat("player", idx)
            line.value:SetText(fmt("%.0f", eff))
            line.tipTitle = fmt("%s %d", line.label:GetText():gsub("|c%x%x%x%x%x%x%x%x",""):gsub("|r",""), eff)
            local tips = {}
            if pos > 0 then tips[#tips+1] = fmt("+%d from buffs", pos) end
            if neg < 0 then tips[#tips+1] = fmt("%d from debuffs", neg) end
            if idx == 1 then
                local ap = GetAttackPowerForStat and GetAttackPowerForStat(1, eff) or 0
                tips[#tips+1] = fmt("Adds %d Attack Power", ap)
            elseif idx == 2 then
                tips[#tips+1] = fmt("%.0f Armor from Agility", eff * 2)
            elseif idx == 3 then
                tips[#tips+1] = fmt("Adds ~%d Health", 20 + math.max(0, eff - 20) * 10)
            elseif idx == 4 then
                tips[#tips+1] = fmt("Adds ~%d Mana", 20 + math.max(0, eff - 20) * 15)
            end
            line.tipLines = tips
        end
    end

    if w.armor then
        local _, eff = UnitArmor("player")
        w.armor.value:SetText(fmt("%.0f", eff))
        local reduction = 0
        if PaperDollFrame_GetArmorReduction then
            reduction = PaperDollFrame_GetArmorReduction(eff, UnitLevel("player"))
        end
        w.armor.tipTitle = fmt("Armor %d", eff)
        w.armor.tipLines = { fmt("%.1f%% Physical Damage Reduction", reduction) }
    end

    ---------- MELEE ----------
    if w.melee_ap then
        local base, pos, neg = UnitAttackPower("player")
        local total = base + pos + neg
        w.melee_ap.value:SetText(fmt("%.0f", total))
        w.melee_ap.tipTitle = fmt("Attack Power %d", total)
        w.melee_ap.tipLines = { fmt("Adds %.1f DPS", total / 14) }
    end
    if w.mh_dmg then
        local lo, hi = UnitDamage("player")
        local speed = UnitAttackSpeed("player")
        w.mh_dmg.value:SetText(fmt("%.0f - %.0f", lo, hi))
        w.mh_dmg.tipTitle = "Main Hand Damage"
        w.mh_dmg.tipLines = { fmt("Speed: %.2f", speed or 0) }
    end
    if w.mh_dps then
        local lo, hi, _, _, pP, pN, pct = UnitDamage("player")
        local speed = UnitAttackSpeed("player")
        if speed and speed > 0 then
            w.mh_dps.value:SetText(fmt("%.1f", (lo + hi) / 2 / speed))
        else
            w.mh_dps.value:SetText("0")
        end
        w.mh_dps.tipTitle = "Main Hand DPS"
        w.mh_dps.tipLines = {}
    end
    if w.oh_dmg then
        local _, ohSpeed = UnitAttackSpeed("player")
        if ohSpeed then
            local _, _, lo, hi = UnitDamage("player")
            w.oh_dmg.value:SetText(fmt("%.0f - %.0f", lo, hi))
        else
            w.oh_dmg.value:SetText("N/A")
        end
        w.oh_dmg.tipTitle = "Off Hand Damage"
        w.oh_dmg.tipLines = {}
    end
    if w.melee_crit then
        local chance = GetCritChance()
        local rating = GetCombatRating(CR_CRIT_MELEE)
        local bonus  = GetCombatRatingBonus(CR_CRIT_MELEE)
        w.melee_crit.value:SetText(fmt("(%d) %.2f%%", rating, chance))
        w.melee_crit.tipTitle = fmt("Melee Crit %.2f%%", chance)
        w.melee_crit.tipLines = { fmt("%d Rating = %.2f%% Crit", rating, bonus) }
    end
    if w.melee_hit then
        local rating = GetCombatRating(CR_HIT_MELEE)
        local bonus  = addon:GetTotalHitChance(CR_HIT_MELEE)
        w.melee_hit.value:SetText(fmt("(%d) %.2f%%", rating, bonus))
        w.melee_hit.tipTitle = fmt("Melee Hit %.2f%%", bonus)
        w.melee_hit.tipLines = { fmt("%d Rating = %.2f%% Hit", rating, bonus),
                                  "8% needed vs +3 boss" }
    end
    if w.melee_haste then
        local rating = GetCombatRating(CR_HASTE_MELEE)
        local bonus  = GetCombatRatingBonus(CR_HASTE_MELEE)
        w.melee_haste.value:SetText(fmt("(%d) %.2f%%", rating, bonus))
        w.melee_haste.tipTitle = fmt("Melee Haste %.2f%%", bonus)
        w.melee_haste.tipLines = { fmt("%d Rating = %.2f%% Haste", rating, bonus) }
    end
    if w.expertise then
        if GetExpertise then
            local exp, ohExp = GetExpertise()
            local rating = GetCombatRating(CR_EXPERTISE)
            local pct, ohPct = 0, 0
            if GetExpertisePercent then pct, ohPct = GetExpertisePercent() end
            w.expertise.value:SetText(fmt("(%d) %.2f%%", exp, pct))
            w.expertise.tipTitle = fmt("Expertise %d (%.2f%%)", exp, pct)
            w.expertise.tipLines = { fmt("%d Rating", rating),
                                      "26 Expertise = 6.5% dodge reduction" }
        else
            w.expertise.value:SetText("N/A")
        end
    end

    ---------- RANGED ----------
    if w.ranged_ap then
        local base, pos, neg = UnitRangedAttackPower("player")
        local total = base + pos + neg
        w.ranged_ap.value:SetText(fmt("%.0f", total))
        w.ranged_ap.tipTitle = fmt("Ranged Attack Power %d", total)
        w.ranged_ap.tipLines = { fmt("Adds %.1f DPS", total / 14) }
    end
    if w.ranged_crit then
        local chance = GetRangedCritChance()
        local rating = GetCombatRating(CR_CRIT_RANGED)
        local bonus  = GetCombatRatingBonus(CR_CRIT_RANGED)
        w.ranged_crit.value:SetText(fmt("(%d) %.2f%%", rating, chance))
        w.ranged_crit.tipTitle = fmt("Ranged Crit %.2f%%", chance)
        w.ranged_crit.tipLines = { fmt("%d Rating = %.2f%% Crit", rating, bonus) }
    end
    if w.ranged_hit then
        local rating = GetCombatRating(CR_HIT_RANGED)
        local bonus  = addon:GetTotalHitChance(CR_HIT_RANGED)
        w.ranged_hit.value:SetText(fmt("(%d) %.2f%%", rating, bonus))
        w.ranged_hit.tipTitle = fmt("Ranged Hit %.2f%%", bonus)
        w.ranged_hit.tipLines = { fmt("%d Rating = %.2f%% Hit", rating, bonus) }
    end
    if w.ranged_haste then
        local rating = GetCombatRating(CR_HASTE_RANGED)
        local bonus  = GetCombatRatingBonus(CR_HASTE_RANGED)
        w.ranged_haste.value:SetText(fmt("(%d) %.2f%%", rating, bonus))
        w.ranged_haste.tipTitle = fmt("Ranged Haste %.2f%%", bonus)
        w.ranged_haste.tipLines = { fmt("%d Rating = %.2f%% Haste", rating, bonus) }
    end

    ---------- SPELL ----------
    if w.spell_dmg then
        local maxDmg = 0
        for i = 2, 7 do
            local d = GetSpellBonusDamage(i)
            if d and d > maxDmg then maxDmg = d end
        end
        w.spell_dmg.value:SetText(fmt("%.0f", maxDmg))
        w.spell_dmg.tipTitle = fmt("Spell Damage %d", maxDmg)
        local schools = {"Physical","Holy","Fire","Nature","Frost","Shadow","Arcane"}
        local tips = {}
        for i = 2, 7 do tips[#tips+1] = fmt("%s: %d", schools[i], GetSpellBonusDamage(i) or 0) end
        w.spell_dmg.tipLines = tips
    end
    if w.healing then
        local h = GetSpellBonusHealing() or 0
        w.healing.value:SetText(fmt("%.0f", h))
        w.healing.tipTitle = fmt("+ Healing %d", h)
        w.healing.tipLines = {}
    end
    if w.spell_crit then
        local minCrit = 100
        for i = 2, 7 do
            local c = GetSpellCritChance(i)
            if c and c < minCrit then minCrit = c end
        end
        local rating = GetCombatRating(CR_CRIT_SPELL)
        local bonus  = GetCombatRatingBonus(CR_CRIT_SPELL)
        w.spell_crit.value:SetText(fmt("(%d) %.2f%%", rating, minCrit))
        w.spell_crit.tipTitle = fmt("Spell Crit %.2f%%", minCrit)
        w.spell_crit.tipLines = { fmt("%d Rating = %.2f%% Crit", rating, bonus) }
    end
    if w.spell_hit then
        local rating = GetCombatRating(CR_HIT_SPELL)
        local bonus  = addon:GetTotalHitChance(CR_HIT_SPELL)
        w.spell_hit.value:SetText(fmt("(%d) %.2f%%", rating, bonus))
        w.spell_hit.tipTitle = fmt("Spell Hit %.2f%%", bonus)
        w.spell_hit.tipLines = { fmt("%d Rating = %.2f%% Hit", rating, bonus),
                                  "17% needed vs +3 boss" }
    end
    if w.spell_haste then
        local rating = GetCombatRating(CR_HASTE_SPELL)
        local bonus  = GetCombatRatingBonus(CR_HASTE_SPELL)
        w.spell_haste.value:SetText(fmt("(%d) %.2f%%", rating, bonus))
        w.spell_haste.tipTitle = fmt("Spell Haste %.2f%%", bonus)
        w.spell_haste.tipLines = { fmt("%d Rating = %.2f%% Haste", rating, bonus) }
    end
    if w.mp5 then
        local _, casting = GetManaRegen()
        local mp5 = (casting or 0) * 5
        w.mp5.value:SetText(fmt("%.1f", mp5))
        w.mp5.tipTitle = fmt("MP5 (casting) %.1f", mp5)
        w.mp5.tipLines = {}
    end

    ---------- DEFENSE ----------
    if w.defense then
        if UnitDefense then
            local base, mod = UnitDefense("player")
            local total = base + mod
            local rating = GetCombatRating(CR_DEFENSE_SKILL)
            local rBonus = GetCombatRatingBonus(CR_DEFENSE_SKILL)
            w.defense.value:SetText(fmt("%.0f (%d)", total, rating))
            w.defense.tipTitle = fmt("Defense %.0f", total)
            w.defense.tipLines = { fmt("Base: %d", base),
                                    fmt("%d Rating = %.1f Defense", rating, rBonus) }
        else
            w.defense.value:SetText("N/A")
        end
    end
    if w.dodge then
        local chance = GetDodgeChance()
        local rating = GetCombatRating(CR_DODGE)
        local bonus  = GetCombatRatingBonus(CR_DODGE)
        w.dodge.value:SetText(fmt("(%d) %.2f%%", rating, chance))
        w.dodge.tipTitle = fmt("Dodge %.2f%%", chance)
        w.dodge.tipLines = { fmt("%d Rating = %.2f%% Dodge", rating, bonus) }
    end
    if w.parry then
        local chance = GetParryChance()
        local rating = GetCombatRating(CR_PARRY)
        local bonus  = GetCombatRatingBonus(CR_PARRY)
        w.parry.value:SetText(fmt("(%d) %.2f%%", rating, chance))
        w.parry.tipTitle = fmt("Parry %.2f%%", chance)
        w.parry.tipLines = { fmt("%d Rating = %.2f%% Parry", rating, bonus) }
    end
    if w.block then
        local chance = GetBlockChance()
        local rating = GetCombatRating(CR_BLOCK)
        local bonus  = GetCombatRatingBonus(CR_BLOCK)
        w.block.value:SetText(fmt("(%d) %.2f%%", rating, chance))
        w.block.tipTitle = fmt("Block %.2f%%", chance)
        w.block.tipLines = { fmt("%d Rating = %.2f%% Block", rating, bonus) }
    end
    if w.block_val then
        local bv = GetShieldBlock and GetShieldBlock() or 0
        w.block_val.value:SetText(fmt("%.0f", bv))
        w.block_val.tipTitle = fmt("Block Value %d", bv)
        w.block_val.tipLines = { "Damage blocked by your shield" }
    end
    if w.resil then
        -- 3.3.5: resilience = CR_CRIT_TAKEN_MELEE (15); CR_RESILIENCE_CRIT_TAKEN doesn't exist
        local crResil = CR_RESILIENCE_CRIT_TAKEN or CR_CRIT_TAKEN_MELEE or 15
        local rating = GetCombatRating(crResil)
        local bonus  = GetCombatRatingBonus(crResil)
        w.resil.value:SetText(fmt("(%d) %.2f%%", rating, bonus))
        w.resil.tipTitle = fmt("Resilience %d", rating)
        w.resil.tipLines = { fmt("Reduces crit chance by %.2f%%", bonus),
                              fmt("Reduces crit damage by %.2f%%", math.min(bonus * 2, 25)) }
    end
    if w.avoidance then
        local defBase, defMod = 350, 0
        if UnitDefense then defBase, defMod = UnitDefense("player") end
        local totalDef     = defBase + defMod
        local playerLvl    = UnitLevel("player")
        local atkSkill     = (playerLvl + 3) * 5
        local missPct      = 5 - (atkSkill - totalDef) * 0.04
        local dodgePct     = GetDodgeChance()
        local parryPct     = GetParryChance()
        local blockPct     = GetBlockChance()
        local total        = missPct + dodgePct + parryPct + blockPct
        local crushGap     = 102.4 - total
        w.avoidance.value:SetText(fmt("%.2f%%", total))
        w.avoidance.tipTitle = fmt("Total Avoidance %.2f%%", total)
        w.avoidance.tipLines = {
            fmt("Miss: %.2f%%",  missPct),
            fmt("Dodge: %.2f%%", dodgePct),
            fmt("Parry: %.2f%%", parryPct),
            fmt("Block: %.2f%%", blockPct),
            fmt("Crushing gap: %.2f%%", math.max(0, crushGap)),
        }
    end

    ---------- RESISTANCES ----------
    if UnitResistance then
        for _, resistance in ipairs(RESISTANCE_ROWS) do
            local line = w[resistance.key]
            if line then
                local base, effective, positive, negative = UnitResistance("player", resistance.school)
                effective = effective or base or 0
                base = base or 0
                positive = positive or 0
                negative = negative or 0

                line.value:SetText(fmt("%.0f", effective))
                line.tipTitle = fmt("%s Resistance %d", resistance.label, effective)

                local tips = { fmt("Base: %d", base) }
                if positive > 0 then
                    tips[#tips + 1] = fmt("+%d from gear and buffs", positive)
                end
                if negative < 0 then
                    tips[#tips + 1] = fmt("%d from debuffs", negative)
                end
                line.tipLines = tips
            end
        end
    end
end

local function UpdateStats()
    if not statsPanel or not statsPanel:IsVisible() then return end
    local ok, err = pcall(UpdateStats_Inner)
    if not ok then
        -- Silently absorb errors from missing TBC APIs
    end
end

-- ============================================================================
-- EVENT-DRIVEN REFRESH
-- ============================================================================
local eventFrame = CreateFrame("Frame")

-- Safely register events — an invalid event name in Classic throws an error
local safeEvents = {
    "PLAYER_LOGIN",
    "UNIT_STATS",
    "UNIT_RESISTANCES",
    "UNIT_AURA",
    "PLAYER_EQUIPMENT_CHANGED",
    "COMBAT_RATING_UPDATE",
    "UNIT_ATTACK_POWER",
    "UNIT_RANGESPEED",
    "PLAYER_DAMAGE_DONE_MODS",
    "UPDATE_SHAPESHIFT_FORM",
    "UNIT_ATTACK",
}
for _, ev in ipairs(safeEvents) do
    pcall(eventFrame.RegisterEvent, eventFrame, ev)
end

eventFrame:SetScript("OnEvent", function(_, event, arg1)
    if event == "PLAYER_LOGIN" then
        BuildStatsPanel()
        UpdateStats()
        return
    end
    -- Filter unit-specific events to "player"
    if arg1 and arg1 ~= "player" and
       (event == "UNIT_STATS" or event == "UNIT_RESISTANCES" or event == "UNIT_AURA"
        or event == "UNIT_ATTACK_POWER" or event == "UNIT_ATTACK") then
        return
    end
    UpdateStats()
end)

-- Also refresh whenever the main frame shows
local function HookMainFrame()
    local f = _G["CharacterGearOptimizerFrame"]
    if not f then return end
    f:HookScript("OnShow", function()
        if not statsPanel then BuildStatsPanel() end
        if statsPanel then
            statsPanel:Show()
            UpdateStats()
        end
    end)
end

-- Build immediately — CharacterGearOptimizerFrame was created by UI_Panel.lua (loaded before us)
BuildStatsPanel()
HookMainFrame()
