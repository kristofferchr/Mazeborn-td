class_name UserSettings
extends RefCounted
## The player's settings in user://settings.cfg: mute, music and sound-effect
## volume (0..1), the default game speed (1x or 2x) and the last map,
## difficulty and mode chosen in the menu. save() writes these keys and keeps any other
## key in the file.

const PATH := "user://settings.cfg"
const SPEEDS: Array[int] = [1, 2]

var path: String
var muted := false
var music_volume := 0.8
var sfx_volume := 1.0
var speed := 1
var difficulty := Difficulty.DEFAULT
var map_id := Maps.DEFAULT
var mode := Progress.CLASSIC  # "classic" or "endless"


func _init(p_path := PATH) -> void:
	path = p_path


static func open(p_path := PATH) -> UserSettings:
	var s := UserSettings.new(p_path)
	s.load_file()
	return s


func load_file() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return
	muted = bool(cfg.get_value("audio", "muted", muted))
	music_volume = clampf(float(cfg.get_value("audio", "music_volume", music_volume)), 0.0, 1.0)
	sfx_volume = clampf(float(cfg.get_value("audio", "sfx_volume", sfx_volume)), 0.0, 1.0)
	var s := int(cfg.get_value("game", "speed", speed))
	speed = s if s in SPEEDS else 1
	var d := str(cfg.get_value("menu", "difficulty", difficulty))
	difficulty = d if Difficulty.exists(d) else Difficulty.DEFAULT
	var m := str(cfg.get_value("menu", "map", map_id))
	map_id = m if Maps.exists(m) else Maps.DEFAULT
	mode = Progress.mode_of({"mode": cfg.get_value("menu", "mode", mode)})


func save() -> Error:
	var cfg := ConfigFile.new()
	cfg.load(path)  # keep keys this class does not know
	cfg.set_value("audio", "muted", muted)
	cfg.set_value("audio", "music_volume", music_volume)
	cfg.set_value("audio", "sfx_volume", sfx_volume)
	cfg.set_value("game", "speed", speed)
	cfg.set_value("menu", "difficulty", difficulty)
	cfg.set_value("menu", "map", map_id)
	cfg.set_value("menu", "mode", mode)
	return cfg.save(path)


## Bus volume in dB for a slider value 0..1 (squared, so the slider feels even).
static func volume_db(value: float) -> float:
	return linear_to_db(clampf(value, 0.0, 1.0) ** 2) if value > 0.001 else -80.0
