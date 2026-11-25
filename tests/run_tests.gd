extends SceneTree
## Headless test runner. Runs every test_* method in res://tests/test_*.gd.
##   godot --headless --path . -s tests/run_tests.gd
## Exit code is the number of failed tests.
## After adding a script with a new class_name, run `godot --headless --path . --import` once so
## Godot registers the class (a -s run does not rescan the project).


## Counts script errors (a test that crashes halfway stops silently, so its failed checks would
## never be reached; the error count catches it).
class ErrorCounter extends Logger:
	var count := 0

	func _log_error(_function: String, _file: String, _line: int, _code: String, _rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_SCRIPT:
			count += 1

	func _log_message(_message: String, _error: bool) -> void:
		pass


var _done := false


## Runs on the first frame rather than in _initialize, so the tree is live and nodes added by
## integration tests get _ready like in the game.
func _process(_delta: float) -> bool:
	if not _done:
		_done = true
		_run_all()
	return false


func _run_all() -> void:
	var errors := ErrorCounter.new()
	OS.add_logger(errors)
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
			var errors_before := errors.count
			var suite = script.new()
			suite.call(test_name)
			if errors.count > errors_before:
				suite.failures.append("script error (see above)")
			if suite.failures.is_empty():
				passed += 1
			else:
				failed += 1
				for failure in suite.failures:
					printerr("FAIL %s::%s  %s" % [file, test_name, failure])
	OS.remove_logger(errors)
	print("%d passed, %d failed" % [passed, failed])
	quit(failed)
