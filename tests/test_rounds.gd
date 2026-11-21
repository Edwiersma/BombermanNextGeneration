extends "res://tests/test_suite.gd"

const INTRO := Rules.INTRO_ROUND_TICKS + Rules.INTRO_READY_TICKS
const ROOM := [
	"#######",
	"#.....#",
	"#.#.#.#",
	"#.....#",
	"#######",
]

var events: Array = []


func _rules(slots: Array[int]) -> MatchRules:
	var rules := MatchRules.new()
	for sig in ["round_started", "ready_shown", "play_started", "hurry_up", "block_falling",
			"block_landed", "round_ended", "next_round", "match_ended", "match_finished"]:
		var name: String = sig
		rules.connect(sig, func(arg = null): events.append([name, arg]))
	rules.begin_match(slots)
	rules.start_round(grid_from_rows(ROOM))
	return rules


func _ticks(rules: MatchRules, count: int) -> void:
	for i in count:
		rules.tick()


func _names() -> Array:
	return events.map(func(e): return e[0])


func _last(name: String) -> Variant:
	for i in range(events.size() - 1, -1, -1):
		if events[i][0] == name:
			return events[i][1]
	return "none"


func test_intro_then_play() -> void:
	var rules := _rules([0, 1])
	check_eq(rules.state, MatchRules.State.INTRO, "starts in intro")
	check_eq(_last("round_started"), 1, "round 1 announced")
	_ticks(rules, INTRO - 1)
	check(not rules.is_playing(), "still in intro")
	check("ready_shown" in _names(), "ready shown")
	rules.tick()
	check(rules.is_playing(), "playing after intro")
	check("play_started" in _names(), "go")


func test_clock_runs_only_while_playing() -> void:
	var rules := _rules([0, 1])
	_ticks(rules, INTRO)
	check_eq(rules.time_left, Rules.ROUND_TICKS, "clock untouched during intro")
	_ticks(rules, 60)
	check_eq(rules.time_left, Rules.ROUND_TICKS - 60, "one second off")


func test_last_player_standing_wins_after_delay() -> void:
	var rules := _rules([0, 1, 2])
	_ticks(rules, INTRO)
	rules.player_died(0)
	_ticks(rules, 10)
	rules.player_died(2)
	_ticks(rules, Rules.ROUND_END_DELAY_TICKS - 1)
	check(rules.is_playing(), "play continues during the end delay")
	rules.tick()
	check_eq(rules.state, MatchRules.State.ROUND_OVER, "round over")
	check_eq(_last("round_ended"), 1, "slot 1 wins")
	check_eq(rules.wins, {0: 0, 1: 1, 2: 0}, "win counted")


func test_simultaneous_deaths_are_a_draw() -> void:
	var rules := _rules([0, 1])
	_ticks(rules, INTRO)
	rules.player_died(0)
	rules.player_died(1)
	_ticks(rules, Rules.ROUND_END_DELAY_TICKS)
	check_eq(_last("round_ended"), -1, "draw")
	check_eq(rules.wins, {0: 0, 1: 0}, "nothing awarded")


func test_survivor_dying_during_delay_is_a_draw() -> void:
	var rules := _rules([0, 1])
	_ticks(rules, INTRO)
	rules.player_died(0)
	_ticks(rules, 30)
	rules.player_died(1)
	_ticks(rules, Rules.ROUND_END_DELAY_TICKS)
	check_eq(_last("round_ended"), -1, "draw")


func test_next_round_then_match_win() -> void:
	var rules := _rules([0, 1])
	for round in Rules.WINS_TO_WIN:
		_ticks(rules, INTRO)
		rules.player_died(1)
		_ticks(rules, Rules.ROUND_END_DELAY_TICKS + Rules.ROUND_OVER_TICKS)
		if round < Rules.WINS_TO_WIN - 1:
			check_eq(_last("next_round"), null, "next round requested")
			rules.start_round(grid_from_rows(ROOM))
	check_eq(rules.state, MatchRules.State.MATCH_OVER, "match over")
	check_eq(_last("match_ended"), 0, "slot 0 takes the match")
	check_eq(rules.round_number, Rules.WINS_TO_WIN, "rounds played")
	_ticks(rules, Rules.MATCH_OVER_TICKS)
	check_eq(rules.state, MatchRules.State.WAITING, "back to waiting")
	check("match_finished" in _names(), "finished signal")


func test_time_out_with_two_alive_is_a_draw() -> void:
	var rules := _rules([0, 1])
	_ticks(rules, INTRO + Rules.ROUND_TICKS)
	check_eq(rules.time_left, 0, "clock ran out")
	check_eq(_last("round_ended"), -1, "draw")


func test_solo_practice_ends_only_when_you_die() -> void:
	var rules := _rules([0])
	_ticks(rules, INTRO + 300)
	check(rules.is_playing(), "one player alone keeps playing")
	rules.player_died(0)
	_ticks(rules, Rules.ROUND_END_DELAY_TICKS)
	check_eq(_last("round_ended"), -1, "no winner in solo")


func test_hurry_up_drops_blocks_in_a_spiral_skipping_pillars() -> void:
	var rules := _rules([0, 1])
	_ticks(rules, INTRO + Rules.ROUND_TICKS - Rules.SUDDEN_DEATH_AT_TICKS)
	check(rules.sudden_death and "hurry_up" in _names(), "hurry up")
	check_eq(_last("block_falling"), Vector2i(1, 1), "first block at the top-left corner")
	_ticks(rules, Rules.FALL_TICKS)
	check_eq(_last("block_landed"), Vector2i(1, 1), "lands after the fall time")
	_ticks(rules, Rules.DROP_INTERVAL_TICKS - Rules.FALL_TICKS)
	check_eq(_last("block_falling"), Vector2i(2, 1), "next spiral cell")
	# Room interior: (1..5, 1..3); pillars at (2,2) and (4,2) are skipped.
	_ticks(rules, Rules.DROP_INTERVAL_TICKS * 20)
	var fallen: Array = []
	for e in events:
		if e[0] == "block_falling":
			fallen.append(e[1])
	check(Vector2i(2, 2) not in fallen and Vector2i(4, 2) not in fallen, "pillars skipped: %s" % [fallen])


func test_spiral_covers_interior_once() -> void:
	var cells := MatchRules.spiral_cells(15, 13)
	check_eq(cells.size(), 13 * 11, "every interior cell")
	var unique := {}
	for cell in cells:
		unique[cell] = true
		check(cell.x >= 1 and cell.x <= 13 and cell.y >= 1 and cell.y <= 11, "inside: %s" % cell)
	check_eq(unique.size(), cells.size(), "no repeats")
	check_eq(cells[0], Vector2i(1, 1), "starts top-left")
	check_eq(cells[12], Vector2i(13, 1), "runs along the top first")
	# 13x11 leaves a 3-cell strip through the middle as the last ring.
	check_eq(cells.slice(-3), [Vector2i(6, 6), Vector2i(7, 6), Vector2i(8, 6)] as Array[Vector2i], "ends in the middle strip")
