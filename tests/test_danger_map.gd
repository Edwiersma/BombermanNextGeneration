extends "res://tests/test_suite.gd"
## DangerMap: the AI's forecast of where and when fire will be.

const OPEN := ["#########", "#.......#", "#.......#", "#.......#", "#########"]
const FLAME := Rules.FLAME_TICKS


func _bomb(cell: Vector2i, fuse := 100, fire_range := 2, extra := {}) -> Dictionary:
	var bomb := {"cell": cell, "owner": 1, "fire_range": fire_range, "fuse": fuse, "remote": false,
		"pierce": false, "dangerous": false, "mine": false, "armed": false, "flying": false}
	bomb.merge(extra, true)
	return bomb


func _map(rows: Array, bombs: Array, flames := {}, doomed := {}) -> DangerMap:
	return DangerMap.build(grid_from_rows(rows), bombs, flames, null, 0, doomed)


func test_a_bomb_threatens_its_cross_from_its_fuse() -> void:
	var map := _map(OPEN, [_bomb(Vector2i(4, 2), 100, 2)])
	check(map.threatened(Vector2i(4, 2)) and map.threatened(Vector2i(6, 2)) and map.threatened(Vector2i(4, 1)), "the cross")
	check(not map.threatened(Vector2i(7, 2)), "beyond its range")
	check(not map.threatened(Vector2i(5, 1)), "not diagonally")
	check(map.is_clear(Vector2i(6, 2), 0, 99), "clear until it goes off")
	check(not map.is_clear(Vector2i(6, 2), 99, 101), "on fire when it does")
	check(map.safe_from(Vector2i(6, 2), 100 + FLAME + 1), "and safe once the fire is out")
	check_eq(map.time_to_fire(Vector2i(6, 2)), 100, "time to fire")


func test_chain_reactions_bring_fire_forward() -> void:
	var map := _map(OPEN, [_bomb(Vector2i(2, 2), 30, 2), _bomb(Vector2i(4, 2), 150, 2)])
	check_eq(map.time_to_fire(Vector2i(6, 2)), 30, "the second bomb goes off with the first")


func test_hard_blocks_and_bricks_stop_fire() -> void:
	var map := _map(["#######", "#..+..#", "#.#.#.#", "#######"], [_bomb(Vector2i(1, 1), 50, 4)])
	check(map.threatened(Vector2i(3, 1)), "the brick itself burns")
	check(not map.threatened(Vector2i(4, 1)), "nothing behind it")
	check(not map.threatened(Vector2i(1, 3)), "the outer wall stops it")


func test_a_brick_an_earlier_blast_burns_stops_nothing_later() -> void:
	# The first bomb (right of the brick) burns it; the second (left) goes off after it is gone,
	# and also passes the first bomb's cell, which is empty by then.
	var rows := ["##########", "#..+.....#", "##########"]
	var map := _map(rows, [_bomb(Vector2i(4, 1), 10, 1), _bomb(Vector2i(1, 1), 100, 6)])
	check_eq(map.time_to_fire(Vector2i(6, 1)), 100, "the later blast passes where the brick was")
	var alone := _map(rows, [_bomb(Vector2i(1, 1), 100, 6)])
	check(not alone.threatened(Vector2i(6, 1)), "without the first bomb the brick shields it")


func test_piercing_fire_goes_through_bricks() -> void:
	var map := _map(["#######", "#..+..#", "#######"], [_bomb(Vector2i(1, 1), 50, 4, {"pierce": true})])
	check(map.threatened(Vector2i(5, 1)), "through the brick")


func test_dangerous_bombs_burn_a_square() -> void:
	var map := _map(OPEN, [_bomb(Vector2i(4, 2), 50, 1, {"dangerous": true})])
	check(map.threatened(Vector2i(4 + Rules.DANGEROUS_RADIUS, 2 - 1)), "corner of the square")


func test_separate_fires_keep_separate_windows() -> void:
	# (2, 1) is hit at tick 10 and again at tick 150; the gap between counts as clear.
	var map := _map(["#######", "#.....#", "#######"], [_bomb(Vector2i(1, 1), 10, 1), _bomb(Vector2i(3, 1), 150, 1)])
	check(map.is_clear(Vector2i(2, 1), 10 + FLAME + 1, 149), "clear between the two")
	check_eq(map.clear_until(Vector2i(2, 1), 60.0), 150.0, "until the second")
	check(not map.safe_from(Vector2i(2, 1), 60), "not safe for good")


func test_current_flames_and_falling_blocks() -> void:
	var map := _map(OPEN, [], {Vector2i(1, 1): 12}, {Vector2i(3, 3): 40})
	check(not map.is_clear(Vector2i(1, 1), 0, 5), "burning now")
	check(map.safe_from(Vector2i(1, 1), 13), "out soon")
	check(map.is_clear(Vector2i(3, 3), 0, 39), "the block has not landed yet")
	check(not map.safe_from(Vector2i(3, 3), 10000), "deadly for good once it has")


func test_remote_bombs() -> void:
	var map := _map(OPEN, [_bomb(Vector2i(2, 2), 0, 1, {"remote": true, "owner": 1}),
		_bomb(Vector2i(6, 2), 0, 1, {"remote": true, "owner": 0})])
	check_eq(map.time_to_fire(Vector2i(2, 2)), DangerMap.ENEMY_REMOTE_TICKS, "someone else's: about to go off")
	check_eq(map.time_to_fire(Vector2i(6, 2)), DangerMap.OWN_REMOTE_TICKS, "our own: when we choose")


func test_land_mines_block_the_way_and_chain() -> void:
	var map := _map(OPEN, [_bomb(Vector2i(5, 2), 0, 2, {"mine": true, "armed": true}), _bomb(Vector2i(3, 2), 40, 2)])
	check(map.mines.has(Vector2i(5, 2)), "an armed mine is off limits")
	check_eq(map.time_to_fire(Vector2i(7, 2)), 40, "set off by the bomb's fire")
	var lone := _map(OPEN, [_bomb(Vector2i(5, 2), 0, 2, {"mine": true, "armed": true})])
	check(not lone.threatened(Vector2i(6, 2)), "a mine on its own has no fuse")
