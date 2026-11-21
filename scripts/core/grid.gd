class_name Grid
extends RefCounted
## Authoritative arena state on an integer grid, outer wall included.
## x grows right, y grows down (towards the camera). Cell (x, y) is centred on world (x, 0, y).
## Pure logic, no nodes: rules can be tested headless and the 3D view only mirrors this state.

signal cell_changed(cell: Vector2i, old_type: int, new_type: int)

enum Cell { EMPTY, HARD, SOFT }

const NO_SPAWN := Vector2i(-1, -1)
const DIRECTIONS := [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]

var width := 0
var height := 0
## Spawn cell per player slot (NO_SPAWN when the level has none for that slot).
var spawns: Array[Vector2i] = []

var _cells := PackedByteArray()


func _init(grid_width: int = 0, grid_height: int = 0) -> void:
	width = grid_width
	height = grid_height
	_cells.resize(width * height)
	_cells.fill(Cell.EMPTY)


func in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < width and cell.y < height


func is_border(cell: Vector2i) -> bool:
	return cell.x == 0 or cell.y == 0 or cell.x == width - 1 or cell.y == height - 1


## Out-of-bounds cells read as HARD, so callers never need a bounds check.
func get_cell(cell: Vector2i) -> int:
	if not in_bounds(cell):
		return Cell.HARD
	return _cells[cell.y * width + cell.x]


func set_cell(cell: Vector2i, cell_type: int) -> void:
	if not in_bounds(cell):
		return
	var index := cell.y * width + cell.x
	var old_type := _cells[index]
	if old_type == cell_type:
		return
	_cells[index] = cell_type
	cell_changed.emit(cell, old_type, cell_type)


func is_blocking(cell: Vector2i) -> bool:
	return get_cell(cell) != Cell.EMPTY


func cells_of(cell_type: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for y in height:
		for x in width:
			if _cells[y * width + x] == cell_type:
				result.append(Vector2i(x, y))
	return result


static func cell_to_world(cell: Vector2i) -> Vector3:
	return Vector3(cell.x, 0.0, cell.y)


static func world_to_cell(point: Vector3) -> Vector2i:
	return Vector2i(roundi(point.x), roundi(point.z))
