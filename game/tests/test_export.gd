extends RefCounted
## Guard for the export: tools/ and tests/ are left out of the web and iOS
## builds (exclude_filter in export_presets.cfg), so nothing else may use a
## class or a file from them.

const EXCLUDED := ["res://tools", "res://tests"]

var t: Object  # test runner (check/eq)


func _files(dir: String, exts: Array[String], out: Array[String]) -> void:
	for sub in DirAccess.get_directories_at(dir):
		if not sub.begins_with("."):
			_files(dir.path_join(sub), exts, out)
	for f in DirAccess.get_files_at(dir):
		if f.get_extension() in exts:
			out.append(dir.path_join(f))


func _excluded(path: String) -> bool:
	for dir: String in EXCLUDED:
		if path.begins_with(dir + "/"):
			return true
	return false


func test_nothing_in_the_export_uses_tools_or_tests() -> void:
	var tool_scripts: Array[String] = []
	_files("res://tools", ["gd"] as Array[String], tool_scripts)
	var names: Array[String] = []
	var re := RegEx.create_from_string("(?m)^class_name\\s+(\\w+)")
	for path in tool_scripts:
		for m in re.search_all(FileAccess.get_file_as_string(path)):
			names.append(m.get_string(1))
	t.check(not names.is_empty() or tool_scripts.is_empty(), "found the tool classes")
	var files: Array[String] = []
	_files("res://", ["gd", "tscn", "tres"] as Array[String], files)
	var checked := 0
	for path in files:
		if _excluded(path):
			continue
		checked += 1
		var text := FileAccess.get_file_as_string(path)
		for dir: String in EXCLUDED:
			t.check(not text.contains(dir + "/"), "%s refers to %s/" % [path, dir])
		for class_id in names:
			var use := RegEx.create_from_string("\\b%s\\b" % class_id)
			t.check(use.search(text) == null, "%s uses %s from tools/" % [path, class_id])
	t.check(checked > 10, "scanned the exported scripts (%d)" % checked)
