class_name BomberAI
extends RefCounted
## A computer player's brain. Every tick it looks at the match (a View) and returns the buttons
## its virtual controller holds. It never touches the game itself, so it walks, bombs, kicks and
## suffers curses by exactly the same rules as a human on a pad.
##
## What it does, re-planned every few ticks (more often on harder levels):
## 1. Fire is coming to its cell (DangerMap): run to the nearest cell no fire will reach, by a
##    path that is not on fire while it passes and crosses few blast lines.
## 2. Standing somewhere a move pays off, make it: drop a bomb (bricks, players in line, players
##    it would corner), a Land Mine in a corridor, kick or punch a bomb at a player, throw one
##    over the walls (Power Glove, charged first with the Super Glove), or lay a Line Bomb down a
##    corridor. Only when there is a way out once that move is counted in (Easy sometimes forgets).
##    Moves that take several buttons run as a short script of held buttons, tick by tick.
## 3. Otherwise walk to the best target: a good item, a spot where a move pays off, or towards the
##    nearest player; with nothing better, wander (towards the middle once sudden death starts).
## Its own Remote Control bombs: once clear of them it sets them off, when they would catch a
## player or nobody is close enough to wait for.

enum Level { EASY, NORMAL, HARD }
## A personality nudges the level's numbers, so several AIs on one level do not all play alike.
enum Personality { BALANCED, AGGRESSIVE, CAUTIOUS, COLLECTOR }

const LEVEL_NAMES := ["Easy", "Normal", "Hard"]
const PERSONALITY_NAMES := ["Balanced", "Aggressive", "Cautious", "Collector"]

## Per level:
##   think       ticks between plans
##   reaction    ticks before it notices fire coming its way
##   aggression  chance per plan to go for players; scales how much hitting a player is worth
##   item_range  how many cells it walks for an item
##   margin      ticks of slack it keeps from fire when planning a path
##   blunder     chance to drop a bomb without checking for a way out
##   hideouts    safe cells it wants within reach before a move (1 = any way out; 2 keeps it out
##               of one-cell pockets where another bomb would trap it)
##   tricks      chance per plan to consider kicks, punches, throws and line bombs
##   trap        chance per plan to check whether a bomb would corner a player (costly)
##   undizzy     makes up for the Dizzy curse (reversed controls)
const PROFILES := [
	{"think": 24, "reaction": 14, "aggression": 0.35, "item_range": 4, "margin": 6, "blunder": 0.05,
		"hideouts": 1, "tricks": 0.3, "trap": 0.0, "undizzy": false},
	{"think": 10, "reaction": 5, "aggression": 0.7, "item_range": 9, "margin": 9, "blunder": 0.01,
		"hideouts": 2, "tricks": 0.7, "trap": 0.5, "undizzy": true},
	{"think": 4, "reaction": 0, "aggression": 1.0, "item_range": 99, "margin": 12, "blunder": 0.0,
		"hideouts": 2, "tricks": 1.0, "trap": 1.0, "undizzy": true},
]
## Items it will not walk over (unless running from fire).
const AVOID_ITEMS := [Items.Type.SKULL, Items.Type.SPEED_DOWN]
## Move spots that get the (costlier) way-out check per plan, best first.
const SPOTS_CHECKED := 4
## A move must be worth at least this much (a brick is 2, a player 6 x aggression).
const MIN_MOVE_VALUE := 2.0
## A Line Bomb spends every bomb at once: it must beat a single bomb by this much.
const LINE_EXTRA_VALUE := 4.0
## Cornering a player: no hiding place left is nearly a kill; a single one is a good squeeze.
const TRAP_KILL_VALUE := 10.0
const TRAP_SQUEEZE_VALUE := 3.0
## Players further than this (cells) from a bomb are not checked for being cornered.
const TRAP_RADIUS := 5
## Choosing where to hide: each cell on the way that fire will reach costs this many ticks extra,
## so it prefers routes that do not run along blast lines (plans change; exposure kills).
const EXPOSURE_TICKS := 12.0
## A script is dropped when fire will reach its cell sooner than this (time to still get away).
const SCRIPT_ABORT_TICKS := 60
const NO_CELL := Vector2i(-1, -1)
const DIRECTION_ACTIONS := {Vector2i.UP: &"up", Vector2i.DOWN: &"down", Vector2i.LEFT: &"left", Vector2i.RIGHT: &"right"}


