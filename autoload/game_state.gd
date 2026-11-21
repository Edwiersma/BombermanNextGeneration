extends Node
## Session state shared between main menu, lobby, match and results.
## Device-to-slot mapping lives in InputRouter; everything else a match needs lives here.

## Colour and ready flag per slot, kept across matches so a rematch keeps everyone's choices.
var lobby := LobbyState.new()
## The stage to play. Phase 1 has one.
var level: LevelData = preload("res://levels/classic.tres")
## True when the lobby set up the match (no drop-in join phase; results screen afterwards).
var in_session := false
## Filled by the match when it ends: {"wins": {slot: int}, "winner": slot, "rounds": int}.
var last_results := {}


## Palette index for a slot: the lobby choice, or the slot's default when it never went
## through the lobby (dev drop-in matches, tests).
func color_index(slot: int) -> int:
	var chosen := lobby.colors[slot]
	return chosen if chosen != LobbyState.NO_COLOR else slot


func color_of(slot: int) -> Color:
	return Palette.PLAYER_COLORS[color_index(slot)]


func color_name(slot: int) -> String:
	return Palette.PLAYER_COLOR_NAMES[color_index(slot)]


## Back to a clean slate (main menu): nobody joined, no session.
func end_session() -> void:
	in_session = false
	last_results = {}
	lobby.reset()
	InputRouter.release_all()
