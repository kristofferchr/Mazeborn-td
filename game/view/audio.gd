class_name GameAudio
extends Node
## Sound effects and music. Listens to the Game's signals (the core knows
## nothing about audio). Sounds: assets/audio/*.ogg, made by scripts/make_sfx.py.
## A small pool of players with per-sound limits and random pitch keeps twenty
## towers from turning into noise. Two music layers play in sync: the calm one
## always, the drums fade in during a wave. Music and effects play on their own
## buses ("Music", "Sfx") with the volumes from the settings; mute silences the
## master bus. Settings: UserSettings (user://settings.cfg). The music ducks
## while the game is paused. Browsers block audio until a user gesture, so on
## the web it starts on the first tap.

signal muted_changed(muted: bool)

const DIR := "res://assets/audio/"
const MUSIC_BUS := "Music"
const SFX_BUS := "Sfx"
const DUCK_DB := -12.0  # music while paused
const POOL_SIZE := 16
const MUSIC_DB := -11.0  # calm layer
const BATTLE_DB := -9.0  # drum layer during a wave
const SILENT_DB := -60.0
const FIRE_SOUNDS := {
	"arrow": "fire_arrow",
	"earth": "fire_earth",
	"wind": "fire_wind",
	"elemental": "fire_arcane",
}
const ELEMENT_FIRE := {
	"fire": "fire_fire",
	"ice": "fire_ice",
	"lightning": "fire_lightning",
	"nature": "fire_nature",
}
const IMPACT_SOUNDS := {
	"arrow": "impact_arrow",
	"earth": "impact_earth",
	"wind": "impact_wind",
	"elemental": "impact_magic",
}
const ELEMENT_IMPACT := {
	"fire": "impact_fire",
	"ice": "impact_ice",
	"lightning": "zap_small",
	"nature": "impact_nature",
}
## Game and UI events and their sound.
const EVENTS := {
	"build": "build",
	"upgrade": "upgrade",
	"sell": "sell",
	"chain": "zap_small",
	"death": "creep_death",
	"coin": "coin",
	"leak": "leak",
	"wave_start": "wave_start",
	"wave_cleared": "wave_cleared",
	"victory": "victory",
	"defeat": "defeat",
	"click": "click",
}
const MUSIC := {"calm": "music_calm", "battle": "music_battle"}
## Per sound: [volume dB, max playing at once, min seconds between starts,
## pitch spread, priority]. A full pool steals the oldest voice of the same or
## lower priority.
const MIX := {
	"fire_arrow": [-15.0, 3, 0.06, 0.12, 0],
	"fire_earth": [-11.0, 2, 0.1, 0.08, 0],
	"fire_wind": [-17.0, 2, 0.08, 0.15, 0],
	"fire_arcane": [-15.0, 2, 0.08, 0.1, 0],
	"fire_fire": [-13.0, 2, 0.1, 0.1, 0],
	"fire_ice": [-13.0, 2, 0.09, 0.1, 0],
	"fire_lightning": [-15.0, 2, 0.1, 0.1, 0],
	"fire_nature": [-14.0, 2, 0.08, 0.15, 0],
	"impact_arrow": [-16.0, 3, 0.05, 0.15, 0],
	"impact_earth": [-10.0, 2, 0.12, 0.1, 0],
	"impact_wind": [-15.0, 2, 0.08, 0.15, 0],
	"impact_magic": [-15.0, 2, 0.08, 0.12, 0],
	"impact_fire": [-12.0, 2, 0.1, 0.1, 0],
	"impact_ice": [-13.0, 2, 0.1, 0.12, 0],
	"impact_nature": [-13.0, 2, 0.1, 0.15, 0],
	"zap_small": [-16.0, 2, 0.06, 0.15, 0],
	"creep_death": [-9.0, 3, 0.06, 0.15, 1],
	"coin": [-16.0, 2, 0.08, 0.05, 1],
	"build": [-5.0, 2, 0.05, 0.06, 2],
	"upgrade": [-5.0, 1, 0.05, 0.0, 2],
	"sell": [-6.0, 1, 0.05, 0.0, 2],
	"click": [-12.0, 2, 0.03, 0.05, 2],
	"leak": [-5.0, 1, 0.4, 0.0, 3],
	"wave_start": [-4.0, 1, 0.5, 0.0, 3],
	"wave_cleared": [-5.0, 1, 0.5, 0.0, 3],
	"victory": [-3.0, 1, 1.0, 0.0, 3],
	"defeat": [-3.0, 1, 1.0, 0.0, 3],
}
const DEFAULT_MIX := [-8.0, 2, 0.05, 0.05, 1]

