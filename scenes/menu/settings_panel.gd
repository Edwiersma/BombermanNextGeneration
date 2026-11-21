extends Control
## Lobby overlay for match settings. Only the device that opened it drives it (the lobby forwards
## that device's presses to handle()):
##   up / down: choose a row     left / right (or bomb): change it
##   back / menu: done           bomb on RESET / DONE: do that
## Rows come from MatchSettings.ROWS, so new settings appear here automatically.

signal closed(changed: bool)

const RESET := "__reset"
const DONE := "__done"

var owner_device := ""

var _settings: MatchSettings
var _before: MatchSettings
var _rows: Array[String] = []
var _row_widgets: Array[Dictionary] = []
var _index := 0
var _list: VBoxContainer


func _ready() -> void:
	# Already in the tree here, so set offsets too (set_anchors_preset alone keeps the zero size).
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UI.panel_style(UI.BG, 20, 4, UI.ACCENT))
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	panel.add_child(column)
	column.add_child(UI.title("MATCH SETTINGS", 48))

	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 6)
	column.add_child(_list)

	column.add_child(UI.label("Up / Down: choose      Left / Right: change      Back / Triangle: done", 16, UI.DIM, 4))


func open(device: String, settings: MatchSettings) -> void:
	owner_device = device
	_settings = settings
	_before = settings.duplicate_settings()
	_index = 0
	_build_rows()
	visible = true
	_refresh()


func handle(action: StringName) -> void:
	var row := _rows[_index]
	match action:
		&"up":
			_index = posmod(_index - 1, _rows.size())
		&"down":
			_index = posmod(_index + 1, _rows.size())
		&"left":
			if not row.begins_with("__"):
				_settings.step(row, -1)
		&"right":
			if not row.begins_with("__"):
				_settings.step(row, 1)
		&"bomb":
			if row == RESET:
				_settings.reset_to_defaults()
			elif row == DONE:
				_close()
				return
			else:
				_settings.step(row, 1)
		&"back", &"menu":
			_close()
			return
	_refresh()


func _close() -> void:
	visible = false
	owner_device = ""
	closed.emit(not _settings.equals(_before))


func _build_rows() -> void:
	for child in _list.get_children():
		child.queue_free()
	_row_widgets.clear()
	_rows.assign(MatchSettings.ROWS)
	_rows.append_array([RESET, DONE])
	for row in _rows:
		var style := UI.panel_style(UI.PANEL, 10)
		style.set_content_margin_all(10)
		var panel := PanelContainer.new()
		panel.custom_minimum_size = Vector2(620, 0)
		panel.add_theme_stylebox_override("panel", style)
		var line := HBoxContainer.new()
		panel.add_child(line)
		var name_label := UI.label("", 26)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(name_label)
		var value_label := UI.label("", 26)
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		line.add_child(value_label)
		_list.add_child(panel)
		_row_widgets.append({"style": style, "name": name_label, "value": value_label})


func _refresh() -> void:
	for i in _rows.size():
		var row := _rows[i]
		var widgets: Dictionary = _row_widgets[i]
		var selected := i == _index
		widgets.style.bg_color = UI.ACCENT if selected else UI.PANEL
		var text_color := Color.BLACK if selected else Color.WHITE
		widgets.name.add_theme_color_override("font_color", text_color)
		widgets.value.add_theme_color_override("font_color", text_color)
		widgets.name.add_theme_constant_override("outline_size", 0 if selected else 6)
		widgets.value.add_theme_constant_override("outline_size", 0 if selected else 6)
		match row:
			RESET:
				widgets.name.text = "RESET TO DEFAULTS"
				widgets.value.text = ""
			DONE:
				widgets.name.text = "DONE"
				widgets.value.text = ""
			_:
				widgets.name.text = _settings.row_label(row)
				var value := _settings.value_text(row)
				widgets.value.text = "<  %s  >" % value if selected else value
