extends "res://tests/test_suite.gd"
## Remote Control, Piercing Bomb, Power Bomb, Land Mine and Bouncy Bomb.

const CORRIDOR := ["############", "#..........#", "############"]

var exploded: Array = []


func _field(rows: Array) -> BombField:
	var field := BombField.new(grid_from_rows(rows))
	field.bomb_exploded.connect(func(id, cell, _owner, flames): exploded.append([id, cell, flames]))
	return field


func _ticks(field: BombField, count: int) -> void:
	for i in count:
		field.tick()


# --- Remote Control ----------------------------------------------------------

func test_remote_bombs_wait_for_the_button() -> void:
	var field := _field(CORRIDOR)
	field.place_bomb(Vector2i(2, 1), 0, 1, {"remote": true})
	_ticks(field, Rules.BOMB_FUSE_TICKS * 3)
	check(exploded.is_empty(), "no fuse")
	check(field.detonate_oldest_remote(0), "button pressed")
	field.tick()
	check_eq(exploded.size(), 1, "went off")


func test_remote_detonates_oldest_first() -> void:
	var field := _field(CORRIDOR)
	field.place_bomb(Vector2i(2, 1), 0, 1, {"remote": true})
	field.place_bomb(Vector2i(6, 1), 0, 1, {"remote": true})
	field.place_bomb(Vector2i(9, 1), 1, 1, {"remote": true})  # someone else's
	field.detonate_oldest_remote(0)
	field.tick()
	check_eq(exploded.map(func(e): return e[1]), [Vector2i(2, 1)], "oldest first")
	field.detonate_oldest_remote(0)
	field.tick()
	check_eq(exploded.map(func(e): return e[1]), [Vector2i(2, 1), Vector2i(6, 1)], "then the next")
	check(not field.detonate_oldest_remote(0), "none left")
	check(field.has_bomb(Vector2i(9, 1)), "other player's bomb untouched")


func test_remote_bomb_still_chains_from_fire() -> void:
	var field := _field(CORRIDOR)
	field.place_bomb(Vector2i(3, 1), 0, 1, {"remote": true})
	field.place_bomb(Vector2i(2, 1), 1, 1)
	_ticks(field, Rules.BOMB_FUSE_TICKS)
	check_eq(exploded.size(), 2, "set off by the neighbour's blast")


func test_release_remote_gives_a_normal_fuse() -> void:
	var field := _field(CORRIDOR)
	field.place_bomb(Vector2i(2, 1), 0, 1, {"remote": true})
	_ticks(field, 500)
	field.release_remote(0)
	_ticks(field, Rules.BOMB_FUSE_TICKS)
	check_eq(exploded.size(), 1, "explodes on its own once released")


# --- Piercing Bomb -----------------------------------------------------------

func test_piercing_blast_goes_through_bricks() -> void:
	var field := _field(["##########", "#.+.+...##", "##########"])
	field.place_bomb(Vector2i(1, 1), 0, 4, {"pierce": true})
	_ticks(field, Rules.BOMB_FUSE_TICKS)
	check(field.is_burning(Vector2i(2, 1)) and field.is_burning(Vector2i(4, 1)), "both bricks burning")
	check(field.has_flame(Vector2i(3, 1)) and field.has_flame(Vector2i(5, 1)), "flames past them")
	check(not field.has_flame(Vector2i(6, 1)), "still limited by range")


func test_normal_blast_still_stops_at_the_first_brick() -> void:
	var field := _field(["##########", "#.+.+...##", "##########"])
	field.place_bomb(Vector2i(1, 1), 0, 4)
	_ticks(field, Rules.BOMB_FUSE_TICKS)
	check(field.is_burning(Vector2i(2, 1)) and not field.is_burning(Vector2i(4, 1)), "stopped at the first")


# --- Land Mine ---------------------------------------------------------------

