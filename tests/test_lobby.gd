extends "res://tests/test_suite.gd"

const WHITE := 0
const BLACK := 1
const RED := 2
const BLUE := 3
const GREEN := 4


func test_join_uses_slot_default_colour() -> void:
	var lobby := LobbyState.new()
	lobby.join(2)
	lobby.join(0)
	check_eq(lobby.colors[2], RED, "slot 3 defaults to red")
	check_eq(lobby.colors[0], WHITE, "slot 1 defaults to white")
	check_eq(lobby.joined_slots(), [0, 2] as Array[int], "joined slots")


func test_join_skips_a_taken_default() -> void:
	var lobby := LobbyState.new()
	lobby.join(0)
	lobby.cycle_color(0, 1)  # white -> black
	lobby.join(1)            # black is taken
	check_eq(lobby.colors[0], BLACK, "slot 1 took black")
	check_eq(lobby.colors[1], RED, "slot 2 gets the next free colour")


func test_cycle_skips_taken_colours_both_ways() -> void:
	var lobby := LobbyState.new()
	lobby.join(0)
	lobby.join(1)
	lobby.join(2)
	lobby.cycle_color(0, 1)
	check_eq(lobby.colors[0], BLUE, "white -> (black, red taken) -> blue")
	lobby.cycle_color(0, -1)
	check_eq(lobby.colors[0], WHITE, "back to white")
	lobby.cycle_color(0, -1)
	check_eq(lobby.colors[0], Palette.PLAYER_COLORS.size() - 1, "wraps to the last colour")


func test_colours_stay_unique() -> void:
	var lobby := LobbyState.new()
	for slot in 4:
		lobby.join(slot)
	for i in 20:
		lobby.cycle_color(i % 4, 1 if i % 3 else -1)
	var seen := {}
	for slot in 4:
		seen[lobby.colors[slot]] = true
	check_eq(seen.size(), 4, "four different colours: %s" % [lobby.colors])


func test_ready_locks_colour() -> void:
	var lobby := LobbyState.new()
	lobby.join(0)
	lobby.set_ready(0, true)
	lobby.cycle_color(0, 1)
	check_eq(lobby.colors[0], WHITE, "colour locked while ready")


func test_can_start_only_when_everyone_is_ready() -> void:
	var lobby := LobbyState.new()
	check(not lobby.can_start(), "nobody joined")
	lobby.join(0)
	lobby.join(1)
	lobby.set_ready(0, true)
	check(not lobby.can_start(), "one not ready")
	lobby.set_ready(1, true)
	check(lobby.can_start(), "all ready")
	check(not lobby.is_practice(), "two players is versus")


func test_solo_practice_can_start() -> void:
	var lobby := LobbyState.new()
	lobby.join(3)
	lobby.set_ready(3, true)
	check(lobby.can_start() and lobby.is_practice(), "practice")


func test_leave_frees_colour_and_ready() -> void:
	var lobby := LobbyState.new()
	lobby.join(0)
	lobby.set_ready(0, true)
	lobby.leave(0)
	check(not lobby.is_joined(0) and not lobby.ready[0], "left")
	lobby.join(1)
	lobby.cycle_color(1, -1)
	check_eq(lobby.colors[1], WHITE, "white is free again")


func test_set_ready_ignores_empty_slots() -> void:
	var lobby := LobbyState.new()
	lobby.set_ready(2, true)
	check(not lobby.ready[2], "cannot ready an empty slot")
