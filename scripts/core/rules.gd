class_name Rules
extends RefCounted
## Gameplay numbers in one place. They become match parameters in Phase 2.
## Values marked VERIFY are best guesses until checked against Bomberman Generations footage.

## Base walking speed in cells per second. VERIFY
const PLAYER_SPEED := 4.0

## Minimum sideways overlap (in cells) with the neighbouring lane before a blocked player
## slides around the corner into it.
const CORNER_ASSIST_MIN := 0.25

## Largest distance moved in one tick, so a player can never skip past a cell centre.
const MAX_STEP := 0.45

## Simulation rate. Must match physics/common/physics_ticks_per_second in project.godot.
const TICKS_PER_SECOND := 60

## Bomb fuse: 3.0 s. VERIFY
const BOMB_FUSE_TICKS := 180

## How long flames (and a burning brick) last: 0.5 s. VERIFY
const FLAME_TICKS := 30

## Starting stats. Fixed in Phase 1; power-ups raise them in Phase 2.
const START_BOMBS := 1
const START_FIRE := 2

## --- Rounds (all VERIFY against Generations) ---
## Round wins needed to win the match.
const WINS_TO_WIN := 3
## Round clock: 3:00.
const ROUND_TICKS := 3 * 60 * TICKS_PER_SECOND
## "Hurry up" sudden death starts with 1:00 left: blocks fall in a spiral from the edge inward.
const SUDDEN_DEATH_AT_TICKS := 60 * TICKS_PER_SECOND
## One falling block every 0.5 s, so the ~113 open cells fill just before time runs out.
const DROP_INTERVAL_TICKS := 30
## How long a falling block takes to land (it crushes on landing).
const FALL_TICKS := 18
## After only one player is left, play on this long before the round is decided. If the last
## player dies in this window (e.g. their own bomb), the round is a draw.
const ROUND_END_DELAY_TICKS := 90
## Intro: "ROUND n" then "READY?" then play starts with "GO!".
const INTRO_ROUND_TICKS := 60
const INTRO_READY_TICKS := 60
## Pause on the round result, and on the match result.
const ROUND_OVER_TICKS := 180
const MATCH_OVER_TICKS := 300

## --- Items (Phase 2) ---
## Caps from the Generation battle game: 8 bombs, fire 8.
const MAX_BOMBS := 8
const MAX_FIRE := 8
## Speed levels: you start at 1; Speed Up / Speed Down move between 0 and 6. Each level is
## SPEED_STEP cells/s. VERIFY against Generation.
const START_SPEED_LEVEL := 1
const MIN_SPEED_LEVEL := 0
const MAX_SPEED_LEVEL := 6
const SPEED_STEP := 0.6
## Share of bricks hiding an item for each item-frequency setting (off, low, normal, high).
## Raised in P2-M8 so the 18 item types do not dilute Bomb Up / Fire Up too much. VERIFY
const ITEM_SHARE := [0.0, 0.3, 0.5, 0.7]

## Heart: after it absorbs a hit you are invulnerable this long, to get out of the fire. VERIFY
const HEART_GRACE_TICKS := 120
## Safety Vest: invulnerable for 16 s (Generation).
const VEST_TICKS := 16 * TICKS_PER_SECOND
## The vest flickers this long before it runs out.
const VEST_WARNING_TICKS := 3 * TICKS_PER_SECOND

## --- Moving bombs (Kick, Punch) --- all VERIFY against Generation
## A kicked bomb slides this many cells per second.
const KICK_SPEED := 8.0
## A punched bomb flies this many cells, over anything in between.
const PUNCH_DISTANCE := 3
const PUNCH_FLIGHT_TICKS := 24
## When a punched bomb lands on a taken cell it bounces one cell further.
const BOUNCE_FLIGHT_TICKS := 10
## Peak height of a punched bomb's arc, in cells.
const PUNCH_ARC_HEIGHT := 1.6
## Two kicked bombs colliding merge into a Dangerous Bomb: fuse and square blast radius.
const DANGEROUS_FUSE_TICKS := 120
const DANGEROUS_RADIUS := 2

## --- Slot A (Power Glove, Super Power Glove, Line Bomb) --- VERIFY against Generation
## A thrown bomb flies this many cells (like a punch, over anything, wrapping at the edge).
const THROW_DISTANCE := 4
const THROW_FLIGHT_TICKS := 30
## Holding a bomb this long with the Super Power Glove makes it a Dangerous Bomb.
const SUPER_GLOVE_CHARGE_TICKS := 120
## How high a carried bomb sits above the player, in cells.
const CARRY_HEIGHT := 1.15

## --- Curses (Skull) --- all VERIFY against Generation
const CURSE_TICKS := 15 * TICKS_PER_SECOND
const CURSE_FAST_SPEED := 9.0   # cells per second
const CURSE_SLOW_SPEED := 1.8
const SHORT_FUSE_TICKS := 60
const LONG_FUSE_TICKS := 360
## Swap curse: time between swaps is random in this range.
const SWAP_MIN_TICKS := 120
const SWAP_MAX_TICKS := 300
## Players closer than this (in cells) are touching, for spreading curses.
const CURSE_TOUCH_DISTANCE := 0.6


static func ticks_to_seconds(ticks: int) -> float:
	return ticks / float(TICKS_PER_SECOND)
