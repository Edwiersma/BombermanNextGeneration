class_name LobbyState
extends RefCounted
## Lobby choices per player slot: colour and ready flag. Pure logic; which device sits in which
## slot is InputRouter's business. A slot counts as joined while it has a colour.
##
## - Joining picks the slot's default colour (White, Black, Red, Blue) or the next free one.
## - Colours are unique; cycling skips colours other players have. Ready players are locked.
## - The match can start once at least one player has joined and everyone joined is ready
##   (one player alone = practice).

const NO_COLOR := -1

var colors: Array[int] = []
var ready: Array[bool] = []


func _init(slot_count: int = 4) -> void:
	colors.resize(slot_count)
	colors.fill(NO_COLOR)
	ready.resize(slot_count)
	ready.fill(false)


func is_joined(slot: int) -> bool:
	return colors[slot] != NO_COLOR


func joined_slots() -> Array[int]:
	var slots: Array[int] = []
	for slot in colors.size():
		if is_joined(slot):
			slots.append(slot)
	return slots


func joined_count() -> int:
	return joined_slots().size()


func join(slot: int) -> void:
	if is_joined(slot):
		return
	colors[slot] = _next_free_color(slot - 1, 1, slot)
	ready[slot] = false


func leave(slot: int) -> void:
	colors[slot] = NO_COLOR
	ready[slot] = false


func cycle_color(slot: int, step: int) -> void:
	if is_joined(slot) and not ready[slot]:
		colors[slot] = _next_free_color(colors[slot], step, slot)


func is_taken(color: int, except_slot: int) -> bool:
	for slot in colors.size():
		if slot != except_slot and colors[slot] == color:
			return true
	return false


func set_ready(slot: int, value: bool) -> void:
	if is_joined(slot):
		ready[slot] = value


func all_ready() -> bool:
	var slots := joined_slots()
	if slots.is_empty():
		return false
	for slot in slots:
		if not ready[slot]:
			return false
	return true


func can_start() -> bool:
	return all_ready()


func is_practice() -> bool:
	return joined_count() == 1


func unready_all() -> void:
	ready.fill(false)


func reset() -> void:
	colors.fill(NO_COLOR)
	ready.fill(false)


## First colour after `start` (stepping by `step`, wrapping) that nobody else has.
## Returns the slot's current colour when every other colour is taken.
func _next_free_color(start: int, step: int, slot: int) -> int:
	var count := Palette.PLAYER_COLORS.size()
	for i in range(1, count + 1):
		var color := posmod(start + step * i, count)
		if not is_taken(color, slot):
			return color
	return colors[slot]