## What the AI sees each tick.
class View:
	var grid: Grid
	var bombs: BombField
	var items: ItemField
	var pos := Vector2.ZERO
	var facing := Vector2i.DOWN
	## Holding a bomb overhead (Power Glove): letting go of Bomb throws it.
	var carrying := false
	var stats: PlayerStats
	## Living opponents' positions.
	var others: Array[Vector2] = []
	## Sudden death: cell -> ticks until a block lands there.
	var doomed := {}


var slot := 0
var level: int = Level.NORMAL
var personality: int = Personality.BALANCED
var rng := RandomNumberGenerator.new()
## The last few plans in words, newest last (for debugging: tools/ai_soak.gd prints them).
var notes: Array[String] = []

var _profile: Dictionary
var _path: Array[Vector2i] = []  # cells still to walk through, next first
var _goal := NO_CELL
var _act_at_goal := false        # think again on arrival: a move is waiting there
var _escaping := false           # the path leads out of fire
var _refuge_found := false       # ...to a cell fire will not reach (false: just the best we saw)
var _script: Array[Dictionary] = []  # held buttons for the coming ticks, one entry per tick
var _think_in := 0
var _danger_ticks := 0           # how long fire has been coming without a plan for it
var _presses := {}               # one-tick presses for the next actions: &"bomb", &"special"
var _last_pos := Vector2.INF
var _last_dir := Vector2i.ZERO
var _stuck_ticks := 0
var _other_cells := {}           # cells other players stand in (this tick)


## `chosen_personality` -1 picks one at random.
func _init(player_slot := 0, difficulty: int = Level.NORMAL, seed_value := 0, chosen_personality := -1) -> void:
	slot = player_slot
	level = clampi(difficulty, 0, PROFILES.size() - 1)
	if seed_value != 0:
		rng.seed = seed_value
	else:
		rng.randomize()
	personality = chosen_personality if chosen_personality >= 0 else rng.randi_range(0, Personality.size() - 1)
	_profile = profile_for(level, personality)


## A level's numbers with a personality's nudges.
static func profile_for(difficulty: int, chosen_personality: int) -> Dictionary:
	var profile: Dictionary = PROFILES[difficulty].duplicate()
	profile["item_bonus"] = 0.0
	match chosen_personality:
		Personality.AGGRESSIVE:
			profile.aggression = minf(profile.aggression + 0.2, 1.0)
			profile.margin = maxi(profile.margin - 2, 4)
		Personality.CAUTIOUS:
			profile.aggression = maxf(profile.aggression - 0.2, 0.1)
			profile.margin += 4
		Personality.COLLECTOR:
			profile.item_range += 5
			profile.item_bonus = 4.0
	return profile


## Forget the plan (new round, new arena).
func reset() -> void:
	_path.clear()
	_goal = NO_CELL
	_act_at_goal = false
	_escaping = false
	_script.clear()
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

	if not _script.is_empty():
		if danger.time_to_fire(cell) > SCRIPT_ABORT_TICKS:
			return _script_actions(view)
		_script.clear()  # fire is coming: drop the move (a held bomb gets thrown) and run
		_think_in = 0
	elif view.carrying:
		_plan_throw(view, cell, bombs, danger)  # holding a bomb with no plan: throw it somewhere useful
		return _script_actions(view)

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
			or _next_step_blocked(view, danger) or (arrived and _act_at_goal)
	if rethink:
		_think(view, cell, bombs, danger, in_danger)
		if not _script.is_empty():
			return _script_actions(view)
	return _actions(view, cell)


