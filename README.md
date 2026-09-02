# CharacterGearOptimizer (CGO)

Multi-version dynamic gear optimization, stat weight evaluator, equipment set manager, and in-game HUD for World of Warcraft.

## Features
- **Multi-Version Compatibility**: Supports Retail (The War Within / Midnight), Classic Era (Season of Discovery), Burning Crusade Classic, Wrath of the Lich King Classic, and Cataclysm Classic.
- **Dynamic Stat Weights & Gear Optimizer**: Bag and equipped gear scoring using custom and preset spec weights.
- **In-Game Settings UI**: Full configuration panel registered under `Game Menu -> Options -> AddOns -> CharacterGearOptimizer` (supporting modern Settings API and legacy InterfaceOptions).
- **Spec HUD & Cap Tracker**: Floating HUD tracking combat ratings, soft/hard stat caps, and effective health pool (EHP).
- **Auto-Roller & Sell-o-matic**: Built-in loot rolling automation and merchant auto-vendor utilities.
- **DevTool & Debug Integration**: Live table inspection via `/cgo dev` or `DevTool:AddData(CharacterGearOptimizer, "CGO")`.

## Slash Commands
- `/cgo` - Open main optimizer panel
- `/cgo opt` or `/cgo config` - Open in-game AddOn Settings panel
- `/cgo hud` - Toggle floating Spec HUD
- `/cgo scan` - Force inventory and gear rescan
- `/cgo sets` - Open Equipment Manager
- `/cgo dev` - Inspect addon state in DevTool

## License
MIT