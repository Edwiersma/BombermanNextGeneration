class_name MatchSettings
extends RefCounted
## Match parameters chosen in the lobby settings panel, saved between visits.
## Defaults are the Phase 1 rules plus items at normal frequency. The panel is generic: it shows
## rows() using row_label() / value_text() and changes values with step(), so a new setting only
## needs adding here. Item rows ("item:<key>") toggle one item type each.

const SAVE_PATH := "user://settings.cfg"
const SECTION := "match"
const ITEMS_SECTION := "items"

## Round clock choices in seconds; 0 means no time limit (and so no sudden death).
const ROUND_TIME_OPTIONS := [60, 120, 180, 240, 300, 0]
const MAX_WINS := 5
const FREQUENCY_NAMES := ["Off", "Low", "Normal", "High"]
const ITEM_ROW_PREFIX := "item:"

## Plain settings, in panel order. Item on/off rows follow them.
const SCALAR_ROWS := ["wins_to_win", "round_seconds", "sudden_death", "start_bombs", "start_fire",
	"item_frequency", "death_items"]

## What happens to the items a player collected when they die.
enum DeathItems { SCATTER, LOST }

var wins_to_win := Rules.WINS_TO_WIN
var round_seconds := Rules.ROUND_TICKS / Rules.TICKS_PER_SECOND
var sudden_death := true
var start_bombs := Rules.START_BOMBS
var start_fire := Rules.START_FIRE
var item_frequency := 2  # index into FREQUENCY_NAMES / Rules.ITEM_SHARE
var death_items: int = DeathItems.SCATTER
## Item key -> enabled. Missing keys count as enabled, so new items are on by default.
var item_enabled := {}


func rows() -> Array[String]:
	var result: Array[String] = []
	result.assign(SCALAR_ROWS)
	for type in Items.IMPLEMENTED:
		result.append(ITEM_ROW_PREFIX + Items.key(type))
	return result


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


func is_item_enabled(type: int) -> bool:
	return item_enabled.get(Items.key(type), true)


## Item types that can be hidden under bricks this match.
func enabled_item_types() -> Array:
	return Items.IMPLEMENTED.filter(is_item_enabled)


func items_active() -> bool:
	return item_frequency > 0 and not enabled_item_types().is_empty()


# --- Panel helpers -----------------------------------------------------------

func row_label(key: String) -> String:
	if key.begins_with(ITEM_ROW_PREFIX):
		return "  " + Items.display_name(_row_item(key))
	match key:
		"wins_to_win": return "Wins needed"
		"round_seconds": return "Round time"
		"sudden_death": return "Sudden death"
		"start_bombs": return "Starting bombs"
		"start_fire": return "Starting fire"
		"item_frequency": return "Items"
		"death_items": return "Items of fallen players"
	return key


func value_text(key: String) -> String:
	if key.begins_with(ITEM_ROW_PREFIX):
		return "On" if is_item_enabled(_row_item(key)) else "Off"
	match key:
		"round_seconds":
			return "No limit" if round_seconds == 0 else "%d:%02d" % [round_seconds / 60, round_seconds % 60]
		"sudden_death":
			return "On" if sudden_death else "Off"
		"item_frequency":
			return FREQUENCY_NAMES[item_frequency]
		"death_items":
			return "Scatter" if death_items == DeathItems.SCATTER else "Lost"
	return str(get(key))


## Changes a setting by one step (dir = -1 or 1), wrapping around at the ends.
func step(key: String, dir: int) -> void:
	if key.begins_with(ITEM_ROW_PREFIX):
		var item_key := key.trim_prefix(ITEM_ROW_PREFIX)
		item_enabled[item_key] = not item_enabled.get(item_key, true)
		return
	match key:
		"wins_to_win":
			wins_to_win = _wrap(wins_to_win + dir, 1, MAX_WINS)
		"round_seconds":
			var index := ROUND_TIME_OPTIONS.find(round_seconds)
			round_seconds = ROUND_TIME_OPTIONS[posmod(index + dir, ROUND_TIME_OPTIONS.size())]
		"sudden_death":
			sudden_death = not sudden_death
		"start_bombs":
			start_bombs = _wrap(start_bombs + dir, 1, Rules.MAX_BOMBS)
		"start_fire":
			start_fire = _wrap(start_fire + dir, 1, Rules.MAX_FIRE)
		"item_frequency":
			item_frequency = posmod(item_frequency + dir, FREQUENCY_NAMES.size())
		"death_items":
			death_items = DeathItems.LOST if death_items == DeathItems.SCATTER else DeathItems.SCATTER


func reset_to_defaults() -> void:
	var defaults := MatchSettings.new()
	for key in SCALAR_ROWS:
		set(key, defaults.get(key))
	item_enabled.clear()


func equals(other: MatchSettings) -> bool:
	for key in SCALAR_ROWS:
		if get(key) != other.get(key):
			return false
	for type in Items.IMPLEMENTED:
		if is_item_enabled(type) != other.is_item_enabled(type):
			return false
	return true


func duplicate_settings() -> MatchSettings:
	var copy := MatchSettings.new()
	for key in SCALAR_ROWS:
		copy.set(key, get(key))
	copy.item_enabled = item_enabled.duplicate()
	return copy


# --- Saving ------------------------------------------------------------------

func save(path := SAVE_PATH) -> Error:
	var config := ConfigFile.new()
	for key in SCALAR_ROWS:
		config.set_value(SECTION, key, get(key))
	for item_key in item_enabled:
		config.set_value(ITEMS_SECTION, item_key, item_enabled[item_key])
	return config.save(path)


## Saved settings, or defaults when there are none. Bad or out-of-range values are corrected.
static func load_or_default(path := SAVE_PATH) -> MatchSettings:
	var settings := MatchSettings.new()
	var config := ConfigFile.new()
	if config.load(path) == OK:
		for key in SCALAR_ROWS:
			if config.has_section_key(SECTION, key):
				settings.set(key, config.get_value(SECTION, key))
		if config.has_section(ITEMS_SECTION):
			for item_key in config.get_section_keys(ITEMS_SECTION):
				if Items.from_key(item_key) != Items.NONE:
					settings.item_enabled[item_key] = bool(config.get_value(ITEMS_SECTION, item_key))
	settings._sanitize()
	return settings


func _sanitize() -> void:
	var defaults := MatchSettings.new()
	wins_to_win = clampi(int(wins_to_win), 1, MAX_WINS)
	if int(round_seconds) not in ROUND_TIME_OPTIONS:
		round_seconds = defaults.round_seconds
	sudden_death = bool(sudden_death)
	start_bombs = clampi(int(start_bombs), 1, Rules.MAX_BOMBS)
	start_fire = clampi(int(start_fire), 1, Rules.MAX_FIRE)
	item_frequency = clampi(int(item_frequency), 0, FREQUENCY_NAMES.size() - 1)
	death_items = clampi(int(death_items), 0, DeathItems.size() - 1)


func _row_item(key: String) -> int:
	return Items.from_key(key.trim_prefix(ITEM_ROW_PREFIX))


static func _wrap(value: int, low: int, high: int) -> int:
	return low + posmod(value - low, high - low + 1)
