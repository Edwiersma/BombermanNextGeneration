class_name Items
extends RefCounted
## Item types and their data. Later Phase 2 milestones append types; IMPLEMENTED lists the ones
## this build supports (only those can be hidden under bricks or toggled in settings).
## Items are saved by `key`, so the enum order can grow without breaking saved settings.

enum Type { BOMB_UP, FIRE_UP, FULL_FIRE, SPEED_UP, SPEED_DOWN, HEART, VEST, KICK, PUNCH,
	GLOVE, SUPER_GLOVE, LINE_BOMB }

const NONE := -1

## weight: how common it is under bricks, relative to the others (VERIFY against Generation).
const INFO := {
	Type.BOMB_UP: {"key": "bomb_up", "name": "Bomb Up", "symbol": "B+", "weight": 10, "color": Color(0.25, 0.45, 0.95)},
	Type.FIRE_UP: {"key": "fire_up", "name": "Fire Up", "symbol": "F+", "weight": 10, "color": Color(1.0, 0.5, 0.1)},
	Type.FULL_FIRE: {"key": "full_fire", "name": "Full Fire", "symbol": "FF", "weight": 1, "color": Color(0.9, 0.12, 0.1)},
	Type.SPEED_UP: {"key": "speed_up", "name": "Speed Up", "symbol": "S+", "weight": 6, "color": Color(0.2, 0.8, 0.3)},
	Type.SPEED_DOWN: {"key": "speed_down", "name": "Speed Down", "symbol": "S-", "weight": 2, "color": Color(0.5, 0.3, 0.6)},
	Type.HEART: {"key": "heart", "name": "Heart", "symbol": "H", "weight": 3, "color": Color(1.0, 0.35, 0.55)},
	Type.VEST: {"key": "safety_vest", "name": "Safety Vest", "symbol": "V", "weight": 1, "color": Color(0.2, 0.85, 0.95)},
	Type.KICK: {"key": "bomb_kick", "name": "Bomb Kick", "symbol": "K", "weight": 4, "color": Color(1.0, 0.8, 0.2)},
	Type.PUNCH: {"key": "bomb_punch", "name": "Bomb Punch", "symbol": "P", "weight": 3, "color": Color(0.85, 0.3, 0.9)},
	Type.GLOVE: {"key": "power_glove", "name": "Power Glove", "symbol": "G", "weight": 2, "color": Color(0.85, 0.55, 0.3)},
	Type.SUPER_GLOVE: {"key": "super_power_glove", "name": "Super Power Glove", "symbol": "SG", "weight": 1, "color": Color(1.0, 0.85, 0.3)},
	Type.LINE_BOMB: {"key": "line_bomb", "name": "Line Bomb", "symbol": "L", "weight": 2, "color": Color(0.3, 0.6, 0.75)},
}

## Items that share one slot: picking one up replaces whichever of them you had.
const SLOT_A := [Type.GLOVE, Type.SUPER_GLOVE, Type.LINE_BOMB]

const IMPLEMENTED := [Type.BOMB_UP, Type.FIRE_UP, Type.FULL_FIRE, Type.SPEED_UP, Type.SPEED_DOWN,
	Type.HEART, Type.VEST, Type.KICK, Type.PUNCH, Type.GLOVE, Type.SUPER_GLOVE, Type.LINE_BOMB]


static func key(type: int) -> String:
	return INFO[type].key


static func display_name(type: int) -> String:
	return INFO[type].name


static func symbol(type: int) -> String:
	return INFO[type].symbol


static func color(type: int) -> Color:
	return INFO[type].color


static func weight(type: int) -> int:
	return INFO[type].weight


static func from_key(item_key: String) -> int:
	for type in INFO:
		if INFO[type].key == item_key:
			return type
	return NONE


## Picks one of `types` at random, weighted by rarity. NONE when the list is empty.
static func pick_weighted(types: Array, rng: RandomNumberGenerator) -> int:
	var total := 0
	for type in types:
		total += weight(type)
	if total <= 0:
		return NONE
	var roll := rng.randi_range(1, total)
	for type in types:
		roll -= weight(type)
		if roll <= 0:
			return type
	return types[-1]