# --- Planning ------------------------------------------------------------------

func _think(view: View, cell: Vector2i, bombs: Array[Dictionary], danger: DangerMap, in_danger: bool) -> void:
	_think_in = _profile.think
	_danger_ticks = 0
	_stuck_ticks = 0
	_path.clear()
	_goal = NO_CELL
	_act_at_goal = false
	_escaping = false
	_refuge_found = false

	if in_danger:
		# A bomb next to us threatens our cell: kicking or punching it at a player beats running.
		if _centred(view, cell) and rng.randf() < _profile.tricks:
			var shots := _moves_at(view, cell, bombs, _stops(bombs), danger, true, true, view.facing) \
				.filter(func(m): return m.kind in ["kick", "punch"] and m.value >= MIN_MOVE_VALUE)
			shots.sort_custom(func(a, b): return a.value > b.value)
			for move: Dictionary in shots:
				if _check_move(view, cell, move, 0.0, false).refuge.found:
					_start_move(view, cell, move, {})
					return
		var refuge := _refuge(view, cell, danger, true)
		_follow(refuge, true)
		_note("at %s: run to %s%s" % [cell, refuge.goal, "" if refuge.found else " (no safe cell)"])
		return
	_maybe_detonate(view, bombs)
	if _centred(view, cell):
		var hunting := _hunting(view)
		var tricks: bool = rng.randf() < _profile.tricks
		var moves := _moves_at(view, cell, bombs, _stops(bombs), danger, hunting, tricks, view.facing)
		moves.sort_custom(func(a, b): return a.value > b.value)
		var trap: bool = rng.randf() < _profile.trap and _distance_to_others(view, cell) <= TRAP_RADIUS
		for move: Dictionary in moves.slice(0, 3):
			if move.value < MIN_MOVE_VALUE and not (trap and move.kind == "bomb"):
				continue
			var check := _check_move(view, cell, move, 0.0, trap)
			var value: float = move.value + check.trap
			if value < MIN_MOVE_VALUE:
				continue
			if check.refuge.found or (move.kind == "bomb" and rng.randf() < _profile.blunder):
				_start_move(view, cell, move, check.refuge)
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
	var hunting := _hunting(view)
	var tricks: bool = rng.randf() < _profile.tricks
	var stops := _stops(bombs)
	var candidates: Array = []  # [score, cell, move or {}]
	for target: Vector2i in reached:
		var steps: float = reached[target][1] / per_cell
		var score := -INF
		var best_move := {}
		var item := view.items.item_at(target)
		if item != Items.NONE and item not in AVOID_ITEMS and steps <= _profile.item_range:
			score = 14.0 + _profile.item_bonus - steps
		var arrival := target - (reached[target][0] as Vector2i) if target != cell else view.facing
		for move: Dictionary in _moves_at(view, target, bombs, stops, danger, hunting, tricks and steps <= 8.0, arrival):
			if move.value >= MIN_MOVE_VALUE and move.value - steps * 0.7 > score:
				score = move.value - steps * 0.7
				best_move = move
		if score > -INF:
			candidates.append([score, target, best_move])
	candidates.sort_custom(func(a, b): return a[0] > b[0])

	var checked := 0
	for candidate: Array in candidates:
		var target: Vector2i = candidate[1]
		var move: Dictionary = candidate[2]
		if not move.is_empty():
			if checked >= SPOTS_CHECKED:
				continue
			checked += 1
			if not _check_move(view, target, move, reached[target][1], false).refuge.found:
				continue  # a dead end once the move is made
		_go(reached, target, not move.is_empty(), move.get("kind", "item"))
		return

	# Nothing worth doing: close in on the nearest player (Easy only when hunting); in sudden
	# death head for the middle; else wander.
	var target := NO_CELL
	var best := INF
	if (hunting or level != Level.EASY) and not view.others.is_empty():
		for c: Vector2i in reached:
			var score: float = _distance_to_others(view, c) + reached[c][1] / per_cell * 0.1
			if score < best:
				best = score
				target = c
	elif not view.doomed.is_empty():
		var middle := Vector2(view.grid.width - 1, view.grid.height - 1) / 2.0
		for c: Vector2i in reached:
			var score := Vector2(c).distance_to(middle)
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
		_go(reached, target, false, "wander")


