extends SceneTree
## Headless test runner. Runs every test_* method in res://tests/test_*.gd.
##   godot --headless --path . -s tests/run_tests.gd
## Exit code is the number of failed tests.


func _initialize() -> void:
	var passed := 0
	var failed := 0
	var files := Array(DirAccess.get_files_at("res://tests"))
	files.sort()
	for file: String in files:
		if not (file.begins_with("test_") and file.ends_with(".gd")) or file == "test_suite.gd":
			continue
		var script: GDScript = load("res://tests/" + file)
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
