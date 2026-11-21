extends "res://tests/test_suite.gd"
## Integration tests: the real match scene with players, bombs and rounds, ticked by hand.

const MATCH_SCENE := preload("res://scenes/game/match.tscn")
const TICK := 1.0 / Rules.TICKS_PER_SECOND
const INTRO := Rules.INTRO_ROUND_TICKS + Rules.INTRO_READY_TICKS


## A match with players in `slots`, already past the intro of round 1.
func _playing(slots: Array[int], settings := MatchSettings.new()) -> Node3D:
	GameState.settings = settings  # never the player's saved settings
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


func test_bomb_kills_player_standing_on_it() -> void:
	var m := _playing([0])
	var p: Node3D = m.players[0]
	m.try_place_bomb(p)
	check(m.bombs.has_bomb(Vector2i(1, 1)), "bomb under the player")
	_run(m, Rules.BOMB_FUSE_TICKS - 1)
	check(p.alive, "alive before the explosion")
	_run(m, 1)
	check(not p.alive, "killed by own bomb")
	m.free()


func test_no_bombs_during_intro() -> void:
	var m := _playing([0])
	m._start_round()  # back into an intro
	m.try_place_bomb(m.players[0])
	check_eq(m.bombs.bomb_count(0), 0, "bomb refused while input is locked")
	check(not m.players[0].input_enabled, "input locked in intro")
	m.free()


func test_bomb_limit_is_one_at_start() -> void:
	var m := _playing([0])
	var p: Node3D = m.players[0]
	m.try_place_bomb(p)
	p.grid_pos = Vector2(2, 1)
	m.try_place_bomb(p)
	check_eq(m.bombs.bomb_count(0), 1, "second bomb refused")
	m.free()


func test_bomb_blocks_other_players_but_not_its_owner_leaving() -> void:
	var m := _playing([0, 1])
	var bomber: Node3D = m.players[0]
	m.try_place_bomb(bomber)
	check(m.is_blocked_for(m.players[1], Vector2i(1, 1)), "bomb cell blocked")
	var result := GridMovement.step(bomber.grid_pos, [Vector2i.RIGHT] as Array[Vector2i], 0.2,
		func(cell): return m.is_blocked_for(bomber, cell))
	check(result.pos.x > 1.0, "owner walks off the bomb: %s" % result.pos)
	m.free()


func test_blast_burns_brick_and_frees_the_cell() -> void:
	var m := _playing([0])
	var p: Node3D = m.players[0]
	p.grid_pos = Vector2(3, 1)  # classic level: brick at (4, 1)
	m.try_place_bomb(p)
	p.grid_pos = Vector2(1, 2)  # out of range, around the corner
	_run(m, Rules.BOMB_FUSE_TICKS)
	check(m.bombs.is_burning(Vector2i(4, 1)), "brick burning")
	check(p.alive, "player out of range survived")
	_run(m, Rules.FLAME_TICKS)
	check_eq(m.grid.get_cell(Vector2i(4, 1)), Grid.Cell.EMPTY, "brick gone")
	m.free()


func test_walking_into_fire_kills() -> void:
	var m := _playing([0, 1])
	var bomber: Node3D = m.players[0]
	var victim: Node3D = m.players[1]
	bomber.grid_pos = Vector2(10, 3)
	m.try_place_bomb(bomber)
	bomber.grid_pos = Vector2(13, 5)
	victim.grid_pos = Vector2(13, 3)  # outside the blast (range 2 reaches x=12)
	_run(m, Rules.BOMB_FUSE_TICKS)
	check(victim.alive, "outside the blast")
	victim.grid_pos = Vector2(12, 3)  # steps into the flame
	_run(m, 1)
	check(not victim.alive, "walked into fire")
	m.free()


func test_round_win_then_fresh_round() -> void:
	var m := _playing([0, 1])
	var loser: Node3D = m.players[1]
	m.try_place_bomb(loser)  # blows itself up at its spawn
	_run(m, Rules.BOMB_FUSE_TICKS + Rules.ROUND_END_DELAY_TICKS)
	check_eq(m.rules.state, MatchRules.State.ROUND_OVER, "round decided")
	check_eq(m.rules.wins, {0: 1, 1: 0}, "white wins the round")
	_run(m, Rules.ROUND_OVER_TICKS)
	check_eq(m.rules.round_number, 2, "round 2 started")
	check(loser.alive and loser.grid_pos == Vector2(m.grid.spawns[1]), "loser back at spawn")
	check(not loser.input_enabled, "locked during the intro")
	check_eq(m.bombs.bomb_count(1), 0, "bombs cleared")
	m.free()


