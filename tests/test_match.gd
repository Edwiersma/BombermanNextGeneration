extends "res://tests/test_suite.gd"
## Integration tests: the real match scene with players and bombs, ticked by hand.

const MATCH_SCENE := preload("res://scenes/game/match.tscn")
const TICK := 1.0 / Rules.TICKS_PER_SECOND


func _new_match() -> Node3D:
	var match_node: Node3D = MATCH_SCENE.instantiate()
	match_node.allow_drop_in = false
	match_node.rng_seed = 1
	(Engine.get_main_loop() as SceneTree).root.add_child(match_node)
	return match_node


func _run(match_node: Node3D, ticks: int) -> void:
	for i in ticks:
		match_node._physics_process(TICK)
		for player in match_node.players:
			if player:
				player._physics_process(TICK)


func _player(match_node: Node3D, slot: int) -> Node3D:
	match_node._spawn_player(slot, "kb%d" % slot)
	return match_node.players[slot]


func test_bomb_kills_player_standing_on_it() -> void:
	var m := _new_match()
	var p := _player(m, 0)
	m.try_place_bomb(p)
	check(m.bombs.has_bomb(Vector2i(1, 1)), "bomb under the player")
	_run(m, Rules.BOMB_FUSE_TICKS - 1)
	check(p.alive, "alive before the explosion")
	_run(m, 1)
	check(not p.alive, "killed by own bomb")
	m.free()


func test_bomb_limit_is_one_at_start() -> void:
	var m := _new_match()
	var p := _player(m, 0)
	m.try_place_bomb(p)
	p.grid_pos = Vector2(2, 1)
	m.try_place_bomb(p)
	check_eq(m.bombs.bomb_count(0), 1, "second bomb refused")
	m.free()


func test_bomb_blocks_other_players_but_not_its_owner_leaving() -> void:
	var m := _new_match()
	var owner := _player(m, 0)
	var other := _player(m, 1)
	m.try_place_bomb(owner)
	check(m.is_blocked_for(other, Vector2i(1, 1)), "bomb cell blocked")
	# The owner stands on the bomb and can still step off it to the right.
	var result := GridMovement.step(owner.grid_pos, [Vector2i.RIGHT] as Array[Vector2i], 0.2,
		func(cell): return m.is_blocked_for(owner, cell))
	check(result.pos.x > 1.0, "owner walks off the bomb: %s" % result.pos)
	m.free()


func test_blast_burns_brick_and_frees_the_cell() -> void:
	var m := _new_match()
	var p := _player(m, 0)
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
	var m := _new_match()
	var bomber := _player(m, 0)
	var victim := _player(m, 1)
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
