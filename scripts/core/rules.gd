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


static func ticks_to_seconds(ticks: int) -> float:
	return ticks / float(TICKS_PER_SECOND)
