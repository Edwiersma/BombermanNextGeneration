extends "res://tests/test_suite.gd"
## The lobby scene with InputRouter and GameState (both autoloads; cleaned up after each test).

const LOBBY_SCENE := preload("res://scenes/menu/lobby.tscn")


const TEST_SETTINGS_PATH := "user://test_lobby_settings.cfg"


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


func test_disconnected_pad_is_dropped_from_the_lobby() -> void:
	InputRouter.release_all()
	InputRouter.assign_slot("kb0")
	InputRouter.assign_slot("pad7")  # no such pad connected (e.g. battery died mid-match)
	GameState.lobby.join(0)
	GameState.lobby.join(1)
	var lobby := _open_lobby()
	check_eq(InputRouter.slot_of("pad7"), -1, "dead pad's slot freed")
	check(not GameState.lobby.is_joined(1), "dead pad left the lobby")
	check(GameState.lobby.is_joined(0), "keyboard player kept")
	GameState.lobby.set_ready(0, true)
	check(GameState.lobby.can_start(), "the rest can start")
	_cleanup(lobby)


func test_no_joins_after_start_is_accepted() -> void:
	InputRouter.release_all()
	InputRouter.assign_slot("kb0")
	var lobby := _open_lobby()
	lobby._on_action("kb0", &"bomb")   # ready
	lobby._on_action("kb0", &"start")  # starts (scene change is deferred)
	lobby._on_action("kb1", &"bomb")   # same frame: would join
	check_eq(InputRouter.slot_of("kb1"), -1, "late join ignored")
	(Engine.get_main_loop() as SceneTree).paused = false
	GameState.in_session = false
	_cleanup(lobby)


func test_settings_panel_changes_and_saves() -> void:
	InputRouter.release_all()
	InputRouter.assign_slot("kb0")
	InputRouter.assign_slot("kb1")
	var lobby := _open_lobby()
	lobby._on_action("kb1", &"bomb")     # player 2 ready
	lobby._on_action("kb0", &"menu")     # player 1 opens settings
	check(lobby._settings_panel.visible, "panel open")
	lobby._on_action("kb1", &"right")    # not the owner: ignored
	lobby._on_action("kb0", &"right")    # wins needed 3 -> 4
	check_eq(GameState.settings.wins_to_win, 4, "owner changed wins needed")
	lobby._on_action("kb0", &"back")     # done
	check(not lobby._settings_panel.visible, "panel closed")
	check(not GameState.lobby.ready[1], "everyone un-readied after a change")
	check_eq(MatchSettings.load_or_default(TEST_SETTINGS_PATH).wins_to_win, 4, "saved")
	check("First to 4" in lobby._summary.text, "summary updated: %s" % lobby._summary.text)
	_cleanup(lobby)


func test_closing_without_changes_keeps_ready() -> void:
	InputRouter.release_all()
	InputRouter.assign_slot("kb0")
	var lobby := _open_lobby()
	lobby._on_action("kb0", &"bomb")     # ready
	lobby._on_action("kb0", &"menu")
	lobby._on_action("kb0", &"down")
	lobby._on_action("kb0", &"menu")     # close again, nothing changed
	check(GameState.lobby.ready[0], "still ready")
	check(not FileAccess.file_exists(TEST_SETTINGS_PATH), "nothing saved")
	_cleanup(lobby)


func test_settings_panel_closes_when_its_pad_disconnects() -> void:
	# Review fix: the panel only listens to the device that opened it.
	InputRouter.release_all()
	InputRouter.assign_slot("kb0")
	var lobby := _open_lobby()
	lobby._on_action("kb0", &"menu")
	lobby._settings_panel.owner_device = "pad9"  # as if a pad had opened it and then vanished
	lobby._on_devices_changed()
	check(not lobby._settings_panel.visible, "closed")
	lobby._on_action("kb0", &"bomb")
	check(GameState.lobby.ready[0], "the lobby responds again")
	_cleanup(lobby)
