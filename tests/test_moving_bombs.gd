extends "res://tests/test_suite.gd"
## Kick, punch and the Dangerous Bomb.

const CORRIDOR := ["##########", "#........#", "##########"]
const RIGHT := Vector2i.RIGHT
const LEFT := Vector2i.LEFT

var exploded: Array = []
var removed: Array = []


func _field(rows: Array) -> BombField:
	var field := BombField.new(grid_from_rows(rows))
	field.bomb_exploded.connect(func(_id, cell, _owner, flames): exploded.append([cell, flames]))
	field.bomb_removed.connect(func(id, _cell): removed.append(id))
	return field


func _ticks(field: BombField, count: int) -> void:
	for i in count:
		field.tick()


func _position_of_only_bomb(field: BombField) -> Vector3:
	return field.bomb_positions().values()[0]


# --- Kick --------------------------------------------------------------------

func test_kicked_bomb_slides_to_the_wall() -> void:
	var field := _field(CORRIDOR)
	field.place_bomb(Vector2i(2, 1), 0, 2)
	check(field.kick(Vector2i(2, 1), RIGHT), "kicked")
	_ticks(field, 4)
	var x := _position_of_only_bomb(field).x
	check(x > 2.2 and x < 3.0, "moving smoothly: x=%s" % x)
	_ticks(field, 120)
	check(field.has_bomb(Vector2i(8, 1)), "stopped in the last cell before the wall")
	check(not field.is_sliding(Vector2i(8, 1)), "at rest")
	check_eq(_position_of_only_bomb(field).x, 8.0, "centred")


func test_kick_needs_room() -> void:
	var field := _field(["#####", "#..##", "#####"])
	field.place_bomb(Vector2i(2, 1), 0, 2)
	check(not field.kick(Vector2i(2, 1), RIGHT), "wall right behind it")
	check(not field.kick(Vector2i(1, 1), RIGHT), "no bomb there")


func test_kicked_bomb_stops_before_a_player_and_an_item() -> void:
	var field := _field(CORRIDOR)
	field.player_at = func(cell): return cell == Vector2i(6, 1)
	field.place_bomb(Vector2i(2, 1), 0, 2)
	field.kick(Vector2i(2, 1), RIGHT)
	_ticks(field, 40)  # well inside the 3 s fuse
	check(field.has_bomb(Vector2i(5, 1)), "stopped before the player")

	var items := ItemField.new(field.grid)
	field.items = items
	field.player_at = Callable()
	items.place(Vector2i(7, 1), Items.Type.BOMB_UP)
	field.kick(Vector2i(5, 1), RIGHT)
	_ticks(field, 40)
	check(field.has_bomb(Vector2i(6, 1)), "stopped before the item")
	check(items.has_item(Vector2i(7, 1)), "item untouched")


func test_kicked_bomb_stops_before_a_still_bomb() -> void:
	var field := _field(CORRIDOR)
	field.place_bomb(Vector2i(2, 1), 0, 2)
	field.place_bomb(Vector2i(6, 1), 1, 2)
	field.kick(Vector2i(2, 1), RIGHT)
	_ticks(field, 60)
	check(field.has_bomb(Vector2i(5, 1)) and field.has_bomb(Vector2i(6, 1)), "parked next to it")
	check(not field.is_dangerous(Vector2i(5, 1)), "no merge with a still bomb")


func test_sliding_into_fire_explodes() -> void:
	var field := _field(CORRIDOR)
	field.place_bomb(Vector2i(8, 1), 1, 1)
	_ticks(field, Rules.BOMB_FUSE_TICKS - 30)
	field.place_bomb(Vector2i(2, 1), 0, 1)
	field.kick(Vector2i(2, 1), RIGHT)
	_ticks(field, 30)  # the far bomb explodes, flames reach (7, 1)
	_ticks(field, 30)
	check_eq(exploded.size(), 2, "the kicked bomb went off in the fire")


