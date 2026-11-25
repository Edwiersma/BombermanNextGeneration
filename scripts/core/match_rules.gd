class_name MatchRules
extends RefCounted
## Round and match flow for versus, advanced one physics tick at a time. Pure logic: the Match
## node builds arenas, moves players and applies falling blocks in response to the signals.
##
## WAITING -> begin_match() -> [INTRO -> PLAYING -> ROUND_OVER]* -> MATCH_OVER -> WAITING
##
## - A round ends when at most one player is left (none in solo practice), after a short delay
##   during which play continues. One survivor wins the round; nobody left is a draw.
## - The clock runs only while PLAYING. With `sudden_death_at` ticks left, blocks start falling in
##   a spiral from the edge inward. When the clock hits 0 with several players alive: draw.
##   round_ticks = 0 means no time limit (and so no sudden death).
## - Draws award nothing. First to `wins_to_win` round wins takes the match.

signal round_started(round_number: int)  # intro begins: show "ROUND n"
signal ready_shown                       # intro: show "READY?"
signal play_started                      # "GO!": unlock input
signal hurry_up                          # sudden death begins
signal block_falling(cell: Vector2i)     # start the falling animation
signal block_landed(cell: Vector2i)      # apply: cell becomes hard, crush what is there
signal round_ended(winner: int)          # slot, or -1 for a draw
signal next_round                        # build a fresh arena and call start_round()
signal match_ended(winner: int)
signal match_finished                    # result shown long enough; back to WAITING

enum State { WAITING, INTRO, PLAYING, ROUND_OVER, MATCH_OVER }

# Tunable per match; see configure().
var wins_to_win := Rules.WINS_TO_WIN
var round_ticks := Rules.ROUND_TICKS          # 0 = no time limit
var sudden_death_at := Rules.SUDDEN_DEATH_AT_TICKS  # -1 = never

var state := State.WAITING
var round_number := 0
var participants: Array[int] = []
var alive: Array[int] = []
var wins := {}  # slot -> round wins
var time_left := 0
var sudden_death := false
var round_winner := -1
var match_winner := -1

var _grid: Grid
var _state_ticks := 0     # time spent in the current state
var _end_delay := -1      # ticks until the round is decided; -1 = not counting
var _spiral: Array[Vector2i] = []
var _spiral_index := 0
var _next_drop := 0
var _falling := {}        # Vector2i -> ticks until it lands


func configure(settings: MatchSettings) -> void:
	wins_to_win = settings.wins_to_win
	round_ticks = settings.round_ticks()
	sudden_death_at = settings.sudden_death_at_ticks()


func has_time_limit() -> bool:
	return round_ticks > 0


func begin_match(slots: Array[int]) -> void:
	participants = slots.duplicate()
	participants.sort()
	wins.clear()
	for slot in participants:
		wins[slot] = 0
	round_number = 0
	match_winner = -1


## Call with the freshly built grid for the round (after begin_match, and on next_round).
func start_round(grid: Grid) -> void:
	_grid = grid
	round_number += 1
	alive = participants.duplicate()
	time_left = round_ticks
	sudden_death = false
	round_winner = -1
	_end_delay = -1
	_spiral = spiral_cells(grid.width, grid.height)
	_spiral_index = 0
	_falling.clear()
	_enter(State.INTRO)
	round_started.emit(round_number)


func player_died(slot: int) -> void:
	alive.erase(slot)


func is_playing() -> bool:
	return state == State.PLAYING


func tick() -> void:
	_state_ticks += 1
	match state:
		State.INTRO:
			if _state_ticks == Rules.INTRO_ROUND_TICKS:
				ready_shown.emit()
			elif _state_ticks == Rules.INTRO_ROUND_TICKS + Rules.INTRO_READY_TICKS:
				_enter(State.PLAYING)
				play_started.emit()
		State.PLAYING:
			_tick_playing()
		State.ROUND_OVER:
			if _state_ticks >= Rules.ROUND_OVER_TICKS:
				if match_winner != -1:
					_enter(State.MATCH_OVER)
					match_ended.emit(match_winner)
				else:
					_enter(State.WAITING)  # until the listener calls start_round()
					next_round.emit()
		State.MATCH_OVER:
			if _state_ticks >= Rules.MATCH_OVER_TICKS:
				_enter(State.WAITING)
				match_finished.emit()


