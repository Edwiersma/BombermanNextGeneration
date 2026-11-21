class_name BombField
extends RefCounted
## Bombs, flames and burning bricks on a Grid, advanced one physics tick at a time.
## Pure logic, so the rules can be tested headless; the 3D views only listen to the signals and
## read bomb_positions() every frame.
##
## Blasts:
## - A blast spreads from the bomb in 4 directions up to its fire range.
## - Hard blocks stop it. The first soft block in a direction stops it and starts burning;
##   a burning block still stops flames until it is gone (after Rules.FLAME_TICKS).
## - A flame that reaches another bomb stops there and that bomb explodes in the same tick.
## - A flame that reaches an item on the floor burns it and stops there (when `items` is set).
## - A bomb sitting in an active flame explodes on the next tick.
## - A Dangerous Bomb burns a square of Rules.DANGEROUS_RADIUS around it instead of a cross.
##
## Moving bombs:
## - kick(): the bomb slides at Rules.KICK_SPEED and stops at the centre of the last free cell
##   before a wall, brick, bomb, floor item or player (`player_at`). Two sliding bombs that meet
##   merge into one Dangerous Bomb.
## - punch(): the bomb leaves the grid and flies Rules.PUNCH_DISTANCE cells over anything,
##   wrapping around the arena edge. A taken landing cell makes it bounce one cell further.
##   In the air it blocks nothing and cannot be set off; its fuse never runs out mid-air.

signal bomb_placed(id: int, cell: Vector2i, owner: int)
## `flames` lists every cell the blast touched, for visuals:
## [{"cell": Vector2i, "kind": Flame, "axis": Vector2i}], axis is ZERO for the centre.
signal bomb_exploded(id: int, cell: Vector2i, owner: int, flames: Array)
## A bomb vanished without exploding (crushed by a sudden-death block, or merged into another).
signal bomb_removed(id: int, cell: Vector2i)
## A bomb changed kind (became a Dangerous Bomb).
signal bomb_changed(id: int)
signal block_burning(cell: Vector2i)
## A soft block finished burning and is gone. Phase 2: power-ups can appear here.
signal block_destroyed(cell: Vector2i)

enum Flame { CENTER, ARM, END, BLOCK }


class Bomb:
	var id: int
	var cell: Vector2i       # the cell it occupies (nearest cell while sliding; landing cell in the air)
	var owner: int
	var fire_range: int
	var fuse: int
	var dangerous := false
	# Sliding (kicked):
	var slide_dir := Vector2i.ZERO
	var offset := 0.0        # -0.5..0.5 cells from `cell` along slide_dir
	# Flying (punched):
	var flying := false
	var fly_from := Vector2.ZERO
	var fly_to := Vector2.ZERO   # target used for the arc
	var fly_ticks := 0
	var fly_total := 1

	func is_sliding() -> bool:
		return slide_dir != Vector2i.ZERO


var grid: Grid
## Optional: floor items that flames burn and stop at, and that stop sliding bombs.
var items: ItemField
## Optional: returns true when a living player stands in the cell (stops sliding bombs).
var player_at: Callable

var _next_id := 1
var _bombs := {}    # Vector2i -> Bomb, on the grid (still or sliding)
var _flying: Array[Bomb] = []
var _flames := {}   # Vector2i -> ticks left
var _burning := {}  # Vector2i -> ticks left


func _init(target_grid: Grid) -> void:
	grid = target_grid


func has_bomb(cell: Vector2i) -> bool:
	return _bombs.has(cell)


func is_dangerous(cell: Vector2i) -> bool:
	return _bombs.has(cell) and _bombs[cell].dangerous


func is_sliding(cell: Vector2i) -> bool:
	return _bombs.has(cell) and _bombs[cell].is_sliding()


func flying_count() -> int:
	return _flying.size()


func has_flame(cell: Vector2i) -> bool:
	return _flames.has(cell)


func is_burning(cell: Vector2i) -> bool:
	return _burning.has(cell)


func fuse_left(cell: Vector2i) -> int:
	return _bombs[cell].fuse if _bombs.has(cell) else 0


func bomb_count(owner: int) -> int:
	var count := 0
	for bomb: Bomb in _all_bombs():
		if bomb.owner == owner:
			count += 1
	return count


