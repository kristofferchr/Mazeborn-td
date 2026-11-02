extends SceneTree
## Minimal headless test runner. Runs every `test_*` method in tests/**/test_*.gd.
## Usage: scripts/test.sh

const TESTS_DIR := "res://tests"

var _failures: Array[String] = []
var _current := ""


func _initialize() -> void:
	var files := _find_tests(TESTS_DIR)
	var count := 0
	for file in files:
		var script: GDScript = load(file)
		for method in script.get_script_method_list():
			var name: String = method.name
			if not name.begins_with("test_"):
				continue
			var case: Object = script.new()
			case.set("t", self)
			_current = "%s::%s" % [file.get_file(), name]
			var before := _failures.size()
			case.call(name)
			count += 1
			print(("  ok   " if _failures.size() == before else "  FAIL ") + _current)
	print("\n%d tests, %d failures" % [count, _failures.size()])
	for f in _failures:
		printerr("FAIL: " + f)
	quit(1 if not _failures.is_empty() or count == 0 else 0)


func check(cond: bool, msg := "expected true") -> void:
	if not cond:
		_failures.append("%s: %s" % [_current, msg])


func eq(actual: Variant, expected: Variant, msg := "") -> void:
	check(actual == expected, "%s expected %s, got %s" % [msg, expected, actual])


func _find_tests(dir: String) -> Array[String]:
	var out: Array[String] = []
	for sub in DirAccess.get_directories_at(dir):
		out.append_array(_find_tests(dir.path_join(sub)))
	for f in DirAccess.get_files_at(dir):
		if f.begins_with("test_") and f.ends_with(".gd"):
			out.append(dir.path_join(f))
	out.sort()
	return out
