class_name UI
extends RefCounted
## Shared look for menus: colours, labels, buttons, panels. Built in code so menus need no theme
## resource and stay readable from far away on a TV.

const BG := Color(0.05, 0.08, 0.14)
const PANEL := Color(0.11, 0.15, 0.24)
const ACCENT := Color(1.0, 0.78, 0.22)
const DIM := Color(1, 1, 1, 0.55)
const GOOD := Color(0.45, 1.0, 0.45)


static func label(text: String, font_size := 24, color := Color.WHITE, outline := 6) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", outline)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l


static func title(text: String, font_size := 84) -> Label:
	return label(text, font_size, ACCENT, 16)


static func panel_style(color := PANEL, radius := 16, border := 0, border_color := Color.WHITE) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	style.set_border_width_all(border)
	style.border_color = border_color
	style.set_content_margin_all(16)
	return style


static func button(text: String, min_width := 380) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_width, 64)
	b.add_theme_font_size_override("font_size", 30)
	b.add_theme_color_override("font_color", Color.WHITE)
	b.add_theme_color_override("font_focus_color", Color.BLACK)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color.BLACK)
	b.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.3))
	b.add_theme_stylebox_override("normal", panel_style(PANEL, 14))
	b.add_theme_stylebox_override("hover", panel_style(PANEL.lightened(0.15), 14))
	b.add_theme_stylebox_override("pressed", panel_style(ACCENT.darkened(0.2), 14))
	b.add_theme_stylebox_override("disabled", panel_style(PANEL.darkened(0.3), 14))
	# The focus style is drawn over the normal one: a bright accent fill so the selection reads
	# at a glance from the couch.
	b.add_theme_stylebox_override("focus", panel_style(ACCENT, 14, 4, Color.WHITE))
	b.focus_mode = Control.FOCUS_ALL
	return b


## Full-screen background for a menu scene.
static func add_background(parent: Control) -> void:
	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(bg)