func _tick_playing() -> void:
	if has_time_limit():
		time_left = maxi(time_left - 1, 0)

	if not sudden_death and sudden_death_at >= 0 and has_time_limit() and time_left <= sudden_death_at:
		sudden_death = true
		_next_drop = 0
		hurry_up.emit()
	if sudden_death:
		_tick_sudden_death()

	var last_standing := 1 if participants.size() >= 2 else 0
	if _end_delay < 0 and alive.size() <= last_standing:
		_end_delay = Rules.ROUND_END_DELAY_TICKS
	if _end_delay >= 0:
		_end_delay -= 1
		if _end_delay <= 0:
			var winner := alive[0] if alive.size() == 1 and participants.size() >= 2 else -1
			_finish_round(winner)
	elif has_time_limit() and time_left == 0:
		_finish_round(-1)


func _tick_sudden_death() -> void:
	for cell: Vector2i in _falling.keys():
		_falling[cell] -= 1
		if _falling[cell] <= 0:
			_falling.erase(cell)
			block_landed.emit(cell)
	_next_drop -= 1
	if _next_drop > 0:
		return
	_next_drop = Rules.DROP_INTERVAL_TICKS
	# Skip cells that are already solid (pillars, earlier blocks).
	while _spiral_index < _spiral.size():
		var cell := _spiral[_spiral_index]
		_spiral_index += 1
		if _grid.get_cell(cell) != Grid.Cell.HARD and not _falling.has(cell):
			_falling[cell] = Rules.FALL_TICKS
			block_falling.emit(cell)
			return


## Sudden death, for the AI: cells where a block is falling and the next `lookahead` cells of the
## spiral, each with the ticks until its block lands. Empty before sudden death.
func doomed_cells(lookahead := 6) -> Dictionary:
	var doomed := {}
	if not sudden_death or _grid == null:
		return doomed
	for cell: Vector2i in _falling:
		doomed[cell] = _falling[cell]
	var lands_in := maxi(_next_drop, 0) + Rules.FALL_TICKS
	var index := _spiral_index
	while index < _spiral.size() and lookahead > 0:
		var cell := _spiral[index]
		index += 1
		if _grid.get_cell(cell) != Grid.Cell.HARD and not doomed.has(cell):
			doomed[cell] = lands_in
			lands_in += Rules.DROP_INTERVAL_TICKS
			lookahead -= 1
	return doomed


func _finish_round(winner: int) -> void:
	round_winner = winner
	if winner != -1:
		wins[winner] += 1
		if wins[winner] >= wins_to_win:
			match_winner = winner
	_enter(State.ROUND_OVER)
	round_ended.emit(winner)


func _enter(new_state: State) -> void:
	state = new_state
	_state_ticks = 0


## Interior cells (inside the outer wall) in a clockwise spiral from the top-left corner inward.
static func spiral_cells(width: int, height: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var left := 1
	var top := 1
	var right := width - 2
	var bottom := height - 2
	while left <= right and top <= bottom:
		for x in range(left, right + 1):
			cells.append(Vector2i(x, top))
		for y in range(top + 1, bottom + 1):
			cells.append(Vector2i(right, y))
		if top < bottom:
			for x in range(right - 1, left - 1, -1):
				cells.append(Vector2i(x, bottom))
		if left < right:
			for y in range(bottom - 1, top, -1):
				cells.append(Vector2i(left, y))
		left += 1
		top += 1
		right -= 1
		bottom -= 1
	return cells
