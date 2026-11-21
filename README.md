# Bomberman Next Generation

Bomberman Generations-style versus game for Godot 4.7.1 (GDScript). Local multiplayer, up to 4 players, keyboard or PlayStation controllers, web (browser).

## Status
Phase 1: planning / early development.

## Assets
Art, models and audio are **not** in this repository. The game falls back to procedural placeholders when `assets_ext/` is missing, so a fresh clone runs.
To use the real assets, junction your local asset folder: `New-Item -ItemType Junction -Path assets_ext -Target <path-to>\assets\export`.

## Running
- **Editor:** open this folder in Godot 4.7.1 and press F5.
- **Browser (how the game is meant to be played):**
  ```powershell
  .\tools\export_web.ps1
  .\tools\serve.ps1
  ```
  Then open http://localhost:8060/ in Chrome or Firefox. Use `localhost`, not a LAN IP: browsers only expose gamepads on secure origins.
- **Dev scenes:** add `?scene=controller_test` to the URL (or `-- --scene=controller_test` on the command line) to open the pad tester.
- **Tests:**
  ```powershell
  & "C:\Program Files\Godot\4.7.1\Godot_v4.7.1-stable_win64_console.exe" --headless --path . -s tests/run_tests.gd
  ```

## Levels
Levels are ASCII in `levels/*.tres` (`#` hard, `+` soft, `?` random soft, `.` floor, `1`-`4` spawns). See `scripts/levels/level_data.gd`.

## Controls
| | Keyboard 1 | Keyboard 2 | PlayStation pad |
|---|---|---|---|
| Move | WASD | Arrow keys | D-pad / left stick |
| Bomb / join | Space | Enter | Cross |
| Special / leave | E / Esc | Shift / Backspace | Circle |
| Start | Tab | P | Options |

Browsers hide pads until a button is pressed on each one.

Until the lobby exists, players join a running match by pressing **Cross / Space / Enter**. **F3** toggles the debug readout (FPS, physics ticks, player positions).
