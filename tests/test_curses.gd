extends "res://tests/test_suite.gd"
## Skull curses: rules on PlayerStats, plus their effects in the real match.

const MATCH_SCENE := preload("res://scenes/game/match.tscn")
const TICK := 1.0 / Rules.TICKS_PER_SECOND
const INTRO := Rules.INTRO_ROUND_TICKS + Rules.INTRO_READY_TICKS


func _playing(slots: Array[int], settings := MatchSettings.new()) -> Node3D:
	GameState.settings = settings
	var match_node: Node3D = MATCH_SCENE.instantiate()
	match_node.allow_drop_in = false
	match_node.leave_on_finish = false
	match_node.rng_seed = 1
	(Engine.get_main_loop() as SceneTree).root.add_child(match_node)
	for slot in slots:
		match_node._spawn_player(slot, "kb%d" % slot)
	match_node._begin_match()
	_run(match_node, INTRO)
	return match_node


func _run(match_node: Node3D, ticks: int) -> void:
	for i in ticks:
		match_node._physics_process(TICK)
		for player in match_node.players:
			if player:
				player._physics_process(TICK)


func _done(match_node: Node3D) -> void:
	GameState.settings = MatchSettings.new()
	match_node.free()


# --- PlayerStats -------------------------------------------------------------

func test_curse_lasts_its_time() -> void:
	var stats := PlayerStats.new()
	stats.set_curse(Curses.Type.DIZZY, 10)
	for i in 9:
		stats.tick()
	check(stats.has_curse(Curses.Type.DIZZY), "still cursed")
	stats.tick()
	check(not stats.is_cursed(), "worn off")


func test_no_power_and_speed_curses_are_temporary() -> void:
	var stats := PlayerStats.new()
	stats.max_bombs = 5
	stats.fire_range = 6
	stats.set_curse(Curses.Type.NO_POWER, 5)
	check_eq([stats.bomb_capacity(), stats.blast_range()], [1, 1], "no power")
	stats.clear_curse()
	check_eq([stats.bomb_capacity(), stats.blast_range()], [5, 6], "stats come back")
	stats.set_curse(Curses.Type.TOO_FAST, 5)
	check_eq(stats.speed(), Rules.CURSE_FAST_SPEED, "too fast")
	stats.set_curse(Curses.Type.TOO_SLOW, 5)
	check_eq(stats.speed(), Rules.CURSE_SLOW_SPEED, "too slow")


func test_fuse_curses() -> void:
	var stats := PlayerStats.new()
	check_eq(stats.bomb_fuse(), Rules.BOMB_FUSE_TICKS, "normal")
	stats.set_curse(Curses.Type.SHORT_FUSE, 5)
	check_eq(stats.bomb_fuse(), Rules.SHORT_FUSE_TICKS, "short")
	stats.set_curse(Curses.Type.LONG_FUSE, 5)
	check_eq(stats.bomb_fuse(), Rules.LONG_FUSE_TICKS, "long")


func test_random_curse_covers_all() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var seen := {}
	for i in 500:
		seen[Curses.random(rng)] = true
	check_eq(seen.size(), Curses.ALL.size(), "every curse comes up")
	for curse in Curses.ALL:
		check(Curses.display_name(curse) != "", "name for %d" % curse)


func test_curse_spread_setting() -> void:
	var s := MatchSettings.new()
	check(s.curse_spread and s.value_text("curse_spread") == "On", "on by default")
	s.step("curse_spread", 1)
	check(not s.curse_spread, "toggled")
	check("curse_spread" in s.rows(), "in the panel")


# --- In the match --------------------------------------------------------------

func test_skull_pickup_curses_the_player() -> void:
	var m := _playing([0])
	var p: Node3D = m.players[0]
	m.items.place(p.get_cell(), Items.Type.SKULL)
	_run(m, 1)
	check(p.stats.is_cursed(), "cursed: %s" % Curses.display_name(p.stats.curse))
	check_eq(p.stats.curse_ticks, Rules.CURSE_TICKS, "full duration (timers already ticked this tick)")
	_done(m)