## Going for players this plan? A roll against aggression; always once sudden death has begun.
func _hunting(view: View) -> bool:
	return not view.doomed.is_empty() or rng.randf() < _profile.aggression


func _go(reached: Dictionary, target: Vector2i, act_there: bool, why: String) -> void:
	_path = _path_to(reached, target)
	_goal = target
	_act_at_goal = act_there
	_note("go to %s (%s)" % [target, why])


func _note(text: String) -> void:
	if not notes.is_empty() and notes.back() == text:
		return
	notes.append(text)
	if notes.size() > 10:
		notes.pop_front()


## The current plan, for debugging.
func debug_state() -> String:
	return "path %s, goal %s, escaping %s (refuge found %s), act at goal %s, script %d, think in %d, stuck %d" % [
		_path, _goal, _escaping, _refuge_found, _act_at_goal, _script.size(), _think_in, _stuck_ticks]


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


## Breadth-first search over walkable cells, timing each step at the player's speed. Returns
## {cell: [previous cell, arrival tick]}. `avoid_fire`: skip every cell fire will ever reach;
## otherwise only cells on fire while we pass. `delay`: ticks before we start from `from`.
## Starting from where the player stands now, the first step counts how far it already is
## towards (or away from) each neighbour, so plans agree with the way it is moving.
func _explore(view: View, from: Vector2i, danger: DangerMap, avoid_fire: bool, fleeing: bool, delay := 0.0,
		extra_blocked := {}) -> Dictionary:
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
			if reached.has(next) or extra_blocked.has(next) or not _walkable(view, next, danger, fleeing):
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


# --- Moves ---------------------------------------------------------------------
# A move made from a cell: {"kind": "bomb" | "kick" | "punch" | "throw" | "line", "dir": Vector2i,
# "value": float, "bombs": the bomb list once it is made (for the way-out check), "new": cells of
# bombs it adds (they block the way out), "ticks": how long its buttons take}.

