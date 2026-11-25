class_name BomberAI
extends RefCounted
## A computer player's brain. Every tick it looks at the match (a View) and returns the buttons
## its virtual controller holds. It never touches the game itself, so it walks, bombs and suffers
## curses by exactly the same rules as a human on a pad.
##
## What it does, re-planned every few ticks (more often on harder levels):
## 1. Fire is coming to its cell (DangerMap): run to the nearest cell no fire will reach, by a
##    path that is not on fire while it passes.
## 2. Standing somewhere a bomb would catch a player or break bricks: drop it, but only if there
##    is a way out once that bomb is counted in (Easy sometimes forgets to check).
## 3. Otherwise walk to the best target: a good item, a spot to bomb a player or bricks from, or
##    towards the nearest player; with nothing better, wander. Paths keep clear of any fire.
## Its own Remote Control bombs: it runs clear first, then presses Special.

enum Level { EASY, NORMAL, HARD }

## Per level:
##   think       ticks between plans
##   reaction    ticks before it notices fire coming its way
##   aggression  chance per plan to go for players; scales how much bombing a player is worth
##   item_range  how many cells it walks for an item
##   margin      ticks of slack it keeps from fire when planning a path
##   blunder     chance to drop a bomb without checking for a way out
##   hideouts    safe cells it wants within reach before dropping a bomb (1 = any way out; 2
##               keeps it out of one-cell pockets where another bomb would trap it)
##   undizzy     makes up for the Dizzy curse (reversed controls)
const PROFILES := [
	{"think": 24, "reaction": 14, "aggression": 0.35, "item_range": 4, "margin": 6, "blunder": 0.05, "hideouts": 1, "undizzy": false},
	{"think": 10, "reaction": 5, "aggression": 0.7, "item_range": 9, "margin": 9, "blunder": 0.01, "hideouts": 2, "undizzy": true},
	{"think": 4, "reaction": 0, "aggression": 1.0, "item_range": 99, "margin": 12, "blunder": 0.0, "hideouts": 2, "undizzy": true},
]
## Items it will not walk over (unless running from fire).
const AVOID_ITEMS := [Items.Type.SKULL, Items.Type.SPEED_DOWN]
## Bombing spots that get the (costlier) way-out check per plan, best first.
const SPOTS_CHECKED := 4
## A bombing spot must be worth at least this much (a brick is 2, a player 6 x aggression).
const MIN_BOMB_VALUE := 2.0
## Choosing where to hide: each cell on the way that fire will reach costs this many ticks extra,
## so it prefers routes that do not run along blast lines (plans change; exposure kills).
const EXPOSURE_TICKS := 12.0
const NO_CELL := Vector2i(-1, -1)
const DIRECTION_ACTIONS := {Vector2i.UP: &"up", Vector2i.DOWN: &"down", Vector2i.LEFT: &"left", Vector2i.RIGHT: &"right"}


## What the AI sees each tick.
class View:
	var grid: Grid
	var bombs: BombField
	var items: ItemField
	var pos := Vector2.ZERO
	var stats: PlayerStats
	## Living opponents' positions.
	var others: Array[Vector2] = []
	## Sudden death: cell -> ticks until a block lands there.
	var doomed := {}


var slot := 0
var level: int = Level.NORMAL
var rng := RandomNumberGenerator.new()
## The last few plans in words, newest last (for debugging: tools/ai_soak.gd prints them).
var notes: Array[String] = []

var _profile: Dictionary
var _path: Array[Vector2i] = []  # cells still to walk through, next first
var _goal := NO_CELL
var _bomb_at_goal := false       # drop a bomb once the goal is reached
var _escaping := false           # the path leads out of fire
var _refuge_found := false       # ...to a cell fire will not reach (false: just the best we saw)
var _think_in := 0
var _danger_ticks := 0           # how long fire has been coming without a plan for it
var _presses := {}               # one-tick presses for the next actions: &"bomb", &"special"
var _last_pos := Vector2.INF
var _last_dir := Vector2i.ZERO
var _stuck_ticks := 0
var _other_cells := {}           # cells other players stand in (this tick)


func _init(player_slot := 0, difficulty: int = Level.NORMAL, seed_value := 0) -> void:
	slot = player_slot
	level = clampi(difficulty, 0, PROFILES.size() - 1)
	_profile = PROFILES[level]
	if seed_value != 0:
		rng.seed = seed_value
	else:
		rng.randomize()


