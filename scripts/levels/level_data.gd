class_name LevelData
extends Resource
## A versus stage written as ASCII, one string per row, outer wall included.
##   #    hard block (outer wall and pillars)
##   +    soft block, always placed
##   ?    soft block placed with probability random_soft_chance
##   .    empty floor
##   1-4  spawn point for that player slot (empty floor)
## A spawn cell and its 4 neighbours never get a soft block, whatever the layout says.

const MAX_SPAWNS := 4
const LEGEND := "#+?.1234"

@export var display_name := ""
@export var layout := PackedStringArray()
@export_range(0.0, 1.0) var random_soft_chance := 0.0


func get_width() -> int:
	return layout[0].length() if layout.size() > 0 else 0


func get_height() -> int:
	return layout.size()


## Problems with the layout; empty means the level is usable.
func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	var w := get_width()
	var h := get_height()
	if w < 3 or h < 3:
		errors.append("layout must be at least 3x3")
		return errors
	var spawn_counts := {}
	for y in h:
		var row := layout[y]
		if row.length() != w:
			errors.append("row %d has length %d, expected %d" % [y, row.length(), w])
			continue
		for x in w:
			var ch := row[x]
			if ch not in LEGEND:
				errors.append("unknown character '%s' at (%d, %d)" % [ch, x, y])
			var on_border := x == 0 or y == 0 or x == w - 1 or y == h - 1
			if on_border and ch != "#":
				errors.append("border cell (%d, %d) must be '#'" % [x, y])
			if ch in "1234":
				spawn_counts[ch] = spawn_counts.get(ch, 0) + 1
	for n in MAX_SPAWNS:
		var key := str(n + 1)
		if spawn_counts.get(key, 0) != 1:
			errors.append("spawn %s must appear exactly once" % key)
	return errors


## Builds a fresh Grid. The RNG only affects '?' cells, so the same seed gives the same grid.
func build_grid(rng: RandomNumberGenerator) -> Grid:
	var errors := validate()
	if not errors.is_empty():
		push_error("Level '%s' is invalid: %s" % [display_name, "; ".join(errors)])

	var grid := Grid.new(get_width(), get_height())
	grid.spawns.resize(MAX_SPAWNS)
	grid.spawns.fill(Grid.NO_SPAWN)

	for y in get_height():
		var row := layout[y]
		for x in mini(row.length(), grid.width):
			var cell := Vector2i(x, y)
			var ch := row[x]
			if ch == "#":
				grid.set_cell(cell, Grid.Cell.HARD)
			elif ch == "+":
				grid.set_cell(cell, Grid.Cell.SOFT)
			elif ch == "?":
				if rng.randf() < random_soft_chance:
					grid.set_cell(cell, Grid.Cell.SOFT)
			elif ch in "1234":
				grid.spawns[int(ch) - 1] = cell

	for spawn in grid.spawns:
		if spawn == Grid.NO_SPAWN:
			continue
		_clear_soft(grid, spawn)
		for dir in Grid.DIRECTIONS:
			_clear_soft(grid, spawn + dir)
	return grid


func _clear_soft(grid: Grid, cell: Vector2i) -> void:
	if grid.get_cell(cell) == Grid.Cell.SOFT:
		grid.set_cell(cell, Grid.Cell.EMPTY)
