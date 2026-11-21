# Bomberman Next Generation

A local-multiplayer versus game in the style of **Bomberman Generations** (GameCube), built with Godot 4.7.1 and GDScript. Up to 4 players on keyboards or PlayStation controllers, played in the browser.

> Fan project. Not affiliated with or endorsed by Konami or Hudson Soft; Bomberman is a trademark of Konami Digital Entertainment. This repository contains code only, no original game assets.

## Status
**Phase 1** (local multiplayer, base mechanics) is playable: main menu, 4-player lobby, Bomberman-style movement, bombs and chain reactions, rounds with a clock and sudden death, results and rematch. Remaining for Phase 1: a full 4-controller browser playtest.
**Phase 2** (in progress): match settings and items are in (stat items, Heart, Safety Vest so far); still to come from the Bomberman Generation battle set: Kick, Punch, Gloves, Line Bomb, Remote, Piercing, Power Bomb, Land Mine, Bouncy Bomb and curses.

## Play it locally
Requires Godot 4.7.1 with its export templates, and Python 3 for the local web server.

```powershell
.\tools\export_web.ps1
```
```powershell
.\tools\serve.ps1
```

Then open **http://localhost:8060/** in Chrome or Firefox. Use `localhost`, not a LAN IP: browsers only expose gamepads to secure pages, and plain http is only treated as secure on localhost. Press a button on every controller so the browser lets the game see it.

You can also open this folder in the Godot editor and press F5.

**Flow:** main menu → VERSUS → lobby (join on your own device, pick a colour with left/right, ready up; any player can open the match settings) → START → match (first to 3 round wins; Start pauses) → results (rematch / lobby / main menu). A single ready player gets a practice match.

## Controls
| | Keyboard 1 | Keyboard 2 | PlayStation pad |
|---|---|---|---|
| Move / menus | WASD | Arrow keys | D-pad or left stick |
| Bomb · join · ready · select | Space | Enter | Cross |
| Back · un-ready · leave | Esc | Backspace | Circle |
| Start · pause | Tab | P | Options |
| Match settings (lobby) | Q | Delete | Triangle |
| Special (Phase 2) | E | Shift | Circle |

## Rules (Phase 1)
13 × 11 arena with pillars and brick walls. Bombs (1 at a time, fire range 2 by default) explode after 3 s in a cross, destroy the first brick in each direction and set off other bombs in the same instant. Fire kills, including your own. Last player standing wins the round; at 1:00 left, **HURRY UP!** blocks fall in a spiral and crush anything below. Wins needed (1-5), round time (1:00-5:00 or no limit), sudden death and starting bombs/fire are match settings, saved in the browser. The full spec, including which numbers still need checking against the original, is kept with the project plan; all tunable numbers are in [`scripts/core/rules.gd`](scripts/core/rules.gd).

## Items
Items hide under bricks and appear when the brick burns away; walk over one to pick it up. Fire destroys items lying on the floor (and stops there). Each round starts with fresh stats. Heart and Vest protect against fire only: sudden-death blocks still crush.

| Tile | Item | Effect |
|---|---|---|
| B+ | Bomb Up | one more bomb at a time (max 8) |
| F+ | Fire Up | blast reaches one cell further (max 8) |
| FF | Full Fire | blast range to the maximum |
| S+ | Speed Up | walk faster |
| S- | Speed Down | walk slower |
| H | Heart | survive one hit by fire, then blink briefly while invulnerable (carry one at a time) |
| V | Safety Vest | invulnerable to fire for 16 s |

Match settings choose how often items appear (off / low / normal / high), which items can appear, and whether a fallen player's items scatter across the arena or are lost.

## Project layout
```
autoload/        InputRouter (devices -> player slots), GameState (session), AssetLibrary (art or placeholders)
scripts/core/    pure game logic: grid, movement, bombs, rounds, lobby, rules constants
scripts/levels/  LevelData: stages written as ASCII
scripts/ui/      menu styling, menu navigation, scene paths
scenes/          boot, menus (main menu, lobby, results), game (match, arena, player, HUD...), debug (pad tester)
levels/          classic.tres
tests/           headless tests
tools/           web export and local server scripts
```
Game rules live in plain classes under `scripts/core/` that tick at 60 Hz with no nodes, so they are covered by headless tests; scenes only draw and react to their signals.

## Tests
```powershell
& "C:\Program Files\Godot\4.7.1\Godot_v4.7.1-stable_win64_console.exe" --headless --path . -s tests/run_tests.gd
```
Prints `N passed, M failed` and exits with the number of failures.

## Levels
Stages are ASCII in `levels/*.tres`: `#` hard block, `+` brick, `?` random brick, `.` floor, `1`-`4` spawns. See [`scripts/levels/level_data.gd`](scripts/levels/level_data.gd).

## Art and sound
Not in this repository. The game draws generated placeholders when `assets_ext/` is missing, so a fresh clone runs. To use a local asset folder, link it in (the folder is git-ignored):

```powershell
.\tools\link_assets.ps1 -Target <path-to>\assets\export
```
Files are looked up by key, e.g. `assets_ext/textures/soft_block.png` or `assets_ext/models/bomber.glb`; see [`autoload/asset_library.gd`](autoload/asset_library.gd).

## Development helpers
- `?scene=<name>` in the URL (or `-- --scene=<name>` on the command line) opens a scene directly: `menu`, `lobby`, `match`, `results`, `controller_test`.
- `?scene=match` starts in a quick join phase: join with Cross / Space / Enter, start with Options / Tab / P.
- In a match: **F3** toggles a debug readout (FPS, ticks, state, positions). Dev matches only: **F4** skips the clock to just before sudden death; **F5** drops the next item type at the first player's feet.
