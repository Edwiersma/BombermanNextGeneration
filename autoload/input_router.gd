extends Node
## Maps physical input devices to player slots and exposes per-device virtual actions.
##
## Device ids:
##   "kb0"  keyboard, WASD + Space
##   "kb1"  keyboard, arrow keys + Enter
##   "padN" Godot joypad index N (PlayStation pads via the browser Gamepad API)
##   "aiN"  virtual controller of the AI player in slot N (1-6): code sets what it holds
##
## Menus and gameplay read input only through this node, never from raw devices.
## That keeps the door open for AI or network players later.

signal action_pressed(device_id: String, action: StringName)
signal action_released(device_id: String, action: StringName)
signal devices_changed
signal slots_changed

const MAX_SLOTS := 6
const STICK_DEADZONE := 0.5

const ACTIONS := [&"up", &"down", &"left", &"right", &"bomb", &"special", &"back", &"start", &"menu"]

const KEYBOARD_LAYOUTS := {
	"kb0": {
		&"up": KEY_W, &"down": KEY_S, &"left": KEY_A, &"right": KEY_D,
		&"bomb": KEY_SPACE, &"special": KEY_E, &"back": KEY_ESCAPE, &"start": KEY_TAB, &"menu": KEY_Q,
	},
	"kb1": {
		&"up": KEY_UP, &"down": KEY_DOWN, &"left": KEY_LEFT, &"right": KEY_RIGHT,
		&"bomb": KEY_ENTER, &"special": KEY_SHIFT, &"back": KEY_BACKSPACE, &"start": KEY_P, &"menu": KEY_DELETE,
	},
}

const KEYBOARD_LABELS := {
	"kb0": "Keyboard (WASD + Space)",
	"kb1": "Keyboard (Arrows + Enter)",
}

## PlayStation layout: Cross = bomb, Circle = special / back, Options = start, Triangle = menu.
## Godot maps the browser's "standard" gamepad layout onto these JoyButton values.
const PAD_BUTTONS := {
	&"up": [JOY_BUTTON_DPAD_UP],
	&"down": [JOY_BUTTON_DPAD_DOWN],
	&"left": [JOY_BUTTON_DPAD_LEFT],
	&"right": [JOY_BUTTON_DPAD_RIGHT],
	&"bomb": [JOY_BUTTON_A],
	&"special": [JOY_BUTTON_B],
	&"back": [JOY_BUTTON_B],
	&"start": [JOY_BUTTON_START],
	&"menu": [JOY_BUTTON_Y],
}

## Sony USB product ids, as they appear in the browser's gamepad id string.
const SONY_PRODUCTS := {
	"0ce6": "DualSense",
	"0df2": "DualSense Edge",
	"05c4": "DualShock 4",
	"09cc": "DualShock 4",
	"0ba0": "DualShock 4 (wireless adapter)",
}

## Slot index -> device id ("" = free). A disconnected pad keeps its slot so it
## gets its player back when it reconnects.
var slots: Array[String] = []

var _devices: Array[String] = []
## Virtual controllers (AI players): device id -> {action: bool} set by code, reported like a
## real controller's state on the next tick.
var _virtual := {}
var _held := {}  # device id -> {action: bool}
## Presses seen as events since the last tick. Polling alone misses a tap that is
## pressed and released between two ticks; a latched press counts as held for one tick.
var _latched := {}  # device id -> {action: true}


## Godot's built-in UI actions. Menus are driven through this router instead (MenuNavigator),
## so these are cleared to stop arrow keys / Enter / pad buttons acting twice.
const GODOT_UI_ACTIONS := [&"ui_accept", &"ui_select", &"ui_cancel", &"ui_up", &"ui_down",
	&"ui_left", &"ui_right", &"ui_focus_next", &"ui_focus_prev"]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for action in GODOT_UI_ACTIONS:
		if InputMap.has_action(action):
			InputMap.action_erase_events(action)
	slots.resize(MAX_SLOTS)
	slots.fill("")
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	_refresh_devices()


func _physics_process(_delta: float) -> void:
	# Autoloads run before scene nodes, so state is fresh for gameplay each tick.
	for device in _devices:
		_update_device(device)
	for device: String in _virtual.keys():
		_update_device(device)
	_latched.clear()


func _update_device(device: String) -> void:
	var before: Dictionary = _held.get(device, {})
	var now := _read_device(device)
	for action in _latched.get(device, {}):
		now[action] = true
	_held[device] = now
	for action in ACTIONS:
		var was_held: bool = before.get(action, false)
		var held_now: bool = now[action]
		if held_now and not was_held:
			action_pressed.emit(device, action)
		elif was_held and not held_now:
			action_released.emit(device, action)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key: Key = event.physical_keycode
		for device in KEYBOARD_LAYOUTS:
			var layout: Dictionary = KEYBOARD_LAYOUTS[device]
			for action in ACTIONS:
				if layout[action] == key:
					_latch(device, action)
	elif event is InputEventJoypadButton and event.pressed:
		var device := "pad%d" % event.device
		for action in ACTIONS:
			if event.button_index in PAD_BUTTONS[action]:
				_latch(device, action)


# --- Devices -----------------------------------------------------------------

func get_devices() -> Array[String]:
	return _devices


func is_pad(device: String) -> bool:
	return device.begins_with("pad")


