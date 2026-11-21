class_name BombField
extends RefCounted
## Bombs, flames and burning bricks on a Grid, advanced one physics tick at a time.
## Pure logic, so the rules can be tested headless; the 3D views only listen to the signals.
##
## - A blast spreads from the bomb in 4 directions up to its fire range.
## - Hard blocks stop it. The first soft block in a direction stops it and starts burning;
##   a burning block still stops flames until it is gone (after Rules.FLAME_TICKS).
## - A flame that reaches another bomb stops there and that bomb explodes in the same tick.
## - A bomb sitting in an active flame explodes on the next tick.

signal bomb_placed(cell: Vector2i, owner: int)
## `flames` lists every cell the blast touched, for visuals:
## [{"cell": Vector2i, "kind": Flame, "axis": Vector2i}], axis is ZERO for the centre.
signal bomb_exploded(cell: Vector2i, owner: int, flames: Array)
signal block_burning(cell: Vector2i)
## A soft block finished burning and is gone. Phase 2: power-ups can appear here.
signal block_destroyed(cell: Vector2i)

enum Flame { CENTER, ARM, END, BLOCK }


class Bomb:
	var cell: Vector2i
	var owner: int
	var fire_range: int
	var fuse: int


var grid: Grid

var _bombs := {}    # Vector2i -> Bomb
var _flames := {}   # Vector2i -> ticks left
var _burning := {}  # Vector2i -> ticks left


func _init(target_grid: Grid) -> void:
	grid = target_grid


func has_bomb(cell: Vector2i) -> bool:
	return _bombs.has(cell)


func has_flame(cell: Vector2i) -> bool:
	return _flames.has(cell)


func is_burning(cell: Vector2i) -> bool:
	return _burning.has(cell)


func fuse_left(cell: Vector2i) -> int:
	return _bombs[cell].fuse if _bombs.has(cell) else 0


func bomb_count(owner: int) -> int:
	var count := 0
	for bomb: Bomb in _bombs.values():
		if bomb.owner == owner:
			count += 1
	return count


## Places a bomb unless the cell is solid or already holds one.
func place_bomb(cell: Vector2i, owner: int, fire_range: int) -> bool:
	if grid.is_blocking(cell) or _bombs.has(cell):
		return false
	var bomb := Bomb.new()
	bomb.cell = cell
	bomb.owner = owner
	bomb.fire_range = fire_range
	bomb.fuse = Rules.BOMB_FUSE_TICKS
	_bombs[cell] = bomb
	bomb_placed.emit(cell, owner)
	return true


func tick() -> void:
	_age(_flames, false)
	_age(_burning, true)

	var due: Array[Vector2i] = []
	for cell: Vector2i in _bombs:
		var bomb: Bomb = _bombs[cell]
		bomb.fuse -= 1
		if bomb.fuse <= 0 or _flames.has(cell):
			due.append(cell)

	# Chain reactions resolve within this tick.
	while not due.is_empty():
		var cell: Vector2i = due.pop_front()
		if not _bombs.has(cell):
			continue
		var bomb: Bomb = _bombs[cell]
		_bombs.erase(cell)
		var flames := _blast(bomb)
		for flame in flames:
			if _bombs.has(flame.cell):
				due.append(flame.cell)
		bomb_exploded.emit(cell, bomb.owner, flames)


func _blast(bomb: Bomb) -> Array:
	var flames: Array = [_flame(bomb.cell, Flame.CENTER, Vector2i.ZERO)]
	_ignite(bomb.cell)
	for dir: Vector2i in Grid.DIRECTIONS:
		for dist in range(1, bomb.fire_range + 1):
			var cell: Vector2i = bomb.cell + dir * dist
			var cell_type := grid.get_cell(cell)
			if cell_type == Grid.Cell.HARD:
				break
			if cell_type == Grid.Cell.SOFT:
				_start_burning(cell)
				flames.append(_flame(cell, Flame.BLOCK, dir))
				break
			_ignite(cell)
			var hits_bomb := _bombs.has(cell)
			var is_tip := dist == bomb.fire_range or hits_bomb or grid.get_cell(cell + dir) == Grid.Cell.HARD
			flames.append(_flame(cell, Flame.END if is_tip else Flame.ARM, dir))
			if hits_bomb:
				break
	return flames


func _ignite(cell: Vector2i) -> void:
	_flames[cell] = maxi(_flames.get(cell, 0), Rules.FLAME_TICKS)


func _start_burning(cell: Vector2i) -> void:
	if not _burning.has(cell):
		_burning[cell] = Rules.FLAME_TICKS
		block_burning.emit(cell)


## Counts down timers; burning blocks that run out are removed from the grid.
func _age(timers: Dictionary, destroys_blocks: bool) -> void:
	for cell: Vector2i in timers.keys():
		timers[cell] -= 1
		if timers[cell] <= 0:
			timers.erase(cell)
			if destroys_blocks:
				grid.set_cell(cell, Grid.Cell.EMPTY)
				block_destroyed.emit(cell)


static func _flame(cell: Vector2i, kind: Flame, axis: Vector2i) -> Dictionary:
	return {"cell": cell, "kind": kind, "axis": axis}
