extends SceneTree
## Dev tool: AI-only matches run headless as fast as possible, with stats on how rounds end and
## how players die (own bomb, someone else's, crushed by sudden death).
##   godot --headless --path . -s tools/ai_soak.gd -- [players=4] [level=1] [rounds=10] [seed=7] [verbose]
## verbose: print the AI's last plans whenever it dies to its own bomb.
## level: 0 Easy, 1 Normal, 2 Hard.

const MATCH_SCENE_PATH := "res://scenes/game/match.tscn"  # loaded at run time, once autoloads exist
const TICK := 1.0 / Rules.TICKS_PER_SECOND
const MAX_TICKS := 60 * 60 * 60  # an hour of game time at most

var _done := false


func _process(_delta: float) -> bool:
	if not _done:
		_done = true
		_run()
	return false


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var count := int(args[0]) if args.size() > 0 else 4
	var level := int(args[1]) if args.size() > 1 else 1
	var rounds_wanted := int(args[2]) if args.size() > 2 else 10
	var seed_value := int(args[3]) if args.size() > 3 else 7
	var verbose := "verbose" in args

	var game_state: Node = root.get_node("GameState")
	var router: Node = root.get_node("InputRouter")
	var settings := MatchSettings.new()
	settings.wins_to_win = MatchSettings.MAX_WINS
	game_state.settings = settings

	var m: Node3D = (load(MATCH_SCENE_PATH) as PackedScene).instantiate()
	m.allow_drop_in = false
	m.leave_on_finish = false
	m.rng_seed = seed_value
	root.add_child(m)
	for slot in count:
		m.add_ai_player(slot, level)
	m._begin_match()

	var deaths := {"own bomb": 0, "own bomb set off early": 0, "other's bomb": 0, "crushed": 0}
	var wins := 0
	var draws := 0
	var round_seconds: Array[float] = []
	var round_start := 0
	var rounds := 0
	var bricks_start := 0
	var bricks_broken := 0
	var flame_owner := {}
	var clock := {"tick": 0}  # shared with the signal lambdas (they copy plain locals)
	var placed := {}          # bomb id -> tick placed
	var placed_cell := {}     # bomb id -> cell placed
	var kicked_by := {}       # bomb id -> slot that kicked it
	var booms: Array = []     # this tick: [owner, cell, age in ticks]
	var watched_bombs: Object = null
	var alive_before := {}
	var state_before: int = m.rules.state
	var started := Time.get_ticks_msec()

	for tick in MAX_TICKS:
		if m.bombs != watched_bombs:
			watched_bombs = m.bombs
			flame_owner.clear()
			bricks_start = m.grid.cells_of(Grid.Cell.SOFT).size()
			m.bombs.bomb_exploded.connect(func(id, cell, owner, flames):
				booms.append([owner, cell, clock.tick - placed.get(id, clock.tick), placed_cell.get(id, cell), kicked_by.get(id, -1)])
				for flame in flames:
					flame_owner[flame.cell] = owner)
			m.bombs.bomb_placed.connect(func(id, cell, _owner): placed[id] = clock.tick; placed_cell[id] = cell)
			m.bombs.bomb_kicked.connect(func(id, cell, dir):
				for p in m.players:
					if p and p.alive and p.get_cell() == cell - dir:
						kicked_by[id] = p.slot)
		for slot in count:
			alive_before[slot] = m.players[slot].alive
		clock.tick = tick
		booms.clear()

		router._physics_process(TICK)
		m._physics_process(TICK)
		for player in m.players:
			if player:
				player._physics_process(TICK)

		for slot in count:
			var player: Node3D = m.players[slot]
			if alive_before[slot] and not player.alive:
				var cell: Vector2i = player.get_cell()
				if not m.bombs.has_flame(cell):
					deaths["crushed"] += 1
				elif flame_owner.get(cell, -1) == slot:
					# Set off early (chain or kick from someone else): mostly being trapped, not a blunder.
					var early := booms.any(func(b): return b[0] == slot and b[2] < Rules.BOMB_FUSE_TICKS - 10)
					deaths["own bomb set off early" if early else "own bomb"] += 1
					if verbose:
						var plans := "\n    ".join(m.ais[slot].notes)
						var went_off := booms.map(func(b): return "P%d bomb at %s (placed at %s%s), %d ticks old" % [b[0] + 1, b[1], b[3], ", kicked by P%d" % (b[4] + 1) if b[4] != -1 else "", b[2]])
						print("P%d killed by own bomb at %s (pos %s), tick %d. Plans:\n    %s\n  now: %s\n  went off: %s" % [
							slot + 1, cell, player.grid_pos, tick - round_start, plans, m.ais[slot].debug_state(), went_off])
				else:
					deaths["other's bomb"] += 1
		var state: int = m.rules.state
		if state == MatchRules.State.PLAYING and state_before != MatchRules.State.PLAYING:
			round_start = tick
		if state == MatchRules.State.ROUND_OVER and state_before == MatchRules.State.PLAYING:
			rounds += 1
			round_seconds.append((tick - round_start) / float(Rules.TICKS_PER_SECOND))
			bricks_broken += bricks_start - m.grid.cells_of(Grid.Cell.SOFT).size()
			if m.rules.round_winner == -1:
				draws += 1
			else:
				wins += 1
			if rounds >= rounds_wanted:
				break
		if state == MatchRules.State.WAITING and state_before != MatchRules.State.WAITING:
			m._begin_match()  # match over: start another
		state_before = state

	var total := 0.0
	for s in round_seconds:
		total += s
	print("AI soak: %d players, level %s, %d rounds (%.1f s real time)" % [
		count, BomberAI.LEVEL_NAMES[level], rounds, (Time.get_ticks_msec() - started) / 1000.0])
	print("  rounds won %d, draws %d, average round %.1f s (shortest %.1f, longest %.1f)" % [
		wins, draws, total / maxf(rounds, 1), round_seconds.min() if rounds else 0.0, round_seconds.max() if rounds else 0.0])
	print("  deaths: %s" % deaths)
	print("  bricks broken per round: %.1f" % (bricks_broken / maxf(rounds, 1)))
	m.free()
	quit()
