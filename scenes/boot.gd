extends Node
## Entry point. Opens the default scene, or one picked for development:
##   browser:  http://localhost:8060/?scene=controller_test
##   desktop:  godot --path . -- --scene=controller_test

const DEFAULT_SCENE := "menu"


func _ready() -> void:
	var requested := _requested_scene()
	if requested != "" and not Scenes.BY_NAME.has(requested):
		push_warning("Unknown scene '%s'; options: %s" % [requested, ", ".join(Scenes.BY_NAME.keys())])
	var path: String = Scenes.BY_NAME.get(requested, Scenes.BY_NAME[DEFAULT_SCENE])
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
