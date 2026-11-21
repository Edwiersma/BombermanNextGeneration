extends "res://tests/test_suite.gd"
## The lobby scene with InputRouter and GameState (both autoloads; cleaned up after each test).

const LOBBY_SCENE := preload("res://scenes/menu/lobby.tscn")


func _open_lobby() -> Control:
	var lobby: Control = LOBBY_SCENE.instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(lobby)
	return lobby


func _cleanup(lobby: Control) -> void:
	lobby.free()
	GameState.lobby.reset()
	InputRouter.release_all()


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
