extends Node
## Session state shared between main menu, lobby, match and results.
## Device-to-slot mapping lives in InputRouter; everything else a match needs lives here.

## Versus screen choices per slot (kind, portrait), kept across matches so a rematch keeps them.
var lobby := LobbyState.new()
## Match parameters from the lobby settings panel; saved with save_settings().
var settings := MatchSettings.load_or_default()
## Where save_settings() writes (tests point this elsewhere).
var settings_path := MatchSettings.SAVE_PATH
## The stage to play. Phase 1 has one.
var level: LevelData = preload("res://levels/classic.tres")
## True when the lobby set up the match (no drop-in join phase; results screen afterwards).
var in_session := false
## Filled by the match when it ends: {"wins": {slot: int}, "winner": slot, "rounds": int}.
var last_results := {}


## Palette index for a slot: the lobby choice, or the slot's default when it never went
## through the lobby (dev drop-in matches, tests).
func color_index(slot: int) -> int:
	return lobby.color_index(slot)


func color_of(slot: int) -> Color:
	return Palette.PLAYER_COLORS[color_index(slot)]


func color_name(slot: int) -> String:
	return Palette.PLAYER_COLOR_NAMES[color_index(slot)]


func save_settings() -> void:
	var error := settings.save(settings_path)
	if error != OK:
		push_warning("Could not save settings (error %d)" % error)


## Back to a clean slate (main menu): nobody joined, no session.
func end_session() -> void:
	in_session = false
	last_results = {}
	lobby.reset()
	InputRouter.release_all()
