extends Node3D
## 3D view of a Grid. Holds no rules: it builds blocks from the grid and mirrors cell changes.

const WALL_HEIGHT := 1.0
const PILLAR_HEIGHT := 0.8
const SOFT_HEIGHT := 0.85
const BLOCK_SIZE := 0.98      # small gap so neighbouring blocks read as separate
const OUTSIDE_SIZE := 81      # odd, so outside tiles line up with cell edges

## Coloured discs on the spawn cells, until players exist (M3).
@export var show_spawn_markers := true

var grid: Grid

var _soft_blocks := {}  # Vector2i -> Node3D
var _meshes := {}


func build(new_grid: Grid) -> void:
	if grid and grid.cell_changed.is_connected(_on_cell_changed):
		grid.cell_changed.disconnect(_on_cell_changed)
	for child in get_children():
		child.queue_free()
	_soft_blocks.clear()

	grid = new_grid
	_build_ground()
	for y in grid.height:
		for x in grid.width:
			_add_cell_visual(Vector2i(x, y))
	if show_spawn_markers:
		_add_spawn_markers()
	grid.cell_changed.connect(_on_cell_changed)


## World-space box around the arena, for framing the camera.
func get_bounds() -> AABB:
	return AABB(Vector3(-0.5, 0.0, -0.5), Vector3(grid.width, WALL_HEIGHT, grid.height))


func _add_cell_visual(cell: Vector2i) -> void:
	var cell_type := grid.get_cell(cell)
	if cell_type == Grid.Cell.HARD:
		if grid.is_border(cell):
			_add_block(cell, "wall_block", WALL_HEIGHT)
		else:
			_add_block(cell, "hard_block", PILLAR_HEIGHT)
	elif cell_type == Grid.Cell.SOFT:
		_soft_blocks[cell] = _add_block(cell, "soft_block", SOFT_HEIGHT)


func _on_cell_changed(cell: Vector2i, old_type: int, _new_type: int) -> void:
	# M4 replaces the instant removal with a break animation.
	if old_type == Grid.Cell.SOFT and _soft_blocks.has(cell):
		_soft_blocks[cell].queue_free()
		_soft_blocks.erase(cell)
	_add_cell_visual(cell)


## Each block is a Node3D at the cell's floor centre, holding either the imported model or a box.
func _add_block(cell: Vector2i, key: String, block_height: float) -> Node3D:
	var node: Node3D
	var scene := AssetLibrary.model(key)
	if scene:
		node = scene.instantiate()
	else:
		node = Node3D.new()
		var mesh_instance := MeshInstance3D.new()
		mesh_instance.mesh = _box_mesh(key, block_height)
		mesh_instance.position.y = block_height / 2.0
		node.add_child(mesh_instance)
	node.name = "%s_%d_%d" % [key, cell.x, cell.y]
	node.position = Grid.cell_to_world(cell)
	add_child(node)
	return node


func _box_mesh(key: String, block_height: float) -> BoxMesh:
	var cache_key := "%s:%s" % [key, block_height]
	if not _meshes.has(cache_key):
		var mesh := BoxMesh.new()
		mesh.size = Vector3(BLOCK_SIZE, block_height, BLOCK_SIZE)
		mesh.material = AssetLibrary.material(key, Vector2(3, 2))
		_meshes[cache_key] = mesh
	return _meshes[cache_key]


func _build_ground() -> void:
	var centre := Vector3((grid.width - 1) / 2.0, 0.0, (grid.height - 1) / 2.0)

	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(grid.width, grid.height)
	floor_mesh.material = AssetLibrary.material("floor", Vector2(grid.width / 2.0, grid.height / 2.0))
	var floor_instance := MeshInstance3D.new()
	floor_instance.name = "Floor"
	floor_instance.mesh = floor_mesh
	floor_instance.position = centre
	add_child(floor_instance)

	var outside_mesh := PlaneMesh.new()
	outside_mesh.size = Vector2(OUTSIDE_SIZE, OUTSIDE_SIZE)
	outside_mesh.material = AssetLibrary.material("outside", Vector2(OUTSIDE_SIZE, OUTSIDE_SIZE))
	var outside_instance := MeshInstance3D.new()
	outside_instance.name = "Outside"
	outside_instance.mesh = outside_mesh
	outside_instance.position = centre + Vector3(0.0, -0.01, 0.0)
	add_child(outside_instance)


func _add_spawn_markers() -> void:
	for slot in grid.spawns.size():
		var spawn := grid.spawns[slot]
		if spawn == Grid.NO_SPAWN:
			continue
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.35
		mesh.bottom_radius = 0.35
		mesh.height = 0.03
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Palette.PLAYER_COLORS[slot]
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mesh.material = mat
		var marker := MeshInstance3D.new()
		marker.name = "SpawnMarker%d" % (slot + 1)
		marker.mesh = mesh
		marker.position = Grid.cell_to_world(spawn) + Vector3(0.0, 0.02, 0.0)
		add_child(marker)
