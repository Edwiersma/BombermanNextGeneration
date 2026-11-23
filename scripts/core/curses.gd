class_name Curses
extends RefCounted
## The Skull's curses from the Generation battle game. A curse lasts Rules.CURSE_TICKS; while
## cursed you can pass it on by touching a player who has none (match setting).

enum Type { NONE = -1, TOO_FAST, TOO_SLOW, LOOSE_HANDS, HANDS_TIED, NO_POWER, CANT_STOP, DIZZY,
	SHORT_FUSE, LONG_FUSE, SWAP }

const ALL := [Type.TOO_FAST, Type.TOO_SLOW, Type.LOOSE_HANDS, Type.HANDS_TIED, Type.NO_POWER,
	Type.CANT_STOP, Type.DIZZY, Type.SHORT_FUSE, Type.LONG_FUSE, Type.SWAP]

const NAMES := {
	Type.TOO_FAST: "Too Fast",          # can hardly control it
	Type.TOO_SLOW: "Too Slow",
	Type.LOOSE_HANDS: "Loose Hands",    # drops bombs on its own
	Type.HANDS_TIED: "Hands Tied",      # cannot drop bombs
	Type.NO_POWER: "No Power",          # 1 bomb, range 1
	Type.CANT_STOP: "Can't Stop",       # keeps walking
	Type.DIZZY: "Dizzy",                # reversed controls
	Type.SHORT_FUSE: "Short Fuse",
	Type.LONG_FUSE: "Long Fuse",
	Type.SWAP: "Swap",                  # trades places with another player now and then
}


static func display_name(curse: int) -> String:
	return NAMES.get(curse, "")


static func random(rng: RandomNumberGenerator) -> int:
	return ALL[rng.randi_range(0, ALL.size() - 1)]
