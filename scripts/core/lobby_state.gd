class_name LobbyState
extends RefCounted
## The versus screen as pure logic: six player slots, the portrait grid, one cursor per human
## player and the settings section. The lobby scene draws it; InputRouter says which device sits
## in which slot.
##
## - A slot is OFF, PLAYER (a controller sits in it) or AI. A joining controller takes the first
##   OFF slot, or replaces the first AI when there is none. Cross on an empty slot's card toggles
##   it OFF -> PLAYER (only when a spare controller is connected to sit in it) -> AI -> OFF.
## - Portraits: two rows, 7 on top and 8 below; the far right of the bottom row is Random. The
##   first Palette.PLAYER_COLORS.size() portraits are the playable colours, the rest are locked.
##   A portrait can be claimed by one slot only; Random by any number. AI slots pick Random.
## - Cursors move over the portraits, then the slot row below them. Moving right past the end of
##   either row enters the settings section, which one player at a time can use; moving left
##   leaves it again, back to where that cursor came from.
## - The match can start once every human player has claimed a portrait (one participant alone,
##   human or not, = practice).

enum Kind { OFF, PLAYER, AI }
enum Area { PORTRAITS, SLOTS, SETTINGS }

const SLOT_COUNT := 6
const TOP_ROW := 7
const BOTTOM_ROW := 8
const PORTRAIT_COUNT := TOP_ROW + BOTTOM_ROW
const RANDOM := PORTRAIT_COUNT - 1
const NONE := -1

var kinds: Array[int] = []
## Claimed portrait per slot (RANDOM allowed); NONE while still choosing.
var picks: Array[int] = []
## The portrait each slot plays as, Random settled; filled by resolve_picks() at match start.
var resolved: Array[int] = []
var cursor_area: Array[int] = []
var cursor_index: Array[int] = []
## Slot whose cursor is in the settings section, or NONE.
var settings_owner := NONE

## Where each cursor was before it entered the settings, to return there.
var _return_area: Array[int] = []
var _return_index: Array[int] = []


func _init() -> void:
	for list: Array[int] in [kinds, picks, resolved, cursor_area, cursor_index, _return_area, _return_index]:
		list.resize(SLOT_COUNT)
	reset()


func reset() -> void:
	kinds.fill(Kind.OFF)
	picks.fill(NONE)
	resolved.fill(NONE)
	cursor_area.fill(Area.PORTRAITS)
	cursor_index.fill(0)
	_return_area.fill(Area.PORTRAITS)
	_return_index.fill(0)
	settings_owner = NONE


## Entering the screen (again, e.g. after a match): picks stay, cursors go back onto them and
## nobody is in the settings.
func prepare() -> void:
	settings_owner = NONE
	for slot in SLOT_COUNT:
		cursor_area[slot] = Area.PORTRAITS
		cursor_index[slot] = picks[slot] if picks[slot] != NONE else _default_portrait(slot)


# --- Portraits -----------------------------------------------------------------

static func unlocked_count() -> int:
	return Palette.PLAYER_COLORS.size()


static func is_locked(portrait: int) -> bool:
	return portrait >= unlocked_count() and portrait != RANDOM


## 0 = top row, 1 = bottom row.
static func portrait_row(portrait: int) -> int:
	return 0 if portrait < TOP_ROW else 1


static func portrait_column(portrait: int) -> int:
	return portrait if portrait < TOP_ROW else portrait - TOP_ROW


## The slot card under bottom-row column `column` (8 portraits over 6 cards, by position).
static func slot_under_column(column: int) -> int:
	return floori((column + 0.5) * SLOT_COUNT / float(BOTTOM_ROW))


## The bottom-row column above slot card `slot`.
static func column_above_slot(slot: int) -> int:
	return floori((slot + 0.5) * BOTTOM_ROW / float(SLOT_COUNT))


## The slot that claimed `portrait`, or NONE. Random is never "claimed".
func claimed_by(portrait: int) -> int:
	if portrait == RANDOM:
		return NONE
	for slot in SLOT_COUNT:
		if kinds[slot] != Kind.OFF and picks[slot] == portrait:
			return slot
	return NONE


