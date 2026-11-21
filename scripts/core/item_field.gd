class_name ItemField
extends RefCounted
## Items on a Grid: hidden under bricks at round start, revealed when their brick finishes
## burning, then lying on the floor until picked up, burnt by a flame or crushed by a
## sudden-death block. Pure logic; the 3D views listen to the signals.

signal item_revealed(cell: Vector2i, item: int)  # appeared on the floor (also scattered items)
signal item_removed(cell: Vector2i, item: int, reason: Removed)

enum Removed { TAKEN, BURNED, CRUSHED }

var grid: Grid

var _hidden := {}  # Vector2i -> item, under a brick
var _items := {}   # Vector2i -> item, on the floor


func _init(target_grid: Grid) -> void:
	grid = target_grid


## Hides items under random bricks: Rules.ITEM_SHARE[frequency] of them, each a weighted pick
## from `types`. Deterministic for a given RNG state.
func hide_items(rng: RandomNumberGenerator, frequency: int, types: Array) -> void:
	_hidden.clear()
	var bricks := grid.cells_of(Grid.Cell.SOFT)
	var count := roundi(bricks.size() * float(Rules.ITEM_SHARE[clampi(frequency, 0, Rules.ITEM_SHARE.size() - 1)]))
	if count == 0 or types.is_empty():
		return
	# Fisher-Yates shuffle with our RNG (Array.shuffle would use the global one).
	for i in range(bricks.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var swap := bricks[i]
		bricks[i] = bricks[j]
		bricks[j] = swap
	for i in mini(count, bricks.size()):
		_hidden[bricks[i]] = Items.pick_weighted(types, rng)


func hidden_count() -> int:
	return _hidden.size()


func hidden_at(cell: Vector2i) -> int:
	return _hidden.get(cell, Items.NONE)


func item_at(cell: Vector2i) -> int:
	return _items.get(cell, Items.NONE)


func has_item(cell: Vector2i) -> bool:
	return _items.has(cell)


func floor_items() -> Dictionary:
	return _items.duplicate()


## A brick finished burning: its hidden item (if any) appears.
func reveal(cell: Vector2i) -> void:
	if _hidden.has(cell):
		place(cell, _hidden[cell])
		_hidden.erase(cell)


## Puts an item on the floor (revealed, or scattered from a dead player).
func place(cell: Vector2i, item: int) -> void:
	_items[cell] = item
	item_revealed.emit(cell, item)


## Picks up the item in `cell`; returns it, or Items.NONE.
func take(cell: Vector2i) -> int:
	return _remove(cell, Removed.TAKEN)


## A flame reached the item: it is destroyed.
func burn(cell: Vector2i) -> void:
	_remove(cell, Removed.BURNED)


## A sudden-death block landed: floor and hidden items there are gone.
func crush(cell: Vector2i) -> void:
	_hidden.erase(cell)
	_remove(cell, Removed.CRUSHED)


## Places `items` on random cells for which `is_free.call(cell)` is true and that hold no item.
## Items that do not fit are lost. Returns the cells used.
func scatter(items: Array[int], rng: RandomNumberGenerator, is_free: Callable) -> Array[Vector2i]:
	var free: Array[Vector2i] = []
	for cell in grid.cells_of(Grid.Cell.EMPTY):
		if not _items.has(cell) and is_free.call(cell):
			free.append(cell)
	var used: Array[Vector2i] = []
	for item in items:
		if free.is_empty():
			break
		var cell: Vector2i = free.pop_at(rng.randi_range(0, free.size() - 1))
		place(cell, item)
		used.append(cell)
	return used


func _remove(cell: Vector2i, reason: Removed) -> int:
	if not _items.has(cell):
		return Items.NONE
	var item: int = _items[cell]
	_items.erase(cell)
	item_removed.emit(cell, item, reason)
	return item
