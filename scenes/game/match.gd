extends Node3D
## Versus match root: builds the arena, spawns a player per joined slot and answers collision
## questions. Bombs (M4) and round flow (M5) are added here.

const PLAYER_SCENE := preload("res://scenes/game/player.tscn")

@export var level: LevelData = preload("res://levels/classic.tres")
## Fixed seed for '?' cells; 0 picks a new random layout every time.
@export var rng_seed := 0
## Dev convenience until the lobby exists (M6): any device pressing bomb joins mid-match.
@export var allow_drop_in := true

var grid: Grid
var players: Array = []  # Player node or null, indexed by slot

var _ticks := 0

@onready var arena: Node3D = $Arena
@onready var camera: Camera3D = $Camera
@onready var players_root: Node3D = $Players
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


func _process(_delta: float) -> void:
	if debug_label.visible:
		var lines: Array[String] = ["FPS %d   physics ticks %d   (F3 hides)" % [Engine.get_frames_per_second(), _ticks]]
		for player in players:
			if player:
				lines.append("P%d %-4s  (%.2f, %.2f)" % [player.slot + 1, player.device, player.grid_pos.x, player.grid_pos.y])
		debug_label.text = "\n".join(lines)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F3:
		debug_label.visible = not debug_label.visible


## Movement collision: can `player` enter `cell`? M4 adds bombs here.
func is_blocked_for(_player: Node, cell: Vector2i) -> bool:
	return grid.is_blocking(cell)


func _on_action_pressed(device: String, action: StringName) -> void:
	if not allow_drop_in or action != &"bomb" or InputRouter.slot_of(device) != -1:
		return
	var slot := InputRouter.assign_slot(device)
	if slot != -1:
		_spawn_player(slot, device)
		_update_hint()


func _spawn_player(slot: int, device: String) -> void:
	var spawn := grid.spawns[slot]
	if spawn == Grid.NO_SPAWN:
		push_error("Level has no spawn for slot %d" % slot)
		return
	var player := PLAYER_SCENE.instantiate()
	player.setup(self, slot, device, Palette.PLAYER_COLORS[slot], spawn)
	players_root.add_child(player)
	players[slot] = player


func _update_hint() -> void:
	var joined := InputRouter.joined_count()
	hint.visible = allow_drop_in
	if joined < InputRouter.MAX_SLOTS:
		hint.text = "%d / %d players  -  press Cross / Space / Enter to join" % [joined, InputRouter.MAX_SLOTS]
	else:
		hint.text = "%d / %d players" % [joined, InputRouter.MAX_SLOTS]