func test_kicked_bombs_meeting_become_a_dangerous_bomb() -> void:
	var field := _field(CORRIDOR)
	field.place_bomb(Vector2i(2, 1), 0, 2)
	field.place_bomb(Vector2i(7, 1), 1, 2)
	field.kick(Vector2i(2, 1), RIGHT)
	field.kick(Vector2i(7, 1), LEFT)
	_ticks(field, 40)
	check_eq(removed.size(), 1, "one bomb absorbed")
	check_eq(field.bomb_positions().size(), 1, "one bomb left")
	var cell := Vector2i(field.bomb_positions().values()[0].x, 1)
	check(field.is_dangerous(cell), "it is dangerous")
	check_eq(field.bomb_count(0) + field.bomb_count(1), 1, "absorbed bomb's slot freed")
	var fuse := field.fuse_left(cell)
	check(fuse > Rules.DANGEROUS_FUSE_TICKS - 40 and fuse <= Rules.DANGEROUS_FUSE_TICKS, "fresh dangerous fuse: %d" % fuse)


func test_dangerous_bomb_burns_a_square() -> void:
	var field := _field([
		"#########",
		"#.......#",
		"#.#.#.#.#",
		"#...+...#",
		"#.#.#.#.#",
		"#.......#",
		"#########",
	])
	# Make (4, 3) dangerous by merging two kicked bombs there.
	field.grid.set_cell(Vector2i(4, 3), Grid.Cell.EMPTY)
	field.place_bomb(Vector2i(3, 3), 0, 1)
	field.place_bomb(Vector2i(5, 3), 1, 1)
	field.kick(Vector2i(3, 3), RIGHT)
	field.kick(Vector2i(5, 3), LEFT)
	_ticks(field, 20)
	var cells: Array = field.bomb_positions().values()
	check_eq(cells.size(), 1, "merged")
	var centre := Vector2i(roundi(cells[0].x), 3)
	check(field.is_dangerous(centre), "dangerous")
	_ticks(field, Rules.DANGEROUS_FUSE_TICKS)
	check_eq(exploded.size(), 1, "exploded")
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			var cell := centre + Vector2i(dx, dy)
			var hard := field.grid.get_cell(cell) == Grid.Cell.HARD
			check(hard or field.has_flame(cell), "square cell %s burning or hard" % cell)
	check(not field.has_flame(centre + Vector2i(3, 0)), "nothing outside the square")


# --- Punch -------------------------------------------------------------------

func test_punch_flies_three_cells_over_obstacles() -> void:
	var field := _field(["##########", "#..++....#", "##########"])
	field.place_bomb(Vector2i(2, 1), 0, 2)
	check(field.punch(Vector2i(2, 1), RIGHT), "punched")
	check(not field.has_bomb(Vector2i(2, 1)), "left the grid")
	check_eq(field.flying_count(), 1, "in the air")
	check_eq(field.bomb_count(0), 1, "still counts as the owner's bomb")
	_ticks(field, Rules.PUNCH_FLIGHT_TICKS / 2)
	check(_position_of_only_bomb(field).y > 0.5, "arcs up")
	_ticks(field, Rules.PUNCH_FLIGHT_TICKS)
	check(field.has_bomb(Vector2i(5, 1)), "landed 3 cells away, past the bricks")


func test_punch_bounces_off_a_taken_landing_cell() -> void:
	var field := _field(["##########", "#........#", "##########"])
	field.place_bomb(Vector2i(2, 1), 0, 2)
	field.place_bomb(Vector2i(5, 1), 1, 2)
	field.punch(Vector2i(2, 1), RIGHT)
	_ticks(field, Rules.PUNCH_FLIGHT_TICKS + Rules.BOUNCE_FLIGHT_TICKS + 2)
	check(field.has_bomb(Vector2i(6, 1)), "bounced one further")


func test_punch_wraps_around_the_edge() -> void:
	var field := _field(["#######", "#.....#", "#######"])
	field.place_bomb(Vector2i(4, 1), 0, 2)
	field.punch(Vector2i(4, 1), RIGHT)  # 4 + 3 = 7 -> wraps to 2
	_ticks(field, Rules.PUNCH_FLIGHT_TICKS + 2)
	check(field.has_bomb(Vector2i(2, 1)), "came round the other side")


