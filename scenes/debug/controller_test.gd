extends Control
## M1 controller spike. Shows every input device with live button and stick state,
## and lets devices join/leave the 4 player slots the way the lobby will.
##   Join:  Cross / Space / Enter
##   Leave: Circle / Esc / Backspace
##   Main menu: Options / Tab / P

const PAD_BUTTON_NAMES := {
	JOY_BUTTON_A: "Cross",
	JOY_BUTTON_B: "Circle",
	JOY_BUTTON_X: "Square",
	JOY_BUTTON_Y: "Triangle",
	JOY_BUTTON_BACK: "Share",
	JOY_BUTTON_GUIDE: "PS",
	JOY_BUTTON_START: "Options",
	JOY_BUTTON_LEFT_STICK: "L3",
	JOY_BUTTON_RIGHT_STICK: "R3",
	JOY_BUTTON_LEFT_SHOULDER: "L1",
	JOY_BUTTON_RIGHT_SHOULDER: "R1",
	JOY_BUTTON_DPAD_UP: "D-Up",
	JOY_BUTTON_DPAD_DOWN: "D-Down",
	JOY_BUTTON_DPAD_LEFT: "D-Left",
	JOY_BUTTON_DPAD_RIGHT: "D-Right",
	JOY_BUTTON_TOUCHPAD: "Touchpad",
}

const BG_COLOR := Color(0.09, 0.16, 0.11)
const CARD_COLOR := Color(0.16, 0.22, 0.18)

var _grid: GridContainer
var _info: Label
var _log: Label
var _cards := {}  # device id -> {panel: PanelContainer, style: StyleBoxFlat, title: Label, body: Label}
var _max_pads_seen := 0
var _log_lines: Array[String] = []


func _ready() -> void:
	_build_ui()
	InputRouter.devices_changed.connect(_rebuild_cards)
	InputRouter.slots_changed.connect(_refresh_card_colors)
	InputRouter.action_pressed.connect(_on_action_pressed)
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	_rebuild_cards()


func _process(_delta: float) -> void:
	_max_pads_seen = maxi(_max_pads_seen, Input.get_connected_joypads().size())
	_info.text = _info_text()
	for device in _cards:
		_cards[device].body.text = _device_text(device)


# --- UI ----------------------------------------------------------------------

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = BG_COLOR
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "Controller test"
	title.add_theme_font_size_override("font_size", 32)
	vbox.add_child(title)

	var help := Label.new()
	help.text = "Browsers hide controllers until a button is pressed: press any button on every pad.\n" \
		+ "Join a slot: Cross / Space / Enter.   Leave: Circle / Esc / Backspace.   Main menu: Options / Tab / P."
	help.modulate = Color(1, 1, 1, 0.8)
	vbox.add_child(help)

	_info = Label.new()
	vbox.add_child(_info)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)

	_grid = GridContainer.new()
	_grid.columns = 3
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 12)
	_grid.add_theme_constant_override("v_separation", 12)
	scroll.add_child(_grid)

	_log = Label.new()
	_log.modulate = Color(1, 1, 1, 0.7)
	vbox.add_child(_log)


func _rebuild_cards() -> void:
	for child in _grid.get_children():
		child.queue_free()
	_cards.clear()
	for device in InputRouter.get_devices():
		_cards[device] = _make_card()
		_cards[device].title.text = InputRouter.device_label(device)
	_refresh_card_colors()


func _make_card() -> Dictionary:
	var style := StyleBoxFlat.new()
	style.bg_color = CARD_COLOR
	style.set_corner_radius_all(8)
	style.set_content_margin_all(12)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(390, 190)
	panel.add_theme_stylebox_override("panel", style)
	_grid.add_child(panel)

	var vbox := VBoxContainer.new()
	panel.add_child(vbox)

	var title := Label.new()
	title.add_theme_font_size_override("font_size", 18)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(title)

	var body := Label.new()
	vbox.add_child(body)

	return {"panel": panel, "style": style, "title": title, "body": body}


func _refresh_card_colors() -> void:
	for device in _cards:
		var card: Dictionary = _cards[device]
		var slot := InputRouter.slot_of(device)
		var bg: Color = CARD_COLOR if slot == -1 else Palette.PLAYER_COLORS[slot]
		card.style.bg_color = bg
		var fg := Color.WHITE if slot == -1 else Palette.text_on(bg)
		card.title.add_theme_color_override("font_color", fg)
		card.body.add_theme_color_override("font_color", fg)