## Slots that picked Random.
func random_pickers() -> Array[int]:
	var slots: Array[int] = []
	for slot in SLOT_COUNT:
		if kinds[slot] != Kind.OFF and picks[slot] == RANDOM:
			slots.append(slot)
	return slots


func can_claim(slot: int, portrait: int) -> bool:
	if portrait < 0 or portrait >= PORTRAIT_COUNT or is_locked(portrait):
		return false
	var holder := claimed_by(portrait)
	return holder == NONE or holder == slot


func claim_portrait(slot: int, portrait: int) -> bool:
	if kinds[slot] == Kind.OFF or not can_claim(slot, portrait):
		return false
	picks[slot] = portrait
	resolved[slot] = NONE
	return true


## Cross on the portrait under the slot's cursor. Claiming another portrait swaps to it.
func claim(slot: int) -> bool:
	if cursor_area[slot] != Area.PORTRAITS:
		return false
	return claim_portrait(slot, cursor_index[slot])


func unclaim(slot: int) -> void:
	picks[slot] = NONE
	resolved[slot] = NONE


func has_pick(slot: int) -> bool:
	return picks[slot] != NONE


# --- Slots ---------------------------------------------------------------------

func is_human(slot: int) -> bool:
	return kinds[slot] == Kind.PLAYER


func is_active(slot: int) -> bool:
	return kinds[slot] != Kind.OFF


func humans() -> Array[int]:
	var slots: Array[int] = []
	for slot in SLOT_COUNT:
		if kinds[slot] == Kind.PLAYER:
			slots.append(slot)
	return slots


## Every slot that plays: humans and AI, in slot order.
func participants() -> Array[int]:
	var slots: Array[int] = []
	for slot in SLOT_COUNT:
		if kinds[slot] != Kind.OFF:
			slots.append(slot)
	return slots


## Where a joining controller goes: the first OFF slot, else the first AI slot. NONE when full.
func free_slot() -> int:
	var first_ai := NONE
	for slot in SLOT_COUNT:
		if kinds[slot] == Kind.OFF:
			return slot
		if kinds[slot] == Kind.AI and first_ai == NONE:
			first_ai = slot
	return first_ai


func add_player(slot: int) -> void:
	kinds[slot] = Kind.PLAYER
	picks[slot] = NONE
	resolved[slot] = NONE
	cursor_area[slot] = Area.PORTRAITS
	cursor_index[slot] = _default_portrait(slot)


func add_ai(slot: int) -> void:
	set_off(slot)
	kinds[slot] = Kind.AI
	picks[slot] = RANDOM


func set_off(slot: int) -> void:
	if settings_owner == slot:
		settings_owner = NONE
	kinds[slot] = Kind.OFF
	picks[slot] = NONE
	resolved[slot] = NONE
	cursor_area[slot] = Area.PORTRAITS


## What Cross on slot `slot`'s card turns it into: OFF -> PLAYER (only when a spare controller is
## connected to sit in it) -> AI -> OFF. A human's slot does not toggle; they leave with Back.
func next_kind(slot: int, spare_controller: bool) -> int:
	match kinds[slot]:
		Kind.OFF:
			return Kind.PLAYER if spare_controller else Kind.AI
		Kind.AI:
			return Kind.OFF
	return Kind.PLAYER


## Brings slot kinds in line with which slots have a controller (InputRouter's view):
## a controller makes its slot a PLAYER, a PLAYER slot without one turns OFF.
func sync_devices(has_device: Array[bool]) -> void:
	for slot in SLOT_COUNT:
		if has_device[slot] and kinds[slot] != Kind.PLAYER:
			add_player(slot)
		elif not has_device[slot] and kinds[slot] == Kind.PLAYER:
			set_off(slot)


# --- Cursors -------------------------------------------------------------------

