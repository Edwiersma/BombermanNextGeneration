extends Control
## Versus screen. Left two thirds: the portrait grid (7 on top, 8 below, Random at the far right)
## and the six player slots under it; right third: the match settings. The rules of the screen
## live in LobbyState; this scene routes input and draws.
##   Join:      Cross / Space / Enter on a new controller (takes the next free slot, gets a cursor)
##   Move:      d-pad / left stick / WASD / arrows (hold to repeat)
##   Cross:     claim the portrait under the cursor; on a slot card, step Off / Player / AI level
##   Triangle:  on an AI's card, pick up its token (Cross on a portrait gives it to the AI); on an
##              empty card, fill empty slots with AIs; elsewhere, jump to the settings
##   Back:      drop your portrait, then leave; with nobody joined, back to the main menu
##   Start:     begin once every player has a portrait (one participant = practice)
##   Settings:  move right past the end of a row (or Triangle / Q / Delete); left or Back leaves.
##              One player at a time.

const PortraitTile := preload("res://scenes/menu/portrait_tile.gd")
const SlotCard := preload("res://scenes/menu/slot_card.gd")
const SettingsSection := preload("res://scenes/menu/settings_panel.gd")

const DIRECTIONS := {&"up": Vector2i.UP, &"down": Vector2i.DOWN, &"left": Vector2i.LEFT, &"right": Vector2i.RIGHT}
const REPEAT_DELAY := 0.38
const REPEAT_INTERVAL := 0.11
const FLASH_SECONDS := 1.6
const WARN := Color(1.0, 0.45, 0.35)
const HINTS := ("Move: D-pad / Left stick     Pick, toggle a slot: Cross     Back: Circle     Start: Options     Settings: move past the right edge\n"
	+ "Keyboard: WASD + Space, Esc, Tab, Q     or     Arrows + Enter, Backspace, P, Delete")

var _lobby: LobbyState
var _tiles: Array = []  # PortraitTile per portrait
var _cards: Array = []  # SlotCard per slot
var _settings_section: SettingsSection
var _prompt: Label
var _starting := false  # START accepted; ignore further presses until the match loads
var _rng := RandomNumberGenerator.new()
var _repeat := {}  # slot -> {"action": StringName, "time": float} for held directions
var _flash_text := ""
var _flash_left := 0.0


func _ready() -> void:
	_rng.randomize()
	_lobby = GameState.lobby
	_lobby.prepare()
	_build_ui()
	_sync_with_router()
	InputRouter.action_pressed.connect(_on_action)
	InputRouter.devices_changed.connect(_on_devices_changed)
	_refresh()


func _exit_tree() -> void:
	InputRouter.action_pressed.disconnect(_on_action)
	InputRouter.devices_changed.disconnect(_on_devices_changed)


func _process(delta: float) -> void:
	if _flash_left > 0.0:
		_flash_left -= delta
		if _flash_left <= 0.0:
			_refresh_prompt()
	_repeat_held_directions(delta)


func _on_devices_changed() -> void:
	_sync_with_router()
	_refresh()


## Keeps slot kinds and InputRouter slots in agreement (e.g. after a dev match). A pad that
## disconnected keeps its slot during a match so it can rejoin, but here it would block START
## forever (it can never pick or leave), so its slot is freed. If it was in the settings, they
## close (saving any change), or nobody else could get in.
func _sync_with_router() -> void:
	var has_device: Array[bool] = []
	for slot in LobbyState.SLOT_COUNT:
		var device := InputRouter.device_in_slot(slot)
		if device != "" and not InputRouter.is_connected_device(device):
			InputRouter.release_slot(slot)
			device = ""
		has_device.append(device != "")
	_lobby.sync_devices(has_device)
	if _settings_section.is_focused() and _lobby.settings_owner == LobbyState.NONE:
		_close_settings()


func _on_action(device: String, action: StringName) -> void:
	if _starting:
		return
	_flash_left = 0.0  # a message answers the latest press only
	var slot := InputRouter.slot_of(device)
	if slot == -1:
		if action == &"bomb":
			_join(device)
		elif action == &"back" and _lobby.humans().is_empty():
			Scenes.go(Scenes.MENU)
			return
	elif action == &"start":
		if _lobby.can_start():
			_start_match()
			return
		_flash(_waiting_text())
	elif _lobby.cursor_area[slot] == LobbyState.Area.SETTINGS:
		_settings_action(slot, action)
	else:
		_cursor_action(slot, action)
	_refresh()


func _join(device: String) -> void:
	var slot := _lobby.free_slot()
	if slot == LobbyState.NONE:
		_flash("All %d slots are taken" % LobbyState.SLOT_COUNT)
	elif InputRouter.assign_to(device, slot):
		_lobby.add_player(slot)


