extends "res://tests/test_suite.gd"
## LobbyState: the versus screen's slots, portraits, cursors and settings ownership.

const S := preload("res://scripts/core/lobby_state.gd")


func _lobby_with_players(count: int) -> LobbyState:
	var lobby := LobbyState.new()
	for slot in count:
		lobby.add_player(slot)
	return lobby


# --- Slots -------------------------------------------------------------------

func test_joining_takes_the_first_off_slot_then_replaces_ai() -> void:
	var lobby := LobbyState.new()
	lobby.add_ai(0)
	check_eq(lobby.free_slot(), 1, "first OFF slot, AI kept")
	for slot in range(1, S.SLOT_COUNT):
		lobby.add_ai(slot)
	check_eq(lobby.free_slot(), 0, "all AI: the first AI makes room")
	for slot in S.SLOT_COUNT:
		lobby.add_player(slot)
	check_eq(lobby.free_slot(), S.NONE, "full")


func test_slot_toggle_order() -> void:
	var lobby := _lobby_with_players(1)
	check_eq(lobby.next_kind(1, false), S.Kind.AI, "off -> AI")
	check_eq(lobby.next_kind(1, true), S.Kind.PLAYER, "off -> player when a spare pad is connected")
	lobby.add_ai(1)
	check_eq(lobby.next_kind(1, true), S.Kind.OFF, "AI -> off")
	check_eq(lobby.next_kind(0, true), S.Kind.PLAYER, "a human's slot does not toggle")


func test_ai_picks_random() -> void:
	var lobby := LobbyState.new()
	lobby.add_ai(3)
	check_eq(lobby.picks[3], S.RANDOM, "random")
	check_eq(lobby.random_pickers(), [3] as Array[int], "listed on the Random portrait")
	lobby.set_off(3)
	check(lobby.random_pickers().is_empty(), "gone when switched off")


func test_sync_devices() -> void:
	var lobby := LobbyState.new()
	lobby.add_ai(2)
	lobby.add_player(4)
	lobby.sync_devices([true, false, true, false, false, false] as Array[bool])
	check_eq(lobby.kinds, [S.Kind.PLAYER, S.Kind.OFF, S.Kind.PLAYER, S.Kind.OFF, S.Kind.OFF, S.Kind.OFF] as Array[int],
		"controllers become players (replacing AI), players without one turn off")


# --- Portraits ---------------------------------------------------------------

func test_portrait_grid() -> void:
	check_eq(S.PORTRAIT_COUNT, 15, "7 + 8 portraits")
	check_eq(S.RANDOM, 14, "Random is the far right of the bottom row")
	check(not S.is_locked(Palette.PLAYER_COLORS.size() - 1), "every colour is playable")
	check(S.is_locked(Palette.PLAYER_COLORS.size()), "the rest are locked")
	check(not S.is_locked(S.RANDOM), "Random is not locked")
	check_eq([S.portrait_row(6), S.portrait_column(6)], [0, 6], "end of the top row")
	check_eq([S.portrait_row(7), S.portrait_column(7)], [1, 0], "start of the bottom row")


func test_a_portrait_can_only_be_claimed_once() -> void:
	var lobby := _lobby_with_players(2)
	check(lobby.claim_portrait(0, 2), "P1 takes red")
	check(not lobby.claim_portrait(1, 2), "P2 cannot")
	check_eq(lobby.claimed_by(2), 0, "red is P1's")
	check(lobby.claim_portrait(0, 3), "P1 swaps to blue")
	check_eq(lobby.claimed_by(2), S.NONE, "red is free again")
	check(lobby.claim_portrait(1, 2), "so P2 can take it")
	lobby.unclaim(1)
	check_eq(lobby.claimed_by(2), S.NONE, "dropped")


func test_random_can_be_picked_by_many_and_locked_by_nobody() -> void:
	var lobby := _lobby_with_players(3)
	check(lobby.claim_portrait(0, S.RANDOM) and lobby.claim_portrait(1, S.RANDOM), "two randoms")
	check_eq(lobby.random_pickers(), [0, 1] as Array[int], "both listed")
	check(not lobby.claim_portrait(2, 10), "locked")
	check(not lobby.claim_portrait(2, S.PORTRAIT_COUNT), "out of range")


func test_claim_uses_the_cursor() -> void:
	var lobby := _lobby_with_players(1)
	lobby.move_cursor(0, Vector2i.RIGHT)
	check(lobby.claim(0), "claimed")
	check_eq(lobby.picks[0], 1, "the portrait under the cursor")
	lobby.move_cursor(0, Vector2i.DOWN)
	lobby.move_cursor(0, Vector2i.DOWN)  # slot row
	check(not lobby.claim(0), "nothing to claim on the slot row")


func test_resolve_gives_randoms_free_distinct_colours() -> void:
	for run in 40:
		var lobby := _lobby_with_players(1)
		lobby.claim_portrait(0, 2)
		for slot in range(1, S.SLOT_COUNT):
			lobby.add_ai(slot)
		var rng := RandomNumberGenerator.new()
		rng.seed = run
		lobby.resolve_picks(rng)
		check_eq(lobby.resolved[0], 2, "claimed colour kept")
		var seen := {}
		for slot in S.SLOT_COUNT:
			check(lobby.resolved[slot] >= 0 and lobby.resolved[slot] < Palette.PLAYER_COLORS.size(), "playable colour")
			seen[lobby.resolved[slot]] = true
		check_eq(seen.size(), S.SLOT_COUNT, "all different (seed %d)" % run)