func test_mine_blocks_nothing_and_arms_once_left() -> void:
	var field := _field(CORRIDOR)
	var on_mine := [true]
	field.player_at = func(cell): return on_mine[0] and cell == Vector2i(3, 1)
	field.place_bomb(Vector2i(3, 1), 0, 1, {"mine": true})
	check(not field.has_bomb(Vector2i(3, 1)) and field.has_mine(Vector2i(3, 1)), "sunk, not a blocking bomb")
	check_eq(field.bomb_count(0), 1, "counts as the owner's bomb")
	_ticks(field, Rules.BOMB_FUSE_TICKS * 2)
	check(exploded.is_empty(), "owner standing on it: no trigger, no fuse")
	on_mine[0] = false
	field.tick()  # owner stepped off: armed
	on_mine[0] = true
	field.tick()  # someone steps on it
	check_eq(exploded.size(), 1, "triggered")


func test_fire_sets_off_a_mine() -> void:
	var field := _field(CORRIDOR)
	field.place_bomb(Vector2i(3, 1), 0, 1, {"mine": true})
	field.place_bomb(Vector2i(2, 1), 1, 1)
	_ticks(field, Rules.BOMB_FUSE_TICKS)
	check_eq(exploded.size(), 2, "chained")


func test_crush_removes_a_mine() -> void:
	var field := _field(CORRIDOR)
	field.place_bomb(Vector2i(3, 1), 0, 1, {"mine": true})
	field.crush(Vector2i(3, 1))
	check(not field.has_mine(Vector2i(3, 1)) and field.bomb_count(0) == 0, "gone")


# --- Bouncy Bomb -------------------------------------------------------------

func test_bouncy_kick_hops_until_it_explodes() -> void:
	var field := _field(["#########", "#.......#", "#.......#", "#.......#", "#########"])
	field.rng.seed = 11
	field.place_bomb(Vector2i(4, 2), 0, 1)
	check(field.kick(Vector2i(4, 2), Vector2i.RIGHT, true), "bouncy kick")
	check(not field.has_bomb(Vector2i(4, 2)), "off the grid")
	var max_flying := 0
	for i in Rules.BOMB_FUSE_TICKS + Rules.BOUNCE_FLIGHT_TICKS * 4:
		field.tick()
		max_flying = maxi(max_flying, field.flying_count())
	check_eq(max_flying, 1, "hopping")
	check_eq(exploded.size(), 1, "came down and exploded")


func test_bouncy_punch_keeps_hopping_after_landing() -> void:
	var field := _field(["#########", "#.......#", "#.......#", "#.......#", "#########"])
	field.place_bomb(Vector2i(2, 2), 0, 1)
	field.punch(Vector2i(2, 2), Vector2i.RIGHT, true)
	_ticks(field, Rules.PUNCH_FLIGHT_TICKS + 2)
	check_eq(field.flying_count(), 1, "still in the air after the punch lands")


# --- Items and flags ---------------------------------------------------------

func test_slot_b_items_replace_each_other() -> void:
	var stats := PlayerStats.new()
	stats.apply(Items.Type.REMOTE)
	check(stats.has_remote(), "remote")
	stats.apply(Items.Type.LAND_MINE)
	check(stats.has_land_mine() and not stats.has_remote(), "mine replaced remote")
	stats.apply(Items.Type.GLOVE)
	check(stats.has_land_mine() and stats.has_glove(), "slot A and B are independent")
	stats.reset(MatchSettings.new())
	check_eq(stats.slot_b, Items.NONE, "reset each round")


func test_bomb_flags() -> void:
	var field := _field(CORRIDOR)
	field.place_bomb(Vector2i(2, 1), 0, 1, {"remote": true, "pierce": true})
	var flags := field.bomb_flags(1)
	check(flags.remote and flags.pierce and not flags.mine, "flags: %s" % flags)
	check(field.bomb_flags(99).is_empty(), "unknown id")


func test_bouncy_kicked_remote_bomb_still_explodes() -> void:
	# Review fix: a remote bomb sent bouncing used to hop forever (no fuse, out of the button's reach).
	var field := _field(["#########", "#.......#", "#.......#", "#.......#", "#########"])
	field.rng.seed = 5
	field.place_bomb(Vector2i(4, 2), 0, 1, {"remote": true})
	field.kick(Vector2i(4, 2), Vector2i.RIGHT, true)
	_ticks(field, Rules.BOMB_FUSE_TICKS + Rules.BOUNCE_FLIGHT_TICKS * 4)
	check_eq(exploded.size(), 1, "exploded")
	check_eq(field.bomb_count(0), 0, "owner got the bomb back")
