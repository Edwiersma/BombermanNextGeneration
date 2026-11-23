class_name PlayerStats
extends RefCounted
## A player's abilities for the current round, changed by items. Pure data: the Player node reads
## it, Match applies picked-up items and flame hits, and `collected` is what gets scattered on death.
##
## Protection (fire only; sudden-death blocks always crush):
## - Heart: absorbs one hit, then a short grace period of invulnerability. Carry one at most.
## - Safety Vest: invulnerable for Rules.VEST_TICKS. Picking up another restarts it.

var max_bombs := Rules.START_BOMBS
var fire_range := Rules.START_FIRE
var speed_level := Rules.START_SPEED_LEVEL
## Every item picked up this round, in order.
var collected: Array[int] = []
var has_heart := false
var has_kick := false   # walk into a bomb to kick it
var has_punch := false  # special punches the bomb in front
## Power Glove, Super Power Glove or Line Bomb (one at a time), or Items.NONE.
var slot_a := Items.NONE
## Remote Control, Piercing Bomb, Power Bomb, Land Mine or Bouncy Bomb (one at a time), or NONE.
var slot_b := Items.NONE
var vest_ticks := 0   # Safety Vest time left
var grace_ticks := 0  # invulnerable after a Heart absorbed a hit
## Current curse (Curses.Type) and its time left; swap_timer drives the Swap curse.
var curse: int = Curses.Type.NONE
var curse_ticks := 0
var swap_timer := 0


## Fresh stats for a new round.
func reset(settings: MatchSettings) -> void:
	max_bombs = settings.start_bombs
	fire_range = settings.start_fire
	speed_level = Rules.START_SPEED_LEVEL
	collected.clear()
	has_heart = false
	has_kick = false
	has_punch = false
	slot_a = Items.NONE
	slot_b = Items.NONE
	vest_ticks = 0
	grace_ticks = 0
	clear_curse()


## Counts protection and curse timers down; call once per tick of play.
func tick() -> void:
	vest_ticks = maxi(vest_ticks - 1, 0)
	grace_ticks = maxi(grace_ticks - 1, 0)
	if curse != Curses.Type.NONE:
		curse_ticks -= 1
		if curse_ticks <= 0:
			clear_curse()


func set_curse(new_curse: int, ticks: int) -> void:
	curse = new_curse
	curse_ticks = ticks
	swap_timer = Rules.TICKS_PER_SECOND  # first swap after a second


func clear_curse() -> void:
	curse = Curses.Type.NONE
	curse_ticks = 0
	swap_timer = 0


func is_cursed() -> bool:
	return curse != Curses.Type.NONE


func has_curse(which: int) -> bool:
	return curse == which


## Bombs allowed out at once, after curses (No Power: 1).
func bomb_capacity() -> int:
	return 1 if curse == Curses.Type.NO_POWER else max_bombs


## Blast range for new bombs, after curses (No Power: 1).
func blast_range() -> int:
	return 1 if curse == Curses.Type.NO_POWER else fire_range


## Fuse for new bombs, after curses.
func bomb_fuse() -> int:
	match curse:
		Curses.Type.SHORT_FUSE:
			return Rules.SHORT_FUSE_TICKS
		Curses.Type.LONG_FUSE:
			return Rules.LONG_FUSE_TICKS
	return Rules.BOMB_FUSE_TICKS


func is_invulnerable() -> bool:
	return vest_ticks > 0 or grace_ticks > 0


## The player is in fire. Returns true when that kills them.
func take_hit() -> bool:
	if is_invulnerable():
		return false
	if has_heart:
		has_heart = false
		grace_ticks = Rules.HEART_GRACE_TICKS
		return false
	return true


func has_glove() -> bool:
	return slot_a == Items.Type.GLOVE or slot_a == Items.Type.SUPER_GLOVE


func has_super_glove() -> bool:
	return slot_a == Items.Type.SUPER_GLOVE


func has_line_bomb() -> bool:
	return slot_a == Items.Type.LINE_BOMB


func has_remote() -> bool:
	return slot_b == Items.Type.REMOTE


func has_pierce() -> bool:
	return slot_b == Items.Type.PIERCE


func has_power_bomb() -> bool:
	return slot_b == Items.Type.POWER_BOMB


func has_land_mine() -> bool:
	return slot_b == Items.Type.LAND_MINE


func has_bouncy() -> bool:
	return slot_b == Items.Type.BOUNCY


func speed() -> float:
	match curse:
		Curses.Type.TOO_FAST:
			return Rules.CURSE_FAST_SPEED
		Curses.Type.TOO_SLOW:
			return Rules.CURSE_SLOW_SPEED
	return Rules.PLAYER_SPEED + (speed_level - Rules.START_SPEED_LEVEL) * Rules.SPEED_STEP


func apply(item: int) -> void:
	match item:
		Items.Type.BOMB_UP:
			max_bombs = mini(max_bombs + 1, Rules.MAX_BOMBS)
		Items.Type.FIRE_UP:
			fire_range = mini(fire_range + 1, Rules.MAX_FIRE)
		Items.Type.FULL_FIRE:
			fire_range = Rules.MAX_FIRE
		Items.Type.SPEED_UP:
			speed_level = mini(speed_level + 1, Rules.MAX_SPEED_LEVEL)
		Items.Type.SPEED_DOWN:
			speed_level = maxi(speed_level - 1, Rules.MIN_SPEED_LEVEL)
		Items.Type.HEART:
			has_heart = true
		Items.Type.VEST:
			vest_ticks = Rules.VEST_TICKS
		Items.Type.KICK:
			has_kick = true
		Items.Type.PUNCH:
			has_punch = true
		Items.Type.GLOVE, Items.Type.SUPER_GLOVE, Items.Type.LINE_BOMB:
			slot_a = item
		Items.Type.REMOTE, Items.Type.PIERCE, Items.Type.POWER_BOMB, Items.Type.LAND_MINE, Items.Type.BOUNCY:
			slot_b = item
	collected.append(item)
