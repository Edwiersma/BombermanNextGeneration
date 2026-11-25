extends Control
## One portrait on the versus screen: a colour's bomber face, a padlock (locked) or Random.
## Claims show as filled player tags at the bottom (and a tint), cursors as frames and outlined
## tags at the top. Drawn in code; LobbyState decides what it shows.

const Draw := preload("res://scenes/menu/lobby_draw.gd")
const SIZE := Vector2(92, 108)

var portrait := 0

var _claimed: Array = []
var _cursors: Array = []
var _bg := StyleBoxFlat.new()


func _init(index := 0) -> void:
	portrait = index
	custom_minimum_size = SIZE
	_bg.set_corner_radius_all(10)


## `claimed`: slots that claimed it (several only for Random); `cursors`: slots whose cursor is here.
func show_state(claimed: Array, cursors: Array) -> void:
	if claimed == _claimed and cursors == _cursors:
		return
	_claimed = claimed
	_cursors = cursors
	queue_redraw()


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	var font := get_theme_default_font()
	var locked := LobbyState.is_locked(portrait)
	var is_random := portrait == LobbyState.RANDOM

	_bg.bg_color = UI.PANEL.darkened(0.4) if locked else UI.PANEL
	if not is_random and not _claimed.is_empty():
		_bg.bg_color = UI.PANEL.lerp(Palette.CURSOR_COLORS[_claimed[0]], 0.4)
	draw_style_box(_bg, rect)

	var center := Vector2(size.x / 2.0, size.y * 0.42)
	var radius := minf(size.x, size.y) * 0.29
	var name_text := ""
	if locked:
		Draw.padlock(self, center, radius)
		name_text = "LOCKED"
	elif is_random:
		Draw.random_mark(self, center, radius, font)
		name_text = "RANDOM"
	else:
		Draw.face(self, center, radius, Palette.PLAYER_COLORS[portrait])
		name_text = Palette.PLAYER_COLOR_NAMES[portrait].to_upper()
	draw_string(font, Vector2(0.0, size.y - 8.0), name_text, HORIZONTAL_ALIGNMENT_CENTER, size.x, 14,
		UI.DIM if locked else Color.WHITE)

	if not _claimed.is_empty():
		var shown := mini(_claimed.size(), 3)
		var width := shown * Draw.TAG_SIZE.x + (shown - 1) * 3.0
		var origin := Vector2((size.x - width) / 2.0, size.y - 26.0 - Draw.TAG_SIZE.y)
		Draw.tag_rows(self, font, origin, _claimed, true, -1.0)
	Draw.cursors(self, font, rect, _cursors, Vector2(5, 5))
