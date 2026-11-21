extends Node3D
## Versus match root. M2: builds the arena from the level and frames the camera.
## Players, bombs and round flow are added here in later milestones.

@export var level: LevelData = preload("res://levels/classic.tres")
## Fixed seed for '?' cells; 0 picks a new random layout every time.
@export var rng_seed := 0

var grid: Grid

@onready var arena: Node3D = $Arena
@onready var camera: Camera3D = $Camera


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	if rng_seed != 0:
		rng.seed = rng_seed
	else:
		rng.randomize()
	grid = level.build_grid(rng)
	arena.build(grid)
	camera.frame(arena.get_bounds())
