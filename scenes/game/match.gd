extends Node3D
## Versus match root. Owns the arena, players, bombs and the round flow (MatchRules), and turns
## rule signals into scene changes: fresh arena per round, input locks, falling blocks, HUD.
##
## Per physics tick: InputRouter (autoload) -> Match (rules, bombs, deaths) -> Players (movement).

const PLAYER_SCENE := preload("res://scenes/game/player.tscn")
const BombView := preload("res://scenes/game/bomb_view.gd")
const ExplosionView := preload("res://scenes/game/explosion_view.gd")

@export var level: LevelData = preload("res://levels/classic.tres")
## Fixed seed for '?' cells; 0 picks a new random layout every round.
@export var rng_seed := 0
## Until the lobby exists (M6) the match opens in a join phase: devices join with bomb and
## start begins the match; afterwards it returns there. Off = start at once with joined slots.
@export var allow_drop_in := true

var grid: Grid
var bombs: BombField
var rules := MatchRules.new()
var players: Array = []  # Player node or null, indexed by slot

var _rng := RandomNumberGenerator.new()
var _bomb_views := {}  # Vector2i -> BombView
var _ticks := 0

@onready var arena: Node3D = $Arena
@onready var camera: Camera3D = $Camera
@onready var players_root: Node3D = $Players
@onready var effects: Node3D = $Effects
@onready var hud: CanvasLayer = $Hud
@onready var hint: Label = $Hud/Hint
@onready var debug_label: Label = $Hud/Debug


func _ready() -> void:
	if rng_seed != 0:
		_rng.seed = rng_seed
	else:
		_rng.randomize()
	_build_arena()
	camera.frame(arena.get_bounds())
	_warm_up_effects()
	_connect_rules()

	players.resize(InputRouter.MAX_SLOTS)
	for slot in InputRouter.MAX_SLOTS:
		var device := InputRouter.device_in_slot(slot)
		if device != "":
			_spawn_player(slot, device)
	InputRouter.action_pressed.connect(_on_action_pressed)
	debug_label.visible = allow_drop_in
	_enter_join_phase()


func _physics_process(_delta: float) -> void:
	_ticks += 1
	rules.tick()
	if rules.is_playing():
		bombs.tick()
		_check_deaths()


func _process(_delta: float) -> void:
	hud.set_time(rules.time_left, rules.sudden_death)
	if debug_label.visible:
		var lines: Array[String] = ["FPS %d   physics ticks %d   state %s   (F3 hides)" % [
			Engine.get_frames_per_second(), _ticks, MatchRules.State.keys()[rules.state]]]
		for player in players:
			if player:
				lines.append("P%d %-4s  (%.2f, %.2f)%s" % [player.slot + 1, player.device,
					player.grid_pos.x, player.grid_pos.y, "" if player.alive else "  dead"])
		debug_label.text = "\n".join(lines)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.physical_keycode == KEY_F3:
		debug_label.visible = not debug_label.visible
	elif event.physical_keycode == KEY_F4 and allow_drop_in and rules.is_playing():
		# Dev: skip the clock to 2 s before sudden death.
		rules.time_left = mini(rules.time_left, rules.sudden_death_at + 2 * Rules.TICKS_PER_SECOND)


## Movement collision: can `player` enter `cell`? A player standing on a bomb can still walk off
## it, because movement only ever checks the cell ahead.
func is_blocked_for(_player: Node, cell: Vector2i) -> bool:
	return grid.is_blocking(cell) or bombs.has_bomb(cell)


func try_place_bomb(player: Node) -> void:
	if not rules.is_playing() or bombs.bomb_count(player.slot) >= player.max_bombs:
		return
	bombs.place_bomb(player.get_cell(), player.slot, player.fire_range)


# --- Match flow --------------------------------------------------------------

func _connect_rules() -> void:
	rules.round_started.connect(func(n): hud.announce("ROUND %d" % n))
	rules.ready_shown.connect(func(): hud.announce("READY?"))
	rules.play_started.connect(_on_play_started)
	rules.hurry_up.connect(func(): hud.announce("HURRY UP!", 1.5, Color(1.0, 0.35, 0.25)))
	rules.block_falling.connect(func(cell): arena.drop_block(cell, Rules.ticks_to_seconds(Rules.FALL_TICKS)))
	rules.block_landed.connect(_on_block_landed)
	rules.round_ended.connect(_on_round_ended)
	rules.next_round.connect(_start_round)
	rules.match_ended.connect(_on_match_ended)
	rules.match_finished.connect(_enter_join_phase)


func _enter_join_phase() -> void:
	_set_input(false)
	_build_arena()
	for player in players:
		if player:
			player.respawn(grid.spawns[player.slot])
	hud.show_clock(false)
	hud.setup_players(_joined_slots())
	hud.set_wins({})
	if allow_drop_in:
		hud.announce("PRESS START" if InputRouter.joined_count() > 0 else "JOIN IN!")
		_update_hint()
	else:
		_begin_match()


func _begin_match() -> void:
	var slots := _joined_slots()
	if slots.is_empty():
		return
	rules.begin_match(slots)
	hud.setup_players(slots)
	hud.show_clock(true)
	hint.visible = false
	_start_round()