## Forget the plan (new round, new arena).
func reset() -> void:
	_path.clear()
	_goal = NO_CELL
	_bomb_at_goal = false
	_escaping = false
	_think_in = rng.randi_range(0, _profile.think)  # stagger AIs so they do not all plan at once
	_danger_ticks = 0
	_presses.clear()
	_last_pos = Vector2.INF
	_last_dir = Vector2i.ZERO
	_stuck_ticks = 0


## One tick: returns the actions held, {&"up": true, &"bomb": true, ...}.
func tick(view: View) -> Dictionary:
	var cell := GridMovement.nearest_cell(view.pos)
	var bombs := view.bombs.bomb_list()
	_other_cells.clear()
	for other in view.others:
		_other_cells[GridMovement.nearest_cell(other)] = true
	var danger := DangerMap.build(view.grid, bombs, view.bombs.flame_cells(), view.items, slot, view.doomed)
	_track_stuck(view.pos)
	while not _path.is_empty() and _path[0] == cell:
		_path.pop_front()

	var in_danger := danger.threatened(cell)
	_think_in -= 1
	var rethink := _stuck_ticks > 30
	if _escaping:
		# Stick to the way out while it holds: re-planning every few ticks made it dither between
		# equally good hiding places and never leave. Look again on arrival, when the way stops
		# being safe, and every few ticks while it has not found a cell fire will not reach.
		if _path.is_empty():
			rethink = rethink or _refuge_found or _think_in <= 0
		else:
			rethink = rethink or not _escape_holds(view, danger) or (not _refuge_found and _think_in <= 0)
	else:
		_danger_ticks = _danger_ticks + 1 if in_danger else 0
		var arrived := _path.is_empty() and _goal != NO_CELL and _centred(view, cell)
		rethink = rethink or _think_in <= 0 or _danger_ticks > _profile.reaction \
			or _next_step_blocked(view, danger) or (arrived and _bomb_at_goal)
	if rethink:
		_think(view, cell, bombs, danger, in_danger)
	return _actions(view, cell)


# --- Planning ------------------------------------------------------------------

func _think(view: View, cell: Vector2i, bombs: Array[Dictionary], danger: DangerMap, in_danger: bool) -> void:
	_think_in = _profile.think
	_danger_ticks = 0
	_stuck_ticks = 0
	_path.clear()
	_goal = NO_CELL
	_bomb_at_goal = false
	_escaping = false
	_refuge_found = false

	if in_danger:
		var refuge := _refuge(view, cell, danger, true)
		_follow(refuge, true)
		_note("at %s: run to %s%s" % [cell, refuge.goal, "" if refuge.found else " (no safe cell)"])
		return
	if view.stats.has_remote() and _has_remote_out(bombs):
		_presses[&"special"] = true  # we are clear of them: set them off
	if _centred(view, cell) and _may_bomb(view, cell):
		var hunting := _hunting(view)
		if _bomb_value(view, cell, danger, _stops(bombs), hunting) >= MIN_BOMB_VALUE:
			var way_out := _refuge_after_bomb(view, cell, bombs)
			if way_out.found or rng.randf() < _profile.blunder:
				_presses[&"bomb"] = true
				_follow(way_out, true)
				_note("at %s: bomb, then run to %s%s" % [cell, way_out.goal, "" if way_out.found else " (BLUNDER)"])
				return
	_choose_goal(view, cell, bombs, danger)


## Starts walking a refuge result ({"found", "goal", "path"}).
func _follow(refuge: Dictionary, escaping: bool) -> void:
	_path = refuge.path
	_goal = refuge.goal
	_escaping = escaping
	_refuge_found = refuge.found


## The escape path is still walkable and clear of fire at the times we will pass, and its end
## still safe. Half the planning margin is enough here, so small timing changes keep the plan.
func _escape_holds(view: View, danger: DangerMap) -> bool:
	var per_cell := _ticks_per_cell(view)
	var slack: float = _profile.margin * 0.5
	var first := _path[0]
	var arrive := (absf(view.pos.x - first.x) + absf(view.pos.y - first.y)) * per_cell
	for i in _path.size():
		var c := _path[i]
		if i > 0:
			arrive += per_cell
		if not _walkable(view, c, danger, true):
			return false
		if not danger.is_clear(c, arrive - per_cell * 0.5 - slack, arrive + per_cell * 0.5 + slack):
			return false
	return not _refuge_found or danger.safe_from(_goal, arrive - slack)


