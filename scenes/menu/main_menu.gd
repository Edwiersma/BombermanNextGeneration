extends Control
## Title screen: VERSUS, CONTROLLERS (pad tester), OPTIONS (Phase 2), QUIT (desktop only).
## Any pad or keyboard drives it: up/down + Cross / Space / Enter.

var _navigator: MenuNavigator


func _ready() -> void:
	GameState.end_session()  # coming back here clears the lobby and device slots
	UI.add_background(self)

	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_CENTER)
	column.grow_horizontal = Control.GROW_DIRECTION_BOTH
	column.grow_vertical = Control.GROW_DIRECTION_BOTH
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 14)
	add_child(column)

	column.add_child(UI.title("BOMBERMAN"))
	column.add_child(UI.label("NEXT GENERATION", 34, Color.WHITE, 8))
	column.add_child(_spacer(40))

	var versus := UI.button("VERSUS")
	versus.pressed.connect(func(): Scenes.go(Scenes.LOBBY))
	var controllers := UI.button("CONTROLLERS")
	controllers.pressed.connect(func(): Scenes.go(Scenes.CONTROLLER_TEST))
	var options := UI.button("OPTIONS  (PHASE 2)")
	options.disabled = true
	var quit := UI.button("QUIT")
	quit.pressed.connect(func(): get_tree().quit())
	quit.visible = not OS.has_feature("web")  # a web page cannot close itself

	var buttons: Array[Button] = [versus, controllers, options, quit]
	for b in buttons:
		b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		column.add_child(b)

	var footer := UI.label("Move: D-pad / stick / arrows / WASD      Select: Cross / Space / Enter\n"
		+ "Press a button on each controller so the browser can see it.", 18, UI.DIM, 4)
	footer.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	footer.grow_horizontal = Control.GROW_DIRECTION_BOTH
	footer.grow_vertical = Control.GROW_DIRECTION_BEGIN
	footer.position.y -= 24
	add_child(footer)

	_navigator = MenuNavigator.new(buttons)
	add_child(_navigator)


func _spacer(height: float) -> Control:
	var spacer := Control.new()
	spacer.custom_minimum_size.y = height
	return spacer
