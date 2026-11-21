extends Node3D
## Fire for one explosion: a round fireball per cell (orange shell, yellow-white core), like the
## puffs in the original. Bursts in, wobbles, shrinks away, then frees itself.
## Pure presentation; BombField decides which cells burn and for how long.

const BURST_TIME := 0.08   # seconds to reach full size
const FADE_TIME := 0.15    # seconds of shrinking at the end
const SHELL_RADIUS := 0.44
const CORE_RADIUS := 0.27

static var _shell_material: StandardMaterial3D
static var _core_material: StandardMaterial3D
static var _shell_mesh: SphereMesh
static var _core_mesh: SphereMesh

var _flames: Array = []
var _duration := 0.5
var _age := 0.0
var _puffs: Array[Node3D] = []


## `flames` as emitted by BombField.bomb_exploded.
func setup(flames: Array, duration: float) -> void:
	_flames = flames
	_duration = duration


func _ready() -> void:
	_ensure_resources()
	for flame in _flames:
		var puff := Node3D.new()
		puff.position = Grid.cell_to_world(flame.cell) + Vector3(0.0, SHELL_RADIUS, 0.0)
		var size := 0.8 if flame.kind == BombField.Flame.BLOCK else 1.0
		puff.set_meta("size", size)
		puff.add_child(_mesh(_shell_mesh, _shell_material, Vector3.ZERO))
		# Core pokes out of the shell's top so the overhead camera sees a bright centre.
		puff.add_child(_mesh(_core_mesh, _core_material, Vector3(0.0, SHELL_RADIUS - CORE_RADIUS + 0.06, 0.0)))
		puff.scale = Vector3.ZERO
		add_child(puff)
		_puffs.append(puff)


func _process(delta: float) -> void:
	_age += delta
	if _age >= _duration:
		queue_free()
		return
	var burst := ease(clampf(_age / BURST_TIME, 0.0, 1.0), 0.4)
	var fade := clampf((_duration - _age) / FADE_TIME, 0.0, 1.0)
	for i in _puffs.size():
		var wobble := 1.0 + 0.07 * sin(_age * 45.0 + i * 1.7)
		_puffs[i].scale = Vector3.ONE * burst * fade * wobble * float(_puffs[i].get_meta("size"))


static func _ensure_resources() -> void:
	if _shell_material:
		return
	_shell_material = StandardMaterial3D.new()
	_shell_material.albedo_color = Color(1.0, 0.55, 0.12)
	_shell_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_core_material = StandardMaterial3D.new()
	_core_material.albedo_color = Color(1.0, 0.96, 0.6)
	_core_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_shell_mesh = SphereMesh.new()
	_shell_mesh.radius = SHELL_RADIUS
	_shell_mesh.height = SHELL_RADIUS * 2.0
	_core_mesh = SphereMesh.new()
	_core_mesh.radius = CORE_RADIUS
	_core_mesh.height = CORE_RADIUS * 2.0


static func _mesh(mesh: Mesh, material: Material, offset: Vector3) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = offset
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return instance