## Every bomb's position in cells: Vector3(x, height, y) keyed by bomb id.
func bomb_positions() -> Dictionary:
	var positions := {}
	for bomb: Bomb in _bombs.values():
		var at := Vector2(bomb.cell) + Vector2(bomb.slide_dir) * bomb.offset
		positions[bomb.id] = Vector3(at.x, 0.0, at.y)
	for bomb in _flying:
		var t := 1.0 - float(bomb.fly_ticks) / bomb.fly_total
		var at := bomb.fly_from.lerp(bomb.fly_to, t)
		var height := 4.0 * Rules.PUNCH_ARC_HEIGHT * t * (1.0 - t) * (bomb.fly_total / float(Rules.PUNCH_FLIGHT_TICKS))
		positions[bomb.id] = Vector3(at.x, height, at.y)
	return positions


## Places a bomb unless the cell is solid or already holds one.
func place_bomb(cell: Vector2i, owner: int, fire_range: int) -> bool:
	if grid.is_blocking(cell) or _bombs.has(cell):
		return false
	var bomb := Bomb.new()
	bomb.id = _next_id
	_next_id += 1
	bomb.cell = cell
	bomb.owner = owner
	bomb.fire_range = fire_range
	bomb.fuse = Rules.BOMB_FUSE_TICKS
	_bombs[cell] = bomb
	bomb_placed.emit(bomb.id, cell, owner)
	return true


## Starts the still bomb in `cell` sliding in `dir`. False when there is no bomb or it cannot move.
func kick(cell: Vector2i, dir: Vector2i) -> bool:
	if not _bombs.has(cell):
		return false
	var bomb: Bomb = _bombs[cell]
	if bomb.is_sliding() or _blocks_slide(cell + dir):
		return false
	bomb.slide_dir = dir
	bomb.offset = 0.0
	return true


## Sends the bomb in `cell` flying in `dir`. False when there is no bomb there.
func punch(cell: Vector2i, dir: Vector2i) -> bool:
	if not _bombs.has(cell):
		return false
	var bomb: Bomb = _bombs[cell]
	_bombs.erase(cell)
	var from := Vector2(cell) + Vector2(bomb.slide_dir) * bomb.offset
	bomb.slide_dir = Vector2i.ZERO
	bomb.offset = 0.0
	_launch(bomb, from, cell + dir * Rules.PUNCH_DISTANCE, Rules.PUNCH_FLIGHT_TICKS)
	return true


## A sudden-death block landed here: the bomb vanishes without exploding and any flame or
## burning brick in the cell stops.
func crush(cell: Vector2i) -> void:
	if _bombs.has(cell):
		var bomb: Bomb = _bombs[cell]
		_bombs.erase(cell)
		bomb_removed.emit(bomb.id, cell)
	_flames.erase(cell)
	_burning.erase(cell)


func tick() -> void:
	_age(_flames, false)
	_age(_burning, true)
	_move_sliding()
	_move_flying()

	var due: Array[Vector2i] = []
	for cell: Vector2i in _bombs:
		var bomb: Bomb = _bombs[cell]
		bomb.fuse -= 1
		if bomb.fuse <= 0 or _flames.has(cell):
			due.append(cell)
	for bomb in _flying:
		bomb.fuse = maxi(bomb.fuse - 1, 1)  # goes off right after landing if it runs out mid-air

	# Chain reactions resolve within this tick.
	while not due.is_empty():
		var cell: Vector2i = due.pop_front()
		if not _bombs.has(cell):
			continue
		var bomb: Bomb = _bombs[cell]
		_bombs.erase(cell)
		var flames := _square_blast(bomb) if bomb.dangerous else _blast(bomb)
		for flame in flames:
			if _bombs.has(flame.cell):
				due.append(flame.cell)
		bomb_exploded.emit(bomb.id, cell, bomb.owner, flames)


# --- Moving ------------------------------------------------------------------

func _move_sliding() -> void:
	var step := Rules.KICK_SPEED / Rules.TICKS_PER_SECOND
	for bomb: Bomb in _bombs.values():
		if not bomb.is_sliding() or _bombs.get(bomb.cell) != bomb:
			continue  # stopped, or merged away earlier this tick
		var before := bomb.offset
		bomb.offset += step
		if before < 0.0 and bomb.offset >= 0.0:
			# At the centre of its cell: carry on only if the next cell is free.
			var ahead := bomb.cell + bomb.slide_dir
			if _bombs.has(ahead) and _bombs[ahead].is_sliding():
				_merge(bomb, _bombs[ahead])
				continue
			if _blocks_slide(ahead):
				_stop(bomb)
				continue
		if bomb.offset >= 0.5:
			var next := bomb.cell + bomb.slide_dir
			if _bombs.has(next):
				if _bombs[next].is_sliding():
					_merge(bomb, _bombs[next])
				else:
					_stop(bomb)
				continue
			_bombs.erase(bomb.cell)
			bomb.cell = next
			bomb.offset -= 1.0
			_bombs[next] = bomb


