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
## Bombs, fire, speed and collected items for this round.
var stats := PlayerStats.new()
var alive := true
var input_enabled := true
## Id of the bomb held overhead with a Power Glove, or -1; and for how many ticks.
var carried_bomb := -1
var carry_ticks := 0

## Must provide is_blocked_for(player, cell), try_place_bomb(player), release_bomb(player),
## try_kick(player, dir) and try_special(player).
var _world: Node
var _previous_pos := Vector2.ZERO  # grid_pos at the previous tick, for interpolation
var _held_dirs: Array[Vector2i] = []  # most recently pressed first
var _model: Node3D
var _moving := false
var _walk_time := 0.0
var _death_tween: Tween
var _heart_marker: Node3D        # shown while carrying a Heart
var _curse_label: Label3D        # curse name above the head while cursed
var _vest_bubble: MeshInstance3D  # shown while the Safety Vest lasts


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
	_build_protection_visuals()
	_sync_transform(1.0)
	InputRouter.action_pressed.connect(_on_action_pressed)
	InputRouter.action_released.connect(_on_action_released)


func get_cell() -> Vector2i:
	return GridMovement.nearest_cell(grid_pos)


func die() -> void:
	if not alive:
		return
	alive = false
	_heart_marker.visible = false
	_curse_label.visible = false
	_vest_bubble.visible = false
	_model.visible = true
	_moving = false
	_previous_pos = grid_pos
	died.emit(self)
	# Spin and squash flat, then disappear.
	_death_tween = create_tween().set_parallel(true)
	_death_tween.tween_property(_model, "rotation:y", _model.rotation.y + TAU * 2.0, DEATH_TIME)
	var squash := _death_tween.tween_property(_model, "scale", Vector3(1.4, 0.05, 1.4), DEATH_TIME)
	squash.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	_death_tween.chain().tween_callback(hide)


## Starting stats for a round (items picked up last round are gone).
func reset_stats(settings: MatchSettings) -> void:
	stats.reset(settings)


## Back to life at `cell`, e.g. at the start of every round.
func respawn(cell: Vector2i) -> void:
	if _death_tween:
		_death_tween.kill()
	alive = true
	grid_pos = Vector2(cell)
	_previous_pos = grid_pos
	facing = Vector2i.DOWN
	_model.scale = Vector3.ONE
	_model.rotation = Vector3.ZERO
	_model.visible = true
	carried_bomb = -1
	carry_ticks = 0
	show()


## Held directions after curses: Dizzy reverses them, Can't Stop keeps walking with none held.
func movement_dirs(held: Array[Vector2i]) -> Array[Vector2i]:
	var dirs: Array[Vector2i] = held.duplicate()
	if stats.has_curse(Curses.Type.DIZZY):
		for i in dirs.size():
			dirs[i] = -dirs[i]
	if stats.has_curse(Curses.Type.CANT_STOP) and dirs.is_empty() and input_enabled:
		dirs.append(facing)
	return dirs


## Jump to a position (Swap curse) without sliding there.
func teleport(pos: Vector2) -> void:
	grid_pos = pos
	_previous_pos = pos


func is_carrying() -> bool:
	return carried_bomb != -1


func _on_action_released(device_id: String, action: StringName) -> void:
	if device_id == device and action == &"bomb" and alive:
		_world.release_bomb(self)


func _on_action_pressed(device_id: String, action: StringName) -> void:
	if device_id != device:
		return
	if action == &"bomb":
		if alive and input_enabled:
			_world.try_place_bomb(self)
		return
	if action == &"special":
		if alive and input_enabled and _world.try_special(self):
			_play_action_pop()
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
	var dirs := movement_dirs(_held_dirs if input_enabled else ([] as Array[Vector2i]))
	var result := GridMovement.step(grid_pos, dirs, stats.speed() * delta, _is_blocked)
	_moving = result.dir != Vector2i.ZERO
	if _moving:
		facing = result.dir
	elif not dirs.is_empty():
		facing = dirs[0]  # turn to face a direction even when blocked (aiming a punch)
	_previous_pos = grid_pos
	grid_pos = result.pos
	# Kick: pressing into a bomb that blocks the way.
	if stats.has_kick and not dirs.is_empty() and result.dir != dirs[0]:
		if _world.try_kick(self, dirs[0]):
			_play_action_pop()


func _process(delta: float) -> void:
	_sync_transform(Engine.get_physics_interpolation_fraction())
	if not alive:
		return
	_update_protection_visuals(delta)
	var target_angle := atan2(float(facing.x), float(facing.y))
	_model.rotation.y = rotate_toward(_model.rotation.y, target_angle, TURN_SPEED * delta)
	if _moving:
		_walk_time += delta
		_model.position.y = absf(sin(_walk_time * stats.speed() * PI)) * BOB_HEIGHT
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


## Small squash-and-stretch for a kick or punch.
func _play_action_pop() -> void:
	var tween := create_tween()
	tween.tween_property(_model, "scale", Vector3(1.25, 0.8, 1.25), 0.06)
	tween.tween_property(_model, "scale", Vector3.ONE, 0.12)


# --- Protection visuals --------------------------------------------------------------

func _build_protection_visuals() -> void:
	_heart_marker = Node3D.new()
	_heart_marker.position.y = 1.32
	var diamond := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3.ONE * 0.16
	diamond.mesh = box
	diamond.rotation_degrees = Vector3(45, 0, 45)
	var heart_mat := StandardMaterial3D.new()
	heart_mat.albedo_color = Items.color(Items.Type.HEART)
	heart_mat.emission_enabled = true
	heart_mat.emission = Items.color(Items.Type.HEART) * 0.6
	diamond.material_override = heart_mat
	_heart_marker.add_child(diamond)
	_heart_marker.visible = false
	add_child(_heart_marker)

	_vest_bubble = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.56
	sphere.height = 1.12
	_vest_bubble.mesh = sphere
	var vest_mat := StandardMaterial3D.new()
	vest_mat.albedo_color = Color(Items.color(Items.Type.VEST), 0.28)
	vest_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	vest_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	vest_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_vest_bubble.material_override = vest_mat
	_vest_bubble.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_vest_bubble.position.y = 0.5
	_vest_bubble.visible = false
	add_child(_vest_bubble)

	_curse_label = Label3D.new()
	_curse_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_curse_label.no_depth_test = true
	_curse_label.font_size = 40
	_curse_label.pixel_size = 0.009
	_curse_label.outline_size = 12
	_curse_label.modulate = Items.color(Items.Type.SKULL).lightened(0.55)
	_curse_label.position.y = 1.6
	_curse_label.visible = false
	add_child(_curse_label)


func _update_protection_visuals(delta: float) -> void:
	var now := Time.get_ticks_msec()
	_heart_marker.visible = stats.has_heart
	_curse_label.visible = stats.is_cursed()
	if stats.is_cursed():
		_curse_label.text = Curses.display_name(stats.curse)
		_curse_label.position.y = 1.6 + sin(now / 200.0) * 0.05
	_heart_marker.rotation.y += delta * 3.0
	var vest_on := stats.vest_ticks > 0
	var vest_ending := stats.vest_ticks < Rules.VEST_WARNING_TICKS
	_vest_bubble.visible = vest_on and (not vest_ending or (now / 120) % 2 == 0)
	_vest_bubble.scale = Vector3.ONE * (1.0 + 0.04 * sin(now / 150.0))
	# Blink while a lost Heart's grace period protects us.
	_model.visible = stats.grace_ticks <= 0 or (now / 90) % 2 == 0


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