func _choose_goal(view: View, cell: Vector2i, bombs: Array[Dictionary], danger: DangerMap) -> void:
	var reached := _explore(view, cell, danger, true, false)
	var per_cell := _ticks_per_cell(view)
	var stops := _stops(bombs)
	var can_bomb := _may_bomb_at_all(view)
	var hunting := _hunting(view)
	var candidates: Array = []  # [score, cell, bomb_there]
	for target: Vector2i in reached:
		var steps: float = reached[target][1] / per_cell
		var score := -INF
		var bomb_there := false
		var item := view.items.item_at(target)
		if item != Items.NONE and item not in AVOID_ITEMS and steps <= _profile.item_range:
			score = 14.0 - steps
		if can_bomb and not view.bombs.has_bomb(target) and not view.bombs.has_mine(target):
			var value := _bomb_value(view, target, danger, stops, hunting)
			if value >= MIN_BOMB_VALUE and value - steps * 0.7 > score:
				score = value - steps * 0.7
				bomb_there = true
		if score > -INF:
			candidates.append([score, target, bomb_there])
	candidates.sort_custom(func(a, b): return a[0] > b[0])

	var checked := 0
	for candidate: Array in candidates:
		var target: Vector2i = candidate[1]
		if candidate[2]:
			if checked >= SPOTS_CHECKED:
				continue
			checked += 1
			if not _refuge_after_bomb(view, target, bombs, reached[target][1]).found:
				continue  # a dead end once the bomb is down
		_go(reached, target, candidate[2])
		return

	# Nothing worth doing: close in on the nearest player (Easy only when hunting), else wander.
	var target := NO_CELL
	if (hunting or level != Level.EASY) and not view.others.is_empty():
		var best := INF
		for c: Vector2i in reached:
			var score: float = _distance_to_others(view, c) + reached[c][1] / per_cell * 0.1
			if score < best:
				best = score
				target = c
	if target == NO_CELL or target == cell:
		var nearby: Array[Vector2i] = []
		for c: Vector2i in reached:
			var steps: float = reached[c][1] / per_cell
			if steps >= 1.0 and steps <= 6.0:
				nearby.append(c)
		if not nearby.is_empty():
			target = nearby[rng.randi_range(0, nearby.size() - 1)]
	if target != NO_CELL:
		_go(reached, target, false)


## Going for players this plan? A roll against aggression; always once sudden death has begun.
func _hunting(view: View) -> bool:
	return not view.doomed.is_empty() or rng.randf() < _profile.aggression


func _go(reached: Dictionary, target: Vector2i, bomb_there: bool) -> void:
	_path = _path_to(reached, target)
	_goal = target
	_bomb_at_goal = bomb_there
	_note("go to %s%s" % [target, " to bomb" if bomb_there else ""])


func _note(text: String) -> void:
	if not notes.is_empty() and notes.back() == text:
		return
	notes.append(text)
	if notes.size() > 10:
		notes.pop_front()


## The current plan, for debugging.
func debug_state() -> String:
	return "path %s, goal %s, escaping %s (refuge found %s), bomb at goal %s, think in %d, stuck %d" % [
		_path, _goal, _escaping, _refuge_found, _bomb_at_goal, _think_in, _stuck_ticks]


## The nearest cell fire will not reach (in time), and the way there:
## {"found": bool, "goal": Vector2i, "path": Array[Vector2i], "safe_cells": int}. When nothing
## is safe, the path leads to the cell where fire arrives last (found = false).
func _refuge(view: View, cell: Vector2i, danger: DangerMap, fleeing: bool, delay := 0.0) -> Dictionary:
	var reached := _explore(view, cell, danger, false, fleeing, delay)
	var margin: float = _profile.margin
	var best := NO_CELL
	var best_cost := INF
	var safe_cells := 0
	for target: Vector2i in reached:
		var arrive: float = reached[target][1]
		if danger.safe_from(target, arrive - margin) and not danger.mines.has(target):
			safe_cells += 1
			var cost := arrive + _exposure(reached, target, danger) * EXPOSURE_TICKS
			if cost < best_cost:
				best = target
				best_cost = cost
	if best != NO_CELL:
		return {"found": true, "goal": best, "path": _path_to(reached, best), "safe_cells": safe_cells}
	# Nowhere is safe for good: go where we get the longest time before fire comes.
	var latest := -INF
	for target: Vector2i in reached:
		var arrive: float = reached[target][1]
		var spare := danger.clear_until(target, arrive - margin) - arrive
		if spare > latest and not danger.mines.has(target):
			latest = spare
			best = target
	return {"found": false, "goal": best, "path": _path_to(reached, best) if best != NO_CELL else ([] as Array[Vector2i]),
		"safe_cells": 0}


