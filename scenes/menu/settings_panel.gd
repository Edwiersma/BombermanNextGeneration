extends PanelContainer
## The versus screen's settings column: every match setting in a scrolling list, always on show.
## One player at a time drives it; the lobby decides who (LobbyState.settings_owner) and forwards
## that player's presses to handle():
##   up / down          choose a row
##   right / Cross      change the row (Cross on RESET TO DEFAULTS resets everything)
##   while changing:    left / right step the value; Cross, Back, up or down finish
##   left / Back        leave the settings (handle() returns false)
## Rows come from MatchSettings.rows(), so new settings appear here automatically.

const RESET := "__reset"
const ROW_FONT := 17

## Slot driving the list, or -1.
var owner_slot := -1
## Changing the selected row's value (left / right step it) rather than moving between rows.
var editing := false

var _settings: MatchSettings
var _before: MatchSettings
var _rows: Array[String] = []
var _row_widgets: Array[Dictionary] = []
var _index := 0
var _style: StyleBoxFlat
var _status: Label
var _footer: Label
var _list: VBoxContainer
var _scroll: ScrollContainer


func _ready() -> void:
	_style = UI.panel_style(UI.PANEL.darkened(0.25), 16, 3, UI.PANEL)
	_style.set_content_margin_all(12)
	add_theme_stylebox_override("panel", _style)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	add_child(column)
	column.add_child(UI.label("MATCH SETTINGS", 26, UI.ACCENT, 8))
	_status = UI.label("", 15, UI.DIM, 4)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_status)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 4)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_list)

	_footer = UI.label("", 14, UI.DIM, 4)
	_footer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_footer)


## Shows `settings` (changed in place while someone edits them).
func setup(settings: MatchSettings) -> void:
	_settings = settings
	_build_rows()
	_refresh()


func is_focused() -> bool:
	return owner_slot != -1


## Player `slot` takes the list over.
func focus(slot: int) -> void:
	owner_slot = slot
	editing = false
	_before = _settings.duplicate_settings()
	_refresh()


## The owner left. Returns true when they changed something (the lobby then saves).
func unfocus() -> bool:
	var changed := is_focused() and not _settings.equals(_before)
	owner_slot = -1
	editing = false
	_refresh()
	return changed


## One press from the owner. Returns false when it means "leave the settings".
func handle(action: StringName) -> bool:
	var row := _rows[_index]
	if editing:
		match action:
			&"left":
				_settings.step(row, -1)
			&"right":
				_settings.step(row, 1)
			&"up":
				editing = false
				_index = posmod(_index - 1, _rows.size())
			&"down":
				editing = false
				_index = posmod(_index + 1, _rows.size())
			&"bomb", &"back":
				editing = false
	else:
		match action:
			&"up":
				_index = posmod(_index - 1, _rows.size())
			&"down":
				_index = posmod(_index + 1, _rows.size())
			&"right", &"bomb":
				if row != RESET:
					editing = true
				elif action == &"bomb":
					_settings.reset_to_defaults()
			&"left", &"back":
				return false
	_refresh()
	return true


func _build_rows() -> void:
	for child in _list.get_children():
		child.queue_free()
	_row_widgets.clear()
	_rows = _settings.rows()
	_rows.append(RESET)
	for row in _rows:
		var style := UI.panel_style(UI.PANEL, 8, 2, UI.PANEL)
		style.content_margin_left = 10
		style.content_margin_right = 10
		style.content_margin_top = 5
		style.content_margin_bottom = 5
		var panel := PanelContainer.new()
		panel.add_theme_stylebox_override("panel", style)
		var line := HBoxContainer.new()
		panel.add_child(line)
		var name_label := UI.label("", ROW_FONT, Color.WHITE, 4)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(name_label)
		var value_label := UI.label("", ROW_FONT, Color.WHITE, 4)
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		line.add_child(value_label)
		_list.add_child(panel)
		_row_widgets.append({"panel": panel, "style": style, "name": name_label, "value": value_label})


func _refresh() -> void:
	var focused := is_focused()
	var owner_color: Color = Palette.CURSOR_COLORS[owner_slot] if focused else UI.PANEL
	_style.border_color = owner_color
	if focused:
		_status.text = "P%d is changing the settings" % (owner_slot + 1)
		_status.add_theme_color_override("font_color", owner_color)
		_footer.text = ("Left / Right: change\nCross / Back: done" if editing
			else "Up / Down: choose     Right / Cross: change\nLeft / Back: leave the settings")
	else:
		_status.text = "Move a cursor right past the portraits or slots to change these. One player at a time."
		_status.add_theme_color_override("font_color", UI.DIM)
		_footer.text = ""

	for i in _rows.size():
		var row := _rows[i]
		var widgets: Dictionary = _row_widgets[i]
		var selected := focused and i == _index
		var filled := selected and editing
		widgets.style.bg_color = UI.ACCENT if filled else (UI.PANEL.lightened(0.18) if selected else UI.PANEL)
		widgets.style.border_color = owner_color if selected else UI.PANEL
		var text_color := Color.BLACK if filled else Color.WHITE
		for key in ["name", "value"]:
			widgets[key].add_theme_color_override("font_color", text_color)
			widgets[key].add_theme_constant_override("outline_size", 0 if filled else 4)
		if row == RESET:
			widgets.name.text = "RESET TO DEFAULTS"
			widgets.value.text = ""
		else:
			widgets.name.text = _settings.row_label(row)
			var value := _settings.value_text(row)
			widgets.value.text = "<  %s  >" % value if filled else value
	if focused:
		_scroll.ensure_control_visible.call_deferred(_row_widgets[_index].panel)