## Every move worth considering from `cell`, arriving there facing `facing`. `tricks`: also kicks,
## punches, throws and line bombs (when the AI has those items).
func _moves_at(view: View, cell: Vector2i, bombs: Array[Dictionary], stops: Dictionary, danger: DangerMap,
		hunting: bool, tricks: bool, facing: Vector2i) -> Array[Dictionary]:
	var moves: Array[Dictionary] = []
	var stats := view.stats
	var can_drop := _may_bomb(view, cell)
	var first := _new_bomb(view, cell)
	if can_drop:
		var move := _move("bomb", Vector2i.ZERO, _bomb_value(view, first, danger, stops, hunting),
			_with(bombs, [first]), [cell], 1)
		move.mine = first.mine
		moves.append(move)
	if not tricks or not hunting:
		return moves  # the tricks below only aim at players

	var landing_blockers := _other_cells.duplicate()
	landing_blockers[cell] = true  # we stand here too
	if (stats.has_kick or stats.has_punch) and not stats.has_bouncy():
		for dir: Vector2i in Grid.DIRECTIONS:
			var target := cell + dir
			var bomb := _still_bomb_at(view, bombs, target)
			if bomb.is_empty():
				continue
			if stats.has_kick:
				var stop := AIMoves.slide_stop(view.grid, view.bombs, view.items, _other_cells, target, dir)
				if stop != target:
					var moved := bomb.duplicate()
					moved.cell = stop
					var hit := _hit_value(view, moved, _moved_stops(stops, target, stop))
					moves.append(_move("kick", dir, hit, _replaced(bombs, bomb, moved), [], 3))
			if stats.has_punch and (facing == dir or not stats.has_kick):
				var landing := AIMoves.landing(view.grid, view.bombs, landing_blockers, target, dir, Rules.PUNCH_DISTANCE)
				var moved := bomb.duplicate()
				moved.cell = landing[0]
				moved.fuse = maxi(bomb.fuse, Rules.PUNCH_FLIGHT_TICKS + landing[1] * Rules.BOUNCE_FLIGHT_TICKS + 1)
				var hit := _hit_value(view, moved, _moved_stops(stops, target, moved.cell))
				moves.append(_move("punch", dir, hit, _replaced(bombs, bomb, moved), [], 2 if facing == dir else 3))
	if can_drop and not first.mine and stats.has_glove():
		var charge := stats.has_super_glove() and level != Level.EASY
		for dir: Vector2i in Grid.DIRECTIONS:
			var landing := AIMoves.landing(view.grid, view.bombs, landing_blockers, cell, dir, Rules.THROW_DISTANCE)
			var thrown := first.duplicate()
			thrown.cell = landing[0]
			var ticks := 6 + (Rules.SUPER_GLOVE_CHARGE_TICKS if charge else 0)
			thrown.fuse = (Rules.DANGEROUS_FUSE_TICKS if charge else first.fuse) \
				+ Rules.THROW_FLIGHT_TICKS + landing[1] * Rules.BOUNCE_FLIGHT_TICKS + ticks
			thrown.dangerous = charge
			thrown.created = true
			var hit := _hit_value(view, thrown, stops)
			var move := _move("throw", dir, hit, _with(bombs, [thrown]), [], ticks)
			move.charge = charge
			moves.append(move)
	elif can_drop and not first.mine and stats.has_line_bomb():
		var left := stats.bomb_capacity() - view.bombs.bomb_count(slot) - 1
		for dir: Vector2i in Grid.DIRECTIONS:
			var cells := AIMoves.line_cells(view.grid, view.bombs, view.items, _other_cells, cell, dir, left)
			if cells.is_empty():
				continue
			var added: Array[Dictionary] = []
			added.append(first)
			var line_stops := stops.duplicate()
			line_stops[cell] = true
			for c in cells:
				var bomb := _new_bomb(view, c)
				bomb.mine = false
				bomb.fire_range = stats.blast_range()  # only the first bomb out can be a Power Bomb
				bomb.created = true
				added.append(bomb)
				line_stops[c] = true
			var value := _cells_value(view, _union_blast(view, added, line_stops), danger, hunting) - LINE_EXTRA_VALUE
			moves.append(_move("line", dir, value, _with(bombs, added), [cell] + cells, 5))
	return moves


func _move(kind: String, dir: Vector2i, value: float, after: Array, new_cells: Array, ticks: int) -> Dictionary:
	return {"kind": kind, "dir": dir, "value": value, "bombs": after, "new": new_cells, "ticks": ticks}


## Is `move` from `cell` (reached `delay` ticks from now) survivable? Returns {"refuge": our way
## out once it is made, "trap": bonus for players it corners (when `trap` is on)}.
func _check_move(view: View, cell: Vector2i, move: Dictionary, delay: float, trap: bool) -> Dictionary:
	var after: Array = move.bombs.duplicate(true)
	if delay > 0.0:
		for bomb: Dictionary in after:
			if bomb.get("created", false):
				bomb.fuse += int(delay)  # made when we get there; bombs already out keep their time
	var start: float = delay + move.ticks
	var danger := DangerMap.build(view.grid, after, view.bombs.flame_cells(), view.items, slot, view.doomed)
	var blocked := {}
	for c: Vector2i in move.new:
		if c != cell:
			blocked[c] = true
	var reached := _explore(view, cell, danger, false, false, start, blocked)
	var refuge := _refuge_from(reached, danger)
	if refuge.found and refuge.goal == cell and cell in move.new and not move.get("mine", false):
		refuge.found = false  # "safe" on its own bomb only because its fuse is longer than we look
	if refuge.safe_cells < _profile.hideouts:
		refuge.found = false  # a single pocket: another player's bomb would trap us there
	return {"refuge": refuge, "trap": _trap_value(view, danger, _stops(after), cell) if trap else 0.0}