func test_color_index() -> void:
	var lobby := LobbyState.new()
	check_eq(lobby.color_index(3), 3, "no lobby: the slot's default")
	lobby.add_player(3)
	lobby.claim_portrait(3, 6)
	check_eq(lobby.color_index(3), 6, "the claimed portrait")


# --- Cursors -----------------------------------------------------------------

func test_cursor_walks_the_grid() -> void:
	var lobby := _lobby_with_players(1)
	check_eq(lobby.cursor_index[0], 0, "starts on the first portrait")
	check(not lobby.move_cursor(0, Vector2i.LEFT), "left edge")
	check(not lobby.move_cursor(0, Vector2i.UP), "top edge")
	for i in 6:
		lobby.move_cursor(0, Vector2i.RIGHT)
	check_eq(lobby.cursor_index[0], 6, "end of the top row")
	lobby.move_cursor(0, Vector2i.DOWN)
	check_eq(lobby.cursor_index[0], 13, "down to the bottom row")
	lobby.move_cursor(0, Vector2i.RIGHT)
	check_eq(lobby.cursor_index[0], S.RANDOM, "Random")
	lobby.move_cursor(0, Vector2i.UP)
	check_eq(lobby.cursor_index[0], 6, "up from Random: end of the top row")
	lobby.move_cursor(0, Vector2i.DOWN)
	lobby.move_cursor(0, Vector2i.RIGHT)
	lobby.move_cursor(0, Vector2i.DOWN)
	check_eq([lobby.cursor_area[0], lobby.cursor_index[0]], [S.Area.SLOTS, 5], "down from Random: the last slot")
	check(not lobby.move_cursor(0, Vector2i.DOWN), "bottom edge")
	lobby.move_cursor(0, Vector2i.UP)
	check_eq([lobby.cursor_area[0], lobby.cursor_index[0]], [S.Area.PORTRAITS, S.RANDOM], "and back up")


func test_slot_row_lines_up_with_the_bottom_row() -> void:
	check_eq(range(S.BOTTOM_ROW).map(func(c): return S.slot_under_column(c)), [0, 1, 1, 2, 3, 4, 4, 5], "8 columns over 6 slots")
	check_eq(range(S.SLOT_COUNT).map(func(s): return S.column_above_slot(s)), [0, 2, 3, 4, 6, 7], "and back")


func test_right_past_the_end_enters_settings_and_left_returns() -> void:
	var lobby := _lobby_with_players(1)
	for i in 7:
		lobby.move_cursor(0, Vector2i.RIGHT)
	check_eq(lobby.cursor_area[0], S.Area.SETTINGS, "past the top row")
	check_eq(lobby.settings_owner, 0, "owns the settings")
	lobby.move_cursor(0, Vector2i.LEFT)
	check_eq([lobby.cursor_area[0], lobby.cursor_index[0]], [S.Area.PORTRAITS, 6], "back where it came from")
	check_eq(lobby.settings_owner, S.NONE, "free again")
	lobby.move_cursor(0, Vector2i.DOWN)
	lobby.move_cursor(0, Vector2i.DOWN)  # slot row
	for i in 6:
		lobby.move_cursor(0, Vector2i.RIGHT)
	check_eq(lobby.cursor_area[0], S.Area.SETTINGS, "past the slot row")
	lobby.leave_settings(0)
	check_eq([lobby.cursor_area[0], lobby.cursor_index[0]], [S.Area.SLOTS, 5], "back on the last slot")


func test_settings_one_player_at_a_time() -> void:
	var lobby := _lobby_with_players(2)
	check(lobby.enter_settings(0), "P1 in")
	for i in 6:
		lobby.move_cursor(1, Vector2i.RIGHT)  # P2 starts on portrait 1: reaches the end of the row
	check(not lobby.move_cursor(1, Vector2i.RIGHT), "P2 cannot get in")
	check_eq(lobby.cursor_area[1], S.Area.PORTRAITS, "P2 stays on the grid")
	check(not lobby.enter_settings(1), "not by shortcut either")
	lobby.set_off(0)
	check_eq(lobby.settings_owner, S.NONE, "leaving the game frees the settings")
	check(lobby.move_cursor(1, Vector2i.RIGHT), "now P2 can")


func test_cursors_on_lists_humans_only() -> void:
	var lobby := _lobby_with_players(2)
	lobby.add_ai(2)
	lobby.move_cursor(1, Vector2i.LEFT)  # P2 onto portrait 0 with P1
	check_eq(lobby.cursors_on(S.Area.PORTRAITS, 0), [0, 1] as Array[int], "both cursors")
	check(lobby.cursors_on(S.Area.PORTRAITS, 2).is_empty(), "AI has no cursor")


func test_prepare_puts_cursors_on_their_picks() -> void:
	var lobby := _lobby_with_players(2)
	lobby.claim_portrait(0, 5)
	lobby.enter_settings(1)
	lobby.prepare()
	check_eq(lobby.cursor_index[0], 5, "on the pick")
	check_eq([lobby.cursor_area[1], lobby.cursor_index[1]], [S.Area.PORTRAITS, 1], "default spot")
	check_eq(lobby.settings_owner, S.NONE, "settings free")


# --- Starting ----------------------------------------------------------------

func test_start_needs_every_human_to_pick() -> void:
	var lobby := LobbyState.new()
	check(not lobby.can_start(), "nobody")
	lobby.add_ai(1)
	check(not lobby.can_start(), "AI alone cannot start")
	lobby.add_player(0)
	check(not lobby.can_start(), "P1 still choosing")
	lobby.claim_portrait(0, 0)
	check(lobby.can_start(), "everyone picked")
	check(not lobby.is_practice(), "with an AI it is versus")
	lobby.set_off(1)
	check(lobby.is_practice(), "alone: practice")
