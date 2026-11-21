extends CanvasLayer
## Pause overlay for a running match: RESUME or QUIT TO LOBBY. Keeps working while the tree is
## paused. Back resumes.

signal resume_requested
signal quit_requested

var _navigator: MenuNavigator


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_CENTER)
	column.grow_horizontal = Control.GROW_DIRECTION_BOTH
	column.grow_vertical = Control.GROW_DIRECTION_BOTH
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 16)
	add_child(column)

	column.add_child(UI.title("PAUSED", 72))
	var resume := UI.button("RESUME")
	resume.pressed.connect(resume_requested.emit)
	var quit := UI.button("QUIT TO LOBBY")
	quit.pressed.connect(quit_requested.emit)
	var buttons: Array[Button] = [resume, quit]
	for b in buttons:
		b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		column.add_child(b)

	_navigator = MenuNavigator.new(buttons)
	_navigator.back_pressed.connect(resume_requested.emit)
	add_child(_navigator)
	close()


func open() -> void:
	visible = true
	_navigator.active = true
	_navigator.focus_first()


func close() -> void:
	visible = false
	_navigator.active = false
