extends Node
## Entry point. Opens the default scene, or one picked for development:
##   browser:  http://localhost:8060/?scene=controller_test
##   desktop:  godot --path . -- --scene=controller_test

const SCENES := {
	"match": "res://scenes/game/match.tscn",
	"controller_test": "res://scenes/debug/controller_test.tscn",
}
const DEFAULT_SCENE := "match"  # becomes the main menu in M6


func _ready() -> void:
	var requested := _requested_scene()
	if requested != "" and not SCENES.has(requested):
		push_warning("Unknown scene '%s'; options: %s" % [requested, ", ".join(SCENES.keys())])
	var path: String = SCENES.get(requested, SCENES[DEFAULT_SCENE])
	get_tree().change_scene_to_file.call_deferred(path)


func _requested_scene() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--scene="):
			return arg.trim_prefix("--scene=")
	if OS.has_feature("web"):
		var value = JavaScriptBridge.eval("new URLSearchParams(window.location.search).get('scene') || ''")
		if value is String:
			return value
	return ""
