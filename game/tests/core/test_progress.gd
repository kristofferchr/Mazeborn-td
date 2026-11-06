extends RefCounted
## Tests for core/progress.gd: star rules, best results and the file.

const TEMP := "user://test_progress.cfg"

var t: Object  # test runner (check/eq)


func _won(lives: int, stars: int) -> Dictionary:
	return {"won": true, "lives": lives, "wave": 12, "waves": 12, "stars": stars, "mode": "classic"}


func _lost(wave: int, lives := 0) -> Dictionary:
	return {"won": false, "lives": lives, "wave": wave, "waves": 12, "stars": 0, "mode": "classic"}


func _clean_up() -> void:
	for p: String in [TEMP, TEMP + ".bak", TEMP + ".tmp"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


func test_corrupt_file_is_kept_and_not_lost() -> void:
	_clean_up()
	var garbage := '[engen]\nnormal={"won": true, "lives": 1'
	var f := FileAccess.open(TEMP, FileAccess.WRITE)
	f.store_string(garbage)
	f.close()
	var p := Progress.new(TEMP)
	t.check(p.load_file() not in [OK, ERR_FILE_NOT_FOUND], "the file does not load")
	t.eq(p.best("engen", "normal"), {}, "nothing read from it")
	t.check(FileAccess.file_exists(TEMP + ".bak"), "kept as .bak")
	t.eq(FileAccess.get_file_as_string(TEMP + ".bak"), garbage, "the .bak holds the old file")
	t.check(p.record("klofta", "normal", _won(12, 2)), "a new result")
	t.eq(p.save(), OK, "saved")
	t.eq(Progress.open(TEMP).best("klofta", "normal"), _won(12, 2), "the new file loads")
	t.eq(FileAccess.get_file_as_string(TEMP + ".bak"), garbage, "the .bak is untouched")
	t.check(not FileAccess.file_exists(TEMP + ".tmp"), "no temp file left")
	t.eq(Progress.new(TEMP + ".missing").load_file(), ERR_FILE_NOT_FOUND, "a missing file")
	t.check(not FileAccess.file_exists(TEMP + ".missing.bak"), "no .bak for a missing file")
	_clean_up()


func test_save_replaces_the_file_atomically() -> void:
	_clean_up()
	var p := Progress.new(TEMP)
	p.record("engen", "normal", _lost(4))
	p.save()
	p.record("engen", "normal", _lost(8))
	t.eq(p.save(), OK, "saved over the old file")
	t.eq(Progress.open(TEMP).best("engen", "normal").wave, 8, "the newest result")
	t.check(not FileAccess.file_exists(TEMP + ".tmp"), "no temp file left")
	_clean_up()


func test_star_rules() -> void:
	t.eq(Progress.stars_for(false, 20, 20), 0, "a loss gives no stars")
	t.eq(Progress.stars_for(true, 1, 20), 1, "a win")
	t.eq(Progress.stars_for(true, 9, 20), 1, "under half the lives")
	t.eq(Progress.stars_for(true, 10, 20), 2, "half the lives (10 of 20)")
	t.eq(Progress.stars_for(true, 19, 20), 2, "one leak")
	t.eq(Progress.stars_for(true, 20, 20), 3, "no leaks")
	t.eq(Progress.stars_for(true, 5, 10), 2, "half of 10 lives (Ekstrem)")
	t.eq(Progress.stars_for(true, 14, 30), 1, "under half of 30 (Lett)")


func test_result_of_a_game() -> void:
	var g := Game.create_map("engen")
	g.wave = 12
	g.phase = Game.Phase.WON
	g.lives = 20
	t.eq(Progress.result_of(g), _won(20, 3), "flawless win")
	g.lives = 3
	t.eq(Progress.result_of(g).stars, 1, "narrow win")
	g.phase = Game.Phase.LOST
	g.lives = 0
	g.wave = 7
	t.eq(Progress.result_of(g), _lost(7), "loss on wave 7")


func test_better_results() -> void:
	t.check(Progress.is_better(_lost(1), {}), "anything beats nothing")
	t.check(not Progress.is_better({}, _lost(1)), "nothing beats nothing")
	t.check(Progress.is_better(_won(1, 1), _lost(12, 5)), "a win beats a loss")
	t.check(Progress.is_better(_won(20, 3), _won(19, 2)), "more stars")
	t.check(Progress.is_better(_won(15, 2), _won(12, 2)), "more lives")
	t.check(not Progress.is_better(_won(12, 2), _won(12, 2)), "a tie is not better")
	t.check(Progress.is_better(_lost(9), _lost(8)), "further in a loss")
	t.check(not Progress.is_better(_lost(8), _lost(9)), "not as far")


func test_new_record() -> void:
	t.check(not Progress.is_new_record({}, _lost(5)), "a first loss is no record")
	t.check(Progress.is_new_record({}, _won(3, 1)), "a first win is")
	t.check(Progress.is_new_record(_lost(4), _lost(6)), "further than before")
	t.check(Progress.is_new_record(_won(10, 2), _won(20, 3)), "more stars")
	t.check(not Progress.is_new_record(_won(20, 3), _won(19, 2)), "worse")


func test_record_keeps_the_best_per_map_and_difficulty() -> void:
	var p := Progress.new(TEMP)
	t.eq(p.best("engen", "normal"), {}, "nothing yet")
	t.check(p.record("engen", "normal", _lost(6)), "first result")
	t.check(not p.record("engen", "normal", _lost(4)), "worse is not kept")
	t.eq(p.best("engen", "normal").wave, 6, "best wave")
	t.check(p.record("engen", "normal", _won(12, 2)), "win")
	t.check(p.record("engen", "hard", _won(15, 3)), "other difficulty")
	t.eq(p.stars("engen", "normal"), 2, "stars on Normal")
	t.eq(p.stars("engen", "hard"), 3, "stars on Vanskelig")
	t.eq(p.stars("klofta", "normal"), 0, "unplayed map")
	t.eq(p.total_stars("normal", ["engen", "klofta"] as Array[String]), 2, "total")


func test_save_and_load_round_trip() -> void:
	_clean_up()
	var empty := Progress.open(TEMP)
	t.eq(empty.best("engen", "normal"), {}, "no file yet")
	var p := Progress.new(TEMP)
	p.record("engen", "normal", _won(14, 2))
	p.record("klofta", "extreme", _lost(9, 0))
	p.record("tvillingportene", "easy", _won(30, 3))
	t.eq(p.save(), OK, "saved")
	var q := Progress.open(TEMP)
	t.eq(q.best("engen", "normal"), _won(14, 2), "engen normal")
	t.eq(q.best("klofta", "extreme"), _lost(9, 0), "klofta extreme")
	t.eq(q.best("tvillingportene", "easy"), _won(30, 3), "tvillingportene easy")
	t.eq(q.best("engen", "easy"), {}, "not played")
	_clean_up()


func test_hand_edited_file_is_cleaned() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("engen", "normal", {"won": 1, "lives": "7", "stars": 9})
	cfg.set_value("engen", "hard", "garbage")
	cfg.save(TEMP)
	var p := Progress.open(TEMP)
	t.eq(p.best("engen", "normal").stars, 3, "stars clamped")
	t.eq(p.best("engen", "normal").lives, 7, "lives as a number")
	t.eq(p.best("engen", "hard"), {}, "not a result")
	_clean_up()


func _endless(wave: int) -> Dictionary:
	return {"won": false, "lives": 0, "wave": wave, "waves": 0, "stars": 0, "mode": "endless"}


func test_endless_results() -> void:
	t.eq(Progress.mode_of({"mode": "endless"}), "endless", "endless mode")
	t.eq(Progress.mode_of({"difficulty": "hard"}), "classic", "classic by default")
	var g := Game.create_map("engen", 1, {"mode": "endless"})
	g.wave = 25  # sent early while losing
	g.cleared = 23
	g.lives = 0
	g.phase = Game.Phase.LOST
	t.eq(Progress.result_of(g), _endless(23), "endless result: the last wave cleared")
	t.check(Progress.is_new_record({}, _endless(5)), "a first endless round is a record")
	t.check(Progress.is_new_record(_endless(20), _endless(31)), "further")
	t.check(not Progress.is_new_record(_endless(31), _endless(20)), "not as far")


func test_endless_is_kept_apart_from_classic() -> void:
	_clean_up()
	var p := Progress.new(TEMP)
	t.check(p.record("engen", "hard", _won(15, 2)), "classic win")
	t.check(p.record("engen", "hard", _endless(40)), "endless round")
	t.eq(p.best("engen", "hard").wave, 12, "classic best")
	t.eq(p.best("engen", "hard", "endless").wave, 40, "endless best")
	t.eq(p.stars("engen", "hard"), 2, "stars come from classic")
	t.check(not p.record("engen", "hard", _endless(30)), "worse endless round")
	p.save()
	var q := Progress.open(TEMP)
	t.eq(q.best("engen", "hard", "endless"), _endless(40), "endless after load")
	t.eq(q.best("engen", "hard"), _won(15, 2), "classic after load")
	var cfg := ConfigFile.new()
	cfg.load(TEMP)
	t.check(cfg.has_section_key("engen", "hard_endless"), "endless key in the file")
	_clean_up()