# --- Text --------------------------------------------------------------------

func _info_text() -> String:
	var parts: Array[String] = []
	parts.append("Platform: %s" % OS.get_name())
	if OS.has_feature("web"):
		var browser_slots = JavaScriptBridge.eval("navigator.getGamepads ? navigator.getGamepads().length : -1")
		parts.append("Browser gamepad slots: %d" % int(browser_slots))
	parts.append("Pads connected: %d (max seen: %d)" % [Input.get_connected_joypads().size(), _max_pads_seen])
	parts.append("Players joined: %d / %d" % [InputRouter.joined_count(), InputRouter.MAX_SLOTS])
	return "   |   ".join(parts)


func _device_text(device: String) -> String:
	var lines: Array[String] = []
	var slot := InputRouter.slot_of(device)
	if slot == -1:
		lines.append("Not joined")
	else:
		lines.append("PLAYER %d (%s)" % [slot + 1, Palette.PLAYER_COLOR_NAMES[slot]])

	var dir := InputRouter.get_direction(device)
	lines.append("Direction: %s" % _dir_name(dir))

	var actions: Array[String] = []
	for action in InputRouter.ACTIONS:
		if InputRouter.is_held(device, action) and action not in [&"up", &"down", &"left", &"right"]:
			actions.append(String(action))
	lines.append("Actions: %s" % (", ".join(actions) if actions else "-"))

	if InputRouter.is_pad(device):
		var id := InputRouter.pad_index(device)
		var buttons: Array[String] = []
		for b in JOY_BUTTON_SDL_MAX:
			if Input.is_joy_button_pressed(id, b):
				buttons.append(PAD_BUTTON_NAMES.get(b, "b%d" % b))
		lines.append("Buttons: %s" % (" ".join(buttons) if buttons else "-"))
		lines.append("L-stick: %+.2f %+.2f   R-stick: %+.2f %+.2f" % [
			Input.get_joy_axis(id, JOY_AXIS_LEFT_X), Input.get_joy_axis(id, JOY_AXIS_LEFT_Y),
			Input.get_joy_axis(id, JOY_AXIS_RIGHT_X), Input.get_joy_axis(id, JOY_AXIS_RIGHT_Y),
		])
		lines.append("L2: %.2f   R2: %.2f" % [
			Input.get_joy_axis(id, JOY_AXIS_TRIGGER_LEFT), Input.get_joy_axis(id, JOY_AXIS_TRIGGER_RIGHT),
		])
		lines.append("GUID: %s" % Input.get_joy_guid(id))
	return "\n".join(lines)


func _dir_name(dir: Vector2i) -> String:
	if dir == Vector2i.ZERO:
		return "-"
	var names: Array[String] = []
	if dir.y < 0:
		names.append("Up")
	if dir.y > 0:
		names.append("Down")
	if dir.x < 0:
		names.append("Left")
	if dir.x > 0:
		names.append("Right")
	return "+".join(names)


# --- Events ------------------------------------------------------------------

func _on_action_pressed(device: String, action: StringName) -> void:
	if action == &"start":
		Scenes.go(Scenes.MENU)
		return
	var slot := InputRouter.slot_of(device)
	if action == &"bomb" and slot == -1:
		var new_slot := InputRouter.assign_slot(device)
		if new_slot == -1:
			_add_log("%s: all %d slots taken" % [InputRouter.device_label(device), InputRouter.MAX_SLOTS])
		else:
			_add_log("%s joined as Player %d" % [InputRouter.device_label(device), new_slot + 1])
	elif action == &"back" and slot != -1:
		InputRouter.release_slot(slot)
		_add_log("%s left Player %d" % [InputRouter.device_label(device), slot + 1])


func _on_joy_connection_changed(device: int, connected: bool) -> void:
	if connected:
		_add_log("Pad %d connected: %s" % [device, InputRouter.pad_model(device)])
	else:
		_add_log("Pad %d disconnected" % device)


func _add_log(line: String) -> void:
	_log_lines.append(line)
	if _log_lines.size() > 4:
		_log_lines.pop_front()
	_log.text = "\n".join(_log_lines)