func _start_round() -> void:
	_build_arena()
	for slot in rules.participants:
		players[slot].respawn(grid.spawns[slot])
		hud.set_alive(slot, true)
	_set_input(false)
	hud.set_wins(rules.wins)
	rules.start_round(grid)


func _on_play_started() -> void:
	_set_input(true)
	hud.announce("GO!", 0.5)


func _on_round_ended(winner: int) -> void:
	_set_input(false)
	hud.set_wins(rules.wins)
	if winner == -1:
		hud.announce("DRAW")
	else:
		hud.announce("%s WINS!" % _player_name(winner), 0.0, Palette.PLAYER_COLORS[winner])


func _on_match_ended(winner: int) -> void:
	hud.announce("%s WINS THE MATCH!" % _player_name(winner), 0.0, Palette.PLAYER_COLORS[winner])


## Sudden death: the block lands, crushing whatever is in the cell.
func _on_block_landed(cell: Vector2i) -> void:
	bombs.crush(cell)
	grid.set_cell(cell, Grid.Cell.HARD)
	for player in players:
		if player and player.alive and player.get_cell() == cell:
			player.die()


func _check_deaths() -> void:
	for player in players:
		if player and player.alive and bombs.has_flame(player.get_cell()):
			player.die()


func _on_player_died(player: Node) -> void:
	rules.player_died(player.slot)
	hud.set_alive(player.slot, false)


# --- Arena, players, effects -------------------------------------------------

## Fresh grid, arena and bombs (each round, and for the join phase).
func _build_arena() -> void:
	grid = level.build_grid(_rng)
	arena.build(grid)
	for child in effects.get_children():
		child.queue_free()
	_bomb_views.clear()
	bombs = BombField.new(grid)
	bombs.bomb_placed.connect(_on_bomb_placed)
	bombs.bomb_exploded.connect(_on_bomb_exploded)
	bombs.bomb_removed.connect(_remove_bomb_view)
	bombs.block_burning.connect(arena.burn_block)


func _set_input(enabled: bool) -> void:
	for player in players:
		if player:
			player.input_enabled = enabled


func _joined_slots() -> Array[int]:
	var slots: Array[int] = []
	for slot in players.size():
		if players[slot]:
			slots.append(slot)
	return slots


func _player_name(slot: int) -> String:
	return String(Palette.PLAYER_COLOR_NAMES[slot]).to_upper()


func _on_action_pressed(device: String, action: StringName) -> void:
	if not allow_drop_in or rules.state != MatchRules.State.WAITING:
		return
	var slot := InputRouter.slot_of(device)
	if action == &"bomb" and slot == -1:
		slot = InputRouter.assign_slot(device)
		if slot != -1:
			_spawn_player(slot, device)
			hud.setup_players(_joined_slots())
			hud.announce("PRESS START")
			_update_hint()
	elif action == &"start" and slot != -1:
		_begin_match()


func _spawn_player(slot: int, device: String) -> void:
	var spawn := grid.spawns[slot]
	if spawn == Grid.NO_SPAWN:
		push_error("Level has no spawn for slot %d" % slot)
		return
	var player := PLAYER_SCENE.instantiate()
	player.setup(self, slot, device, Palette.PLAYER_COLORS[slot], spawn)
	player.input_enabled = false
	player.died.connect(_on_player_died)
	players_root.add_child(player)
	players[slot] = player


func _on_bomb_placed(cell: Vector2i, _owner: int) -> void:
	var view := BombView.new()
	view.position = Grid.cell_to_world(cell)
	effects.add_child(view)
	_bomb_views[cell] = view


func _on_bomb_exploded(cell: Vector2i, _owner: int, flames: Array) -> void:
	_remove_bomb_view(cell)
	var view := ExplosionView.new()
	view.setup(flames, Rules.ticks_to_seconds(Rules.FLAME_TICKS))
	effects.add_child(view)


func _remove_bomb_view(cell: Vector2i) -> void:
	if _bomb_views.has(cell):
		_bomb_views[cell].queue_free()
		_bomb_views.erase(cell)


## WebGL compiles a shader the first time it is drawn, which stalls that frame. Draw one bomb and
## one fireball out of sight (under the floor) at load, so the first real explosion is smooth.
func _warm_up_effects() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var centre: Vector3 = arena.get_bounds().get_center()
	var hidden_spot := Vector3(centre.x, -3.0, centre.z)
	var bomb := BombView.new()
	var boom := ExplosionView.new()
	boom.setup([{"cell": Vector2i.ZERO, "kind": BombField.Flame.CENTER, "axis": Vector2i.ZERO}], 60.0)
	for node: Node3D in [bomb, boom]:
		node.position = hidden_spot
		add_child(node)  # not under Effects, which is cleared when arenas rebuild
	for i in 3:
		await get_tree().process_frame
	bomb.queue_free()
	boom.queue_free()


func _update_hint() -> void:
	var joined := InputRouter.joined_count()
	hint.visible = allow_drop_in
	var lines: Array[String] = []
	if joined < InputRouter.MAX_SLOTS:
		lines.append("Join: Cross / Space / Enter")
	if joined > 0:
		lines.append("Start: Options / Tab / P" + ("  (1 player = practice)" if joined == 1 else ""))
	hint.text = "\n".join(lines)
