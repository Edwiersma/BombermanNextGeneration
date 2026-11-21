extends "res://tests/test_suite.gd"

# 7x7 open room with a pillar pattern-free interior.
const OPEN := [
	"#########",
	"#.......#",
	"#.......#",
	"#.......#",
	"#.......#",
	"#.......#",
	"#.......#",
	"#.......#",
	"#########",
]

var exploded: Array = []  # [cell, owner, flames] per explosion


func _field(rows: Array) -> BombField:
	var field := BombField.new(grid_from_rows(rows))
	field.bomb_exploded.connect(func(_id, cell, owner, flames): exploded.append([cell, owner, flames]))
	return field


func _ticks(field: BombField, count: int) -> void:
	for i in count:
		field.tick()


func _flame_cells(flames: Array) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for flame in flames:
		if flame.kind != BombField.Flame.BLOCK:
			cells.append(flame.cell)
	cells.sort()
	return cells


func _sorted(cells: Array) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	result.assign(cells)
	result.sort()
	return result


func test_place_bomb_blocks_cell_once() -> void:
	var field := _field(OPEN)
	check(field.place_bomb(Vector2i(4, 4), 0, 2), "first bomb placed")
	check(not field.place_bomb(Vector2i(4, 4), 1, 2), "second bomb in same cell refused")
	check(field.has_bomb(Vector2i(4, 4)), "cell has bomb")
	check(not field.place_bomb(Vector2i(0, 0), 0, 2), "cannot place in a wall")
	check_eq(field.bomb_count(0), 1, "owner 0 bomb count")
	check_eq(field.bomb_count(1), 0, "owner 1 bomb count")


func test_explodes_exactly_when_fuse_runs_out() -> void:
	var field := _field(OPEN)
	field.place_bomb(Vector2i(4, 4), 0, 2)
	_ticks(field, Rules.BOMB_FUSE_TICKS - 1)
	check(exploded.is_empty(), "not yet exploded")
	field.tick()
	check_eq(exploded.size(), 1, "exploded on the last fuse tick")
	check(not field.has_bomb(Vector2i(4, 4)), "bomb removed")
	check_eq(field.bomb_count(0), 0, "bomb slot freed")


func test_blast_is_a_cross_of_fire_range() -> void:
	var field := _field(OPEN)
	field.place_bomb(Vector2i(4, 4), 0, 2)
	_ticks(field, Rules.BOMB_FUSE_TICKS)
	var expected := _sorted([
		Vector2i(4, 4),
		Vector2i(4, 3), Vector2i(4, 2), Vector2i(4, 5), Vector2i(4, 6),
		Vector2i(3, 4), Vector2i(2, 4), Vector2i(5, 4), Vector2i(6, 4),
	])
	check_eq(_flame_cells(exploded[0][2]), expected, "flame cells")
	check(field.has_flame(Vector2i(2, 4)), "flame active at the tip")
	check(not field.has_flame(Vector2i(1, 4)), "no flame beyond range")
	check(not field.has_flame(Vector2i(5, 5)), "no diagonal flame")


func test_flame_tips_and_centre_kinds() -> void:
	var field := _field(OPEN)
	field.place_bomb(Vector2i(4, 4), 0, 2)
	_ticks(field, Rules.BOMB_FUSE_TICKS)
	var kinds := {}
	for flame in exploded[0][2]:
		kinds[flame.cell] = flame.kind
	check_eq(kinds[Vector2i(4, 4)], BombField.Flame.CENTER, "centre")
	check_eq(kinds[Vector2i(4, 3)], BombField.Flame.ARM, "arm")
	check_eq(kinds[Vector2i(4, 2)], BombField.Flame.END, "tip")


func test_hard_blocks_stop_the_blast() -> void:
	var field := _field([
		"#######",
		"#.....#",
		"#.#.#.#",
		"#.....#",
		"#######",
	])
	field.place_bomb(Vector2i(3, 1), 0, 3)
	_ticks(field, Rules.BOMB_FUSE_TICKS)
	check(not field.has_flame(Vector2i(3, 0)), "wall above not burnt")
	check(field.has_flame(Vector2i(3, 3)), "flame passes the open gap down")
	check(not field.has_flame(Vector2i(3, 4)), "stops at the outer wall")
	check(field.has_flame(Vector2i(1, 1)) and field.has_flame(Vector2i(5, 1)), "spreads along the corridor")


