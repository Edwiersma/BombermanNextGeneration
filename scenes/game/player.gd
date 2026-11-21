extends Node3D
## A bomber. Reads its device through InputRouter and moves on the grid every physics tick.
## Position lives in `grid_pos` (cells); the node's transform only mirrors it, interpolated
## between ticks so motion is smooth on displays faster than 60 Hz.

signal died(player: Node3D)

const DIRECTION_ACTIONS := {
	&"up": Vector2i.UP,
	&"down": Vector2i.DOWN,
	&"left": Vector2i.LEFT,
	&"right": Vector2i.RIGHT,
}
const TURN_SPEED := 18.0  # radians per second for the visual turn
const BOB_HEIGHT := 0.05
const DEATH_TIME := 0.9

var slot := -1
var device := ""
var color := Color.WHITE
var grid_pos := Vector2.ZERO
var facing := Vector2i.DOWN
var speed := Rules.PLAYER_SPEED
var max_bombs := Rules.START_BOMBS
var fire_range := Rules.START_FIRE
var alive := true
var input_enabled := true

## Must provide is_blocked_for(player, cell: Vector2i) -> bool and try_place_bomb(player).
var _world: Node
var _previous_pos := Vector2.ZERO  # grid_pos at the previous tick, for interpolation
var _held_dirs: Array[Vector2i] = []  # most recently pressed first
var _model: Node3D
var _moving := false
var _walk_time := 0.0
var _death_tween: Tween


func setup(world: Node, player_slot: int, player_device: String, player_color: Color, spawn: Vector2i) -> void:
	_world = world
	slot = player_slot
	device = player_device
	color = player_color
	grid_pos = Vector2(spawn)
	_previous_pos = grid_pos
	name = "Player%d" % (slot + 1)


func _ready() -> void:
	_model = _build_model()
	add_child(_model)
	_sync_transform(1.0)
	InputRouter.action_pressed.connect(_on_action_pressed)


func get_cell() -> Vector2i:
	return GridMovement.nearest_cell(grid_pos)


func die() -> void:
	if not alive:
		return
	alive = false
	_moving = false
	_previous_pos = grid_pos
	died.emit(self)
	# Spin and squash flat, then disappear.
	_death_tween = create_tween().set_parallel(true)
	_death_tween.tween_property(_model, "rotation:y", _model.rotation.y + TAU * 2.0, DEATH_TIME)
	var squash := _death_tween.tween_property(_model, "scale", Vector3(1.4, 0.05, 1.4), DEATH_TIME)
	squash.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	_death_tween.chain().tween_callback(hide)


## Dev only until rounds exist (M5): bring a dead player back at a cell.
func respawn(cell: Vector2i) -> void:
	if _death_tween:
		_death_tween.kill()
	alive = true
	grid_pos = Vector2(cell)
	_previous_pos = grid_pos
	facing = Vector2i.DOWN
	_model.scale = Vector3.ONE
	_model.rotation = Vector3.ZERO
	show()


func _on_action_pressed(device_id: String, action: StringName) -> void:
	if device_id != device:
		return
	if action == &"bomb":
		if alive and input_enabled:
			_world.try_place_bomb(self)
		return
	if not DIRECTION_ACTIONS.has(action):
		return
	var dir: Vector2i = DIRECTION_ACTIONS[action]
	_held_dirs.erase(dir)
	_held_dirs.push_front(dir)


func _physics_process(delta: float) -> void:
	_update_held_dirs()
	if not alive:
		return
	var dirs: Array[Vector2i] = _held_dirs if input_enabled else ([] as Array[Vector2i])
	var result := GridMovement.step(grid_pos, dirs, speed * delta, _is_blocked)
	_moving = result.dir != Vector2i.ZERO
	if _moving:
		facing = result.dir
	_previous_pos = grid_pos
	grid_pos = result.pos