func pad_index(device: String) -> int:
	return int(device.substr(3)) if is_pad(device) else -1


func is_connected_device(device: String) -> bool:
	return device in _devices


func device_label(device: String) -> String:
	if is_pad(device):
		var id := pad_index(device)
		var label := pad_model(id) if is_connected_device(device) else "disconnected"
		return "Pad %d: %s" % [id, label]
	return KEYBOARD_LABELS.get(device, device)


## Human-readable pad model. On the web Godot reports every pad as
## "Standard Gamepad Mapping", so read the browser's own id string instead.
func pad_model(id: int) -> String:
	var raw := Input.get_joy_name(id)
	if OS.has_feature("web"):
		var browser_id = JavaScriptBridge.eval(
			"(function(){var p=navigator.getGamepads()[%d];return p?p.id:'';})()" % id)
		if browser_id is String and browser_id != "":
			raw = browser_id
	var lower := raw.to_lower()
	if "054c" in lower:
		for product in SONY_PRODUCTS:
			if product in lower:
				return SONY_PRODUCTS[product]
	return raw


func is_held(device: String, action: StringName) -> bool:
	return _held.get(device, {}).get(action, false)


## Held directions as a vector (x right, y down). Can be diagonal; movement code
## decides how to resolve it to 4-way motion.
func get_direction(device: String) -> Vector2i:
	var dir := Vector2i.ZERO
	if is_held(device, &"left"):
		dir.x -= 1
	if is_held(device, &"right"):
		dir.x += 1
	if is_held(device, &"up"):
		dir.y -= 1
	if is_held(device, &"down"):
		dir.y += 1
	return dir


# --- Virtual controllers (AI) --------------------------------------------------

## Device id of the AI player in `slot`.
static func ai_device(slot: int) -> String:
	return "ai%d" % (slot + 1)


func add_virtual_device(device: String) -> void:
	_virtual[device] = {}


func remove_virtual_device(device: String) -> void:
	_virtual.erase(device)
	_held.erase(device)


func is_virtual(device: String) -> bool:
	return _virtual.has(device)


## What the virtual controller holds from the next tick on: {action: true}. Missing = released.
func set_virtual_actions(device: String, held: Dictionary) -> void:
	if _virtual.has(device):
		_virtual[device] = held


# --- Slots -------------------------------------------------------------------

## Puts the device in the first free slot. Returns the slot, or -1 if full.
func assign_slot(device: String) -> int:
	var existing := slot_of(device)
	if existing != -1:
		return existing
	for i in MAX_SLOTS:
		if slots[i] == "":
			slots[i] = device
			slots_changed.emit()
			return i
	return -1


## Puts the device in a specific slot (the versus screen decides which). False if it is taken.
func assign_to(device: String, slot: int) -> bool:
	if slot < 0 or slot >= MAX_SLOTS or (slots[slot] != "" and slots[slot] != device):
		return false
	var existing := slot_of(device)
	if existing != -1:
		slots[existing] = ""
	slots[slot] = device
	slots_changed.emit()
	return true


## Connected pads that are not in a slot yet.
func spare_pads() -> Array[String]:
	var pads: Array[String] = []
	for device in _devices:
		if is_pad(device) and slot_of(device) == -1:
			pads.append(device)
	return pads


func release_slot(slot: int) -> void:
	if slot >= 0 and slot < MAX_SLOTS and slots[slot] != "":
		slots[slot] = ""
		slots_changed.emit()


func release_all() -> void:
	slots.fill("")
	slots_changed.emit()


func slot_of(device: String) -> int:
	return slots.find(device)


func device_in_slot(slot: int) -> String:
	return slots[slot]


func joined_count() -> int:
	return MAX_SLOTS - slots.count("")


# --- Internals ---------------------------------------------------------------

func _refresh_devices() -> void:
	var list: Array[String] = ["kb0", "kb1"]
	for id in Input.get_connected_joypads():
		list.append("pad%d" % id)
	_devices = list
	for device in _held.keys():
		if device not in list:
			_held.erase(device)
	devices_changed.emit()


func _latch(device: String, action: StringName) -> void:
	if not _latched.has(device):
		_latched[device] = {}
	_latched[device][action] = true


func _on_joy_connection_changed(_device: int, _connected: bool) -> void:
	_refresh_devices()


func _read_device(device: String) -> Dictionary:
	var state := {}
	if _virtual.has(device):
		var held: Dictionary = _virtual[device]
		for action in ACTIONS:
			state[action] = held.get(action, false)
	elif is_pad(device):
		var id := pad_index(device)
		for action in ACTIONS:
			var pressed := false
			for button in PAD_BUTTONS[action]:
				if Input.is_joy_button_pressed(id, button):
					pressed = true
			state[action] = pressed
		var x := Input.get_joy_axis(id, JOY_AXIS_LEFT_X)
		var y := Input.get_joy_axis(id, JOY_AXIS_LEFT_Y)
		if x <= -STICK_DEADZONE:
			state[&"left"] = true
		if x >= STICK_DEADZONE:
			state[&"right"] = true
		if y <= -STICK_DEADZONE:
			state[&"up"] = true
		if y >= STICK_DEADZONE:
			state[&"down"] = true
	else:
		var layout: Dictionary = KEYBOARD_LAYOUTS[device]
		for action in ACTIONS:
			state[action] = Input.is_physical_key_pressed(layout[action])
	return state
