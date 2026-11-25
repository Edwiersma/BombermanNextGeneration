class_name DangerMap
extends RefCounted
## Fire forecast for the AI: for every cell, the window of ticks (counted from now) during which
## fire will be there. Built from:
## - bombs: their fuses, and chain reactions (a blast that reaches another bomb sets it off at
##   the same moment, so that bomb's fire comes sooner);
## - flames burning right now;
## - sudden-death blocks about to land (deadly from then on).
## Blasts follow BombField's rules: crosses stopped by hard blocks, the first brick (unless
## piercing), a bomb or a floor item; Dangerous Bombs burn a square. A brick an earlier blast hit
## is gone once it has burned (Rules.FLAME_TICKS later) and an item it hit is gone at once, so
## later blasts reach further. A cell hit more than once keeps a window per fire (overlapping
## windows merge), so the gap between two fires counts as clear.

const NEVER := 1 << 30
## A remote bomb goes off whenever its owner wants, so someone else's counts as about to blow.
const ENEMY_REMOTE_TICKS := 20
## The AI's own remote bombs are planned as if on a normal fuse: it runs clear, then presses.
const OWN_REMOTE_TICKS := Rules.BOMB_FUSE_TICKS

## Cell -> Array of [from, to] tick windows during which fire is there.
var windows := {}
## Armed land mines: stepping on one sets it off.
var mines := {}


## `bombs`: BombField.bomb_list() (plus any "what if" bombs). `me`: the AI's slot, whose remote
## bombs it controls itself. `doomed`: MatchRules.doomed_cells().
static func build(grid: Grid, bombs: Array, flames: Dictionary, items: ItemField, me: int, doomed := {}) -> DangerMap:
	var map := DangerMap.new()
	for cell: Vector2i in flames:
		map._mark(cell, 0, flames[cell])
	for cell: Vector2i in doomed:
		map._mark(cell, doomed[cell], NEVER)

	var times: Array[int] = []
	var chain_at := {}  # cell -> index of the bomb a flame there would set off
	var stops := {}     # cells whose bomb stops a flame (mines lie flat and do not)
	for i in bombs.size():
		var bomb: Dictionary = bombs[i]
		var time: int = bomb.fuse
		if bomb.mine:
			time = NEVER  # only goes off when stepped on or set off by fire
			if bomb.armed:
				map.mines[bomb.cell] = true
		elif bomb.remote:
			time = OWN_REMOTE_TICKS if bomb.owner == me else ENEMY_REMOTE_TICKS
		if flames.has(bomb.cell) and not bomb.flying:
			time = mini(time, 1)
		times.append(time)
		if not bomb.flying:
			chain_at[bomb.cell] = i
			if not bomb.mine:
				stops[bomb.cell] = true

	# Bombs go off in time order; each blast may bring later ones forward (chain reactions).
	var cleared := {}  # cell -> tick a brick or item there is gone
	var done: Array[bool] = []
	done.resize(bombs.size())
	done.fill(false)
	while true:
		var next := -1
		for i in bombs.size():
			if not done[i] and times[i] < NEVER and (next == -1 or times[i] < times[next]):
				next = i
		if next == -1:
			break
		done[next] = true
		stops.erase(bombs[next].cell)  # gone once it blows: later fire passes its cell
		var time := times[next]
		for cell in blast_cells(grid, bombs[next], items, stops, cleared, time):
			map._mark(cell, time, time + Rules.FLAME_TICKS)
			if not cleared.has(cell):
				if grid.get_cell(cell) == Grid.Cell.SOFT:
					cleared[cell] = time + Rules.FLAME_TICKS
				elif items != null and items.has_item(cell):
					cleared[cell] = time
			if chain_at.has(cell):
				var other: int = chain_at[cell]
				if not done[other] and times[other] > time:
					times[other] = time
	return map


## Cells a blast from `bomb` (a bomb_list() entry) reaches. `stops`: cells holding a bomb.
## `cleared`: cell -> tick its brick or item is gone; at tick `time` those no longer stop fire.
static func blast_cells(grid: Grid, bomb: Dictionary, items: ItemField, stops: Dictionary,
		cleared := {}, time := 0) -> Array[Vector2i]:
	var origin: Vector2i = bomb.cell
	var cells: Array[Vector2i] = [origin]
	if bomb.get("dangerous", false):
		var radius := Rules.DANGEROUS_RADIUS
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				var cell := origin + Vector2i(dx, dy)
				if cell != origin and grid.get_cell(cell) != Grid.Cell.HARD:
					cells.append(cell)
		return cells
	for dir: Vector2i in Grid.DIRECTIONS:
		for dist in range(1, int(bomb.fire_range) + 1):
			var cell := origin + dir * dist
			var cell_type := grid.get_cell(cell)
			if cell_type == Grid.Cell.HARD:
				break
			cells.append(cell)
			var gone: bool = cleared.has(cell) and cleared[cell] <= time
			if cell_type == Grid.Cell.SOFT and not gone:
				if bomb.get("pierce", false):
					continue
				break
			if stops.has(cell) or (items != null and items.has_item(cell) and not gone):
				break
	return cells


## Fire will be in `cell` at some point (or is now).
func threatened(cell: Vector2i) -> bool:
	return windows.has(cell)


## No fire in `cell` at any tick between `from` and `to`.
func is_clear(cell: Vector2i, from: float, to: float) -> bool:
	for window: Array in windows.get(cell, []):
		if to >= window[0] and from <= window[1]:
			return false
	return true


## `cell` stays free of fire from tick `from` on.
func safe_from(cell: Vector2i, from: float) -> bool:
	for window: Array in windows.get(cell, []):
		if window[1] >= from:
			return false
	return true


## The first tick at or after `from` when `cell` is on fire (`from` itself if it is then; NEVER
## if fire never comes back).
func clear_until(cell: Vector2i, from: float) -> float:
	var until := float(NEVER)
	for window: Array in windows.get(cell, []):
		if window[1] >= from:
			until = minf(until, maxf(window[0], from))
	return until


## Ticks until fire first reaches `cell` (NEVER if it will not).
func time_to_fire(cell: Vector2i) -> int:
	var first := NEVER
	for window: Array in windows.get(cell, []):
		first = mini(first, window[0])
	return first


func _mark(cell: Vector2i, from: int, to: int) -> void:
	if not windows.has(cell):
		windows[cell] = [[from, to]]
		return
	var list: Array = windows[cell]
	for window: Array in list:
		if from <= window[1] and to >= window[0]:
			window[0] = mini(window[0], from)
			window[1] = maxi(window[1], to)
			return
	list.append([from, to])
