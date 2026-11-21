class_name GridMovement
extends RefCounted
## Bomberman-style movement on the grid, as a pure function so it can be tested headless.
##
## Positions are in cells; cell centres are whole numbers. A player moves along one axis at a time:
## - If the cell ahead is open, the player first lines up with its lane, then moves forward.
## - If the cell ahead is blocked, the player can still walk up to the centre of its own cell.
## - Corner assist: when blocked but overlapping the neighbouring lane by at least
##   Rules.CORNER_ASSIST_MIN, and that lane is open ahead, the player slides sideways into it.
## When several directions are held, the most recent one that produces movement wins, so holding
## a second direction "queues" a turn at the next opening.

const EPSILON := 0.0001


## Moves `pos` by up to `distance` cells. `dirs` are the held directions, most recent first.
## `is_blocked` is called with a Vector2i cell and returns true for cells the player cannot enter.
## Returns {"pos": Vector2, "dir": Vector2i}; dir is the direction that moved (ZERO if none).
static func step(pos: Vector2, dirs: Array[Vector2i], distance: float, is_blocked: Callable) -> Dictionary:
	distance = minf(distance, Rules.MAX_STEP)
	for dir in dirs:
		var new_pos := _step_in_direction(pos, dir, distance, is_blocked)
		if new_pos.distance_squared_to(pos) > EPSILON * EPSILON:
			return {"pos": new_pos, "dir": dir}
	return {"pos": pos, "dir": Vector2i.ZERO}


static func nearest_cell(pos: Vector2) -> Vector2i:
	return Vector2i(roundi(pos.x), roundi(pos.y))


static func _step_in_direction(pos: Vector2, dir: Vector2i, budget: float, is_blocked: Callable) -> Vector2:
	var cell := nearest_cell(pos)
	var forward := Vector2(dir)
	var side_axis := Vector2(absi(dir.y), absi(dir.x))  # unit vector across the direction of travel
	var side_offset := (pos - Vector2(cell)).dot(side_axis)

	if not is_blocked.call(cell + dir):
		# Line up with this lane first, then spend what is left moving forward.
		var align := minf(absf(side_offset), budget)
		pos -= side_axis * signf(side_offset) * align
		budget -= align
		if absf(side_offset) - align < EPSILON:
			pos = _snap_side(pos, side_axis, cell)
		return pos + forward * budget

	# Blocked ahead: walk up to the centre of the current cell, but no further.
	var to_centre := (Vector2(cell) - pos).dot(forward)
	if to_centre > EPSILON:
		return pos + forward * minf(to_centre, budget)

	# Corner assist into the neighbouring lane we overlap.
	if absf(side_offset) >= Rules.CORNER_ASSIST_MIN:
		var side := Vector2i(side_axis * signf(side_offset))
		if not is_blocked.call(cell + side) and not is_blocked.call(cell + side + dir):
			var remaining := 1.0 - absf(side_offset)
			return pos + Vector2(side) * minf(remaining, budget)
	return pos


static func _snap_side(pos: Vector2, side_axis: Vector2, cell: Vector2i) -> Vector2:
	if side_axis.x > 0.0:
		pos.x = cell.x
	else:
		pos.y = cell.y
	return pos
