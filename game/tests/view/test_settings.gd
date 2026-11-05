extends RefCounted
## Tests for view/user_settings.gd and the audio buses in view/audio.gd.

const TEMP := "user://test_settings.cfg"

var t: Object  # test runner (check/eq)


func _clean_up() -> void:
	for p: String in [TEMP, TEMP + ".bak", TEMP + ".tmp"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


func test_corrupt_settings_are_kept_as_backup() -> void:
	_clean_up()
	var garbage := "[audio]\nmuted=tr[ue\nmusic_volume="
	var f := FileAccess.open(TEMP, FileAccess.WRITE)
	f.store_string(garbage)
	f.close()
	var s := UserSettings.open(TEMP)
	t.eq(s.speed, 1, "defaults")
	t.eq(FileAccess.get_file_as_string(TEMP + ".bak"), garbage, "kept as .bak")
	s.speed = 2
	t.eq(s.save(), OK, "saved")
	t.eq(UserSettings.open(TEMP).speed, 2, "the new file loads")
	t.eq(FileAccess.get_file_as_string(TEMP + ".bak"), garbage, "the .bak is untouched")
	t.check(not FileAccess.file_exists(TEMP + ".tmp"), "no temp file left")
	_clean_up()


func test_defaults_without_a_file() -> void:
	_clean_up()
	var s := UserSettings.open(TEMP)
	t.eq(s.muted, false, "not muted")
	t.check(s.music_volume > 0.0 and s.music_volume <= 1.0, "music on")
	t.eq(s.sfx_volume, 1.0, "effects at full volume")
	t.eq(s.speed, 1, "1x")
	t.eq(s.difficulty, "normal", "Normal")
	t.eq(s.map_id, Maps.DEFAULT, "default map")
	t.eq(s.mode, "classic", "classic mode")


func test_save_and_load_round_trip_keeps_other_keys() -> void:
	_clean_up()
	var cfg := ConfigFile.new()
	cfg.set_value("other", "key", 42)
	cfg.save(TEMP)
	var s := UserSettings.new(TEMP)
	s.muted = true
	s.music_volume = 0.25
	s.sfx_volume = 0.5
	s.speed = 2
	s.difficulty = "extreme"
	s.map_id = "klofta"
	s.mode = "endless"
	t.eq(s.save(), OK, "saved")
	var r := UserSettings.open(TEMP)
	t.eq(
		[r.muted, r.music_volume, r.sfx_volume, r.speed, r.difficulty, r.map_id, r.mode],
		[true, 0.25, 0.5, 2, "extreme", "klofta", "endless"],
		"loaded"
	)
	cfg = ConfigFile.new()
	cfg.load(TEMP)
	t.eq(cfg.get_value("other", "key"), 42, "unknown key kept")
	_clean_up()


func test_bad_values_fall_back() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "music_volume", 7.0)
	cfg.set_value("game", "speed", 5)
	cfg.set_value("menu", "difficulty", "nightmare")
	cfg.set_value("menu", "map", "atlantis")
	cfg.save(TEMP)
	var s := UserSettings.open(TEMP)
	t.eq(s.music_volume, 1.0, "volume clamped")
	t.eq(s.speed, 1, "unknown speed")
	t.eq(s.difficulty, "normal", "unknown difficulty")
	t.eq(s.map_id, Maps.DEFAULT, "unknown map")
	_clean_up()


func test_volume_curve() -> void:
	t.eq(UserSettings.volume_db(1.0), 0.0, "full volume is 0 dB")
	t.check(UserSettings.volume_db(0.0) <= -60.0, "zero is silent")
	t.check(UserSettings.volume_db(0.5) < -6.0, "half is quieter than -6 dB")
	t.check(UserSettings.volume_db(0.5) > UserSettings.volume_db(0.25), "rising")


func test_audio_buses_follow_the_volumes() -> void:
	GameAudio.set_volumes(0.5, 1.0)
	var music := GameAudio.bus(GameAudio.MUSIC_BUS)
	var sfx := GameAudio.bus(GameAudio.SFX_BUS)
	t.check(music > 0 and sfx > 0 and music != sfx, "own buses")
	t.eq(GameAudio.bus(GameAudio.MUSIC_BUS), music, "made once")
	t.check(
		is_equal_approx(AudioServer.get_bus_volume_db(music), UserSettings.volume_db(0.5)),
		"music bus volume"
	)
	t.eq(AudioServer.get_bus_volume_db(sfx), 0.0, "effects bus volume")
	GameAudio.set_volumes(1.0, 1.0)


func test_music_ducks_while_paused_and_comes_back_on_exit() -> void:
	var audio := GameAudio.new()
	(t as SceneTree).root.add_child(audio)
	var music := GameAudio.bus(GameAudio.MUSIC_BUS)
	var full := AudioServer.get_bus_volume_db(music)
	audio.set_ducked(true, 0.0)
	t.check(
		is_equal_approx(AudioServer.get_bus_volume_db(music), full + GameAudio.DUCK_DB), "ducked"
	)
	audio.set_ducked(false, 0.0)
	t.check(is_equal_approx(AudioServer.get_bus_volume_db(music), full), "back up")
	audio.set_ducked(true, 0.5)  # mid-fade when the round is left
	(t as SceneTree).root.remove_child(audio)
	t.check(is_equal_approx(AudioServer.get_bus_volume_db(music), full), "not left ducked")
	audio.free()