## _refuge for an exploration already made.
func _refuge_from(reached: Dictionary, danger: DangerMap) -> Dictionary:
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
	if best == NO_CELL:
		return {"found": false, "goal": NO_CELL, "path": [] as Array[Vector2i], "safe_cells": 0}
	return {"found": true, "goal": best, "path": _path_to(reached, best), "safe_cells": safe_cells}


## Begins `move` from `cell`: presses, or a script of held buttons, then the way out.
func _start_move(view: View, cell: Vector2i, move: Dictionary, refuge: Dictionary) -> void:
	var dir: Vector2i = move.dir
	var turn := {DIRECTION_ACTIONS.get(dir, &"none"): true}
	match move.kind:
		"bomb":
			_presses[&"bomb"] = true
			_follow(refuge, true)
		"kick":
			_script.assign([turn, turn, turn])  # pushing into it from the cell centre kicks it
		"punch":
			if view.facing != dir:
				_script.append(turn)
			_script.append({&"special": true})
		"throw":
			# Drop, let go, pick it up, turn while holding it, (charge), let go to throw.
			_script.assign([{&"bomb": true}, {}, {&"bomb": true}, {&"bomb": true, DIRECTION_ACTIONS[dir]: true}])
			if move.get("charge", false):
				for i in Rules.SUPER_GLOVE_CHARGE_TICKS:
					_script.append({&"bomb": true})
			_script.append({})
		"line":
			_script.assign([{&"bomb": true}, {}])
			if view.facing != dir:
				_script.append(turn)
			_script.append_array([{&"bomb": true}, {}])
	_note("at %s: %s%s" % [cell, move.kind, "" if dir == Vector2i.ZERO else " %s" % DIRECTION_ACTIONS[dir]])


## Holding a bomb without a plan (a throw got interrupted): turn to the direction where it would
## catch a player, or else any direction it can be thrown safely, and let go. In danger: let go now.
func _plan_throw(view: View, cell: Vector2i, bombs: Array[Dictionary], danger: DangerMap) -> void:
	_script.clear()
	if danger.threatened(cell):
		_script.append({})
		return
	var stops := _stops(bombs)
	var blockers := _other_cells.duplicate()
	blockers[cell] = true
	var best_dir := view.facing
	var best := -INF
	for dir: Vector2i in Grid.DIRECTIONS:
		var landing := AIMoves.landing(view.grid, view.bombs, blockers, cell, dir, Rules.THROW_DISTANCE)
		var thrown := _new_bomb(view, landing[0])
		thrown.mine = false
		var value := _hit_value(view, thrown, stops)
		if cell in DangerMap.blast_cells(view.grid, thrown, view.items, stops):
			value -= 100.0  # it would come down on top of us
		if value > best:
			best = value
			best_dir = dir
	_script.assign([{&"bomb": true, DIRECTION_ACTIONS[best_dir]: true}, {}])
	_note("at %s: throw the bomb we hold %s" % [cell, DIRECTION_ACTIONS[best_dir]])


