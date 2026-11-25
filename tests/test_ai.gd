extends "res://tests/test_suite.gd"
## BomberAI in a small world without the match scene: it sees a View, and its held buttons move
## it (GridMovement) and drop bombs one tick later, as through InputRouter in a real match.

const DIRECTIONS := {&"up": Vector2i.UP, &"down": Vector2i.DOWN, &"left": Vector2i.LEFT, &"right": Vector2i.RIGHT}


class Sim:
	var grid: Grid
	var bombs: BombField
	var items: ItemField
	var ai: BomberAI
	var stats := PlayerStats.new()
	var pos: Vector2
	var alive := true
	var others: Array[Vector2] = []
	var held := {}
	var previous := {}
	var bombs_dropped := 0
	var specials := 0
	var visited := {}

	func _init(target_grid: Grid, start: Vector2i, level: int) -> void:
		grid = target_grid
		bombs = BombField.new(grid)
		items = ItemField.new(grid)
		bombs.items = items
		ai = BomberAI.new(0, level, 99)
		ai.reset()
		stats.reset(MatchSettings.new())
		pos = Vector2(start)

	func cell() -> Vector2i:
		return GridMovement.nearest_cell(pos)

	func run(ticks: int) -> void:
		for i in ticks:
			step()

	func step() -> void:
		if not alive:
			return
		# Last tick's buttons act now: presses first, as InputRouter emits them.
		if held.get(&"bomb", false) and not previous.get(&"bomb", false):
			if not bombs.has_bomb(cell()) and bombs.bomb_count(0) < stats.bomb_capacity():
				bombs.place_bomb(cell(), 0, stats.blast_range(), {"remote": stats.has_remote(), "pierce": stats.has_pierce()})
				bombs_dropped += 1
		if held.get(&"special", false) and not previous.get(&"special", false):
			specials += 1
			bombs.detonate_oldest_remote(0)
		bombs.tick()
		if bombs.has_flame(cell()):
			alive = false
			return
		var item := items.take(cell())
		if item != Items.NONE:
			stats.apply(item)
		var view := BomberAI.View.new()
		view.grid = grid
		view.bombs = bombs
		view.items = items
		view.pos = pos
		view.stats = stats
		view.others = others
		var decision := ai.tick(view)
		var dirs: Array[Vector2i] = []
		for action: StringName in DIRECTIONS:
			if held.get(action, false):
				dirs.append(DIRECTIONS[action])
		var moved := GridMovement.step(pos, dirs, stats.speed() / Rules.TICKS_PER_SECOND,
			func(c: Vector2i) -> bool: return grid.is_blocking(c) or bombs.has_bomb(c))
		pos = moved.pos
		visited[cell()] = true
		previous = held
		held = decision


func test_never_bombs_where_it_cannot_get_away() -> void:
	# A one-cell pocket next to a brick: a bomb here would be suicide.
	var sim := Sim.new(grid_from_rows(["####", "#.+#", "####"]), Vector2i(1, 1), BomberAI.Level.HARD)
	sim.run(400)
	check_eq(sim.bombs_dropped, 0, "no bomb")
	check(sim.alive, "alive")


func test_breaks_bricks_and_gets_away() -> void:
	var rows := ["#########", "#.......#", "#.#.#.#.#", "#...+...#", "#########"]
	for level in [BomberAI.Level.EASY, BomberAI.Level.NORMAL, BomberAI.Level.HARD]:
		var sim := Sim.new(grid_from_rows(rows), Vector2i(1, 1), level)
		sim.run(15 * Rules.TICKS_PER_SECOND)
		check(sim.bombs_dropped >= 1, "level %d: dropped a bomb" % level)
		check_eq(sim.grid.get_cell(Vector2i(4, 3)), Grid.Cell.EMPTY, "level %d: brick gone" % level)
		check(sim.alive, "level %d: still alive" % level)


func test_runs_from_someone_elses_bomb() -> void:
	var sim := Sim.new(grid_from_rows(["#########", "#.......#", "#.......#", "#.......#", "#########"]), Vector2i(4, 2), BomberAI.Level.NORMAL)
	sim.bombs.place_bomb(Vector2i(3, 2), 1, 4)  # fire through its cell in 3 s
	sim.run(Rules.BOMB_FUSE_TICKS + Rules.FLAME_TICKS + 10)
	check(sim.alive, "got out of the way")


func test_walks_round_a_skull_to_a_good_item() -> void:
	var sim := Sim.new(grid_from_rows(["#######", "#.....#", "#.....#", "#######"]), Vector2i(1, 1), BomberAI.Level.HARD)
	sim.items.place(Vector2i(3, 1), Items.Type.SKULL)
	sim.items.place(Vector2i(5, 1), Items.Type.FIRE_UP)
	var fire_before := sim.stats.blast_range()
	sim.run(300)
	check(not sim.visited.has(Vector2i(3, 1)), "never stepped on the skull")
	check_eq(sim.stats.blast_range(), fire_before + 1, "picked up the Fire Up")


func test_bombs_a_player_in_line() -> void:
	var sim := Sim.new(grid_from_rows(["#########", "#.......#", "#.......#", "#.......#", "#########"]), Vector2i(1, 2), BomberAI.Level.HARD)
	sim.others.append(Vector2(6, 2))  # a player who just stands there
	sim.run(400)
	check(sim.bombs_dropped >= 1, "went for them")
	check(sim.alive, "and got away")


func test_sets_off_its_remote_bombs_once_clear() -> void:
	var sim := Sim.new(grid_from_rows(["#########", "#.......#", "#.#.#.#.#", "#...+...#", "#########"]), Vector2i(1, 1), BomberAI.Level.NORMAL)
	sim.stats.apply(Items.Type.REMOTE)
	sim.run(10 * Rules.TICKS_PER_SECOND)
	check(sim.bombs_dropped >= 1 and sim.specials >= 1, "dropped one and pressed the button")
	check_eq(sim.grid.get_cell(Vector2i(4, 3)), Grid.Cell.EMPTY, "brick gone")
	check(sim.alive, "from a safe spot")


func test_does_not_push_into_a_bomb_from_the_middle_of_a_cell() -> void:
	# Walking into a bomb from a cell centre kicks it (for a Kick holder). A bomb dropped in the
	# AI's way must stop it short, not get shoved into the fire next to its owner.
	var sim := Sim.new(grid_from_rows(["#########", "#.......#", "#########"]), Vector2i(2, 1), BomberAI.Level.HARD)
	sim.bombs.place_bomb(Vector2i(3, 1), 1, 1)
	var view := BomberAI.View.new()
	view.grid = sim.grid
	view.bombs = sim.bombs
	view.items = sim.items
	view.stats = sim.stats
	var ai := sim.ai
	ai._path = [Vector2i(3, 1), Vector2i(4, 1)] as Array[Vector2i]
	view.pos = Vector2(2.0, 1.0)
	check(not ai._actions(view, Vector2i(2, 1)).get(&"right", false), "at the centre: let go")
	ai._path = [Vector2i(3, 1), Vector2i(4, 1)] as Array[Vector2i]
	view.pos = Vector2(1.6, 1.0)
	check(ai._actions(view, Vector2i(2, 1)).get(&"right", false), "still well short of it: keep walking")


func test_view_others_and_stats_shape() -> void:
	var ai := BomberAI.new(2, BomberAI.Level.EASY, 5)
	check_eq(ai.slot, 2, "slot")
	check_eq(ai.level, BomberAI.Level.EASY, "level")
	check_eq(BomberAI.new(0, 99).level, BomberAI.Level.HARD, "level clamped")
