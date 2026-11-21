extends Node3D
## Versus match root: builds the arena, spawns a player per joined slot, runs bombs each tick and
## answers collision questions. Round flow (win/draw, timer, sudden death) comes in M5.
##
## Per physics tick: InputRouter (autoload) -> Match (bombs, deaths) -> Players (movement).

const PLAYER_SCENE := preload("res://scenes/game/player.tscn")
const BombView := preload("res://scenes/game/bomb_view.gd")
const ExplosionView := preload("res://scenes/game/explosion_view.gd")

@export var level: LevelData = preload("res://levels/classic.tres")
## Fixed seed for '?' cells; 0 picks a new random layout every time.
@export var rng_seed := 0
## Dev convenience until the lobby and rounds exist (M5/M6): any device pressing bomb joins
## mid-match, and a dead player respawns with start (Options / Tab / P).
@export var allow_drop_in := true

var grid: Grid
var bombs: BombField
var players: Array = []  # Player node or null, indexed by slot

var _bomb_views := {}  # Vector2i -> BombView
var _ticks := 0

@onready var arena: Node3D = $Arena
@onready var camera: Camera3D = $Camera
@onready var players_root: Node3D = $Players
@onready var effects: Node3D = $Effects
@onready var hint: Label = $Hud/Hint
@onready var debug_label: Label = $Hud/Debug


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	if rng_seed != 0:
		rng.seed = rng_seed
	else:
		rng.randomize()
	grid = level.build_grid(rng)
	arena.build(grid)
	camera.frame(arena.get_bounds())

	bombs = BombField.new(grid)
	bombs.bomb_placed.connect(_on_bomb_placed)
	bombs.bomb_exploded.connect(_on_bomb_exploded)
	bombs.block_burning.connect(arena.burn_block)
	_warm_up_effects()

	players.resize(InputRouter.MAX_SLOTS)
	for slot in InputRouter.MAX_SLOTS:
		var device := InputRouter.device_in_slot(slot)
		if device != "":
			_spawn_player(slot, device)
	InputRouter.action_pressed.connect(_on_action_pressed)
	_update_hint()
	debug_label.visible = allow_drop_in


func _physics_process(_delta: float) -> void:
	_ticks += 1
	bombs.tick()
	_check_deaths()


func _process(_delta: float) -> void:
	if debug_label.visible:
		var lines: Array[String] = ["FPS %d   physics ticks %d   (F3 hides)" % [Engine.get_frames_per_second(), _ticks]]
		for player in players:
			if player:
				lines.append("P%d %-4s  (%.2f, %.2f)%s" % [player.slot + 1, player.device,
					player.grid_pos.x, player.grid_pos.y, "" if player.alive else "  dead"])
		debug_label.text = "\n".join(lines)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F3:
		debug_label.visible = not debug_label.visible


## Movement collision: can `player` enter `cell`? A player standing on a bomb can still walk off
## it, because movement only ever checks the cell ahead.
func is_blocked_for(_player: Node, cell: Vector2i) -> bool:
	return grid.is_blocking(cell) or bombs.has_bomb(cell)


func try_place_bomb(player: Node) -> void:
	if bombs.bomb_count(player.slot) >= player.max_bombs:
		return
	bombs.place_bomb(player.get_cell(), player.slot, player.fire_range)


func _check_deaths() -> void:
	for player in players:
		if player and player.alive and bombs.has_flame(player.get_cell()):
			player.die()


func _on_bomb_placed(cell: Vector2i, _owner: int) -> void:
	var view := BombView.new()
	view.position = Grid.cell_to_world(cell)
	effects.add_child(view)
	_bomb_views[cell] = view


func _on_bomb_exploded(cell: Vector2i, _owner: int, flames: Array) -> void:
	if _bomb_views.has(cell):
		_bomb_views[cell].queue_free()
		_bomb_views.erase(cell)
	var view := ExplosionView.new()
	view.setup(flames, Rules.ticks_to_seconds(Rules.FLAME_TICKS))
	effects.add_child(view)


func _on_action_pressed(device: String, action: StringName) -> void:
	if not allow_drop_in:
		return
	var slot := InputRouter.slot_of(device)
	if action == &"bomb" and slot == -1:
		slot = InputRouter.assign_slot(device)
		if slot != -1:
			_spawn_player(slot, device)
			_update_hint()
	elif action == &"start" and slot != -1 and players[slot] and not players[slot].alive:
		players[slot].respawn(grid.spawns[slot])


func _spawn_player(slot: int, device: String) -> void:
	var spawn := grid.spawns[slot]
	if spawn == Grid.NO_SPAWN:
		push_error("Level has no spawn for slot %d" % slot)
		return
	var player := PLAYER_SCENE.instantiate()
	player.setup(self, slot, device, Palette.PLAYER_COLORS[slot], spawn)
	players_root.add_child(player)
	players[slot] = player


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
		effects.add_child(node)
	for i in 3:
		await get_tree().process_frame
	bomb.queue_free()
	boom.queue_free()


func _update_hint() -> void:
	var joined := InputRouter.joined_count()
	hint.visible = allow_drop_in
	var text := "%d / %d players" % [joined, InputRouter.MAX_SLOTS]
	if joined < InputRouter.MAX_SLOTS:
		text += "  -  Cross / Space / Enter to join"
	if joined > 0:
		text += "  -  Options / Tab / P to respawn"
	hint.text = text