## The next scripted tick's buttons.
func _script_actions(view: View) -> Dictionary:
	var held: Dictionary = _script.pop_front()
	if _script.is_empty():
		_think_in = 0  # move done: plan again (usually: run)
	var out := {}
	for action: StringName in held:
		var dir: Vector2i = DIRECTION_ACTIONS.find_key(action) if DIRECTION_ACTIONS.values().has(action) else Vector2i.ZERO
		if dir != Vector2i.ZERO and _profile.undizzy and view.stats.has_curse(Curses.Type.DIZZY):
			action = DIRECTION_ACTIONS[-dir]
		out[action] = true
	_last_dir = Vector2i.ZERO
	return out


# --- Judging moves -------------------------------------------------------------

## The bomb we would drop at `cell` now (as a bomb_list() entry), following Match's rules for
## Power Bomb and Land Mine (first bomb out only).
func _new_bomb(view: View, cell: Vector2i) -> Dictionary:
	var stats := view.stats
	var first := view.bombs.bomb_count(slot) == 0
	var power := stats.has_power_bomb() and first and not stats.has_curse(Curses.Type.NO_POWER)
	return {"cell": cell, "owner": slot, "fire_range": Rules.MAX_FIRE if power else stats.blast_range(),
		"fuse": stats.bomb_fuse(), "remote": stats.has_remote(), "pierce": stats.has_pierce(),
		"dangerous": false, "mine": stats.has_land_mine() and first, "armed": false, "flying": false,
		"created": true}


func _may_bomb_at_all(view: View) -> bool:
	return not view.carrying and not view.stats.has_curse(Curses.Type.HANDS_TIED) \
		and view.bombs.bomb_count(slot) < view.stats.bomb_capacity()


func _may_bomb(view: View, cell: Vector2i) -> bool:
	return _may_bomb_at_all(view) and not view.bombs.has_bomb(cell) and not view.bombs.has_mine(cell)


## A plain bomb: what its blast achieves (see _cells_value). A Land Mine instead pays off in a
## corridor (two ways in or out), more so near a player.
func _bomb_value(view: View, bomb: Dictionary, danger: DangerMap, stops: Dictionary, hunting: bool) -> float:
	if bomb.mine:
		var cell: Vector2i = bomb.cell
		var open := 0
		for dir: Vector2i in Grid.DIRECTIONS:
			if not view.grid.is_blocking(cell + dir):
				open += 1
		if open != 2:
			return 0.0
		return MIN_MOVE_VALUE + (3.0 if _distance_to_others(view, cell) <= 6 else 0.0)
	return _cells_value(view, DangerMap.blast_cells(view.grid, bomb, view.items, stops), danger, hunting)


## Fire on `cells`: 2 per brick not already doomed, 6 x aggression per player (when hunting),
## minus 3 per good item it would burn.
func _cells_value(view: View, cells: Array[Vector2i], danger: DangerMap, hunting: bool) -> float:
	var value := 0.0
	for c in cells:
		if view.grid.get_cell(c) == Grid.Cell.SOFT and not view.bombs.is_burning(c) and not danger.threatened(c):
			value += 2.0
		var item := view.items.item_at(c)
		if item != Items.NONE and item not in AVOID_ITEMS:
			value -= 3.0
	if hunting:
		value += _players_in(view, cells) * 6.0 * _profile.aggression
	return value


## A bomb sent at players (kick, punch, throw): only the players it catches count.
func _hit_value(view: View, bomb: Dictionary, stops: Dictionary) -> float:
	return _players_in(view, DangerMap.blast_cells(view.grid, bomb, view.items, stops)) * 6.0 * _profile.aggression


func _players_in(view: View, cells: Array[Vector2i]) -> int:
	var count := 0
	for other in view.others:
		if GridMovement.nearest_cell(other) in cells:
			count += 1
	return count


func _union_blast(view: View, bombs: Array[Dictionary], stops: Dictionary) -> Array[Vector2i]:
	var seen := {}
	for bomb in bombs:
		for c in DangerMap.blast_cells(view.grid, bomb, view.items, stops):
			seen[c] = true
	var cells: Array[Vector2i] = []
	cells.assign(seen.keys())
	return cells


