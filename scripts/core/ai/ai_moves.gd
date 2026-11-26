class_name AIMoves
extends RefCounted
## Where bombs end up when kicked, punched, thrown or laid in a line, following BombField's
## rules, so the AI can judge those moves before making them. `players`: cells with a living
## player (they stop slides and landings).


## Kicked from `cell` in `dir`: the cell it stops in. It slides until the next cell holds a wall,
## brick, bomb, floor item or player. Returns `cell` when it cannot move at all.
static func slide_stop(grid: Grid, bombs: BombField, items: ItemField, players: Dictionary,
		cell: Vector2i, dir: Vector2i) -> Vector2i:
	var at := cell
	for i in grid.width + grid.height:
		if _blocks_slide(grid, bombs, items, players, at + dir):
			return at
		at += dir
	return at


## Punched or thrown from `from`: lands `distance` cells along `dir`, wrapping round the arena; a
## taken landing cell (wall, brick, bomb, player) makes it bounce one more cell, again and again.
## The second value is the number of bounces, which add flight time.
static func landing(grid: Grid, bombs: BombField, players: Dictionary, from: Vector2i, dir: Vector2i,
		distance: int) -> Array:
	var cell := _wrap(grid, from + dir * distance)
	for bounces in grid.width + grid.height:
		if not grid.is_blocking(cell) and not bombs.has_bomb(cell) and not players.has(cell):
			return [cell, bounces]
		cell = _wrap(grid, cell + dir)
	return [cell, 0]


## Line Bomb from `from` in `dir`: the cells it would fill (at most `count`), stopping at the first
## wall, brick, bomb, item or player.
static func line_cells(grid: Grid, bombs: BombField, items: ItemField, players: Dictionary,
		from: Vector2i, dir: Vector2i, count: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for i in range(1, count + 1):
		var cell := from + dir * i
		if _blocks_slide(grid, bombs, items, players, cell):
			break
		cells.append(cell)
	return cells


static func _blocks_slide(grid: Grid, bombs: BombField, items: ItemField, players: Dictionary, cell: Vector2i) -> bool:
	return grid.is_blocking(cell) or bombs.has_bomb(cell) or (items != null and items.has_item(cell)) \
		or players.has(cell)


## BombField._wrap_inside: into the arena interior.
static func _wrap(grid: Grid, cell: Vector2i) -> Vector2i:
	var inner := Vector2i(grid.width - 2, grid.height - 2)
	return Vector2i(1 + posmod(cell.x - 1, inner.x), 1 + posmod(cell.y - 1, inner.y))
