extends Control
## One of the six player slots under the portraits: Off / Player / AI, the portrait it claimed,
## its controller and whether it is ready. Cursors on it show as frames and tags; `hint` says
## what Cross does here. Drawn in code; the lobby fills it from LobbyState.

const Draw := preload("res://scenes/menu/lobby_draw.gd")
const SIZE := Vector2(125, 196)
const KIND_NAMES := ["OFF", "PLAYER", "AI"]

var slot := 0

var _state := {}
var _bg := StyleBoxFlat.new()


func _init(index := 0) -> void:
	slot = index
	custom_minimum_size = SIZE
	_bg.set_corner_radius_all(12)


## state: {"kind": LobbyState.Kind, "pick": portrait or LobbyState.NONE, "device": String,
## "cursors": Array of slots, "hint": String}
func show_state(state: Dictionary) -> void:
	if state == _state:
		return
	_state = state
	queue_redraw()


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	var font := get_theme_default_font()
	var kind: int = _state.get("kind", LobbyState.Kind.OFF)
	var pick: int = _state.get("pick", LobbyState.NONE)
	var active := kind != LobbyState.Kind.OFF
	var color: Color = Palette.CURSOR_COLORS[slot]

	_bg.bg_color = UI.PANEL if active else UI.PANEL.darkened(0.45)
	draw_style_box(_bg, rect)

	# Header: player number and slot kind.
	var header := Rect2(4.0, 4.0, size.x - 8.0, 24.0)
	draw_rect(header, color if active else UI.PANEL.darkened(0.1))
	var header_text := Palette.text_on(color) if active else UI.DIM
	draw_string(font, Vector2(10.0, 22.0), "P%d" % (slot + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, header_text)
	draw_string(font, Vector2(0.0, 21.0), KIND_NAMES[kind], HORIZONTAL_ALIGNMENT_RIGHT, size.x - 10.0, 13, header_text)

	# The pick.
	var center := Vector2(size.x / 2.0, 70.0)
	var radius := 27.0
	var pick_text := ""
	if not active:
		draw_string(font, Vector2(0.0, center.y + 9.0), "OFF", HORIZONTAL_ALIGNMENT_CENTER, size.x, 26, Color(1, 1, 1, 0.2))
	elif pick == LobbyState.NONE:
		draw_arc(center, radius, 0.0, TAU, 32, UI.DIM, 2.0, true)
		draw_string(font, Vector2(0.0, center.y + 9.0), "?", HORIZONTAL_ALIGNMENT_CENTER, size.x, 26, UI.DIM)
		pick_text = "choosing..."
	elif pick == LobbyState.RANDOM:
		Draw.random_mark(self, center, radius, font)
		pick_text = "RANDOM"
	else:
		Draw.face(self, center, radius, Palette.PLAYER_COLORS[pick])
		pick_text = Palette.PLAYER_COLOR_NAMES[pick].to_upper()
	draw_string(font, Vector2(0.0, 118.0), pick_text, HORIZONTAL_ALIGNMENT_CENTER, size.x, 15,
		Color.WHITE if pick != LobbyState.NONE else UI.DIM)

	# Controller (or AI note), two lines at most.
	var device: String = _state.get("device", "")
	if device != "":
		draw_multiline_string(font, Vector2(6.0, 138.0), device, HORIZONTAL_ALIGNMENT_CENTER, size.x - 12.0, 11, 2, UI.DIM)

	# Bottom line: what Cross does here while a cursor is on it, else READY.
	var hint: String = _state.get("hint", "")
	var cursors: Array = _state.get("cursors", [])
	if hint != "" and not cursors.is_empty():
		draw_string(font, Vector2(0.0, size.y - 12.0), hint, HORIZONTAL_ALIGNMENT_CENTER, size.x, 13, UI.ACCENT)
	elif active and pick != LobbyState.NONE:
		draw_string(font, Vector2(0.0, size.y - 11.0), "READY", HORIZONTAL_ALIGNMENT_CENTER, size.x, 18, UI.GOOD)
	Draw.cursors(self, font, rect, cursors, Vector2(6.0, 32.0))
