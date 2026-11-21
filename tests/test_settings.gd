extends "res://tests/test_suite.gd"

const TEST_PATH := "user://test_settings.cfg"


func test_defaults_match_phase1_rules() -> void:
	var s := MatchSettings.new()
	check_eq(s.wins_to_win, Rules.WINS_TO_WIN, "wins")
	check_eq(s.round_ticks(), Rules.ROUND_TICKS, "round time")
	check_eq(s.sudden_death_at_ticks(), Rules.SUDDEN_DEATH_AT_TICKS, "sudden death at 1:00")
	check_eq([s.start_bombs, s.start_fire], [Rules.START_BOMBS, Rules.START_FIRE], "start stats")


func test_step_wraps_around() -> void:
	var s := MatchSettings.new()
	s.wins_to_win = MatchSettings.MAX_WINS
	s.step("wins_to_win", 1)
	check_eq(s.wins_to_win, 1, "5 -> 1")
	s.step("wins_to_win", -1)
	check_eq(s.wins_to_win, MatchSettings.MAX_WINS, "1 -> 5")
	s.start_fire = 1
	s.step("start_fire", -1)
	check_eq(s.start_fire, MatchSettings.MAX_START_FIRE, "fire 1 -> 8")


func test_round_time_cycles_through_options_including_no_limit() -> void:
	var s := MatchSettings.new()
	var seen: Array = []
	for i in MatchSettings.ROUND_TIME_OPTIONS.size():
		s.step("round_seconds", 1)
		seen.append(s.round_seconds)
	check_eq(seen.size(), MatchSettings.ROUND_TIME_OPTIONS.size(), "visited every option")
	check(0 in seen, "includes no limit")
	s.round_seconds = 0
	check_eq(s.value_text("round_seconds"), "No limit", "label")
	check(not s.has_time_limit(), "no time limit")
	check_eq(s.sudden_death_at_ticks(), -1, "no sudden death without a clock")


func test_short_round_starts_sudden_death_halfway() -> void:
	var s := MatchSettings.new()
	s.round_seconds = 60
	check_eq(s.sudden_death_at_ticks(), 30 * Rules.TICKS_PER_SECOND, "halfway through a 1:00 round")
	s.sudden_death = false
	check_eq(s.sudden_death_at_ticks(), -1, "off")


func test_value_texts() -> void:
	var s := MatchSettings.new()
	check_eq(s.value_text("round_seconds"), "3:00", "clock")
	check_eq(s.value_text("sudden_death"), "On", "toggle")
	check_eq(s.value_text("start_bombs"), "1", "number")
	for key in MatchSettings.ROWS:
		check(s.row_label(key) != key, "label for %s" % key)


func test_save_and_load_round_trip() -> void:
	var s := MatchSettings.new()
	s.wins_to_win = 5
	s.round_seconds = 0
	s.sudden_death = false
	s.start_bombs = 3
	s.start_fire = 6
	check_eq(s.save(TEST_PATH), OK, "saved")
	var loaded := MatchSettings.load_or_default(TEST_PATH)
	check(loaded.equals(s), "same values after loading")
	DirAccess.remove_absolute(TEST_PATH)


func test_missing_file_gives_defaults() -> void:
	check(MatchSettings.load_or_default("user://does_not_exist.cfg").equals(MatchSettings.new()), "defaults")


func test_bad_saved_values_are_corrected() -> void:
	var config := ConfigFile.new()
	config.set_value(MatchSettings.SECTION, "wins_to_win", 99)
	config.set_value(MatchSettings.SECTION, "round_seconds", 77)
	config.set_value(MatchSettings.SECTION, "start_bombs", -4)
	config.save(TEST_PATH)
	var loaded := MatchSettings.load_or_default(TEST_PATH)
	check_eq(loaded.wins_to_win, MatchSettings.MAX_WINS, "wins clamped")
	check_eq(loaded.round_seconds, 180, "unknown time -> default")
	check_eq(loaded.start_bombs, 1, "bombs clamped")
	DirAccess.remove_absolute(TEST_PATH)


func test_reset_and_duplicate() -> void:
	var s := MatchSettings.new()
	s.step("wins_to_win", 1)
	var copy := s.duplicate_settings()
	check(copy.equals(s), "copy equal")
	s.reset_to_defaults()
	check(s.equals(MatchSettings.new()), "reset")
	check(not copy.equals(s), "copy independent")
