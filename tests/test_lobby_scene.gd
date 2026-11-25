extends "res://tests/test_suite.gd"
## The versus screen with InputRouter and GameState (both autoloads; cleaned up after each test).

const LOBBY_SCENE := preload("res://scenes/menu/lobby.tscn")
const TEST_SETTINGS_PATH := "user://test_lobby_settings.cfg"
const S := preload("res://scripts/core/lobby_state.gd")


func _open_lobby() -> Control:
	GameState.settings = MatchSettings.new()
	GameState.settings_path = TEST_SETTINGS_PATH
	var lobby: Control = LOBBY_SCENE.instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(lobby)
	return lobby


func _cleanup(lobby: Control) -> void:
	lobby.free()
	GameState.lobby.reset()
	InputRouter.release_all()
	GameState.settings = MatchSettings.new()
	GameState.settings_path = MatchSettings.SAVE_PATH
	DirAccess.remove_absolute(TEST_SETTINGS_PATH)


func _press(lobby: Control, device: String, actions: Array) -> void:
	for action: StringName in actions:
		lobby._on_action(device, action)


func test_disconnected_pad_is_dropped_from_the_lobby() -> void:
	InputRouter.release_all()
	InputRouter.assign_to("kb0", 0)
	InputRouter.assign_to("pad7", 1)  # no such pad connected (e.g. battery died mid-match)
	var lobby := _open_lobby()
	check_eq(InputRouter.slot_of("pad7"), -1, "dead pad's slot freed")
	check_eq(GameState.lobby.kinds[1], S.Kind.OFF, "its slot is off")
	check_eq(GameState.lobby.kinds[0], S.Kind.PLAYER, "keyboard player kept")
	_cleanup(lobby)


func test_join_pick_and_start() -> void:
	InputRouter.release_all()
	var lobby := _open_lobby()
	_press(lobby, "kb0", [&"bomb"])  # joins
	check_eq(InputRouter.slot_of("kb0"), 0, "first slot")
	check_eq(GameState.lobby.kinds[0], S.Kind.PLAYER, "a player")
	check_eq([GameState.lobby.cursor_area[0], GameState.lobby.cursor_index[0]], [S.Area.PORTRAITS, 0], "cursor on the grid")
	check(not GameState.lobby.has_pick(0), "the join press does not also pick")
	_press(lobby, "kb1", [&"bomb"])
	check_eq(InputRouter.slot_of("kb1"), 1, "next slot")
	_press(lobby, "kb0", [&"bomb"])  # white
	check(not GameState.lobby.can_start(), "P2 still choosing")
	check("P2" in lobby._prompt.text, "prompt says who: %s" % lobby._prompt.text)
	_press(lobby, "kb1", [&"left", &"bomb"])  # white is P1's
	check(not GameState.lobby.has_pick(1), "taken")
	check("Taken by P1" in lobby._prompt.text, "told why: %s" % lobby._prompt.text)
	_press(lobby, "kb1", [&"right", &"right", &"bomb"])  # red
	check_eq(GameState.lobby.picks[1], 2, "red")
	check(GameState.lobby.can_start(), "ready")
	check("START" in lobby._prompt.text, "prompt: %s" % lobby._prompt.text)
	_cleanup(lobby)


func test_back_drops_the_pick_then_leaves() -> void:
	InputRouter.release_all()
	var lobby := _open_lobby()
	_press(lobby, "kb0", [&"bomb", &"bomb"])
	_press(lobby, "kb0", [&"back"])
	check(not GameState.lobby.has_pick(0) and GameState.lobby.is_human(0), "pick dropped, still in")
	_press(lobby, "kb0", [&"back"])
	check_eq(GameState.lobby.kinds[0], S.Kind.OFF, "left")
	check_eq(InputRouter.slot_of("kb0"), -1, "slot released")
	_cleanup(lobby)


func test_slot_cards_toggle_off_and_ai() -> void:
	InputRouter.release_all()
	var lobby := _open_lobby()
	_press(lobby, "kb0", [&"bomb", &"down", &"down"])  # join, then down to the slot row
	check_eq([GameState.lobby.cursor_area[0], GameState.lobby.cursor_index[0]], [S.Area.SLOTS, 0], "on own slot")
	_press(lobby, "kb0", [&"bomb"])
	check_eq(GameState.lobby.kinds[0], S.Kind.PLAYER, "own slot does not toggle")
	_press(lobby, "kb0", [&"right", &"bomb"])
	check_eq(GameState.lobby.kinds[1], S.Kind.AI, "slot 2 -> AI")
	_press(lobby, "kb1", [&"bomb"])
	check_eq(InputRouter.slot_of("kb1"), 2, "a new controller skips the AI slot")
	_press(lobby, "kb0", [&"bomb"])
	check_eq(GameState.lobby.kinds[1], S.Kind.OFF, "AI -> off")
	_cleanup(lobby)


