extends Label3D
## Floating text above a player when they pick something up ("FIRE UP!"): rises and fades.

const LIFETIME := 0.9
const RISE_SPEED := 0.9

var _age := 0.0


func setup(popup_text: String, color: Color) -> void:
	text = popup_text
	modulate = color


func _ready() -> void:
	billboard = BaseMaterial3D.BILLBOARD_ENABLED
	no_depth_test = true
	font_size = 56
	pixel_size = 0.006
	outline_size = 14
	outline_modulate = Color.BLACK
	position.y += 1.3


func _process(delta: float) -> void:
	_age += delta
	if _age >= LIFETIME:
		queue_free()
		return
	position.y += delta * RISE_SPEED
	var fade := _age / LIFETIME
	modulate.a = 1.0 - fade * fade
	outline_modulate.a = modulate.a
