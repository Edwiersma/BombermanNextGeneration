# Bomberman Next Generation

A local-multiplayer versus game in the style of **Bomberman Generations** (GameCube), built with Godot 4.7.1 and GDScript. Up to 6 players on keyboards or PlayStation controllers (AI slots too, though AI players only stand still for now), played in the browser.

> Fan project. Not affiliated with or endorsed by Konami or Hudson Soft; Bomberman is a trademark of Konami Digital Entertainment. This repository contains code only, no original game assets.

## Status
**Phase 1** (local multiplayer, base mechanics) is playable: main menu, a versus screen for up to 6 players (portraits, slots, AI slots, settings), Bomberman-style movement, bombs and chain reactions, rounds with a clock and sudden death, results and rematch. Remaining for Phase 1: a full 4-controller browser playtest.
**Phase 2** (match settings and items) is complete: a lobby settings panel and the full Bomberman Generation battle item set, from Bomb Up to the Skull and its 10 curses. Many timings and item rates are still best guesses until checked against the original; see *Tuning* below.

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

**Flow:** main menu → VERSUS → versus screen → START → match (first to 3 round wins; Start pauses) → results (rematch / lobby / main menu).

**Versus screen:** the left two thirds hold the portraits (7 on top, 8 below; the far right one is Random, colours beyond the 8 playable ones are locked for now) and six player slots under them; the right third lists every match setting.
- Press Cross / Space / Enter on a new controller to join: it takes the next free slot and gets a cursor (P1-P6).
- Move the cursor with the d-pad or left stick (hold to repeat) and press Cross on a portrait to claim it. Each portrait can be claimed once; Random can be picked by anyone and is settled on a free colour when the match starts. Back drops your portrait, Back again leaves.
- Move down to the slot cards and press Cross on an empty slot to toggle it Off → Player (when a spare pad is connected) → AI → Off. AI players pick Random.
- Move right past the end of any row (or press Triangle) to enter the settings; only one player at a time. Up/down choose, right or Cross changes a row (left/right step it, Cross or Back finishes), left or Back leaves.
- START begins once every player has a portrait. One participant alone gets a practice match.

## Controls
| | Keyboard 1 | Keyboard 2 | PlayStation pad |
|---|---|---|---|
| Move / menus | WASD | Arrow keys | D-pad or left stick |
| Bomb · join · claim · select | Space | Enter | Cross |
| Back · drop portrait · leave | Esc | Backspace | Circle |
| Start · pause | Tab | P | Options |
| Settings shortcut (versus screen) | Q | Delete | Triangle |
| Special (punch, remote detonate) | E | Shift | Circle |

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
| K | Bomb Kick | walk into a bomb to send it sliding until something stops it |
| P | Bomb Punch | press Special to punch the bomb in front 3 cells, over anything; it wraps around the arena edge |
| G | Power Glove | standing on your bomb, hold Bomb to lift and carry it; release to throw it 4 cells |
| SG | Super Power Glove | like the Power Glove; hold the bomb for 2 s and it becomes a Dangerous Bomb |
| L | Line Bomb | standing on the bomb you just placed, press Bomb again to lay a line of your remaining bombs |

| RC | Remote Control | your bombs have no fuse; press Special to set off the oldest one |
| PI | Piercing Bomb | blasts burn through bricks out to their full range |
| PW | Power Bomb | your first bomb out has the maximum range |
| LM | Land Mine | your first bomb out sinks into the floor and goes off when someone steps on it |
| BO | Bouncy Bomb | bombs you kick or punch keep hopping around until they explode |
| SK | Skull | a random curse for 15 s (its name floats above you) |

Curses: Too Fast, Too Slow, Loose Hands (drops bombs on its own), Hands Tied (no bombs), No Power (1 bomb, range 1), Can't Stop (keeps walking), Dizzy (reversed controls), Short Fuse, Long Fuse, Swap (trades places with another player now and then). Touching a player passes your curse on (match setting).

Power Glove, Super Power Glove and Line Bomb share one slot; Remote, Piercing, Power, Land Mine and Bouncy share another. Picking up an item replaces the one in its slot. With both Punch and Remote, Special punches the bomb in front of you if there is one, otherwise it sets off a remote bomb.

Two kicked bombs that collide merge into a glowing red **Dangerous Bomb**, which explodes in a 5 × 5 square.

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
Stages are ASCII in `levels/*.tres`: `#` hard block, `+` brick, `?` random brick, `.` floor, `1`-`4` spawns, `5`-`6` optional spawns for a 5th and 6th player (a brick when fewer play). Players take spawns in order, so any four start in the corners. See [`scripts/levels/level_data.gd`](scripts/levels/level_data.gd).

## Art and sound
Not in this repository. The game draws generated placeholders when `assets_ext/` is missing, so a fresh clone runs. To use a local asset folder, link it in (the folder is git-ignored):

```powershell
.\tools\link_assets.ps1 -Target <path-to>\assets\export
```
Files are looked up by key, e.g. `assets_ext/textures/soft_block.png` or `assets_ext/models/bomber.glb`; see [`autoload/asset_library.gd`](autoload/asset_library.gd).

## Tuning
Gameplay numbers are constants in [`scripts/core/rules.gd`](scripts/core/rules.gd) (speeds, fuses, timers, item share per frequency, curse effects) and item rarity weights in [`scripts/core/items.gd`](scripts/core/items.gd). Change a value, re-export, and the headless tests tell you if a rule broke.

## Development helpers
- `?scene=<name>` in the URL (or `-- --scene=<name>` on the command line) opens a scene directly: `menu`, `lobby`, `match`, `results`, `controller_test`.
- `?scene=match` starts in a quick join phase: join with Cross / Space / Enter, start with Options / Tab / P.
- In a match: **F3** toggles a debug readout (FPS, ticks, state, positions). Dev matches only: **F4** skips the clock to just before sudden death; **F5** drops the next item type at the first player's feet.
