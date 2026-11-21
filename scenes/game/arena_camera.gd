extends Camera3D
## Locked overhead camera. Fits a box (the arena) on screen below a strip kept free for the HUD,
## and re-fits whenever the window size changes. No movement during play.

@export_range(30.0, 90.0) var pitch_degrees := 62.0
## Top fraction of the screen kept free for the HUD.
@export_range(0.0, 0.4) var hud_margin := 0.10
@export_range(0.0, 0.2) var edge_margin := 0.02

var _bounds := AABB()


func _ready() -> void:
	get_viewport().size_changed.connect(_refit)


func frame(bounds: AABB) -> void:
	_bounds = bounds
	_refit()


func _refit() -> void:
	if not is_inside_tree() or _bounds.size == Vector3.ZERO:
		return
	var view := get_viewport().get_visible_rect().size
	var avail := Rect2(
		view.x * edge_margin, view.y * hud_margin,
		view.x * (1.0 - 2.0 * edge_margin), view.y * (1.0 - hud_margin - edge_margin))
	var pitch := deg_to_rad(pitch_degrees)
	var back := Vector3(0.0, sin(pitch), cos(pitch))  # from target towards the camera
	var target := _bounds.get_center()
	var distance := maxf(_bounds.size.x, _bounds.size.z) * 2.0

	# Iterate: scale distance so the projected box fits, then shift so it is centred in `avail`.
	for i in 12:
		_place(target, back, distance)
		var box := _projected_rect()
		var fit := maxf(box.size.x / avail.size.x, box.size.y / avail.size.y)
		var delta := box.get_center() - avail.get_center()
		var world_per_px := 2.0 * distance * tan(deg_to_rad(fov) / 2.0) / view.y
		target += global_transform.basis.x * delta.x * world_per_px
		target -= global_transform.basis.y * delta.y * world_per_px
		distance *= fit
	_place(target, back, distance)


func _place(target: Vector3, back: Vector3, distance: float) -> void:
	global_transform = Transform3D(Basis(), target + back * distance).looking_at(target, Vector3.UP)


func _projected_rect() -> Rect2:
	var rect := Rect2(unproject_position(_bounds.get_endpoint(0)), Vector2.ZERO)
	for i in range(1, 8):
		rect = rect.expand(unproject_position(_bounds.get_endpoint(i)))
	return rect