func test_flying_bomb_is_not_set_off_and_waits_to_land() -> void:
	var field := _field(["##########", "#........#", "##########"])
	field.place_bomb(Vector2i(2, 1), 0, 2)
	_ticks(field, Rules.BOMB_FUSE_TICKS - 5)
	field.punch(Vector2i(2, 1), RIGHT)
	_ticks(field, 10)  # fuse would have run out mid-air
	check(exploded.is_empty(), "no explosion in the air")
	_ticks(field, Rules.PUNCH_FLIGHT_TICKS)
	check_eq(exploded.size(), 1, "went off right after landing")
	check_eq(exploded[0][0], Vector2i(5, 1), "where it landed")


func test_crushed_flying_landing_cell_bounces() -> void:
	var field := _field(["##########", "#........#", "##########"])
	field.place_bomb(Vector2i(2, 1), 0, 2)
	field.punch(Vector2i(2, 1), RIGHT)
	field.grid.set_cell(Vector2i(5, 1), Grid.Cell.HARD)  # a sudden-death block lands there meanwhile
	_ticks(field, Rules.PUNCH_FLIGHT_TICKS + Rules.BOUNCE_FLIGHT_TICKS + 2)
	check(field.has_bomb(Vector2i(6, 1)), "bounced past the new block")


# --- Items -------------------------------------------------------------------

func test_kick_and_punch_items() -> void:
	var stats := PlayerStats.new()
	stats.apply(Items.Type.KICK)
	stats.apply(Items.Type.PUNCH)
	check(stats.has_kick and stats.has_punch, "abilities gained")
	stats.reset(MatchSettings.new())
	check(not stats.has_kick and not stats.has_punch, "reset each round")


# --- Power Glove, Super Power Glove, Line Bomb ---------------------------------

func test_lift_and_throw() -> void:
	var field := _field(["############", "#..........#", "############"])
	field.place_bomb(Vector2i(2, 1), 0, 2)
	var id := field.lift(Vector2i(2, 1))
	check(id != -1, "lifted")
	check(not field.has_bomb(Vector2i(2, 1)), "off the grid while carried")
	check_eq(field.bomb_count(0), 1, "still the owner's bomb")
	check(field.bomb_positions().is_empty(), "carried bombs are positioned by the carrier, not the field")
	field.throw(id, Vector2i(2, 1), RIGHT)
	_ticks(field, Rules.THROW_FLIGHT_TICKS + 1)
	check(field.has_bomb(Vector2i(2 + Rules.THROW_DISTANCE, 1)), "landed THROW_DISTANCE away")


func test_carried_bomb_fuse_is_paused() -> void:
	var field := _field(CORRIDOR)
	field.place_bomb(Vector2i(2, 1), 0, 2)
	var id := field.lift(Vector2i(2, 1))
	_ticks(field, Rules.BOMB_FUSE_TICKS * 2)
	check(exploded.is_empty(), "never explodes while held")
	field.drop(id, Vector2i(3, 1))
	check(field.has_bomb(Vector2i(3, 1)), "dropped back on the grid")
	_ticks(field, Rules.BOMB_FUSE_TICKS)
	check_eq(exploded.size(), 1, "fuse runs again once down")


func test_cannot_lift_a_sliding_bomb_or_nothing() -> void:
	var field := _field(CORRIDOR)
	check_eq(field.lift(Vector2i(2, 1)), -1, "no bomb")
	field.place_bomb(Vector2i(2, 1), 0, 2)
	field.kick(Vector2i(2, 1), RIGHT)
	check_eq(field.lift(Vector2i(2, 1)), -1, "sliding")


func test_drop_onto_a_taken_cell_uses_a_neighbour() -> void:
	var field := _field(CORRIDOR)
	field.place_bomb(Vector2i(4, 1), 0, 2)
	var id := field.lift(Vector2i(4, 1))
	field.place_bomb(Vector2i(4, 1), 1, 2)  # someone else put a bomb there meanwhile
	field.drop(id, Vector2i(4, 1))
	check(field.has_bomb(Vector2i(3, 1)) or field.has_bomb(Vector2i(5, 1)), "went next to it")
	check_eq(field.bomb_count(0), 1, "not lost")


