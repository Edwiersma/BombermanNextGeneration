extends "res://tests/test_suite.gd"

const UP := Vector2i.UP
const DOWN := Vector2i.DOWN
const LEFT := Vector2i.LEFT
const RIGHT := Vector2i.RIGHT

# (1,2) is a wall below the start cell, (2,2) is an opening to its right.
const CORNER_ROWS := [
	"######",
	"#....#",
	"##.###",
	"#....#",
	"######",
]


func _grid(rows: Array) -> Grid:
	return grid_from_rows(rows)


func _step(grid: Grid, pos: Vector2, dirs: Array[Vector2i], distance: float) -> Dictionary:
	return GridMovement.step(pos, dirs, distance, grid.is_blocking)


func _near(a: Vector2, b: Vector2) -> bool:
	return a.distance_to(b) < 0.001


func test_moves_freely_in_open_corridor() -> void:
	var result := _step(_grid(CORNER_ROWS), Vector2(1, 1), [RIGHT], 0.25)
	check(_near(result.pos, Vector2(1.25, 1)), "moved right: %s" % result.pos)
	check_eq(result.dir, RIGHT, "dir")


func test_stops_at_cell_centre_before_wall() -> void:
	var grid := _grid(CORNER_ROWS)
	var result := _step(grid, Vector2(1.2, 1), [LEFT], 0.4)
	check(_near(result.pos, Vector2(1, 1)), "walks to centre then stops: %s" % result.pos)
	result = _step(grid, result.pos, [LEFT], 0.4)
	check(_near(result.pos, Vector2(1, 1)), "stays at centre: %s" % result.pos)
	check_eq(result.dir, Vector2i.ZERO, "no movement reported")


func test_lines_up_with_lane_before_turning() -> void:
	var grid := _grid(CORNER_ROWS)
	# Slightly below row 1 centre, pressing right: first moves up to y=1, then right.
	var result := _step(grid, Vector2(1, 1.1), [RIGHT], 0.3)
	check(_near(result.pos, Vector2(1.2, 1)), "aligned then moved: %s" % result.pos)


func test_corner_assist_slides_into_open_lane() -> void:
	var grid := _grid(CORNER_ROWS)
	# Wall below (1,1); overlapping lane x=2 by 0.3, which is open below.
	var result := _step(grid, Vector2(1.3, 1), [DOWN], 0.2)
	check(_near(result.pos, Vector2(1.5, 1)), "slid towards x=2: %s" % result.pos)
	check_eq(result.dir, DOWN, "still facing the pressed direction")
	for i in 10:
		result = _step(grid, result.pos, [DOWN], 0.2)
	check(result.pos.x == 2.0 and result.pos.y > 1.5, "went round the corner: %s" % result.pos)


func test_no_corner_assist_below_threshold() -> void:
	var result := _step(_grid(CORNER_ROWS), Vector2(1.1, 1), [DOWN], 0.2)
	check(_near(result.pos, Vector2(1.1, 1)), "too little overlap, no slide: %s" % result.pos)


func test_newest_direction_wins_when_possible() -> void:
	var result := _step(_grid(CORNER_ROWS), Vector2(2, 1), [DOWN, RIGHT], 0.2)
	check(_near(result.pos, Vector2(2, 1.2)), "turned down: %s" % result.pos)


func test_falls_back_to_older_direction_when_blocked() -> void:
	# Holding right, then pressing down at a wall: keep running right.
	var result := _step(_grid(CORNER_ROWS), Vector2(3, 1), [DOWN, RIGHT], 0.2)
	check(_near(result.pos, Vector2(3.2, 1)), "kept moving right: %s" % result.pos)
	check_eq(result.dir, RIGHT, "dir")


func test_queued_turn_newest_first() -> void:
	# Running left past an opening while also holding down (pressed last): line up, then go down.
	var grid := _grid(["#####", "#...#", "#.#.#", "#...#", "#####"])
	var pos := Vector2(1.27, 1)
	for i in 12:
		pos = _step(grid, pos, [DOWN, LEFT], 0.067).pos
	check(pos.x == 1.0 and pos.y > 1.3, "turned down at x=1: %s" % pos)


func test_queued_turn_oldest_first() -> void:
	# Same, but left was pressed last: run into the wall, then fall back to down.
	var grid := _grid(["#####", "#...#", "#.#.#", "#...#", "#####"])
	var pos := Vector2(1.27, 1)
	for i in 12:
		pos = _step(grid, pos, [LEFT, DOWN], 0.067).pos
	check(pos.x == 1.0 and pos.y > 1.3, "turned down after reaching the wall: %s" % pos)


func test_soft_blocks_block_movement() -> void:
	var grid := _grid(["#####", "#.+.#", "#####"])
	var result := _step(grid, Vector2(1, 1), [RIGHT], 0.4)
	check(_near(result.pos, Vector2(1, 1)), "blocked by brick: %s" % result.pos)


func test_step_never_exceeds_max_step() -> void:
	var grid := _grid(["########", "#......#", "########"])
	var result := _step(grid, Vector2(1, 1), [RIGHT], 5.0)
	check(_near(result.pos, Vector2(1 + Rules.MAX_STEP, 1)), "clamped: %s" % result.pos)


func test_cannot_cross_into_blocked_cell_at_speed() -> void:
	var grid := _grid(["#####", "#..##", "#####"])
	var pos := Vector2(1, 1)
	for i in 20:
		pos = _step(grid, pos, [RIGHT], Rules.MAX_STEP).pos
	check(_near(pos, Vector2(2, 1)), "stopped at the last open cell: %s" % pos)