## Moves the slot's cursor one step in `dir`. Returns false when it cannot: the edge of the
## screen, or the settings section is in use by someone else.
func move_cursor(slot: int, dir: Vector2i) -> bool:
	var area := cursor_area[slot]
	var index := cursor_index[slot]
	match area:
		Area.PORTRAITS:
			var row := portrait_row(index)
			var column := portrait_column(index)
			var row_length := TOP_ROW if row == 0 else BOTTOM_ROW
			if dir.x != 0:
				column += dir.x
				if column < 0:
					return false
				if column >= row_length:
					return enter_settings(slot)
				index = column if row == 0 else TOP_ROW + column
			elif dir.y < 0:
				if row == 0:
					return false
				index = mini(column, TOP_ROW - 1)
			elif dir.y > 0:
				if row == 0:
					index = TOP_ROW + column
				else:
					area = Area.SLOTS
					index = slot_under_column(column)
			else:
				return false
		Area.SLOTS:
			if dir.x != 0:
				index += dir.x
				if index < 0:
					return false
				if index >= SLOT_COUNT:
					return enter_settings(slot)
			elif dir.y < 0:
				area = Area.PORTRAITS
				index = TOP_ROW + column_above_slot(index)
			else:
				return false
		Area.SETTINGS:
			if dir.x < 0:
				leave_settings(slot)
				return true
			return false
	cursor_area[slot] = area
	cursor_index[slot] = index
	return true


## Puts the slot's cursor in the settings section, unless someone else is using it.
func enter_settings(slot: int) -> bool:
	if settings_owner != NONE and settings_owner != slot:
		return false
	if cursor_area[slot] != Area.SETTINGS:
		_return_area[slot] = cursor_area[slot]
		_return_index[slot] = cursor_index[slot]
	settings_owner = slot
	cursor_area[slot] = Area.SETTINGS
	cursor_index[slot] = 0
	return true


## Back from the settings to where the cursor came from.
func leave_settings(slot: int) -> void:
	if cursor_area[slot] != Area.SETTINGS:
		return
	cursor_area[slot] = _return_area[slot]
	cursor_index[slot] = _return_index[slot]
	if settings_owner == slot:
		settings_owner = NONE


## Human slots whose cursor is on `index` in `area`.
func cursors_on(area: int, index: int) -> Array[int]:
	var slots: Array[int] = []
	for slot in SLOT_COUNT:
		if kinds[slot] == Kind.PLAYER and cursor_area[slot] == area and cursor_index[slot] == index:
			slots.append(slot)
	return slots


# --- Starting ------------------------------------------------------------------

func can_start() -> bool:
	var people := humans()
	if people.is_empty():
		return false
	for slot in people:
		if picks[slot] == NONE:
			return false
	return true


func is_practice() -> bool:
	return participants().size() == 1


## Settles every pick for the match: Random (AI included) gets a colour nobody else plays.
func resolve_picks(rng: RandomNumberGenerator) -> void:
	resolved.fill(NONE)
	var taken := {}
	for slot in SLOT_COUNT:
		if kinds[slot] != Kind.OFF and picks[slot] != NONE and picks[slot] != RANDOM:
			resolved[slot] = picks[slot]
			taken[picks[slot]] = true
	for slot in SLOT_COUNT:
		if kinds[slot] == Kind.OFF or resolved[slot] != NONE:
			continue
		var free: Array[int] = []
		for portrait in unlocked_count():
			if not taken.has(portrait):
				free.append(portrait)
		if free.is_empty():
			continue  # more players than colours; cannot happen with 6 slots and 8 colours
		var portrait := free[rng.randi_range(0, free.size() - 1)]
		resolved[slot] = portrait
		taken[portrait] = true


## Palette colour slot `slot` plays as: the settled pick, else the claimed portrait, else (no
## lobby: dev matches, tests) the slot's own default.
func color_index(slot: int) -> int:
	if resolved[slot] != NONE:
		return resolved[slot]
	if picks[slot] != NONE and picks[slot] != RANDOM:
		return picks[slot]
	return slot % unlocked_count()


func _default_portrait(slot: int) -> int:
	return slot % unlocked_count()