func test_falling_block_crushes_player_and_bomb() -> void:
	var m := _playing([0, 1])
	var p: Node3D = m.players[0]
	p.grid_pos = Vector2(3, 1)
	m.try_place_bomb(p)
	m.rules.block_landed.emit(Vector2i(3, 1))
	check_eq(m.grid.get_cell(Vector2i(3, 1)), Grid.Cell.HARD, "cell is now solid")
	check(not m.bombs.has_bomb(Vector2i(3, 1)), "bomb crushed without exploding")
	check(not p.alive, "player crushed")
	m.free()


func test_finished_match_records_results() -> void:
	var m := _playing([0, 1])
	for round in Rules.WINS_TO_WIN:
		m.try_place_bomb(m.players[1])  # black blows itself up every round
		_run(m, Rules.BOMB_FUSE_TICKS + Rules.ROUND_END_DELAY_TICKS + Rules.ROUND_OVER_TICKS)
		if round < Rules.WINS_TO_WIN - 1:
			_run(m, INTRO)
	check_eq(m.rules.state, MatchRules.State.MATCH_OVER, "match over")
	_run(m, Rules.MATCH_OVER_TICKS)
	check_eq(GameState.last_results, {"wins": {0: 3, 1: 0}, "winner": 0, "rounds": 3}, "results stored")
	m.free()


func test_lobby_colours_reach_the_players() -> void:
	GameState.lobby.join(0)
	GameState.lobby.cycle_color(0, 1)  # white -> black
	var m := _playing([0])
	check_eq(m.players[0].color, Palette.PLAYER_COLORS[1], "player uses the lobby colour")
	check_eq(m._player_name(0), "BLACK", "announced by colour name")
	GameState.lobby.reset()
	m.free()


func test_no_bombs_while_paused() -> void:
	var m := _playing([0])
	m._toggle_pause()
	check(m.get_tree().paused, "paused")
	m.try_place_bomb(m.players[0])  # e.g. Cross pressed to choose RESUME
	check_eq(m.bombs.bomb_count(0), 0, "no bomb dropped while paused")
	m._pause_changed_frame = -1
	m._resume()
	check(not m.get_tree().paused, "resumed")
	m.free()


func test_two_pause_presses_in_one_frame_stay_paused() -> void:
	var m := _playing([0, 1])
	m._toggle_pause()
	m._toggle_pause()  # second player, same physics frame
	check(m.get_tree().paused, "still paused")
	m._pause_changed_frame = -1
	m._resume()
	m.free()


func test_death_on_last_end_delay_tick_is_a_draw() -> void:
	var m := _playing([0, 1])
	m.players[1].die()
	m.rules._end_delay = 1  # the round would be decided on the next tick
	m.bombs._flames[m.players[0].get_cell()] = 5  # survivor is standing in fire
	_run(m, 1)
	check(not m.players[0].alive, "survivor died this tick")
	check_eq(m.rules.round_winner, -1, "counted as a draw, not a win")
	m.free()


func test_starting_stats_come_from_settings() -> void:
	var settings := MatchSettings.new()
	settings.start_bombs = 2
	settings.start_fire = 4
	var m := _playing([0], settings)
	var p: Node3D = m.players[0]
	check_eq([p.max_bombs, p.fire_range], [2, 4], "stats applied")
	m.try_place_bomb(p)
	p.grid_pos = Vector2(2, 1)
	m.try_place_bomb(p)
	check_eq(m.bombs.bomb_count(0), 2, "two bombs allowed")
	GameState.settings = MatchSettings.new()
	m.free()


func test_wins_needed_from_settings() -> void:
	var settings := MatchSettings.new()
	settings.wins_to_win = 1
	var m := _playing([0, 1], settings)
	m.try_place_bomb(m.players[1])
	_run(m, Rules.BOMB_FUSE_TICKS + Rules.ROUND_END_DELAY_TICKS + Rules.ROUND_OVER_TICKS)
	check_eq(m.rules.state, MatchRules.State.MATCH_OVER, "one win ends the match")
	GameState.settings = MatchSettings.new()
	m.free()