## Browsers only allow audio after a user gesture; kept across scene reloads.
static var _unlocked := not OS.has_feature("web")
static var _duck := 0.0  # extra dB on the music bus (DUCK_DB while paused)
static var _music_volume := 1.0  # slider values 0..1 from the settings
static var _sfx_volume := 1.0

var muted := false
var _game: Game
var _duck_tween: Tween
var _streams: Dictionary = {}  # sound -> AudioStream
var _pool: Array[AudioStreamPlayer] = []
var _last_start: Dictionary = {}  # sound -> msec of the last start
var _calm: AudioStreamPlayer
var _battle: AudioStreamPlayer
var _battle_tween: Tween


## Sound of a tower kind (and element) firing.
static func fire_sound(kind: String, element := "") -> String:
	if element != "" and ELEMENT_FIRE.has(element):
		return ELEMENT_FIRE[element]
	return FIRE_SOUNDS.get(kind, FIRE_SOUNDS.arrow)


## Sound of a shot from a tower kind (and element) landing.
static func impact_sound(kind: String, element := "") -> String:
	if element != "" and ELEMENT_IMPACT.has(element):
		return ELEMENT_IMPACT[element]
	return IMPACT_SOUNDS.get(kind, IMPACT_SOUNDS.arrow)


static func sound_path(sound: String) -> String:
	return DIR + sound + ".ogg"


## Every sound this node may play.
static func all_sounds() -> Array[String]:
	var out: Array[String] = []
	for table: Dictionary in [
		FIRE_SOUNDS, ELEMENT_FIRE, IMPACT_SOUNDS, ELEMENT_IMPACT, EVENTS, MUSIC
	]:
		for key: String in table:
			if str(table[key]) not in out:
				out.append(str(table[key]))
	return out


## Index of an audio bus, made (sending to the master bus) if it is missing.
static func bus(bus_name: String) -> int:
	var i := AudioServer.get_bus_index(bus_name)
	if i < 0:
		AudioServer.add_bus()
		i = AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, bus_name)
		AudioServer.set_bus_send(i, "Master")
	return i


## Sets the music and effect volumes (slider values 0..1), live.
static func set_volumes(music: float, sfx: float) -> void:
	_music_volume = music
	_sfx_volume = sfx
	_apply_volumes()


static func _apply_volumes() -> void:
	AudioServer.set_bus_volume_db(bus(MUSIC_BUS), UserSettings.volume_db(_music_volume) + _duck)
	AudioServer.set_bus_volume_db(bus(SFX_BUS), UserSettings.volume_db(_sfx_volume))


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = SFX_BUS
		add_child(p)
		_pool.append(p)
	bus(MUSIC_BUS)
	bus(SFX_BUS)
	_calm = _music_player(MUSIC.calm, MUSIC_DB)
	_battle = _music_player(MUSIC.battle, SILENT_DB)
	_load_settings()
	set_ducked(false, 0.0)
	if _unlocked:
		_start_music()
	# Every button in the scene clicks (also ones made later, like upgrade cards).
	get_tree().node_added.connect(_on_node_added)
	for b: Node in get_tree().root.find_children("*", "BaseButton", true, false):
		_on_node_added(b)


## The duck lives on the shared music bus: never leave it down after a round.
func _exit_tree() -> void:
	if _duck_tween:
		_duck_tween.kill()
	_set_duck(0.0)


func setup(p_game: Game) -> void:
	_game = p_game
	_game.tower_built.connect(func(_t: Tower) -> void: play_event("build"))
	_game.tower_upgraded.connect(func(_t: Tower) -> void: play_event("upgrade"))
	_game.tower_sold.connect(func(_t: Tower, _r: int) -> void: play_event("sell"))
	_game.tower_fired.connect(_on_tower_fired)
	_game.projectile_hit.connect(_on_projectile_hit)
	_game.chain_hit.connect(func(_from: Vector2, _c: Creep) -> void: play_event("chain"))
	_game.creep_killed.connect(_on_creep_killed)
	_game.creep_leaked.connect(func(_c: Creep) -> void: play_event("leak"))
	_game.wave_started.connect(_on_wave_started)
	_game.wave_cleared.connect(_on_wave_cleared)
	_game.gold_bonus.connect(_on_gold_bonus)
	_game.game_over.connect(_on_game_over)


func play_event(event: String, pitch := 1.0, volume := 0.0) -> bool:
	return play(EVENTS[event], pitch, volume)