func _stop(bomb: Bomb) -> void:
	bomb.offset = 0.0
	bomb.slide_dir = Vector2i.ZERO


## Two sliding bombs met: `a` becomes a Dangerous Bomb where it is, `b` is absorbed.
func _merge(a: Bomb, b: Bomb) -> void:
	_bombs.erase(b.cell)
	bomb_removed.emit(b.id, b.cell)
	_stop(a)
	a.dangerous = true
	a.fuse = Rules.DANGEROUS_FUSE_TICKS
	bomb_changed.emit(a.id)


func _move_flying() -> void:
	for bomb: Bomb in _flying.duplicate():
		bomb.fly_ticks -= 1
		if bomb.fly_ticks > 0:
			continue
		_flying.erase(bomb)
		var landing := bomb.cell
		if _can_land(landing):
			bomb.flying = false
			_bombs[landing] = bomb
		else:
			# Taken: bounce one more cell in the same direction.
			var dir := Vector2i((bomb.fly_to - bomb.fly_from).sign())
			_launch(bomb, Vector2(landing), landing + dir, Rules.BOUNCE_FLIGHT_TICKS)


func _launch(bomb: Bomb, from: Vector2, target: Vector2i, ticks: int) -> void:
	bomb.flying = true
	bomb.fly_from = from
	bomb.fly_to = Vector2(target)
	bomb.cell = _wrap_inside(target)
	if bomb.cell != target:
		# Wrapped around the edge: come in from just outside the far side.
		var dir := (Vector2(target) - from).normalized()
		bomb.fly_from = Vector2(bomb.cell) - dir
		bomb.fly_to = Vector2(bomb.cell)
	bomb.fly_ticks = ticks
	bomb.fly_total = ticks
	_flying.append(bomb)


func _can_land(cell: Vector2i) -> bool:
	return not grid.is_blocking(cell) and not _bombs.has(cell) and \
		not (player_at.is_valid() and player_at.call(cell))


func _blocks_slide(cell: Vector2i) -> bool:
	return grid.is_blocking(cell) or _bombs.has(cell) or \
		(items != null and items.has_item(cell)) or \
		(player_at.is_valid() and player_at.call(cell))


## Wraps a cell into the arena interior (inside the outer wall).
func _wrap_inside(cell: Vector2i) -> Vector2i:
	var inner := Vector2i(grid.width - 2, grid.height - 2)
	return Vector2i(1 + posmod(cell.x - 1, inner.x), 1 + posmod(cell.y - 1, inner.y))


func _all_bombs() -> Array:
	var all: Array = _bombs.values()
	all.append_array(_flying)
	return all


# --- Blasts ------------------------------------------------------------------

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
			var hits_item := items != null and items.has_item(cell)
			if hits_item:
				items.burn(cell)
			var is_tip := dist == bomb.fire_range or hits_bomb or hits_item or grid.get_cell(cell + dir) == Grid.Cell.HARD
			flames.append(_flame(cell, Flame.END if is_tip else Flame.ARM, dir))
			if hits_bomb or hits_item:
				break
	return flames


## Dangerous Bomb: every cell in a square around it, regardless of what is in between.
func _square_blast(bomb: Bomb) -> Array:
	var flames: Array = []
	var radius := Rules.DANGEROUS_RADIUS
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var cell := bomb.cell + Vector2i(dx, dy)
			var cell_type := grid.get_cell(cell)
			if cell_type == Grid.Cell.HARD:
				continue
			if cell_type == Grid.Cell.SOFT:
				_start_burning(cell)
				flames.append(_flame(cell, Flame.BLOCK, Vector2i.ZERO))
				continue
			_ignite(cell)
			if items != null and items.has_item(cell):
				items.burn(cell)
			flames.append(_flame(cell, Flame.CENTER if cell == bomb.cell else Flame.END, Vector2i.ZERO))
	return flames


func _ignite(cell: Vector2i) -> void:
	_flames[cell] = maxi(_flames.get(cell, 0), Rules.FLAME_TICKS)


func _start_burning(cell: Vector2i) -> void:
	if not _burning.has(cell):
		_burning[cell] = Rules.FLAME_TICKS
		block_burning.emit(cell)


## Counts timers down; burning blocks that run out are removed from the grid.
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
