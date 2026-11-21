extends Node3D
## An item lying on the floor: a coloured tile with its symbol, bobbing gently. Pure presentation;
## ItemField decides where items are. A model at assets_ext/models/item_<key>.glb replaces the tile.

const TILE := Vector3(0.74, 0.14, 0.74)
const BOB_HEIGHT := 0.04
const POP_TIME := 0.2

static var _materials := {}  # item type -> StandardMaterial3D

var item := Items.Type.BOMB_UP
var _age := 0.0
var _body: Node3D


func setup(item_type: int) -> void:
	item = item_type


func _ready() -> void:
	var scene := AssetLibrary.model("item_" + Items.key(item))
	_body = scene.instantiate() if scene else _build_placeholder()
	add_child(_body)
	scale = Vector3.ONE * 0.01
	create_tween().tween_property(self, "scale", Vector3.ONE, POP_TIME).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _process(delta: float) -> void:
	_age += delta
	_body.position.y = 0.05 + sin(_age * 3.0) * BOB_HEIGHT


func _build_placeholder() -> Node3D:
	var root := Node3D.new()
	var tile := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = TILE
	tile.mesh = box
	tile.material_override = _material(item)
	tile.position.y = TILE.y / 2.0
	root.add_child(tile)

	var label := Label3D.new()
	label.text = Items.symbol(item)
	label.font_size = 96
	label.pixel_size = 0.0045
	label.outline_size = 20
	label.outline_modulate = Color(0, 0, 0, 0.85)
	label.rotation_degrees.x = -90.0  # lie flat, readable from the overhead camera
	label.position.y = TILE.y + 0.01
	root.add_child(label)
	return root


static func _material(type: int) -> StandardMaterial3D:
	if not _materials.has(type):
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Items.color(type)
		mat.roughness = 0.35
		mat.emission_enabled = true
		mat.emission = Items.color(type) * 0.35
		_materials[type] = mat
	return _materials[type]
