class_name PlayerStats
extends RefCounted
## A player's abilities for the current round, changed by items. Pure data: the Player node reads
## it, Match applies picked-up items, and `collected` is what gets scattered on death.

var max_bombs := Rules.START_BOMBS
var fire_range := Rules.START_FIRE
var speed_level := Rules.START_SPEED_LEVEL
## Every item picked up this round, in order.
var collected: Array[int] = []


## Fresh stats for a new round.
func reset(settings: MatchSettings) -> void:
	max_bombs = settings.start_bombs
	fire_range = settings.start_fire
	speed_level = Rules.START_SPEED_LEVEL
	collected.clear()


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
	collected.append(item)
