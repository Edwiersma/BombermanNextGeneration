extends Node3D
## Versus match root. Owns the arena, players, bombs and the round flow (MatchRules), and turns
## rule signals into scene changes: fresh arena per round, input locks, falling blocks, HUD.
##
## Per physics tick: InputRouter (autoload) -> Match (bombs, deaths, then rules) -> Players (movement).

const PLAYER_SCENE := preload("res://scenes/game/player.tscn")
const BombView := preload("res://scenes/game/bomb_view.gd")
const ExplosionView := preload("res://scenes/game/explosion_view.gd")
const PauseMenu := preload("res://scenes/game/pause_menu.gd")
const ItemView := preload("res://scenes/game/item_view.gd")
const PickupPopup := preload("res://scenes/game/pickup_popup.gd")

@export var level: LevelData = preload("res://levels/classic.tres")
## Fixed seed for '?' cells; 0 picks a new random layout every round.
@export var rng_seed := 0
## Dev mode when the match is opened directly (?scene=match): it opens in a join phase where
## devices join with bomb and start begins, and returns there afterwards. Matches set up by the
## lobby (GameState.in_session) turn this off: they start at once and end on the results screen.
@export var allow_drop_in := true
## Go to the results screen when a lobby match is over. Tests turn this off.
@export var leave_on_finish := true

var grid: Grid
var bombs: BombField
var items: ItemField
var rules := MatchRules.new()
var players: Array = []  # Player node or null, indexed by slot

var _rng := RandomNumberGenerator.new()
var _bomb_views := {}  # bomb id -> BombView
var _item_views := {}  # Vector2i -> ItemView
var _ticks := 0
var _pause_menu: CanvasLayer
var _pause_changed_frame := -1  # physics frame of the last pause/resume, to act once per frame
var _dev_item_index := 0        # F5 in dev matches cycles through item types

@onready var arena: Node3D = $Arena
@onready var camera: Camera3D = $Camera
@onready var players_root: Node3D = $Players
@onready var effects: Node3D = $Effects
@onready var hud: CanvasLayer = $Hud
@onready var hint: Label = $Hud/Hint
@onready var debug_label: Label = $Hud/Debug


func _ready() -> void:
	if GameState.in_session:
		allow_drop_in = false
		level = GameState.level
	arena.show_spawn_markers = allow_drop_in
	if rng_seed != 0:
		_rng.seed = rng_seed
	else:
		_rng.randomize()
	_build_arena()
	camera.frame(arena.get_bounds())
	_warm_up_effects()
	_connect_rules()

	players.resize(InputRouter.MAX_SLOTS)
	for slot in InputRouter.MAX_SLOTS:
		var device := InputRouter.device_in_slot(slot)
		if device != "":
			_spawn_player(slot, device)
	InputRouter.action_pressed.connect(_on_action_pressed)
	debug_label.visible = allow_drop_in
	_pause_menu = PauseMenu.new()
	_pause_menu.resume_requested.connect(_resume)
	_pause_menu.quit_requested.connect(func(): Scenes.go(Scenes.LOBBY))
	add_child(_pause_menu)
	_enter_join_phase()


func _exit_tree() -> void:
	if InputRouter.action_pressed.is_connected(_on_action_pressed):
		InputRouter.action_pressed.disconnect(_on_action_pressed)


func _physics_process(_delta: float) -> void:
	_ticks += 1
	# Bombs and deaths first, so the rules see this tick's deaths before deciding the round.
	if rules.is_playing():
		for player in players:
			if player and player.alive:
				player.stats.tick()
				_tick_carry(player)
		bombs.tick()
		_check_deaths()
		_check_pickups()
	rules.tick()


func _process(_delta: float) -> void:
	hud.set_time(rules.time_left if rules.has_time_limit() else -1, rules.sudden_death)
	# Bombs can slide and fly: views follow their logical positions.
	var positions := bombs.bomb_positions()
	for id in _bomb_views:
		if positions.has(id):
			_bomb_views[id].position = positions[id]
	for player in players:
		if player and player.is_carrying() and _bomb_views.has(player.carried_bomb):
			_bomb_views[player.carried_bomb].position = player.position + Vector3(0.0, Rules.CARRY_HEIGHT, 0.0)
	if debug_label.visible:
		var lines: Array[String] = ["FPS %d   physics ticks %d   state %s   (F3 hides)" % [
			Engine.get_frames_per_second(), _ticks, MatchRules.State.keys()[rules.state]]]
		for player in players:
			if player:
				lines.append("P%d %-4s  (%.2f, %.2f)%s" % [player.slot + 1, player.device,
					player.grid_pos.x, player.grid_pos.y, "" if player.alive else "  dead"])
		debug_label.text = "\n".join(lines)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.physical_keycode == KEY_F3:
		debug_label.visible = not debug_label.visible
	elif event.physical_keycode == KEY_F4 and allow_drop_in and rules.is_playing():
		# Dev: skip the clock to 2 s before sudden death.
		rules.time_left = mini(rules.time_left, rules.sudden_death_at + 2 * Rules.TICKS_PER_SECOND)
	elif event.physical_keycode == KEY_F5 and allow_drop_in and rules.is_playing():
		_dev_give_next_item()