func _cursor_action(slot: int, action: StringName) -> void:
	if DIRECTIONS.has(action):
		if _lobby.move_cursor(slot, DIRECTIONS[action]):
			if _lobby.cursor_area[slot] == LobbyState.Area.SETTINGS:
				_settings_section.focus(slot)
		elif action == &"right" and _lobby.settings_owner != LobbyState.NONE:
			_flash_settings_busy()  # right only fails at the right edge: the settings are taken
		return
	match action:
		&"bomb":
			var index := _lobby.cursor_index[slot]
			var on_cards := _lobby.cursor_area[slot] == LobbyState.Area.SLOTS
			if _lobby.carrying[slot] != LobbyState.NONE:
				if on_cards:
					_lobby.drop_ai(slot)
				elif not _lobby.place_ai(slot):
					_flash_not_free(index)
			elif on_cards:
				_toggle_slot(index)
			elif not _lobby.claim(slot):
				_flash_not_free(index)
		&"back":
			if _lobby.carrying[slot] != LobbyState.NONE:
				_lobby.drop_ai(slot)
			elif _lobby.has_pick(slot):
				_lobby.unclaim(slot)
			else:
				_lobby.set_off(slot)
				InputRouter.release_slot(slot)
		&"menu":
			var card := _lobby.cursor_index[slot] if _lobby.cursor_area[slot] == LobbyState.Area.SLOTS else LobbyState.NONE
			if card != LobbyState.NONE and _lobby.kinds[card] == LobbyState.Kind.AI:
				_lobby.pick_up_ai(slot, card)
			elif card != LobbyState.NONE and _lobby.kinds[card] == LobbyState.Kind.OFF:
				if _lobby.fill_with_ai() == 0:
					_flash("No empty slots")
			elif _lobby.enter_settings(slot):
				_settings_section.focus(slot)
			else:
				_flash_settings_busy()


func _flash_not_free(portrait: int) -> void:
	var holder := _lobby.claimed_by(portrait)
	_flash("Locked" if LobbyState.is_locked(portrait) else "Taken by P%d" % (holder + 1))


## Cross on a slot card: Off -> Player (a spare connected pad takes it) -> AI Easy / Normal / Hard
## -> Off.
func _toggle_slot(target: int) -> void:
	var spare := InputRouter.spare_pads()
	var kind := _lobby.toggle_slot(target, not spare.is_empty())
	if kind == LobbyState.Kind.PLAYER and _lobby.kinds[target] == LobbyState.Kind.OFF \
			and InputRouter.assign_to(spare[0], target):
		_lobby.add_player(target)


func _settings_action(slot: int, action: StringName) -> void:
	if action == &"menu" or not _settings_section.handle(action):
		_close_settings()
		_lobby.leave_settings(slot)


## The owner is done with the settings: save them if they changed.
func _close_settings() -> void:
	if _settings_section.unfocus():
		GameState.save_settings()


func _start_match() -> void:
	var owner := _lobby.settings_owner
	if owner != LobbyState.NONE:
		_close_settings()
		_lobby.leave_settings(owner)
	_lobby.resolve_picks(_rng)
	_starting = true
	GameState.in_session = true
	Scenes.go(Scenes.MATCH)


## Holding a direction keeps moving: the first step comes from the press itself, then repeats.
func _repeat_held_directions(delta: float) -> void:
	for slot in LobbyState.SLOT_COUNT:
		var device := InputRouter.device_in_slot(slot)
		var action := _held_direction(device) if device != "" else &""
		var state: Dictionary = _repeat.get(slot, {})
		if action == &"":
			_repeat.erase(slot)
		elif state.get("action", &"") != action:
			_repeat[slot] = {"action": action, "time": 0.0}
		else:
			state.time += delta
			if state.time >= REPEAT_DELAY:
				state.time -= REPEAT_INTERVAL
				_on_action(device, action)


func _held_direction(device: String) -> StringName:
	for action: StringName in DIRECTIONS:
		if InputRouter.is_held(device, action):
			return action
	return &""


func _flash(text: String) -> void:
	_flash_text = text
	_flash_left = FLASH_SECONDS
	_refresh_prompt()


func _flash_settings_busy() -> void:
	_flash("P%d is changing the settings" % (_lobby.settings_owner + 1))


func _waiting_text() -> String:
	var waiting: Array[String] = []
	for slot in _lobby.humans():
		if not _lobby.has_pick(slot):
			waiting.append("P%d" % (slot + 1))
	return "Waiting for %s to pick" % ", ".join(waiting)


# --- UI ----------------------------------------------------------------------

