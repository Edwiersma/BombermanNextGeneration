extends SceneTree
## Headless test runner. Runs every test_* method in res://tests/test_*.gd.
##   godot --headless --path . -s tests/run_tests.gd
## Exit code is the number of failed tests.


var _done := false


## Runs on the first frame rather than in _initialize, so the tree is live and nodes added by
## integration tests get _ready like in the game.
func _process(_delta: float) -> bool:
	if not _done:
		_done = true
		_run_all()
	return false


func _run_all() -> void:
	var passed := 0
	var failed := 0
	var files := Array(DirAccess.get_files_at("res://tests"))
	files.sort()
	for file: String in files:
		if not (file.begins_with("test_") and file.ends_with(".gd")) or file == "test_suite.gd":
			continue
		var script: GDScript = load("res://tests/" + file)
		if script == null or not script.can_instantiate():
			failed += 1  # a file that does not compile must never look like a pass
			printerr("FAIL %s  could not be loaded (see the error above)" % file)
			continue
		for method in script.get_script_method_list():
			var test_name: String = method.name
			if not test_name.begins_with("test_"):
				continue
			var suite = script.new()
			suite.call(test_name)
			if suite.failures.is_empty():
				passed += 1
			else:
				failed += 1
				for failure in suite.failures:
					printerr("FAIL %s::%s  %s" % [file, test_name, failure])
	print("%d passed, %d failed" % [passed, failed])
	quit(failed)