## Dev: drop the next item type at the first living player's feet (picked up next tick).
func _dev_give_next_item() -> void:
	for player in players:
		if player and player.alive:
			var item: int = Items.IMPLEMENTED[_dev_item_index % Items.IMPLEMENTED.size()]
			_dev_item_index += 1
			items.place(player.get_cell(), item)
			return


## Movement collision: can `player` enter `cell`? A player standing on a bomb can still walk off
## it, because movement only ever checks the cell ahead.
func is_blocked_for(_player: Node, cell: Vector2i) -> bool:
	return grid.is_blocking(cell) or bombs.has_bomb(cell)


## Bomb button pressed. Standing on your own bomb: lift it (Power Glove) or lay a line (Line
## Bomb). Otherwise: place a bomb if you have one left.
func try_place_bomb(player: Node) -> void:
	# Input keeps flowing while paused (the pause menu needs it), so check the pause here too.
	if not rules.is_playing() or get_tree().paused or player.is_carrying():
		return
	var cell: Vector2i = player.get_cell()
	var stats: PlayerStats = player.stats
	if bombs.has_bomb(cell):
		if bombs.owner_at(cell) == player.slot:
			if stats.has_glove():
				player.carried_bomb = bombs.lift(cell)
				player.carry_ticks = 0
			elif stats.has_line_bomb():
				var left := stats.max_bombs - bombs.bomb_count(player.slot)
				bombs.place_line(cell, player.facing, left, player.slot, stats.fire_range)
		return
	if bombs.bomb_count(player.slot) < stats.max_bombs:
		bombs.place_bomb(cell, player.slot, stats.fire_range)


## Bomb button released: throw a carried bomb the way the player faces.
func release_bomb(player: Node) -> void:
	if not player.is_carrying() or not rules.is_playing() or get_tree().paused:
		return
	bombs.throw(player.carried_bomb, player.get_cell(), player.facing)
	player.carried_bomb = -1


## Super Power Glove: a bomb held long enough becomes a Dangerous Bomb.
func _tick_carry(player: Node) -> void:
	if not player.is_carrying():
		return
	player.carry_ticks += 1
	if player.stats.has_super_glove() and player.carry_ticks == Rules.SUPER_GLOVE_CHARGE_TICKS:
		bombs.make_dangerous(player.carried_bomb)


## Kick: `player` is pressing `dir` into a bomb right in front of them. True if it slid off.
func try_kick(player: Node, dir: Vector2i) -> bool:
	if not rules.is_playing() or get_tree().paused or not player.stats.has_kick:
		return false
	return bombs.kick(player.get_cell() + dir, dir)


## Punch: sends the bomb in front of `player` flying. True if there was one.
func try_punch(player: Node) -> bool:
	if not rules.is_playing() or get_tree().paused or not player.stats.has_punch:
		return false
	return bombs.punch(player.get_cell() + player.facing, player.facing)


# --- Match flow --------------------------------------------------------------

func _connect_rules() -> void:
	rules.round_started.connect(func(n): hud.announce("ROUND %d" % n))
	rules.ready_shown.connect(func(): hud.announce("READY?"))
	rules.play_started.connect(_on_play_started)
	rules.hurry_up.connect(func(): hud.announce("HURRY UP!", 1.5, Color(1.0, 0.35, 0.25)))
	rules.block_falling.connect(func(cell): arena.drop_block(cell, Rules.ticks_to_seconds(Rules.FALL_TICKS)))
	rules.block_landed.connect(_on_block_landed)
	rules.round_ended.connect(_on_round_ended)
	rules.next_round.connect(_start_round)
	rules.match_ended.connect(_on_match_ended)
	rules.match_finished.connect(_on_match_finished)


func _enter_join_phase() -> void:
	_set_input(false)
	if not allow_drop_in:
		_begin_match()  # lobby match: straight in (it builds its own arena)
		return
	_build_arena()
	for player in players:
		if player:
			player.respawn(grid.spawns[player.slot])
	hud.show_clock(false)
	hud.setup_players(_joined_slots())
	hud.set_wins({})
	hud.announce("PRESS START" if InputRouter.joined_count() > 0 else "JOIN IN!")
	_update_hint()