func test_no_joins_after_start_is_accepted() -> void:
	InputRouter.release_all()
	var lobby := _open_lobby()
	_press(lobby, "kb0", [&"bomb", &"bomb", &"start"])  # join, pick, start (scene change is deferred)
	check(GameState.in_session, "started")
	_press(lobby, "kb1", [&"bomb"])  # same frame: would join
	check_eq(InputRouter.slot_of("kb1"), -1, "late join ignored")
	GameState.in_session = false
	_cleanup(lobby)


func test_start_with_ai_settles_random_colours() -> void:
	InputRouter.release_all()
	var lobby := _open_lobby()
	_press(lobby, "kb0", [&"bomb", &"bomb", &"down", &"down", &"right", &"bomb"])  # white, slot 2 AI
	_press(lobby, "kb0", [&"start"])
	var resolved := GameState.lobby.resolved
	check_eq(resolved[0], 0, "P1 white")
	check(resolved[1] > 0 and resolved[1] < Palette.PLAYER_COLORS.size(), "AI got another colour: %d" % resolved[1])
	GameState.in_session = false
	_cleanup(lobby)


func test_settings_by_moving_right_one_player_at_a_time() -> void:
	InputRouter.release_all()
	var lobby := _open_lobby()
	_press(lobby, "kb0", [&"bomb"])
	_press(lobby, "kb1", [&"bomb"])
	_press(lobby, "kb0", [&"right", &"right", &"right", &"right", &"right", &"right", &"right"])
	check_eq(GameState.lobby.settings_owner, 0, "P1 moved past the top row into the settings")
	check(lobby._settings_section.is_focused(), "section focused")
	_press(lobby, "kb1", [&"right", &"right", &"right", &"right", &"right", &"right"])
	check_eq(GameState.lobby.cursor_area[1], S.Area.PORTRAITS, "P2 kept out")
	check("P1 is changing the settings" in lobby._prompt.text, "told why: %s" % lobby._prompt.text)
	_press(lobby, "kb0", [&"right", &"right"])  # edit the first row (wins needed), 3 -> 4
	check_eq(GameState.settings.wins_to_win, 4, "changed")
	_press(lobby, "kb0", [&"left"])
	check_eq(GameState.settings.wins_to_win, 3, "left changes while editing")
	_press(lobby, "kb0", [&"right", &"bomb"])  # 4, done
	check(not lobby._settings_section.editing, "done editing")
	_press(lobby, "kb0", [&"left"])  # leaves
	check_eq([GameState.lobby.cursor_area[0], GameState.lobby.cursor_index[0]], [S.Area.PORTRAITS, 6], "back on the grid")
	check_eq(GameState.lobby.settings_owner, S.NONE, "free")
	check_eq(MatchSettings.load_or_default(TEST_SETTINGS_PATH).wins_to_win, 4, "saved on the way out")
	check(GameState.lobby.move_cursor(1, Vector2i.RIGHT), "P2 can get in now")
	_cleanup(lobby)


func test_leaving_settings_without_changes_saves_nothing() -> void:
	InputRouter.release_all()
	var lobby := _open_lobby()
	_press(lobby, "kb0", [&"bomb", &"menu", &"down", &"back"])  # Triangle shortcut in, Back out
	check_eq(GameState.lobby.cursor_area[0], S.Area.PORTRAITS, "out again")
	check(not FileAccess.file_exists(TEST_SETTINGS_PATH), "nothing saved")
	_cleanup(lobby)


func test_settings_free_up_when_their_pad_disconnects() -> void:
	# The section only listens to its owner: if that pad goes away, the settings must open up again.
	InputRouter.release_all()
	var lobby := _open_lobby()
	_press(lobby, "kb0", [&"bomb", &"menu"])
	check_eq(GameState.lobby.settings_owner, 0, "in")
	InputRouter.slots[0] = "pad9"  # as if slot 1 were a pad that just vanished
	lobby._on_devices_changed()
	check_eq(GameState.lobby.kinds[0], S.Kind.OFF, "its slot is off")
	check(not lobby._settings_section.is_focused(), "section released")
	_press(lobby, "kb1", [&"bomb", &"menu"])
	check_eq(GameState.lobby.settings_owner, 0, "the next player (now in slot 1) can use them")
	_cleanup(lobby)