func _process(delta: float) -> void:
	_sync_transform(Engine.get_physics_interpolation_fraction())
	if not alive:
		return
	var target_angle := atan2(float(facing.x), float(facing.y))
	_model.rotation.y = rotate_toward(_model.rotation.y, target_angle, TURN_SPEED * delta)
	if _moving:
		_walk_time += delta
		_model.position.y = absf(sin(_walk_time * speed * PI)) * BOB_HEIGHT
	else:
		_walk_time = 0.0
		_model.position.y = move_toward(_model.position.y, 0.0, delta)


## Keeps press order for directions still held, and picks up ones held before this player existed.
func _update_held_dirs() -> void:
	var still_held: Array[Vector2i] = []
	for dir in _held_dirs:
		if InputRouter.is_held(device, _action_for(dir)):
			still_held.append(dir)
	for action in DIRECTION_ACTIONS:
		var dir: Vector2i = DIRECTION_ACTIONS[action]
		if dir not in still_held and InputRouter.is_held(device, action):
			still_held.append(dir)
	_held_dirs = still_held


func _action_for(dir: Vector2i) -> StringName:
	return DIRECTION_ACTIONS.find_key(dir)


func _is_blocked(cell: Vector2i) -> bool:
	return _world.is_blocked_for(self, cell)


func _sync_transform(fraction: float) -> void:
	var shown := _previous_pos.lerp(grid_pos, fraction)
	position = Vector3(shown.x, 0.0, shown.y)


# --- Placeholder model ---------------------------------------------------------------
# Faces +Z (towards the camera, "down" on the grid). Replaced by assets_ext/models/bomber.glb.

func _build_model() -> Node3D:
	var scene := AssetLibrary.model("bomber")
	if scene:
		return scene.instantiate()

	var root := Node3D.new()
	root.name = "Model"
	var suit := _material(color)
	var skin := _material(Color(1.0, 0.80, 0.68))
	var dark := _material(Color(0.08, 0.08, 0.10))
	var pink := _material(Color(1.0, 0.40, 0.70))
	var white := _material(Color(0.95, 0.95, 0.95))

	_add_part(root, _capsule(0.19, 0.46), suit, Vector3(0, 0.29, 0))                       # body
	_add_part(root, _sphere(0.25), suit, Vector3(0, 0.68, 0))                              # helmet
	_add_part(root, _sphere(0.18), skin, Vector3(0, 0.67, 0.11), Vector3(1.0, 0.85, 0.6))   # face
	_add_part(root, _sphere(0.035), dark, Vector3(-0.06, 0.69, 0.22), Vector3(0.7, 1.6, 0.5))  # eyes
	_add_part(root, _sphere(0.035), dark, Vector3(0.06, 0.69, 0.22), Vector3(0.7, 1.6, 0.5))
	_add_part(root, _cylinder(0.02, 0.14), white, Vector3(0, 0.97, 0))                      # antenna
	_add_part(root, _sphere(0.07), pink, Vector3(0, 1.06, 0))
	_add_part(root, _sphere(0.08), pink, Vector3(-0.22, 0.33, 0.02))                        # hands
	_add_part(root, _sphere(0.08), pink, Vector3(0.22, 0.33, 0.02))
	_add_part(root, _sphere(0.09), suit, Vector3(-0.09, 0.06, 0.04), Vector3(1, 0.7, 1.4))  # feet
	_add_part(root, _sphere(0.09), suit, Vector3(0.09, 0.06, 0.04), Vector3(1, 0.7, 1.4))
	return root


func _add_part(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, scale_by := Vector3.ONE) -> void:
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.material_override = mat
	part.position = pos
	part.scale = scale_by
	parent.add_child(part)


func _material(albedo: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = albedo
	mat.roughness = 0.6
	return mat


func _sphere(radius: float) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 24
	mesh.rings = 12
	return mesh


func _capsule(radius: float, height: float) -> CapsuleMesh:
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = height
	return mesh


func _cylinder(radius: float, height: float) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	return mesh