## Bonus for players a move corners: for each player near it, how many cells they could still
## reach in time that fire will not (at the base speed). None left is nearly a kill. `bomb_cells`:
## where bombs sit once the move is made.
func _trap_value(view: View, danger: DangerMap, bomb_cells: Dictionary, from: Vector2i) -> float:
	var value := 0.0
	var per_cell := Rules.TICKS_PER_SECOND / Rules.PLAYER_SPEED
	for other in view.others:
		var start := GridMovement.nearest_cell(other)
		if absi(start.x - from.x) + absi(start.y - from.y) > TRAP_RADIUS:
			continue
		var safe := 0
		var reached := {start: 0.0}
		var queue: Array[Vector2i] = [start]
		var head := 0
		while head < queue.size() and safe < 2:
			var current := queue[head]
			head += 1
			var arrive: float = reached[current]
			if danger.safe_from(current, arrive):
				safe += 1  # count it, and keep looking from it: two hideouts mean room to run
			for dir: Vector2i in Grid.DIRECTIONS:
				var next := current + dir
				if reached.has(next) or bomb_cells.has(next) or view.grid.is_blocking(next) \
						or danger.mines.has(next):
					continue
				if danger.is_clear(next, arrive + per_cell * 0.5, arrive + per_cell * 1.5):
					reached[next] = arrive + per_cell
					queue.append(next)
		if safe == 0:
			value += TRAP_KILL_VALUE * _profile.aggression
		elif safe == 1:
			value += TRAP_SQUEEZE_VALUE * _profile.aggression
	return value


func _stops(bombs: Array) -> Dictionary:
	var stops := {}
	for bomb: Dictionary in bombs:
		if not bomb.flying and not bomb.mine:
			stops[bomb.cell] = true
	return stops


func _moved_stops(stops: Dictionary, from: Vector2i, to: Vector2i) -> Dictionary:
	var moved := stops.duplicate()
	moved.erase(from)
	moved[to] = true
	return moved


## A still bomb on the grid in `cell` (kickable, punchable), or {}.
func _still_bomb_at(view: View, bombs: Array[Dictionary], cell: Vector2i) -> Dictionary:
	if not view.bombs.has_bomb(cell) or view.bombs.is_sliding(cell):
		return {}
	for bomb in bombs:
		if bomb.cell == cell and not bomb.flying and not bomb.mine:
			return bomb
	return {}


func _with(bombs: Array, added: Array) -> Array:
	var list: Array = bombs.duplicate()
	list.append_array(added)
	return list


func _replaced(bombs: Array[Dictionary], old: Dictionary, new_bomb: Dictionary) -> Array:
	var list: Array = bombs.duplicate()
	list[list.find(old)] = new_bomb
	return list


## Remote Control: once clear of our remote bombs, set them off if one would catch a player, or if
## no player is close enough to be worth waiting for.
func _maybe_detonate(view: View, bombs: Array[Dictionary]) -> void:
	if not view.stats.has_remote():
		return
	var stops := _stops(bombs)
	var wait := false
	for bomb in bombs:
		if bomb.owner != slot or not bomb.remote or bomb.flying:
			continue
		if _players_in(view, DangerMap.blast_cells(view.grid, bomb, view.items, stops)) > 0:
			_presses[&"special"] = true
			return
		if _distance_to_others(view, bomb.cell) <= 4:
			wait = true
		else:
			_presses[&"special"] = true
	if wait:
		_presses.erase(&"special")


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
	if dir != Vector2i.ZERO and view.bombs.has_bomb(cell + dir) \
			and (view.pos - Vector2(cell)).dot(Vector2(dir)) > -_step(view) * 2.0:
		# Never push into a bomb from the middle of a cell: that kicks it (input arrives a tick
		# late, so stop a little early). Kicks on purpose run as a script instead.
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
