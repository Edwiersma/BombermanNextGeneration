extends "res://tests/test_suite.gd"

const CLASSIC := preload("res://levels/classic.tres")


func _classic(players := 4) -> Grid:
	return CLASSIC.build_grid(RandomNumberGenerator.new(), players)


func _level(rows: Array, chance := 0.0) -> LevelData:
	var level := LevelData.new()
	level.layout = PackedStringArray(rows)
	level.random_soft_chance = chance
	return level


func test_classic_is_valid() -> void:
	check_eq(CLASSIC.validate(), PackedStringArray(), "validation errors")


func test_classic_size_is_13x11_plus_walls() -> void:
	var grid := _classic()
	check_eq(Vector2i(grid.width, grid.height), Vector2i(15, 13), "grid size")


func test_border_is_hard() -> void:
	var grid := _classic()
	for y in grid.height:
		for x in grid.width:
			var cell := Vector2i(x, y)
			if grid.is_border(cell):
				check_eq(grid.get_cell(cell), Grid.Cell.HARD, "border %s" % cell)


func test_pillars_on_even_cells() -> void:
	var grid := _classic()
	for y in range(1, grid.height - 1):
		for x in range(1, grid.width - 1):
			var cell := Vector2i(x, y)
			var is_pillar := x % 2 == 0 and y % 2 == 0
			check_eq(grid.get_cell(cell) == Grid.Cell.HARD, is_pillar, "pillar at %s" % cell)


func test_spawns_in_corners_then_top_and_bottom_middle() -> void:
	var grid := _classic()
	check_eq(grid.spawns, [Vector2i(1, 1), Vector2i(13, 1), Vector2i(1, 11), Vector2i(13, 11),
		Vector2i(7, 1), Vector2i(7, 11)] as Array[Vector2i], "spawns")


func test_spawn_area_is_clear() -> void:
	for players in [4, 5, 6]:
		var grid := _classic(players)
		for i in players:
			var spawn := grid.spawns[i]
			check_eq(grid.get_cell(spawn), Grid.Cell.EMPTY, "%d players: spawn %s" % [players, spawn])
			for dir in Grid.DIRECTIONS:
				check(grid.get_cell(spawn + dir) != Grid.Cell.SOFT, "%d players: soft block next to spawn %s" % [players, spawn])


func test_unused_optional_spawns_stay_bricks() -> void:
	# The original 4-player layout has bricks where the 5th and 6th players would start.
	var grid := _classic(2)
	check_eq(grid.get_cell(Vector2i(7, 1)), Grid.Cell.SOFT, "spawn 5 is a brick")
	check_eq(grid.get_cell(Vector2i(7, 2)), Grid.Cell.SOFT, "and so is its neighbour")
	grid = _classic(5)
	check_eq(grid.get_cell(Vector2i(7, 1)), Grid.Cell.EMPTY, "5 players: spawn 5 open")
	check_eq(grid.get_cell(Vector2i(7, 11)), Grid.Cell.SOFT, "but spawn 6 still a brick")


func test_optional_spawns_may_be_missing_but_not_doubled() -> void:
	check_eq(_level(["#####", "#1.2#", "#...#", "#3.4#", "#####"]).validate(), PackedStringArray(), "no 5/6 is fine")
	var errors := _level(["#####", "#152#", "#.5.#", "#3.4#", "#####"]).validate()
	check("spawn 5" in " | ".join(errors), "doubled spawn 5 reported: %s" % [errors])


func test_out_of_bounds_reads_hard() -> void:
	var grid := _classic()
	check_eq(grid.get_cell(Vector2i(-1, 3)), Grid.Cell.HARD, "left of grid")
	check_eq(grid.get_cell(Vector2i(99, 99)), Grid.Cell.HARD, "far outside")


func test_set_cell_emits_change_once() -> void:
	var grid := _classic()
	var changes := []
	grid.cell_changed.connect(func(cell, old_type, new_type): changes.append([cell, old_type, new_type]))
	var soft: Vector2i = grid.cells_of(Grid.Cell.SOFT)[0]
	grid.set_cell(soft, Grid.Cell.EMPTY)
	grid.set_cell(soft, Grid.Cell.EMPTY)
	check_eq(changes, [[soft, Grid.Cell.SOFT, Grid.Cell.EMPTY]], "change signals")


func test_random_fill_is_deterministic_per_seed() -> void:
	var rows := ["#######", "#1???2#", "#?#?#?#", "#3???4#", "#######"]
	var level := _level(rows, 0.5)
	var a := RandomNumberGenerator.new()
	var b := RandomNumberGenerator.new()
	a.seed = 42
	b.seed = 42
	check_eq(level.build_grid(a).cells_of(Grid.Cell.SOFT), level.build_grid(b).cells_of(Grid.Cell.SOFT), "same seed")


func test_random_fill_respects_spawn_safety() -> void:
	var level := _level(["#######", "#1???2#", "#?#?#?#", "#3???4#", "#######"], 1.0)
	var grid := level.build_grid(RandomNumberGenerator.new())
	# Only the middle column of '?' cells does not touch a spawn.
	check_eq(grid.cells_of(Grid.Cell.SOFT), [Vector2i(3, 1), Vector2i(3, 2), Vector2i(3, 3)] as Array[Vector2i], "soft cells")


func test_validate_reports_problems() -> void:
	var errors := _level(["#####", "#1.2#", "#.x.", "#####"]).validate()
	var text := " | ".join(errors)
	check("length" in text, "ragged row reported: " + text)
	check("spawn 3" in text, "missing spawn reported: " + text)