## The way out if we dropped a bomb at `cell` (reached `delay` ticks from now).
func _refuge_after_bomb(view: View, cell: Vector2i, bombs: Array[Dictionary], delay := 0.0) -> Dictionary:
	var with_bomb: Array = bombs.duplicate()
	var bomb := _new_bomb(view, cell)
	bomb.fuse += int(delay)  # dropped when we get there
	with_bomb.append(bomb)
	var flames := view.bombs.flame_cells()
	var danger := DangerMap.build(view.grid, with_bomb, flames, view.items, slot, view.doomed)
	var refuge := _refuge(view, cell, danger, false, delay)
	if refuge.found and refuge.goal == cell and not bomb.mine:
		refuge.found = false  # "safe" on its own bomb only because its fuse is longer than we look
	if refuge.safe_cells < _profile.hideouts:
		refuge.found = false  # a single pocket: another player's bomb would trap us there
	return refuge


## Breadth-first search over walkable cells, timing each step at the player's speed. Returns
## {cell: [previous cell, arrival tick]}. `avoid_fire`: skip every cell fire will ever reach;
## otherwise only cells on fire while we pass. `delay`: ticks before we start from `from`.
## Starting from where the player stands now, the first step counts how far it already is
## towards (or away from) each neighbour, so plans agree with the way it is moving.
func _explore(view: View, from: Vector2i, danger: DangerMap, avoid_fire: bool, fleeing: bool, delay := 0.0) -> Dictionary:
	var per_cell := _ticks_per_cell(view)
	var margin: float = _profile.margin
	var offset := view.pos - Vector2(from) if delay == 0.0 else Vector2.ZERO
	var reached := {from: [from, delay]}
	var queue: Array[Vector2i] = [from]
	var head := 0
	while head < queue.size():
		var current := queue[head]
		head += 1
		for dir: Vector2i in Grid.DIRECTIONS:
			var arrive: float = reached[current][1] + per_cell
			if current == from:
				var along := offset.dot(Vector2(dir))
				var across := absf(offset.dot(Vector2(dir.y, dir.x)))
				arrive += (across - along) * per_cell
			var next := current + dir
			if reached.has(next) or not _walkable(view, next, danger, fleeing):
				continue
			if avoid_fire and danger.threatened(next):
				continue
			if not danger.is_clear(next, arrive - per_cell * 0.5 - margin, arrive + per_cell * 0.5 + margin):
				continue
			reached[next] = [current, arrive]
			queue.append(next)
	return reached


## Cells a path may use. Unless fleeing, it keeps off bad items and other players' cells: a
## player may drop a bomb there any moment, and walking into it then kicks it (input arrives a
## tick late), usually straight into fire next to its owner.
func _walkable(view: View, cell: Vector2i, danger: DangerMap, fleeing: bool) -> bool:
	if view.grid.is_blocking(cell) or view.bombs.has_bomb(cell) or danger.mines.has(cell):
		return false
	return fleeing or (view.items.item_at(cell) not in AVOID_ITEMS and not _other_cells.has(cell))


## How many cells on the way to `target` (from an _explore result) fire will reach at some point.
func _exposure(reached: Dictionary, target: Vector2i, danger: DangerMap) -> int:
	var count := 0
	var cell := target
	while reached[cell][0] != cell:
		if danger.threatened(cell):
			count += 1
		cell = reached[cell][0]
	return count


