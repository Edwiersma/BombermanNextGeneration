extends Control
## Lobby: up to 4 players join on their own device, pick a colour and ready up.
##   Join, then ready:  Cross / Space / Enter
##   Colour:            left / right (until ready)
##   Back:              un-ready, then leave; with nobody joined, back to the main menu
##   Start:             begin once everyone joined is ready (1 player = practice)

const CORNERS := ["top-left", "top-right", "bottom-left", "bottom-right"]
const JOIN_TEXT := "Press Cross / Space / Enter\nto join"

var _lobby: LobbyState
var _cards: Array[Dictionary] = []
var _prompt: Label
var _starting := false  # START accepted; ignore further presses until the match loads


func _ready() -> void:
	_lobby = GameState.lobby
	_lobby.unready_all()
	_sync_with_router()
	_build_ui()
	InputRouter.action_pressed.connect(_on_action)
	InputRouter.devices_changed.connect(_on_devices_changed)
	_refresh()


func _exit_tree() -> void:
	InputRouter.action_pressed.disconnect(_on_action)
	InputRouter.devices_changed.disconnect(_on_devices_changed)


func _on_devices_changed() -> void:
	_sync_with_router()
	_refresh()


## Keeps lobby choices and InputRouter slots in agreement (e.g. after a dev match). A pad that
## disconnected keeps its slot during a match so it can rejoin, but in the lobby it would block
## START forever (it can never ready up or leave), so its slot is freed here.
func _sync_with_router() -> void:
	for slot in InputRouter.MAX_SLOTS:
		var device := InputRouter.device_in_slot(slot)
		if device != "" and not InputRouter.is_connected_device(device):
			InputRouter.release_slot(slot)
		var has_device := InputRouter.device_in_slot(slot) != ""
		if has_device and not _lobby.is_joined(slot):
			_lobby.join(slot)
		elif not has_device and _lobby.is_joined(slot):
			_lobby.leave(slot)


func _on_action(device: String, action: StringName) -> void:
	if _starting:
		return
	var slot := InputRouter.slot_of(device)
	if slot == -1:
		if action == &"bomb":
			slot = InputRouter.assign_slot(device)
			if slot != -1:
				_lobby.join(slot)
		elif action == &"back" and _lobby.joined_count() == 0:
			Scenes.go(Scenes.MENU)
			return
	else:
		match action:
			&"left":
				_lobby.cycle_color(slot, -1)
			&"right":
				_lobby.cycle_color(slot, 1)
			&"bomb":
				_lobby.set_ready(slot, true)
			&"back":
				if _lobby.ready[slot]:
					_lobby.set_ready(slot, false)
				else:
					_lobby.leave(slot)
					InputRouter.release_slot(slot)
			&"start":
				if _lobby.can_start():
					_starting = true
					GameState.in_session = true
					Scenes.go(Scenes.MATCH)
					return
	_refresh()


# --- UI ----------------------------------------------------------------------

func _build_ui() -> void:
	UI.add_background(self)

	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.add_theme_constant_override("separation", 24)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(column)

	column.add_child(UI.title("VERSUS", 64))
	column.add_child(UI.label("Stage: %s      First to %d wins" % [GameState.level.display_name, Rules.WINS_TO_WIN], 24, UI.DIM))

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 20)
	column.add_child(row)
	for slot in InputRouter.MAX_SLOTS:
		var card := _make_card(slot)
		row.add_child(card.panel)
		_cards.append(card)

	_prompt = UI.label("", 34, UI.ACCENT, 8)
	column.add_child(_prompt)
	column.add_child(UI.label("Colour: Left / Right      Back: Circle / Esc / Backspace      Start: Options / Tab / P", 18, UI.DIM, 4))


func _make_card(slot: int) -> Dictionary:
	var style := UI.panel_style(UI.PANEL, 18, 4, UI.PANEL)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(270, 340)
	panel.add_theme_stylebox_override("panel", style)

	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)

	box.add_child(UI.label("PLAYER %d" % (slot + 1), 28))
	box.add_child(UI.label("starts %s" % CORNERS[slot], 16, UI.DIM, 4))

	var swatch_style := UI.panel_style(Color.DIM_GRAY, 48, 4, Color.BLACK)
	var swatch := Panel.new()
	swatch.custom_minimum_size = Vector2(96, 96)
	swatch.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	swatch.add_theme_stylebox_override("panel", swatch_style)
	box.add_child(swatch)

	var color_label := UI.label("", 28)
	box.add_child(color_label)
	var device_label := UI.label("", 15, UI.DIM, 4)
	device_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	device_label.custom_minimum_size.x = 230
	box.add_child(device_label)
	var status := UI.label("", 22)
	box.add_child(status)

	return {"panel": panel, "style": style, "swatch": swatch, "swatch_style": swatch_style,
		"color": color_label, "device": device_label, "status": status}


func _refresh() -> void:
	for slot in _cards.size():
		var card: Dictionary = _cards[slot]
		if _lobby.is_joined(slot):
			var color := GameState.color_of(slot)
			var is_ready := _lobby.ready[slot]
			card.swatch_style.bg_color = color
			card.swatch.modulate = Color.WHITE
			card.color.text = GameState.color_name(slot).to_upper() if is_ready else "<  %s  >" % GameState.color_name(slot).to_upper()
			card.device.text = InputRouter.device_label(InputRouter.device_in_slot(slot))
			card.status.text = "READY!" if is_ready else "Cross / Space / Enter: ready"
			card.status.add_theme_color_override("font_color", UI.GOOD if is_ready else Color.WHITE)
			card.status.add_theme_font_size_override("font_size", 30 if is_ready else 18)
			card.style.border_color = color if is_ready else UI.PANEL.lightened(0.2)
			card.panel.modulate = Color.WHITE
		else:
			card.swatch_style.bg_color = Color.DIM_GRAY
			card.swatch.modulate = Color(1, 1, 1, 0.25)
			card.color.text = ""
			card.device.text = ""
			card.status.text = JOIN_TEXT
			card.status.add_theme_color_override("font_color", UI.DIM)
			card.status.add_theme_font_size_override("font_size", 18)
			card.style.border_color = UI.PANEL
			card.panel.modulate = Color(1, 1, 1, 0.75)

	if _lobby.joined_count() == 0:
		_prompt.text = "Join in!   (Back: main menu)"
	elif not _lobby.all_ready():
		_prompt.text = "Waiting for everyone to be ready..."
	elif _lobby.is_practice():
		_prompt.text = "Press START for practice"
	else:
		_prompt.text = "Press START to fight!"