func _build_ui() -> void:
	UI.add_background(self)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	add_child(margin)
	var split := HBoxContainer.new()
	split.add_theme_constant_override("separation", 16)
	margin.add_child(split)

	# Left two thirds: portraits, slots, prompt.
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 2.0
	left.alignment = BoxContainer.ALIGNMENT_CENTER
	left.add_theme_constant_override("separation", 12)
	split.add_child(left)

	var title_row := HBoxContainer.new()
	title_row.add_child(UI.title("VERSUS", 44))
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(gap)
	title_row.add_child(UI.label("Stage: %s" % GameState.level.display_name, 18, UI.DIM, 4))
	left.add_child(title_row)

	var portrait_rows: Array[HBoxContainer] = [HBoxContainer.new(), HBoxContainer.new()]
	var grid := VBoxContainer.new()
	grid.add_theme_constant_override("separation", 8)
	left.add_child(grid)
	for row in portrait_rows:
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 8)
		grid.add_child(row)
	for portrait in LobbyState.PORTRAIT_COUNT:
		var tile := PortraitTile.new(portrait)
		portrait_rows[LobbyState.portrait_row(portrait)].add_child(tile)
		_tiles.append(tile)

	var card_row := HBoxContainer.new()
	card_row.alignment = BoxContainer.ALIGNMENT_CENTER
	card_row.add_theme_constant_override("separation", 8)
	left.add_child(card_row)
	for slot in LobbyState.SLOT_COUNT:
		var card := SlotCard.new(slot)
		card_row.add_child(card)
		_cards.append(card)

	_prompt = UI.label("", 26, UI.ACCENT, 8)
	left.add_child(_prompt)
	left.add_child(UI.label(HINTS, 13, UI.DIM, 4))

	# Right third: settings.
	_settings_section = SettingsSection.new()
	_settings_section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_settings_section.size_flags_stretch_ratio = 1.0
	split.add_child(_settings_section)
	_settings_section.setup(GameState.settings)


func _refresh() -> void:
	for portrait in LobbyState.PORTRAIT_COUNT:
		var claimed: Array = []
		if portrait == LobbyState.RANDOM:
			claimed = _lobby.random_pickers()
		elif _lobby.claimed_by(portrait) != LobbyState.NONE:
			claimed = [_lobby.claimed_by(portrait)]
		_tiles[portrait].show_state(claimed, _lobby.cursors_on(LobbyState.Area.PORTRAITS, portrait), _carried())

	var spare_pad := not InputRouter.spare_pads().is_empty()
	for slot in LobbyState.SLOT_COUNT:
		var kind := _lobby.kinds[slot]
		var device := ""
		var hint := ""
		match kind:
			LobbyState.Kind.PLAYER:
				device = InputRouter.device_label(InputRouter.device_in_slot(slot))
			LobbyState.Kind.AI:
				device = "Computer, %s" % BomberAI.LEVEL_NAMES[_lobby.ai_levels[slot]]
				hint = ("Cross: harder" if _lobby.ai_levels[slot] < BomberAI.Level.HARD else "Cross: turn off") \
					+ "\nTriangle: pick"
			LobbyState.Kind.OFF:
				hint = ("Cross: add player" if spare_pad else "Cross: add AI") + "\nTriangle: fill"
		_cards[slot].show_state({
			"kind": kind,
			"pick": _lobby.picks[slot],
			"device": device,
			"cursors": _lobby.cursors_on(LobbyState.Area.SLOTS, slot),
			"carried": _carried(),
			"hint": hint,
		})
	_refresh_prompt()


## Human slot -> AI slot whose token its cursor carries.
func _carried() -> Dictionary:
	var carried := {}
	for slot in LobbyState.SLOT_COUNT:
		if _lobby.carrying[slot] != LobbyState.NONE:
			carried[slot] = _lobby.carrying[slot]
	return carried


func _refresh_prompt() -> void:
	var color := UI.ACCENT
	var carriers := _carried()
	if _flash_left > 0.0:
		_prompt.text = _flash_text
		color = WARN
	elif not carriers.is_empty():
		var slot: int = carriers.keys()[0]
		_prompt.text = "P%d: pick a bomber for P%d (Cross), Back to cancel" % [slot + 1, carriers[slot] + 1]
	elif _lobby.humans().is_empty():
		_prompt.text = "Press Cross / Space / Enter to join     (Back: main menu)"
	elif not _lobby.can_start():
		_prompt.text = _waiting_text()
	elif _lobby.is_practice():
		_prompt.text = "Press START for practice"
	else:
		_prompt.text = "Press START to fight!"
	_prompt.add_theme_color_override("font_color", color)
