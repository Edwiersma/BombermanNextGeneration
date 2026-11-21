class_name Scenes
extends RefCounted
## Scene paths and switching, in one place.

const MENU := "res://scenes/menu/main_menu.tscn"
const LOBBY := "res://scenes/menu/lobby.tscn"
const MATCH := "res://scenes/game/match.tscn"
const RESULTS := "res://scenes/menu/results.tscn"
const CONTROLLER_TEST := "res://scenes/debug/controller_test.tscn"

## Names usable with ?scene=<name> (web) or --scene=<name> (desktop) for development.
const BY_NAME := {
	"menu": MENU,
	"lobby": LOBBY,
	"match": MATCH,
	"results": RESULTS,
	"controller_test": CONTROLLER_TEST,
}


static func go(path: String) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	tree.paused = false
	tree.change_scene_to_file.call_deferred(path)
