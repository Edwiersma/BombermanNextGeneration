extends Control
## Match results: the winner, then every player's round wins. REMATCH keeps the same players
## and colours, LOBBY goes back to change them, MAIN MENU ends the session.

var _navigator: MenuNavigator


func _ready() -> void:
	UI.add_background(self)
	var results: Dictionary = GameState.last_results
	var wins: Dictionary = results.get("wins", {})
	var winner: int = results.get("winner", -1)

	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_CENTER)
	column.grow_horizontal = Control.GROW_DIRECTION_BOTH
	column.grow_vertical = Control.GROW_DIRECTION_BOTH
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 16)
	add_child(column)

	if winner != -1:
		column.add_child(UI.label("%s WINS!" % GameState.color_name(winner).to_upper(), 84, GameState.color_of(winner), 16))
	else:
		column.add_child(UI.title("RESULTS"))
	column.add_child(UI.label("%d rounds played" % results.get("rounds", 0), 22, UI.DIM))

	var slots: Array = wins.keys()
	slots.sort_custom(func(a, b): return wins[a] > wins[b] or (wins[a] == wins[b] and a < b))
	for slot: int in slots:
		column.add_child(_result_row(slot, wins[slot], slot == winner))

	var spacer := Control.new()
	spacer.custom_minimum_size.y = 24
	column.add_child(spacer)

	var rematch := UI.button("REMATCH")
	rematch.pressed.connect(func(): Scenes.go(Scenes.MATCH))
	var lobby := UI.button("LOBBY")
	lobby.pressed.connect(func(): Scenes.go(Scenes.LOBBY))
	var menu := UI.button("MAIN MENU")
	menu.pressed.connect(func(): Scenes.go(Scenes.MENU))
	var buttons: Array[Button] = [rematch, lobby, menu]
	for b in buttons:
		b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		column.add_child(b)

	_navigator = MenuNavigator.new(buttons)
	_navigator.back_pressed.connect(func(): Scenes.go(Scenes.LOBBY))
	add_child(_navigator)


func _result_row(slot: int, wins: int, is_winner: bool) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(520, 0)
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var border := GameState.color_of(slot) if is_winner else UI.PANEL
	panel.add_theme_stylebox_override("panel", UI.panel_style(UI.PANEL, 14, 4, border))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	panel.add_child(row)

	var swatch := Panel.new()
	swatch.custom_minimum_size = Vector2(44, 44)
	swatch.add_theme_stylebox_override("panel", UI.panel_style(GameState.color_of(slot), 22, 3, Color.BLACK))
	row.add_child(swatch)

	var name_label := UI.label(GameState.color_name(slot).to_upper(), 30)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)

	var wins_label := UI.label("%d %s" % [wins, "win" if wins == 1 else "wins"], 30, UI.ACCENT if is_winner else Color.WHITE)
	row.add_child(wins_label)
	return panel