func test_soft_block_stops_blast_and_burns_away() -> void:
	var field := _field(["#######", "#..+..#", "#######"])
	var destroyed: Array = []
	field.block_destroyed.connect(func(cell): destroyed.append(cell))
	field.place_bomb(Vector2i(1, 1), 0, 4)
	_ticks(field, Rules.BOMB_FUSE_TICKS)
	check(field.is_burning(Vector2i(3, 1)), "brick is burning")
	check(not field.has_flame(Vector2i(4, 1)), "flame stopped at the brick")
	check_eq(field.grid.get_cell(Vector2i(3, 1)), Grid.Cell.SOFT, "burning brick still blocks")
	_ticks(field, Rules.FLAME_TICKS - 1)
	check_eq(field.grid.get_cell(Vector2i(3, 1)), Grid.Cell.SOFT, "still there one tick before")
	field.tick()
	check_eq(field.grid.get_cell(Vector2i(3, 1)), Grid.Cell.EMPTY, "brick gone")
	check_eq(destroyed, [Vector2i(3, 1)], "destroyed signal")


func test_burning_block_still_stops_a_second_blast() -> void:
	var field := _field(["#########", "#...+...#", "#########"])
	var brick := Vector2i(4, 1)
	field.place_bomb(Vector2i(2, 1), 0, 2)            # explodes at tick 180, brick burns until 210
	_ticks(field, 10)
	field.place_bomb(Vector2i(6, 1), 1, 4)            # explodes at tick 190, while the brick burns
	_ticks(field, Rules.BOMB_FUSE_TICKS)
	check_eq(exploded.size(), 2, "both exploded")
	var second := _flame_cells(exploded[1][2])
	check(Vector2i(3, 1) not in second and Vector2i(2, 1) not in second, "second blast stopped at the brick: %s" % [second])
	_ticks(field, Rules.FLAME_TICKS - 11)             # tick 209
	check_eq(field.grid.get_cell(brick), Grid.Cell.SOFT, "burn timer not restarted early")
	field.tick()                                      # tick 210
	check_eq(field.grid.get_cell(brick), Grid.Cell.EMPTY, "brick gone on the original schedule")


func test_chain_reaction_in_same_tick() -> void:
	var field := _field(OPEN)
	field.place_bomb(Vector2i(2, 4), 0, 2)
	_ticks(field, 60)
	field.place_bomb(Vector2i(4, 4), 1, 2)  # within range of the first, fuse much longer
	field.place_bomb(Vector2i(4, 7), 2, 1)  # out of range of both
	_ticks(field, Rules.BOMB_FUSE_TICKS - 60)
	check_eq(exploded.size(), 2, "first bomb set off the second")
	check(not field.has_bomb(Vector2i(4, 4)), "chained bomb gone")
	check(field.has_bomb(Vector2i(4, 7)), "distant bomb untouched")
	check(field.has_flame(Vector2i(6, 4)), "chained bomb's own flames")


func test_blast_stops_at_the_bomb_it_hits() -> void:
	var field := _field(OPEN)
	field.place_bomb(Vector2i(2, 4), 0, 4)
	field.place_bomb(Vector2i(3, 4), 1, 1)
	_ticks(field, Rules.BOMB_FUSE_TICKS)
	# Bomb 1 has range 1, so (5,4) is only reachable if bomb 0's flame had passed through.
	check(not field.has_flame(Vector2i(5, 4)), "first flame stopped at the second bomb")
	check(field.has_flame(Vector2i(4, 4)), "second bomb's own flame")


func test_bomb_placed_into_fire_explodes_next_tick() -> void:
	var field := _field(OPEN)
	field.place_bomb(Vector2i(4, 4), 0, 2)
	_ticks(field, Rules.BOMB_FUSE_TICKS)
	field.place_bomb(Vector2i(4, 5), 1, 2)
	field.tick()
	check_eq(exploded.size(), 2, "exploded straight away")


func test_flames_expire() -> void:
	var field := _field(OPEN)
	field.place_bomb(Vector2i(4, 4), 0, 2)
	_ticks(field, Rules.BOMB_FUSE_TICKS + Rules.FLAME_TICKS - 1)
	check(field.has_flame(Vector2i(4, 4)), "flame still burning one tick before")
	field.tick()
	check(not field.has_flame(Vector2i(4, 4)), "flame gone")
	check(not field.has_flame(Vector2i(2, 4)), "tip gone")
