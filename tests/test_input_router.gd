extends "res://tests/test_suite.gd"
## InputRouter slot bookkeeping (the autoload instance; every test leaves the slots empty).


func _router() -> Node:
	InputRouter.release_all()
	return InputRouter


func test_slots_fill_in_order() -> void:
	var router := _router()
	check_eq(router.assign_slot("kb1"), 0, "first device gets slot 0")
	check_eq(router.assign_slot("pad0"), 1, "second gets slot 1")
	check_eq(router.slot_of("pad0"), 1, "lookup by device")
	check_eq(router.device_in_slot(0), "kb1", "lookup by slot")
	check_eq(router.joined_count(), 2, "joined count")
	router.release_all()


func test_same_device_keeps_its_slot() -> void:
	var router := _router()
	router.assign_slot("kb0")
	check_eq(router.assign_slot("kb0"), 0, "joining twice returns the same slot")
	check_eq(router.joined_count(), 1, "still one player")
	router.release_all()


func test_full_lobby_refuses_a_seventh_device() -> void:
	var router := _router()
	for device in ["kb0", "kb1", "pad0", "pad1", "pad2", "pad3"]:
		router.assign_slot(device)
	check_eq(router.assign_slot("pad4"), -1, "no seventh slot")
	router.release_all()


func test_assign_to_a_given_slot() -> void:
	var router := _router()
	check(router.assign_to("kb1", 3), "placed")
	check_eq(router.slot_of("kb1"), 3, "in slot 4")
	check(not router.assign_to("kb0", 3), "taken")
	check(router.assign_to("kb1", 5), "moves")
	check_eq(router.device_in_slot(3), "", "old slot freed")
	router.release_all()


func test_release_frees_the_slot_for_the_next_device() -> void:
	var router := _router()
	router.assign_slot("kb0")
	router.assign_slot("kb1")
	router.release_slot(0)
	check_eq(router.slot_of("kb0"), -1, "released")
	check_eq(router.assign_slot("pad3"), 0, "first free slot reused")
	router.release_all()


func test_device_helpers() -> void:
	var router := _router()
	check(router.is_pad("pad2") and not router.is_pad("kb0"), "pad detection")
	check_eq(router.pad_index("pad2"), 2, "pad index")
	check_eq(router.pad_index("kb1"), -1, "keyboards have no pad index")
	check("WASD" in router.device_label("kb0"), "keyboard label: %s" % router.device_label("kb0"))


func test_direction_from_held_actions() -> void:
	var router := _router()
	# Nothing held in a headless run.
	check_eq(router.get_direction("kb0"), Vector2i.ZERO, "no direction")
	check(not router.is_held("kb0", &"bomb"), "nothing held")


func test_godot_ui_actions_are_cleared() -> void:
	_router()
	for action in [&"ui_accept", &"ui_up", &"ui_down"]:
		check(InputMap.action_get_events(action).is_empty(), "%s has no events" % action)