## Plays a sound unless it is muted, too frequent or already playing too often.
## Returns true if it started.
func play(sound: String, pitch := 1.0, volume := 0.0) -> bool:
	if muted or not _unlocked:
		return false
	var mix: Array = MIX.get(sound, DEFAULT_MIX)
	var now := Time.get_ticks_msec()
	if now - int(_last_start.get(sound, -100000)) < int(float(mix[2]) * 1000.0):
		return false
	var playing := 0
	var free: AudioStreamPlayer = null
	var steal: AudioStreamPlayer = null
	for p in _pool:
		if not p.playing:
			if free == null:
				free = p
			continue
		if p.get_meta("sound", "") == sound:
			playing += 1
		var older: bool = steal == null or int(p.get_meta("at", 0)) < int(steal.get_meta("at", 0))
		if int(p.get_meta("priority", 0)) <= int(mix[4]) and older:
			steal = p
	if playing >= int(mix[1]):
		return false
	var player := free if free else steal
	if player == null:
		return false
	var stream := _stream(sound)
	if stream == null:
		return false
	_last_start[sound] = now
	player.stream = stream
	player.volume_db = float(mix[0]) + volume
	var spread := float(mix[3])
	player.pitch_scale = maxf(pitch * (1.0 + randf_range(-spread, spread)), 0.05)
	player.set_meta("sound", sound)
	player.set_meta("at", now)
	player.set_meta("priority", int(mix[4]))
	player.play()
	return true


func set_muted(value: bool) -> void:
	muted = value
	AudioServer.set_bus_mute(0, muted)
	var settings := UserSettings.open()
	settings.muted = muted
	settings.save()
	muted_changed.emit(muted)


func toggle_muted() -> void:
	set_muted(not muted)


## Fades the music down while paused (or back up).
func set_ducked(on: bool, seconds := 0.3) -> void:
	if _duck_tween:
		_duck_tween.kill()
	var to := DUCK_DB if on else 0.0
	if seconds <= 0.0:
		_set_duck(to)
		return
	_duck_tween = create_tween()
	_duck_tween.tween_method(_set_duck, _duck, to, seconds)


func _set_duck(db: float) -> void:
	_duck = db
	_apply_volumes()


func _load_settings() -> void:
	var settings := UserSettings.open()
	muted = settings.muted
	AudioServer.set_bus_mute(0, muted)
	set_volumes(settings.music_volume, settings.sfx_volume)


func _stream(sound: String) -> AudioStream:
	if not _streams.has(sound):
		var path := sound_path(sound)
		_streams[sound] = load(path) as AudioStream if ResourceLoader.exists(path) else null
	return _streams[sound]


func _music_player(sound: String, db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	var stream := _stream(sound)
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	p.stream = stream
	p.volume_db = db
	p.bus = MUSIC_BUS
	add_child(p)
	return p


func _start_music() -> void:
	if _calm.stream and not _calm.playing:
		# Start both layers together so they stay in time.
		_calm.play()
		_battle.play()
		if _game and _game.phase == Game.Phase.WAVE:
			_battle.volume_db = BATTLE_DB


## Fades the drum layer in (during a wave) or out.
func _set_battle(on: bool, seconds: float) -> void:
	if _battle_tween:
		_battle_tween.kill()
	_battle_tween = create_tween()
	_battle_tween.tween_property(_battle, "volume_db", BATTLE_DB if on else SILENT_DB, seconds)


func _input(event: InputEvent) -> void:
	if _unlocked:
		return
	var gesture := (
		(event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed)
		or (event is InputEventMouseButton and (event as InputEventMouseButton).pressed)
		or (event is InputEventKey and (event as InputEventKey).pressed)
	)
	if gesture:
		_unlocked = true
		_start_music()


func _on_node_added(node: Node) -> void:
	if node is BaseButton and not node.has_meta("click"):
		node.set_meta("click", true)
		(node as BaseButton).pressed.connect(func() -> void: play_event("click"))


func _on_tower_fired(tower: Tower, _creep: Creep, _damage: int) -> void:
	play(fire_sound(tower.kind, tower.element()))


func _on_projectile_hit(p: Projectile, creep: Creep) -> void:
	if creep or p.stats.has("splash_radius"):
		play(impact_sound(p.kind, p.element))


func _on_creep_killed(creep: Creep) -> void:
	if creep.kind == "boss":
		play_event("death", 0.6, 5.0)
	else:
		play_event("death", 1.15 if creep.flying else 1.0)
	play_event("coin")


func _on_wave_started(_number: int) -> void:
	play_event("wave_start")
	_set_battle(true, 2.0)


func _on_wave_cleared(number: int) -> void:
	if number < _game.waves.size():
		play_event("wave_cleared")  # the last one gets the victory fanfare
	_set_battle(false, 4.0)


func _on_gold_bonus(_amount: int, reason: String) -> void:
	if reason == "early":
		play_event("coin", 0.9)


func _on_game_over(won: bool) -> void:
	play_event("victory" if won else "defeat")
	_set_battle(false, 1.5)
	create_tween().tween_property(_calm, "volume_db", MUSIC_DB - 8.0, 1.5)
