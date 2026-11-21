class_name MatchSettings
extends RefCounted
## Match parameters chosen in the lobby settings panel, saved between visits.
## Defaults are the Phase 1 rules. The panel is generic: it shows ROWS using row_label() /
## value_text() and changes values with step(), so a new setting only needs adding here.

const SAVE_PATH := "user://settings.cfg"
const SECTION := "match"

## Round clock choices in seconds; 0 means no time limit (and so no sudden death).
const ROUND_TIME_OPTIONS := [60, 120, 180, 240, 300, 0]
const MAX_WINS := 5
const MAX_START_BOMBS := 8
const MAX_START_FIRE := 8

## Settings shown in the panel, in order.
const ROWS := ["wins_to_win", "round_seconds", "sudden_death", "start_bombs", "start_fire"]

var wins_to_win := Rules.WINS_TO_WIN
var round_seconds := Rules.ROUND_TICKS / Rules.TICKS_PER_SECOND
var sudden_death := true
var start_bombs := Rules.START_BOMBS
var start_fire := Rules.START_FIRE


func round_ticks() -> int:
	return round_seconds * Rules.TICKS_PER_SECOND


func has_time_limit() -> bool:
	return round_seconds > 0


## Ticks left on the clock when sudden death starts, or -1 for none. Normally 1:00 left; on a
## short round, halfway, so there is always some normal play first.
func sudden_death_at_ticks() -> int:
	if not sudden_death or not has_time_limit():
		return -1
	return mini(Rules.SUDDEN_DEATH_AT_TICKS, round_ticks() / 2)


# --- Panel helpers -----------------------------------------------------------

func row_label(key: String) -> String:
	match key:
		"wins_to_win": return "Wins needed"
		"round_seconds": return "Round time"
		"sudden_death": return "Sudden death"
		"start_bombs": return "Starting bombs"
		"start_fire": return "Starting fire"
	return key


func value_text(key: String) -> String:
	match key:
		"round_seconds":
			return "No limit" if round_seconds == 0 else "%d:%02d" % [round_seconds / 60, round_seconds % 60]
		"sudden_death":
			return "On" if sudden_death else "Off"
	return str(get(key))


## Changes a setting by one step (dir = -1 or 1), wrapping around at the ends.
func step(key: String, dir: int) -> void:
	match key:
		"wins_to_win":
			wins_to_win = _wrap(wins_to_win + dir, 1, MAX_WINS)
		"round_seconds":
			var index := ROUND_TIME_OPTIONS.find(round_seconds)
			round_seconds = ROUND_TIME_OPTIONS[posmod(index + dir, ROUND_TIME_OPTIONS.size())]
		"sudden_death":
			sudden_death = not sudden_death
		"start_bombs":
			start_bombs = _wrap(start_bombs + dir, 1, MAX_START_BOMBS)
		"start_fire":
			start_fire = _wrap(start_fire + dir, 1, MAX_START_FIRE)


func reset_to_defaults() -> void:
	var defaults := MatchSettings.new()
	for key in ROWS:
		set(key, defaults.get(key))


func equals(other: MatchSettings) -> bool:
	for key in ROWS:
		if get(key) != other.get(key):
			return false
	return true


func duplicate_settings() -> MatchSettings:
	var copy := MatchSettings.new()
	for key in ROWS:
		copy.set(key, get(key))
	return copy


# --- Saving ------------------------------------------------------------------

func save(path := SAVE_PATH) -> Error:
	var config := ConfigFile.new()
	for key in ROWS:
		config.set_value(SECTION, key, get(key))
	return config.save(path)


## Saved settings, or defaults when there are none. Bad or out-of-range values are corrected.
static func load_or_default(path := SAVE_PATH) -> MatchSettings:
	var settings := MatchSettings.new()
	var config := ConfigFile.new()
	if config.load(path) == OK:
		for key in ROWS:
			if config.has_section_key(SECTION, key):
				settings.set(key, config.get_value(SECTION, key))
	settings._sanitize()
	return settings


func _sanitize() -> void:
	var defaults := MatchSettings.new()
	wins_to_win = clampi(int(wins_to_win), 1, MAX_WINS)
	if int(round_seconds) not in ROUND_TIME_OPTIONS:
		round_seconds = defaults.round_seconds
	sudden_death = bool(sudden_death)
	start_bombs = clampi(int(start_bombs), 1, MAX_START_BOMBS)
	start_fire = clampi(int(start_fire), 1, MAX_START_FIRE)


static func _wrap(value: int, low: int, high: int) -> int:
	return low + posmod(value - low, high - low + 1)
