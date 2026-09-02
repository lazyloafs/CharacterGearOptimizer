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
- [ ] Cloud sync profile integration
