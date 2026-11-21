extends CanvasLayer
## Match HUD, laid out like the original's top bar: round clock, then one badge per player
## (colour + round wins, greyed out when dead). A big centre banner announces round events.
## Pure presentation: Match calls these methods.

const BAR_FONT_SIZE := 28
const BANNER_FONT_SIZE := 72
const HURRY_COLOR := Color(1.0, 0.35, 0.25)

var _bar: PanelContainer
var _bar_row: HBoxContainer
var _clock: Label
var _badges := {}  # slot -> {"root": Control, "wins": Label}
var _banner: Label
var _banner_tween: Tween
var _hurry := false


func _ready() -> void:
	_build_bar()
	_build_banner()


func setup_players(slots: Array[int]) -> void:
	for slot in _badges:
		_badges[slot].root.queue_free()
	_badges.clear()
	for slot in slots:
		_badges[slot] = _make_badge(slot)
	_bar.visible = _clock.visible or not slots.is_empty()


func set_wins(wins: Dictionary) -> void:
	for slot in _badges:
		_badges[slot].wins.text = str(wins.get(slot, 0))


func set_alive(slot: int, alive: bool) -> void:
	if _badges.has(slot):
		_badges[slot].root.modulate = Color.WHITE if alive else Color(1, 1, 1, 0.3)


func show_clock(visible_now: bool) -> void:
	_clock.visible = visible_now
	_bar.visible = visible_now or not _badges.is_empty()


func set_time(ticks: int, hurry: bool) -> void:
	var seconds := ceili(ticks / float(Rules.TICKS_PER_SECOND))
	_clock.text = "%d:%02d" % [seconds / 60, seconds % 60]
	_hurry = hurry
	var color := HURRY_COLOR if hurry else Color.WHITE
	if hurry and fmod(Time.get_ticks_msec() / 1000.0, 0.5) < 0.25:
		color = Color.WHITE
	_clock.add_theme_color_override("font_color", color)


## Shows `text` big in the centre. seconds = 0 keeps it up until the next announcement or clear.
func announce(text: String, seconds := 0.0, color := Color.WHITE) -> void:
	if _banner_tween:
		_banner_tween.kill()
	_banner.text = text
	_banner.add_theme_color_override("font_color", color)
	_banner.modulate = Color.WHITE
	_banner.pivot_offset = _banner.size / 2.0
	_banner.scale = Vector2.ONE * 1.6
	_banner_tween = create_tween()
	_banner_tween.tween_property(_banner, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if seconds > 0.0:
		_banner_tween.tween_interval(seconds)
		_banner_tween.tween_property(_banner, "modulate:a", 0.0, 0.25)


func clear_banner() -> void:
	if _banner_tween:
		_banner_tween.kill()
	_banner.text = ""


# --- Building ----------------------------------------------------------------

func _build_bar() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.07, 0.12, 0.75)
	style.set_corner_radius_all(14)
	style.set_content_margin_all(8)
	style.content_margin_left = 18
	style.content_margin_right = 18

	_bar = PanelContainer.new()
	_bar.add_theme_stylebox_override("panel", style)
	_bar.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_bar.position.y = 10
	_bar.visible = false
	add_child(_bar)

	_bar_row = HBoxContainer.new()
	_bar_row.add_theme_constant_override("separation", 28)
	_bar.add_child(_bar_row)

	_clock = _label("3:00", BAR_FONT_SIZE)
	_clock.custom_minimum_size.x = 80
	_bar_row.add_child(_clock)


func _make_badge(slot: int) -> Dictionary:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var head_style := StyleBoxFlat.new()
	head_style.bg_color = Palette.PLAYER_COLORS[slot]
	head_style.set_corner_radius_all(16)
	head_style.set_border_width_all(3)
	head_style.border_color = Color(0, 0, 0, 0.8)
	var head := Panel.new()
	head.custom_minimum_size = Vector2(32, 32)
	head.add_theme_stylebox_override("panel", head_style)
	head.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(head)

	var wins := _label("0", BAR_FONT_SIZE)
	row.add_child(wins)
	_bar_row.add_child(row)
	return {"root": row, "wins": wins}


func _build_banner() -> void:
	_banner = _label("", BANNER_FONT_SIZE)
	_banner.set_anchors_preset(Control.PRESET_FULL_RECT)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_banner.add_theme_constant_override("outline_size", 14)
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_banner)


func _label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 8)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label
