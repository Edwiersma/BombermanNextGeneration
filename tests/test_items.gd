extends "res://tests/test_suite.gd"

const ROOM := [
	"#########",
	"#.+.+.+.#",
	"#+#+#+#+#",
	"#.+.+.+.#",
	"#########",
]


func _seeded(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


# --- PlayerStats -------------------------------------------------------------

func test_stat_items_raise_stats_up_to_caps() -> void:
	var stats := PlayerStats.new()
	for i in 20:
		stats.apply(Items.Type.BOMB_UP)
		stats.apply(Items.Type.FIRE_UP)
		stats.apply(Items.Type.SPEED_UP)
	check_eq(stats.max_bombs, Rules.MAX_BOMBS, "bombs capped at 8")
	check_eq(stats.fire_range, Rules.MAX_FIRE, "fire capped at 8")
	check_eq(stats.speed_level, Rules.MAX_SPEED_LEVEL, "speed capped")


func test_full_fire_and_speed_down() -> void:
	var stats := PlayerStats.new()
	stats.apply(Items.Type.FULL_FIRE)
	check_eq(stats.fire_range, Rules.MAX_FIRE, "full fire")
	for i in 5:
		stats.apply(Items.Type.SPEED_DOWN)
	check_eq(stats.speed_level, Rules.MIN_SPEED_LEVEL, "speed floor")
	check(stats.speed() < Rules.PLAYER_SPEED, "slower than base")


func test_speed_levels() -> void:
	var stats := PlayerStats.new()
	check_eq(stats.speed(), Rules.PLAYER_SPEED, "base speed at level 1")
	stats.apply(Items.Type.SPEED_UP)
	check(is_equal_approx(stats.speed(), Rules.PLAYER_SPEED + Rules.SPEED_STEP), "one step faster")


func test_collected_and_reset() -> void:
	var stats := PlayerStats.new()
	stats.apply(Items.Type.BOMB_UP)
	stats.apply(Items.Type.SPEED_DOWN)
	check_eq(stats.collected, [Items.Type.BOMB_UP, Items.Type.SPEED_DOWN] as Array[int], "collected in order")
	var settings := MatchSettings.new()
	settings.start_bombs = 3
	stats.reset(settings)
	check(stats.collected.is_empty() and stats.max_bombs == 3 and stats.speed_level == Rules.START_SPEED_LEVEL, "reset")


# --- Item data ---------------------------------------------------------------

func test_item_keys_round_trip() -> void:
	for type in Items.IMPLEMENTED:
		check_eq(Items.from_key(Items.key(type)), type, "key for %s" % Items.display_name(type))
	check_eq(Items.from_key("nonsense"), Items.NONE, "unknown key")


func test_weighted_pick_respects_the_list() -> void:
	var rng := _seeded(7)
	var counts := {}
	for i in 2000:
		var item := Items.pick_weighted([Items.Type.BOMB_UP, Items.Type.FULL_FIRE], rng)
		counts[item] = counts.get(item, 0) + 1
	check_eq(counts.keys().size(), 2, "only listed items")
	check(counts[Items.Type.BOMB_UP] > counts[Items.Type.FULL_FIRE] * 4, "common beats rare: %s" % counts)
	check_eq(Items.pick_weighted([], rng), Items.NONE, "empty list")


# --- ItemField ---------------------------------------------------------------

func test_items_hidden_only_under_bricks_by_frequency() -> void:
	var grid := grid_from_rows(ROOM)
	var bricks := grid.cells_of(Grid.Cell.SOFT)
	for frequency in Rules.ITEM_SHARE.size():
		var field := ItemField.new(grid)
		field.hide_items(_seeded(1), frequency, Items.IMPLEMENTED)
		check_eq(field.hidden_count(), roundi(bricks.size() * float(Rules.ITEM_SHARE[frequency])), "count at frequency %d" % frequency)
		for y in grid.height:
			for x in grid.width:
				var cell := Vector2i(x, y)
				if field.hidden_at(cell) != Items.NONE:
					check(cell in bricks, "hidden under a brick: %s" % cell)


func test_hiding_is_deterministic_and_respects_disabled_items() -> void:
	var grid := grid_from_rows(ROOM)
	var a := ItemField.new(grid)
	var b := ItemField.new(grid)
	a.hide_items(_seeded(42), 3, [Items.Type.SPEED_UP])
	b.hide_items(_seeded(42), 3, [Items.Type.SPEED_UP])
	for cell in grid.cells_of(Grid.Cell.SOFT):
		check_eq(a.hidden_at(cell), b.hidden_at(cell), "same seed, same item at %s" % cell)
		check(a.hidden_at(cell) in [Items.NONE, Items.Type.SPEED_UP], "only enabled items")
	var none := ItemField.new(grid)
	none.hide_items(_seeded(1), 3, [])
	check_eq(none.hidden_count(), 0, "no types enabled, no items")


func test_reveal_take_burn_crush() -> void:
	var field := ItemField.new(grid_from_rows(ROOM))
	var removed: Array = []
	field.item_removed.connect(func(cell, item, reason): removed.append([cell, item, reason]))
	field.place(Vector2i(1, 1), Items.Type.FIRE_UP)
	check_eq(field.take(Vector2i(1, 1)), Items.Type.FIRE_UP, "taken")
	check_eq(field.take(Vector2i(1, 1)), Items.NONE, "gone after taking")
	field.place(Vector2i(3, 1), Items.Type.BOMB_UP)
	field.burn(Vector2i(3, 1))
	field.place(Vector2i(5, 1), Items.Type.BOMB_UP)
	field.crush(Vector2i(5, 1))
	check_eq(removed.map(func(r): return r[2]), [ItemField.Removed.TAKEN, ItemField.Removed.BURNED, ItemField.Removed.CRUSHED], "reasons")


func test_burning_brick_reveals_its_item_and_fire_burns_floor_items() -> void:
	var grid := grid_from_rows(["#######", "#..+..#", "#######"])
	var items := ItemField.new(grid)
	items.hide_items(_seeded(3), 3, [Items.Type.BOMB_UP])  # the only brick gets one at "high"
	var bombs := BombField.new(grid)
	bombs.items = items
	bombs.block_destroyed.connect(items.reveal)
	check_eq(items.hidden_at(Vector2i(3, 1)), Items.Type.BOMB_UP, "hidden under the brick")
	bombs.place_bomb(Vector2i(1, 1), 0, 4)
	for i in Rules.BOMB_FUSE_TICKS + Rules.FLAME_TICKS:
		bombs.tick()
	check_eq(items.item_at(Vector2i(3, 1)), Items.Type.BOMB_UP, "revealed when the brick is gone")
	# A second blast burns it and stops there.
	bombs.place_bomb(Vector2i(1, 1), 0, 4)
	for i in Rules.BOMB_FUSE_TICKS:
		bombs.tick()
	check(not items.has_item(Vector2i(3, 1)), "burnt")
	check(bombs.has_flame(Vector2i(3, 1)) and not bombs.has_flame(Vector2i(4, 1)), "flame stopped at the item")


func test_crush_removes_hidden_items_too() -> void:
	var grid := grid_from_rows(ROOM)
	var field := ItemField.new(grid)
	field.hide_items(_seeded(5), 3, Items.IMPLEMENTED)
	var brick: Vector2i = grid.cells_of(Grid.Cell.SOFT).filter(func(c): return field.hidden_at(c) != Items.NONE)[0]
	field.crush(brick)
	check_eq(field.hidden_at(brick), Items.NONE, "hidden item crushed")


func test_scatter_uses_free_cells_only() -> void:
	var grid := grid_from_rows(ROOM)
	var field := ItemField.new(grid)
	var blocked := Vector2i(1, 1)
	var cells := field.scatter([Items.Type.BOMB_UP, Items.Type.FIRE_UP, Items.Type.SPEED_UP] as Array[int], _seeded(9),
		func(cell): return cell != blocked)
	check_eq(cells.size(), 3, "all placed")
	for cell in cells:
		check(grid.get_cell(cell) == Grid.Cell.EMPTY and cell != blocked, "free cell: %s" % cell)
	check_eq(field.floor_items().size(), 3, "on the floor")


func test_scatter_drops_what_does_not_fit() -> void:
	var grid := grid_from_rows(["#####", "#...#", "#####"])
	var field := ItemField.new(grid)
	var many: Array[int] = []
	for i in 10:
		many.append(Items.Type.BOMB_UP)
	check_eq(field.scatter(many, _seeded(1), func(_c): return true).size(), 3, "only 3 free cells")


# --- Settings ----------------------------------------------------------------

func test_item_settings_rows_and_toggles() -> void:
	var s := MatchSettings.new()
	check_eq(s.value_text("item_frequency"), "Normal", "default frequency")
	check_eq(s.value_text("death_items"), "Scatter", "default: scatter")
	var row := MatchSettings.ITEM_ROW_PREFIX + "speed_down"
	check(row in s.rows(), "item row listed")
	s.step(row, 1)
	check(not s.is_item_enabled(Items.Type.SPEED_DOWN), "toggled off")
	check(Items.Type.SPEED_DOWN not in s.enabled_item_types(), "excluded from hiding")
	s.step("death_items", 1)
	check_eq(s.death_items, MatchSettings.DeathItems.LOST, "lost")
	s.item_frequency = 0
	check(not s.items_active(), "off")


func test_item_settings_save_and_load() -> void:
	var path := "user://test_item_settings.cfg"
	var s := MatchSettings.new()
	s.item_frequency = 3
	s.death_items = MatchSettings.DeathItems.LOST
	s.step(MatchSettings.ITEM_ROW_PREFIX + "full_fire", 1)
	s.save(path)
	var loaded := MatchSettings.load_or_default(path)
	check(loaded.equals(s), "round trip")
	check(not loaded.is_item_enabled(Items.Type.FULL_FIRE), "toggle kept")
	DirAccess.remove_absolute(path)


# --- Heart and Safety Vest -----------------------------------------------------

func test_heart_absorbs_one_hit_then_grace() -> void:
	var stats := PlayerStats.new()
	stats.apply(Items.Type.HEART)
	check(not stats.take_hit(), "heart saves you")
	check(not stats.has_heart, "heart used up")
	check(stats.is_invulnerable(), "grace period")
	check(not stats.take_hit(), "still in fire during grace: fine")
	for i in Rules.HEART_GRACE_TICKS:
		stats.tick()
	check(not stats.is_invulnerable(), "grace over")
	check(stats.take_hit(), "next hit kills")


func test_only_one_heart_at_a_time() -> void:
	var stats := PlayerStats.new()
	stats.apply(Items.Type.HEART)
	stats.apply(Items.Type.HEART)
	check(not stats.take_hit(), "first hit absorbed")
	for i in Rules.HEART_GRACE_TICKS:
		stats.tick()
	check(stats.take_hit(), "a second heart did not stack")


func test_vest_lasts_its_time() -> void:
	var stats := PlayerStats.new()
	stats.apply(Items.Type.VEST)
	for i in Rules.VEST_TICKS - 1:
		stats.tick()
	check(not stats.take_hit(), "protected until the last tick")
	stats.tick()
	check(stats.take_hit(), "vest worn off")


func test_vest_does_not_use_up_the_heart() -> void:
	var stats := PlayerStats.new()
	stats.apply(Items.Type.HEART)
	stats.apply(Items.Type.VEST)
	check(not stats.take_hit(), "vest takes the hit")
	check(stats.has_heart, "heart kept for later")


func test_protection_resets_each_round() -> void:
	var stats := PlayerStats.new()
	stats.apply(Items.Type.HEART)
	stats.apply(Items.Type.VEST)
	stats.reset(MatchSettings.new())
	check(not stats.has_heart and stats.vest_ticks == 0 and not stats.is_invulnerable(), "gone")