func test_hands_tied_blocks_bombs() -> void:
	var m := _playing([0])
	var p: Node3D = m.players[0]
	p.stats.set_curse(Curses.Type.HANDS_TIED, 100)
	m.try_place_bomb(p)
	check_eq(m.bombs.bomb_count(0), 0, "no bomb")
	_done(m)


func test_loose_hands_drops_bombs_by_itself() -> void:
	var m := _playing([0])
	var p: Node3D = m.players[0]
	p.stats.set_curse(Curses.Type.LOOSE_HANDS, 100)
	_run(m, 1)
	check_eq(m.bombs.bomb_count(0), 1, "dropped one without pressing")
	_done(m)


func test_short_fuse_bombs() -> void:
	var m := _playing([0])
	var p: Node3D = m.players[0]
	p.stats.set_curse(Curses.Type.SHORT_FUSE, 1000)
	m.try_place_bomb(p)
	check_eq(m.bombs.fuse_left(p.get_cell()), Rules.SHORT_FUSE_TICKS, "short fuse")
	_done(m)


func test_dizzy_reverses_and_cant_stop_keeps_walking() -> void:
	var m := _playing([0])
	var p: Node3D = m.players[0]
	p.stats.set_curse(Curses.Type.DIZZY, 100)
	check_eq(p.movement_dirs([Vector2i.RIGHT] as Array[Vector2i]), [Vector2i.LEFT] as Array[Vector2i], "reversed")
	p.stats.set_curse(Curses.Type.CANT_STOP, 100)
	p.facing = Vector2i.DOWN
	check_eq(p.movement_dirs([] as Array[Vector2i]), [Vector2i.DOWN] as Array[Vector2i], "keeps walking")
	p.input_enabled = true
	var start: Vector2 = p.grid_pos
	_run(m, 10)
	check(p.grid_pos.y > start.y, "moved with nothing held")
	_done(m)


func test_curse_spreads_on_touch() -> void:
	var m := _playing([0, 1])
	var a: Node3D = m.players[0]
	var b: Node3D = m.players[1]
	a.stats.set_curse(Curses.Type.TOO_SLOW, 500)
	b.grid_pos = a.grid_pos + Vector2(0.3, 0)
	_run(m, 1)
	check(b.stats.has_curse(Curses.Type.TOO_SLOW), "caught it")
	check(a.stats.is_cursed(), "the first player keeps it too")
	check(b.stats.curse_ticks <= 500 and b.stats.curse_ticks > 490, "with the remaining time")
	_done(m)


func test_no_spreading_when_turned_off() -> void:
	var settings := MatchSettings.new()
	settings.curse_spread = false
	var m := _playing([0, 1], settings)
	var a: Node3D = m.players[0]
	var b: Node3D = m.players[1]
	a.stats.set_curse(Curses.Type.TOO_SLOW, 500)
	b.grid_pos = a.grid_pos
	_run(m, 1)
	check(not b.stats.is_cursed(), "not passed on")
	_done(m)


func test_swap_trades_places() -> void:
	var m := _playing([0, 1])
	var a: Node3D = m.players[0]
	var b: Node3D = m.players[1]
	var a_start: Vector2 = a.grid_pos
	var b_start: Vector2 = b.grid_pos
	a.stats.set_curse(Curses.Type.SWAP, 1000)
	_run(m, Rules.TICKS_PER_SECOND + 1)
	check(a.grid_pos == b_start and b.grid_pos == a_start, "swapped: %s %s" % [a.grid_pos, b.grid_pos])
	_done(m)


func test_death_clears_the_curse() -> void:
	var m := _playing([0, 1])
	var p: Node3D = m.players[0]
	p.stats.set_curse(Curses.Type.DIZZY, 500)
	p.die()
	check(not p.stats.is_cursed(), "cleared")
	_done(m)
