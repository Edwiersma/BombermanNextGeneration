extends "res://tests/test_suite.gd"
## BomberAI's item tactics (AI-M2) and cornering (AI-M3) in the real match scene: a Hard AI in
## slot 1 and a player in slot 2 who never presses anything, on the Classic stage with every brick
## cleared away. InputRouter ticks too: that is how the AI's buttons reach its player.

const MATCH_SCENE := preload("res://scenes/game/match.tscn")
const TICK := 1.0 / Rules.TICKS_PER_SECOND
const INTRO := Rules.INTRO_ROUND_TICKS + Rules.INTRO_READY_TICKS


## The match, past the intro, with the AI at `ai_cell` holding `items` and the idle player at
## `target_cell`.
func _arena(ai_cell: Vector2i, target_cell: Vector2i, items: Array = []) -> Node3D:
	var settings := MatchSettings.new()
	settings.item_frequency = 0
	GameState.settings = settings
	var m: Node3D = MATCH_SCENE.instantiate()
	m.allow_drop_in = false
	m.leave_on_finish = false
	m.rng_seed = 5
	(Engine.get_main_loop() as SceneTree).root.add_child(m)
	m.add_ai_player(0, BomberAI.Level.HARD)
	m._spawn_player(1, "idle")
	m._begin_match()
	_run(m, INTRO)
	for cell in m.grid.cells_of(Grid.Cell.SOFT):
		m.grid.set_cell(cell, Grid.Cell.EMPTY)
	m.players[0].teleport(Vector2(ai_cell))
	m.players[1].teleport(Vector2(target_cell))
	for item: int in items:
		m.players[0].stats.apply(item)
	m.ais[0].reset()
	return m


func _run(m: Node3D, ticks: int, until := Callable()) -> bool:
	for i in ticks:
		InputRouter._physics_process(TICK)
		m._physics_process(TICK)
		for player in m.players:
			if player:
				player._physics_process(TICK)
		if until.is_valid() and until.call():
			return true
	return false


func _done(m: Node3D) -> void:
	m.free()


func test_kicks_a_bomb_at_a_player() -> void:
	var m := _arena(Vector2i(3, 1), Vector2i(11, 1), [Items.Type.KICK])
	var kicked := []
	m.bombs.bomb_kicked.connect(func(_id, _cell, dir): kicked.append(dir))
	m.players[0].facing = Vector2i.RIGHT
	m.bombs.place_bomb(Vector2i(4, 1), 1, 2)  # the other player's bomb, right next to the AI
	_run(m, 60, func(): return not kicked.is_empty())
	check_eq(kicked, [Vector2i.RIGHT], "kicked it down the row at the player")
	_done(m)


func test_punches_a_bomb_at_a_player() -> void:
	var m := _arena(Vector2i(3, 1), Vector2i(7, 1), [Items.Type.PUNCH])
	m.players[0].facing = Vector2i.RIGHT
	m.bombs.place_bomb(Vector2i(4, 1), 1, 2)
	check(_run(m, 60, func(): return m.bombs.flying_count() > 0), "punched it")
	_done(m)


func test_throws_a_bomb_at_a_player() -> void:
	var m := _arena(Vector2i(3, 1), Vector2i(7, 1), [Items.Type.GLOVE])
	check(_run(m, 90, func(): return m.bombs.flying_count() > 0), "picked a bomb up and threw it")
	check(m.players[0].alive, "and is fine")
	_done(m)


func test_lays_a_line_bomb_at_a_player() -> void:
	var m := _arena(Vector2i(2, 1), Vector2i(6, 1), [Items.Type.LINE_BOMB, Items.Type.BOMB_UP, Items.Type.BOMB_UP])
	check(_run(m, 90, func(): return m.bombs.bomb_count(0) >= 3), "a row of bombs")
	_done(m)


func test_lays_a_land_mine_in_a_corridor() -> void:
	var m := _arena(Vector2i(2, 1), Vector2i(9, 1), [Items.Type.LAND_MINE])
	var mined := func():
		for x in range(1, 14):
			for y in range(1, 12):
				if m.bombs.has_mine(Vector2i(x, y)):
					return true
		return false
	check(_run(m, 300, mined), "a mine went down")
	_done(m)


func test_cornering_a_player_counts() -> void:
	# A player in a dead end: a bomb at its mouth leaves them nowhere to hide.
	var ai := BomberAI.new(0, BomberAI.Level.HARD, 1, BomberAI.Personality.BALANCED)
	var view := BomberAI.View.new()
	view.grid = grid_from_rows(["###########", "#.........#", "###########"])
	view.bombs = BombField.new(view.grid)
	view.items = ItemField.new(view.grid)
	view.stats = PlayerStats.new()
	view.stats.reset(MatchSettings.new())
	view.others.append(Vector2(1, 1))
	var bomb := {"cell": Vector2i(3, 1), "owner": 0, "fire_range": 3, "fuse": 180, "remote": false, "pierce": false,
		"dangerous": false, "mine": false, "armed": false, "flying": false}
	var danger := DangerMap.build(view.grid, [bomb], {}, view.items, 0)
	check_eq(ai._trap_value(view, danger, {Vector2i(3, 1): true}, Vector2i(3, 1)), BomberAI.TRAP_KILL_VALUE, "cornered")
	var open_view := view
	open_view.others = [Vector2(8, 1)] as Array[Vector2]
	check_eq(ai._trap_value(open_view, danger, {Vector2i(3, 1): true}, Vector2i(3, 1)), 0.0, "far side, out of reach: room to run")
	open_view.others = [Vector2(6, 1)] as Array[Vector2]
	check_eq(ai._trap_value(open_view, danger, {Vector2i(3, 1): true}, Vector2i(3, 1)), 0.0, "far side in the blast, but it can step out")


func test_personalities_nudge_the_numbers() -> void:
	var balanced := BomberAI.profile_for(BomberAI.Level.NORMAL, BomberAI.Personality.BALANCED)
	var aggressive := BomberAI.profile_for(BomberAI.Level.NORMAL, BomberAI.Personality.AGGRESSIVE)
	var cautious := BomberAI.profile_for(BomberAI.Level.NORMAL, BomberAI.Personality.CAUTIOUS)
	var collector := BomberAI.profile_for(BomberAI.Level.NORMAL, BomberAI.Personality.COLLECTOR)
	check(aggressive.aggression > balanced.aggression, "aggressive goes for players more")
	check(cautious.margin > balanced.margin, "cautious keeps more distance from fire")
	check(collector.item_range > balanced.item_range and collector.item_bonus > 0.0, "collector wants items")
	check_eq(BomberAI.PROFILES[BomberAI.Level.NORMAL].aggression, 0.7, "the level's own numbers are untouched")
