extends Node3D
## A ticking bomb: glossy dark sphere with a fuse spark, pulsing faster as the fuse burns down.
## A Dangerous Bomb (two kicked bombs merged) is bigger, glowing red and pulses fast.
## Pure presentation; BombField owns the timer and position (Match moves this node).

const RADIUS := 0.34
const SLOW_PULSE := 2.5   # pulses per second when just placed
const FAST_PULSE := 9.0   # pulses per second just before exploding

static var _body_material: StandardMaterial3D
static var _fuse_material: StandardMaterial3D
static var _spark_material: StandardMaterial3D
static var _danger_material: StandardMaterial3D

var _age := 0.0
var _phase := 0.0
var _body: Node3D
var _spark: Node3D
var _sphere: MeshInstance3D
var _dangerous := false


func _ready() -> void:
	var scene := AssetLibrary.model("bomb")
	_body = scene.instantiate() if scene else _build_placeholder()
	add_child(_body)


func set_dangerous() -> void:
	_dangerous = true
	if _sphere:
		if _danger_material == null:
			_danger_material = StandardMaterial3D.new()
			_danger_material.albedo_color = Color(0.75, 0.05, 0.05)
			_danger_material.roughness = 0.2
			_danger_material.emission_enabled = true
			_danger_material.emission = Color(1.0, 0.15, 0.05) * 0.8
		_sphere.material_override = _danger_material


func _process(delta: float) -> void:
	_age += delta
	var progress := clampf(_age / Rules.ticks_to_seconds(Rules.BOMB_FUSE_TICKS), 0.0, 1.0)
	var rate := FAST_PULSE * 1.5 if _dangerous else lerpf(SLOW_PULSE, FAST_PULSE, progress * progress)
	_phase += delta * TAU * rate
	var pulse := 1.0 + 0.09 * sin(_phase)
	var size := 1.3 if _dangerous else 1.0
	_body.scale = Vector3(pulse, 2.0 - pulse, pulse) * size
	if _spark:
		_spark.scale = Vector3.ONE * randf_range(0.6, 1.4)


func _build_placeholder() -> Node3D:
	if _body_material == null:
		_body_material = StandardMaterial3D.new()
		_body_material.albedo_color = Color(0.07, 0.08, 0.16)
		_body_material.roughness = 0.2
		_body_material.metallic_specular = 0.8
		_fuse_material = StandardMaterial3D.new()
		_fuse_material.albedo_color = Color(0.85, 0.78, 0.6)
		_spark_material = StandardMaterial3D.new()
		_spark_material.albedo_color = Color(1.0, 0.75, 0.2)
		_spark_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	var root := Node3D.new()
	root.name = "Bomb"
	var body := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = RADIUS
	sphere.height = RADIUS * 2.0
	body.mesh = sphere
	body.material_override = _body_material
	body.position.y = RADIUS
	root.add_child(body)
	_sphere = body

	var fuse := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.03
	cylinder.bottom_radius = 0.04
	cylinder.height = 0.14
	fuse.mesh = cylinder
	fuse.material_override = _fuse_material
	fuse.position.y = RADIUS * 2.0 + 0.04
	root.add_child(fuse)

	var spark := MeshInstance3D.new()
	var spark_mesh := SphereMesh.new()
	spark_mesh.radius = 0.06
	spark_mesh.height = 0.12
	spark.mesh = spark_mesh
	spark.material_override = _spark_material
	spark.position.y = RADIUS * 2.0 + 0.13
	root.add_child(spark)
	_spark = spark
	return root