func test_make_dangerous_while_carried() -> void:
	var field := _field(CORRIDOR)
	field.place_bomb(Vector2i(2, 1), 0, 2)
	var id := field.lift(Vector2i(2, 1))
	field.make_dangerous(id)
	check(field.is_carried_dangerous(id), "dangerous in hand")
	field.throw(id, Vector2i(2, 1), RIGHT)
	_ticks(field, Rules.THROW_FLIGHT_TICKS + 1)
	check(field.is_dangerous(Vector2i(6, 1)), "lands as a Dangerous Bomb")


func test_line_bomb_stops_at_obstacles() -> void:
	var field := _field(["##########", "#....+...#", "##########"])
	var placed := field.place_line(Vector2i(1, 1), RIGHT, 6, 0, 2)
	check_eq(placed, 3, "three cells before the brick")
	for x in [2, 3, 4]:
		check(field.has_bomb(Vector2i(x, 1)), "bomb at %d" % x)
	check(not field.has_bomb(Vector2i(6, 1)), "nothing past the brick")


func test_line_bomb_limited_by_count_and_players() -> void:
	var field := _field(CORRIDOR)
	check_eq(field.place_line(Vector2i(1, 1), RIGHT, 2, 0, 2), 2, "only as many as allowed")
	field.player_at = func(cell): return cell == Vector2i(5, 1)
	check_eq(field.place_line(Vector2i(3, 1), RIGHT, 5, 1, 2), 1, "stops before a player")


func test_slot_a_items_replace_each_other() -> void:
	var stats := PlayerStats.new()
	stats.apply(Items.Type.GLOVE)
	check(stats.has_glove() and not stats.has_super_glove(), "glove")
	stats.apply(Items.Type.LINE_BOMB)
	check(stats.has_line_bomb() and not stats.has_glove(), "line bomb replaced it")
	stats.apply(Items.Type.SUPER_GLOVE)
	check(stats.has_super_glove() and stats.has_glove() and not stats.has_line_bomb(), "super glove counts as a glove")
	stats.reset(MatchSettings.new())
	check_eq(stats.slot_a, Items.NONE, "reset each round")


func test_slide_stops_for_something_that_appears_ahead() -> void:
	# Review fix: the next cell was only checked at the cell centre.
	var field := _field(CORRIDOR)
	field.place_bomb(Vector2i(2, 1), 0, 2)
	field.kick(Vector2i(2, 1), RIGHT)
	field.tick()
	field.grid.set_cell(Vector2i(3, 1), Grid.Cell.HARD)  # a sudden-death block lands just ahead
	_ticks(field, 30)
	check(field.has_bomb(Vector2i(2, 1)), "stayed out of the new block")
	check(not field.is_sliding(Vector2i(2, 1)), "stopped")


func test_punching_a_sliding_bomb_sideways_bounces_straight() -> void:
	# Review fix: the bounce direction came from an off-axis start point and could go diagonal.
	var field := _field([
		"#######",
		"#.....#",
		"#.....#",
		"#.....#",
		"#.#...#",
		"#.....#",
		"#######",
	])
	field.place_bomb(Vector2i(2, 1), 0, 2)
	field.kick(Vector2i(2, 1), RIGHT)
	field.tick()
	field.tick()                       # sliding, slightly past the centre of (2, 1)
	field.punch(Vector2i(2, 1), Vector2i.DOWN)  # lands on (2, 4), a pillar: bounce on
	_ticks(field, Rules.PUNCH_FLIGHT_TICKS + Rules.BOUNCE_FLIGHT_TICKS + 2)
	check(field.has_bomb(Vector2i(2, 5)), "bounced straight down to (2, 5)")


func test_bomb_landing_on_an_item_burns_it_when_it_explodes() -> void:
	# Review fix: the centre cell of a normal blast did not burn floor items.
	var field := _field(CORRIDOR)
	var items := ItemField.new(field.grid)
	field.items = items
	items.place(Vector2i(5, 1), Items.Type.FIRE_UP)
	field.place_bomb(Vector2i(2, 1), 0, 1)
	field.punch(Vector2i(2, 1), RIGHT)  # lands on the item at (5, 1)
	_ticks(field, Rules.BOMB_FUSE_TICKS + 2)
	check(not items.has_item(Vector2i(5, 1)), "burnt by its own bomb")
