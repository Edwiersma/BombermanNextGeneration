class_name MenuNavigator
extends Node
## Drives a vertical list of Buttons from any input device through InputRouter: up/down moves
## the focus, bomb (Cross / Space / Enter) presses the focused button, back emits back_pressed.
## Godot's built-in ui_* navigation is switched off by InputRouter, so this is the only path
## (the mouse still works as usual). Add it as a child of the menu it drives.

signal back_pressed

var buttons: Array[Button] = []
var active := true


func _init(menu_buttons: Array[Button] = []) -> void:
	buttons = menu_buttons
	process_mode = Node.PROCESS_MODE_ALWAYS  # also works in the pause menu


func _ready() -> void:
	InputRouter.action_pressed.connect(_on_action)
	focus_first.call_deferred()


func _exit_tree() -> void:
	if InputRouter.action_pressed.is_connected(_on_action):
		InputRouter.action_pressed.disconnect(_on_action)


func focus_first() -> void:
	for b in buttons:
		if _usable(b):
			b.grab_focus()
			return


func _on_action(device: String, action: StringName) -> void:
	if not active or not is_inside_tree() or InputRouter.is_virtual(device):
		return  # AI controllers never drive menus (e.g. the pause menu)
	match action:
		&"up":
			_move(-1)
		&"down":
			_move(1)
		&"bomb":
			var focused := _focused()
			if focused:
				focused.pressed.emit()
		&"back":
			back_pressed.emit()


func _move(step: int) -> void:
	var usable: Array[Button] = buttons.filter(_usable)
	if usable.is_empty():
		return
	var index := usable.find(_focused())
	var next := 0 if index == -1 else posmod(index + step, usable.size())
	usable[next].grab_focus()


func _focused() -> Button:
	for b in buttons:
		if b.has_focus():
			return b
	return null


func _usable(b: Button) -> bool:
	return is_instance_valid(b) and b.is_visible_in_tree() and not b.disabled