func _begin_match() -> void:
	var slots := _joined_slots()
	if slots.is_empty():
		return
	rules.configure(GameState.settings)
	rules.begin_match(slots)
	hud.setup_players(slots)
	hud.show_clock(true)
	hint.visible = false
	_start_round()


func _start_round() -> void:
	_build_arena()
	var settings := GameState.settings
	if settings.items_active():
		items.hide_items(_rng, settings.item_frequency, settings.enabled_item_types())
	for slot in rules.participants:
		players[slot].respawn(grid.spawns[slot])
		players[slot].reset_stats(GameState.settings)
		hud.set_alive(slot, true)
	_set_input(false)
	hud.set_wins(rules.wins)
	rules.start_round(grid)


func _on_play_started() -> void:
	_set_input(true)
	hud.announce("GO!", 0.5)


func _on_round_ended(winner: int) -> void:
	_set_input(false)
	hud.set_wins(rules.wins)
	if winner == -1:
		hud.announce("DRAW")
	else:
		hud.announce("%s WINS!" % _player_name(winner), 0.0, GameState.color_of(winner))


func _on_match_ended(winner: int) -> void:
	hud.announce("%s WINS THE MATCH!" % _player_name(winner), 0.0, GameState.color_of(winner))


func _on_match_finished() -> void:
	GameState.last_results = {
		"wins": rules.wins.duplicate(),
		"winner": rules.match_winner,
		"rounds": rules.round_number,
	}
	if allow_drop_in:
		_enter_join_phase()
	elif leave_on_finish:
		Scenes.go(Scenes.RESULTS)


func _toggle_pause() -> void:
	if get_tree().paused:
		_resume()
	elif _claim_pause_change():
		get_tree().paused = true
		_pause_menu.open()


func _resume() -> void:
	if _claim_pause_change():
		_pause_menu.close()
		get_tree().paused = false


## Pause and resume at most once per physics frame, so two players pressing in the same frame
## (Start + Start, or Start + Cross on RESUME) do not cancel each other out.
func _claim_pause_change() -> bool:
	var frame := Engine.get_physics_frames()
	if frame == _pause_changed_frame:
		return false
	_pause_changed_frame = frame
	return true


## Sudden death: the block lands, crushing whatever is in the cell.
func _on_block_landed(cell: Vector2i) -> void:
	bombs.crush(cell)
	items.crush(cell)
	grid.set_cell(cell, Grid.Cell.HARD)
	for player in players:
		if player and player.alive and player.get_cell() == cell:
			player.die()


## Fire hits go through the player's protection (Heart, Safety Vest).
func _check_deaths() -> void:
	for player in players:
		if player and player.alive and bombs.has_flame(player.get_cell()):
			var had_heart: bool = player.stats.has_heart
			if player.stats.take_hit():
				player.die()
			elif had_heart and not player.stats.has_heart:
				_show_popup(player, "HEART LOST!", Items.color(Items.Type.HEART))


func _check_pickups() -> void:
	for player in players:
		if player and player.alive:
			var item := items.take(player.get_cell())
			if item != Items.NONE:
				player.stats.apply(item)
				_show_pickup(player, item)


func _on_player_died(player: Node) -> void:
	rules.player_died(player.slot)
	hud.set_alive(player.slot, false)
	if player.is_carrying():
		bombs.drop(player.carried_bomb, player.get_cell())  # falls where they fell
		player.carried_bomb = -1
	if rules.is_playing() and GameState.settings.death_items == MatchSettings.DeathItems.SCATTER:
		items.scatter(player.stats.collected, _rng, _is_free_for_items)
	player.stats.collected.clear()


## Where a dead player's items may land: open floor without a bomb, a flame or a living player.
func _is_free_for_items(cell: Vector2i) -> bool:
	return not bombs.has_bomb(cell) and not bombs.has_flame(cell) and not _living_player_at(cell)


# --- Arena, players, effects -------------------------------------------------

## Fresh grid, arena and bombs (each round, and for the join phase).
func _build_arena() -> void:
	grid = level.build_grid(_rng)
	arena.build(grid)
	for child in effects.get_children():
		child.queue_free()
	_bomb_views.clear()
	_item_views.clear()
	items = ItemField.new(grid)
	items.item_revealed.connect(_on_item_revealed)
	items.item_removed.connect(_on_item_removed)
	bombs = BombField.new(grid)
	bombs.items = items
	bombs.player_at = _living_player_at
	bombs.bomb_placed.connect(_on_bomb_placed)
	bombs.bomb_exploded.connect(_on_bomb_exploded)
	bombs.bomb_removed.connect(func(id, _cell): _remove_bomb_view(id))
	bombs.bomb_changed.connect(_on_bomb_changed)
	bombs.block_burning.connect(arena.burn_block)
	bombs.block_destroyed.connect(items.reveal)


