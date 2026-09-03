# CharacterGearOptimizer - Backlog & Milestones

## Milestones & Status

### Phase 1: Core Engine & Multi-Version Architecture
- [x] Multi-TOC and Multi-Lua architecture (`_Mainline.toc`, `_Vanilla.toc`, `_TBC.toc`, `_Wrath.toc`, `_Cata.toc`, `CharacterGearOptimizer.toc`)
- [x] Stat weight calculation engine supporting all classes and specializations
- [x] Dynamic gear scoring algorithm with item upgrade tracking
- [x] Clean forward-slash texture paths and `SetColorTexture` for solid fills
- [x] Zero `setmetatable` usage on frame objects (using `Mixin(frame, ...)`)

### Phase 2: In-Game UI & Options Panel
- [x] Options panel implementation in `Options.lua`
- [x] Retail (10.0+) Game Menu -> Options -> AddOns registration via `Settings.RegisterCanvasLayoutCategory` / `Settings.RegisterAddOnCategory`
- [x] Classic Game Menu -> Interface Options -> AddOns registration via `InterfaceOptions_AddCategory`
- [x] Interactive gear comparison panel (`UI_Panel.lua`, `UI_StatsPanel.lua`)
- [x] Minimap quick-access button with toggle menus

### Phase 3: Automation & Utility
- [x] Sellomatic vendor junk selling and auto-repair automation (`Sellomatic.lua`)
- [x] AutoRoller loot roll confirmation automation (`AutoRoller.lua`)
- [x] SpecHUD overlay for real-time stat visualization (`SpecHUD.lua`)
- [x] DevTool global inspection (`CharacterGearOptimizer` table)

### Phase 4: Future Enhancements
- [x] Pawn string import and export parser
- [x] Multi-set simulation and item upgrade prediction
- [x] Cloud sync profile integration

### Phase 5: Options UI Dropdown Controls & Optimization Preset Config
- [x] In-game Options UI dropdown selectors (Active Profile / Spec Selector, Auto-Roll Policy, Optimization Strategy) and comprehensive settings control in `Options.lua`

### Phase 6: Bug Fixes & Ascension-Legacy Cleanup (BugGrabber triage)
- [x] Fixed invented `AUTOEQUIP_BIND_CONFIRM` event registration in `EquipManager.lua` (real events only: `EQUIP_BIND_CONFIRM`, `EQUIP_BIND_TRADEABLE_CONFIRM`, `EQUIP_BIND_REFUNDABLE_CONFIRM`); this also fixed a downstream `SaveSet is not a function` error in `Sellomatic.lua` caused by the aborted chunk
- [x] Fixed `CloudSync.lua` infinite mutual recursion between `InitializeDatabase()` and `AutoSync()` (guaranteed stack overflow on login since `autoSync` defaults to true)
- [x] Fixed `Options.lua` nil-concat crash in `CreateSlider` (anonymous frames have no `:GetName()`; now given unique real names)
- [x] Fixed `Sellomatic.lua` nil checkbox index crash in `SaveCheckboxStates`/`LoadCheckboxStates` (checkboxes are created lazily on options-panel `OnShow`, but state load ran earlier on `ADDON_LOADED`)
- [x] Hid deprecated Spirit/MP5 stat rows on Mainline/Midnight in `UI_StatsPanel.lua` (completed version-gating started in a prior pass)
- [x] Fully removed PvP Power / PvE Power (Ascension private-server-only stats, no Blizzard equivalent on any client) from `Weights.lua`, `StatCalculations.lua`, `Scanner.lua`, `UI_Panel.lua`, and `Optimizer.lua`; legitimate PvP-vs-PvE cap-priority toggle (`pvpMode`, distinct Blizzard PvP hit/expertise/armor cap constants) was kept
