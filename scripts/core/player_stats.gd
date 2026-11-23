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
var vest_ticks := 0   # Safety Vest time left
var grace_ticks := 0  # invulnerable after a Heart absorbed a hit


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
	vest_ticks = 0
	grace_ticks = 0


## Counts protection timers down; call once per tick of play.
func tick() -> void:
	vest_ticks = maxi(vest_ticks - 1, 0)
	grace_ticks = maxi(grace_ticks - 1, 0)


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


func speed() -> float:
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
	collected.append(item)