func _set_input(enabled: bool) -> void:
	for player in players:
		if player:
			player.input_enabled = enabled


func _joined_slots() -> Array[int]:
	var slots: Array[int] = []
	for slot in players.size():
		if players[slot]:
			slots.append(slot)
	return slots


func _player_name(slot: int) -> String:
	return GameState.color_name(slot).to_upper()


func _on_action_pressed(device: String, action: StringName) -> void:
	var slot := InputRouter.slot_of(device)
	if action == &"start" and slot != -1 and rules.state in [MatchRules.State.INTRO, MatchRules.State.PLAYING]:
		_toggle_pause()
		return
	if not allow_drop_in or rules.state != MatchRules.State.WAITING:
		return
	if action == &"bomb" and slot == -1:
		slot = InputRouter.assign_slot(device)
		if slot != -1:
			_spawn_player(slot, device)
			hud.setup_players(_joined_slots())
			hud.announce("PRESS START")
			_update_hint()
	elif action == &"start" and slot != -1:
		_begin_match()


func _spawn_player(slot: int, device: String) -> void:
	var spawn := grid.spawns[slot]
	if spawn == Grid.NO_SPAWN:
		push_error("Level has no spawn for slot %d" % slot)
		return
	var player := PLAYER_SCENE.instantiate()
	player.setup(self, slot, device, GameState.color_of(slot), spawn)
	player.input_enabled = false
	player.died.connect(_on_player_died)
	players_root.add_child(player)
	players[slot] = player


func _on_bomb_placed(id: int, cell: Vector2i, _owner: int) -> void:
	var view := BombView.new()
	view.position = Grid.cell_to_world(cell)
	effects.add_child(view)
	_bomb_views[id] = view


func _on_bomb_changed(id: int) -> void:
	if _bomb_views.has(id):
		_bomb_views[id].set_dangerous()


func _on_bomb_exploded(id: int, _cell: Vector2i, _owner: int, flames: Array) -> void:
	_remove_bomb_view(id)
	var view := ExplosionView.new()
	view.setup(flames, Rules.ticks_to_seconds(Rules.FLAME_TICKS))
	effects.add_child(view)


func _on_item_revealed(cell: Vector2i, item: int) -> void:
	var view := ItemView.new()
	view.setup(item)
	view.position = Grid.cell_to_world(cell)
	effects.add_child(view)
	_item_views[cell] = view


func _on_item_removed(cell: Vector2i, _item: int, _reason: int) -> void:
	if _item_views.has(cell):
		_item_views[cell].queue_free()
		_item_views.erase(cell)


func _show_pickup(player: Node3D, item: int) -> void:
	_show_popup(player, Items.display_name(item).to_upper() + "!", Items.color(item).lightened(0.3))


func _show_popup(player: Node3D, text: String, color: Color) -> void:
	var popup := PickupPopup.new()
	popup.setup(text, color)
	popup.position = player.position
	effects.add_child(popup)


func _remove_bomb_view(id: int) -> void:
	if _bomb_views.has(id):
		_bomb_views[id].queue_free()
		_bomb_views.erase(id)


func _living_player_at(cell: Vector2i) -> bool:
	for player in players:
		if player and player.alive and player.get_cell() == cell:
			return true
	return false


## WebGL compiles a shader the first time it is drawn, which stalls that frame. Draw one bomb and
## one fireball out of sight (under the floor) at load, so the first real explosion is smooth.
func _warm_up_effects() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var centre: Vector3 = arena.get_bounds().get_center()
	var hidden_spot := Vector3(centre.x, -3.0, centre.z)
	var bomb := BombView.new()
	var boom := ExplosionView.new()
	boom.setup([{"cell": Vector2i.ZERO, "kind": BombField.Flame.CENTER, "axis": Vector2i.ZERO}], 60.0)
	var item := ItemView.new()
	var popup := PickupPopup.new()
	popup.setup("WARM UP", Color.WHITE)
	for node: Node3D in [bomb, boom, item, popup]:
		node.position = hidden_spot
		add_child(node)  # not under Effects, which is cleared when arenas rebuild
	for i in 3:
		await get_tree().process_frame
	for node: Node3D in [bomb, boom, item, popup]:
		if is_instance_valid(node):
			node.queue_free()


func _update_hint() -> void:
	var joined := InputRouter.joined_count()
	hint.visible = allow_drop_in
	var lines: Array[String] = []
	if joined < InputRouter.MAX_SLOTS:
		lines.append("Join: Cross / Space / Enter")
	if joined > 0:
		lines.append("Start: Options / Tab / P" + ("  (1 player = practice)" if joined == 1 else ""))
	hint.text = "\n".join(lines)
