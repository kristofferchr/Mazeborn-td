class_name Haptics
extends RefCounted
## Vibration on phones: a light tap when a tower is built, upgraded or sold,
## and a stronger one when a creep leaks or a boss dies. Uses
## Input.vibrate_handheld (duration and, where supported, amplitude). Only on
## iOS and Android (also the Android browser); on desktop and the iPhone
## browser, which cannot vibrate, every call is a no-op. Switched off with
## "Vibrasjon" in the settings (UserSettings.vibration).

const LIGHT := {"ms": 12, "amplitude": 0.35, "gap": 0.04}  # gap: min seconds between pulses
const STRONG := {"ms": 45, "amplitude": 1.0, "gap": 0.25}
## Platforms (OS feature tags) that can vibrate. The web build only on Android:
## Safari has no vibration.
const PLATFORMS: Array[String] = ["ios", "android", "web_android"]

static var enabled := true  # the setting
static var supported := supported_on(_features())
## Tests: receives (ms, amplitude) instead of the device.
static var sink := Callable()
static var _last: Dictionary = {}  # "light"/"strong" -> msec of the last pulse


## True if a platform with these OS feature tags can vibrate.
static func supported_on(features: Array[String]) -> bool:
	for f in features:
		if f in PLATFORMS:
			return true
	return false


static func _features() -> Array[String]:
	var out: Array[String] = []
	for f in PLATFORMS:
		if OS.has_feature(f):
			out.append(f)
	return out


## Reads the setting (call when a round starts or the setting changes).
static func load_setting(settings: UserSettings) -> void:
	enabled = settings.vibration


static func light() -> bool:
	return _pulse("light", LIGHT)


static func strong() -> bool:
	return _pulse("strong", STRONG)


## Pulses for the game's events: build, upgrade and sell, leaks and bosses.
static func watch(game: Game) -> void:
	game.tower_built.connect(func(_t: Tower) -> void: light())
	game.tower_upgraded.connect(func(_t: Tower) -> void: light())
	game.tower_sold.connect(func(_t: Tower, _r: int) -> void: light())
	game.creep_leaked.connect(func(_c: Creep) -> void: strong())
	game.creep_killed.connect(
		func(c: Creep) -> void:
			if c.kind == "boss":
				strong()
	)


## Vibrates unless switched off, unsupported or too soon after the last one of
## the same kind. Returns true if it did.
static func _pulse(key: String, p: Dictionary) -> bool:
	if not enabled or not supported:
		return false
	var now := Time.get_ticks_msec()
	if now - int(_last.get(key, -100000)) < int(float(p.gap) * 1000.0):
		return false
	_last[key] = now
	if sink.is_valid():
		sink.call(int(p.ms), float(p.amplitude))
	else:
		Input.vibrate_handheld(int(p.ms), float(p.amplitude))
	return true