func _path_to(reached: Dictionary, target: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	var cell := target
	while reached[cell][0] != cell:
		path.push_front(cell)
		cell = reached[cell][0]
	return path


# --- Bombing -------------------------------------------------------------------

## The bomb we would drop at `cell` now (as a bomb_list() entry), following Match's rules for
## Power Bomb and Land Mine (first bomb out only).
func _new_bomb(view: View, cell: Vector2i) -> Dictionary:
	var stats := view.stats
	var first := view.bombs.bomb_count(slot) == 0
	var power := stats.has_power_bomb() and first and not stats.has_curse(Curses.Type.NO_POWER)
	return {"cell": cell, "owner": slot, "fire_range": Rules.MAX_FIRE if power else stats.blast_range(),
		"fuse": stats.bomb_fuse(), "remote": stats.has_remote(), "pierce": stats.has_pierce(),
		"dangerous": false, "mine": stats.has_land_mine() and first, "armed": false, "flying": false}


func _may_bomb_at_all(view: View) -> bool:
	return not view.stats.has_curse(Curses.Type.HANDS_TIED) \
		and view.bombs.bomb_count(slot) < view.stats.bomb_capacity()


func _may_bomb(view: View, cell: Vector2i) -> bool:
	return _may_bomb_at_all(view) and not view.bombs.has_bomb(cell) and not view.bombs.has_mine(cell)


## What a bomb at `cell` would achieve: 2 per brick not already doomed, 6 x aggression per
## player in the blast (when hunting), minus 3 per good item it would burn. Land mines (they
## wait to be stepped on) are not used yet.
func _bomb_value(view: View, cell: Vector2i, danger: DangerMap, stops: Dictionary, hunting: bool) -> float:
	var bomb := _new_bomb(view, cell)
	if bomb.mine:
		return 0.0
	var cells := DangerMap.blast_cells(view.grid, bomb, view.items, stops)
	var value := 0.0
	for c in cells:
		if view.grid.get_cell(c) == Grid.Cell.SOFT and not view.bombs.is_burning(c) and not danger.threatened(c):
			value += 2.0
		var item := view.items.item_at(c)
		if item != Items.NONE and item not in AVOID_ITEMS:
			value -= 3.0
	if hunting:
		for other in view.others:
			if GridMovement.nearest_cell(other) in cells:
				value += 6.0 * _profile.aggression
	return value


func _stops(bombs: Array[Dictionary]) -> Dictionary:
	var stops := {}
	for bomb in bombs:
		if not bomb.flying and not bomb.mine:
			stops[bomb.cell] = true
	return stops


func _has_remote_out(bombs: Array[Dictionary]) -> bool:
	for bomb in bombs:
		if bomb.owner == slot and bomb.remote and not bomb.flying:
			return true
	return false


# --- Steering ------------------------------------------------------------------

## Held actions for this tick: towards the next cell of the path, or onto the centre of the
## current one; plus any one-tick presses.
func _actions(view: View, cell: Vector2i) -> Dictionary:
	var dir := Vector2i.ZERO
	if not _path.is_empty():
		var step := _path[0] - cell
		if absi(step.x) + absi(step.y) == 1:
			dir = step
		else:
			_path.clear()  # moved off the path (Swap curse): plan again
			_think_in = 0
	elif not _centred(view, cell):
		var offset := view.pos - Vector2(cell)
		if absf(offset.x) >= absf(offset.y):
			dir = Vector2i(-int(signf(offset.x)), 0)
		else:
			dir = Vector2i(0, -int(signf(offset.y)))
	if dir != Vector2i.ZERO and view.bombs.has_bomb(cell + dir) 			and (view.pos - Vector2(cell)).dot(Vector2(dir)) > -_step(view) * 2.0:
		# Never push into a bomb from the middle of a cell: that kicks it (input arrives a tick
		# late, so stop a little early). The path gets re-planned around it.
		dir = Vector2i.ZERO
	_last_dir = dir
	if dir != Vector2i.ZERO and _profile.undizzy and view.stats.has_curse(Curses.Type.DIZZY):
		dir = -dir
	var held := {}
	if dir != Vector2i.ZERO:
		held[DIRECTION_ACTIONS[dir]] = true
	for action: StringName in _presses:
		held[action] = true
	_presses.clear()
	return held


func _next_step_blocked(view: View, danger: DangerMap) -> bool:
	if _path.is_empty():
		return false
	var next := _path[0]
	if view.grid.is_blocking(next) or view.bombs.has_bomb(next) or danger.mines.has(next):
		return true
	return not _escaping and danger.threatened(next)  # fire appeared on the way


func _centred(view: View, cell: Vector2i) -> bool:
	var tolerance := maxf(0.08, view.stats.speed() / Rules.TICKS_PER_SECOND * 0.6)
	return view.pos.distance_to(Vector2(cell)) <= tolerance


## Cells moved per tick.
func _step(view: View) -> float:
	return view.stats.speed() / Rules.TICKS_PER_SECOND


func _ticks_per_cell(view: View) -> float:
	return Rules.TICKS_PER_SECOND / maxf(view.stats.speed(), 0.5)


func _distance_to_others(view: View, cell: Vector2i) -> float:
	var best := INF
	for other in view.others:
		var o := GridMovement.nearest_cell(other)
		best = minf(best, absi(o.x - cell.x) + absi(o.y - cell.y))
	return best


func _track_stuck(pos: Vector2) -> void:
	if _last_dir != Vector2i.ZERO and pos.distance_squared_to(_last_pos) < 0.000001:
		_stuck_ticks += 1
	else:
		_stuck_ticks = 0
	_last_pos = pos
