extends RefCounted
## Tests for view/haptics.gd: only phones vibrate, the setting switches it off
## and the game's events give light and strong pulses.

var t: Object  # test runner (check/eq)
var pulses: Array = []  # [ms, amplitude] sent to the sink


func _record(ms: int, amplitude: float) -> void:
	pulses.append([ms, amplitude])


func _setup(supported: bool, enabled: bool) -> void:
	pulses.clear()
	Haptics.sink = _record
	Haptics.supported = supported
	Haptics.enabled = enabled
	Haptics._last.clear()


func _restore() -> void:
	Haptics.sink = Callable()
	Haptics.supported = Haptics.supported_on(Haptics._features())
	Haptics.enabled = true
	Haptics._last.clear()


func test_only_phones_vibrate() -> void:
	t.check(Haptics.supported_on(["ios", "mobile"] as Array[String]), "iPhone app")
	t.check(Haptics.supported_on(["android"] as Array[String]), "Android app")
	t.check(Haptics.supported_on(["web", "web_android"] as Array[String]), "Android browser")
	t.check(not Haptics.supported_on(["web", "web_ios"] as Array[String]), "Safari cannot")
	t.check(not Haptics.supported_on(["linuxbsd", "pc"] as Array[String]), "desktop")
	t.check(not Haptics.supported, "the test machine is no phone")


func test_calls_are_guarded() -> void:
	_setup(false, true)
	t.check(not Haptics.light() and not Haptics.strong(), "no-op where unsupported")
	_setup(true, false)
	t.check(not Haptics.light() and not Haptics.strong(), "no-op when switched off")
	t.eq(pulses.size(), 0, "nothing reached the device")
	_setup(true, true)
	t.check(Haptics.light(), "light")
	t.check(not Haptics.light(), "too soon after the last")
	t.check(Haptics.strong(), "strong has its own gap")
	t.eq(pulses.size(), 2, "two pulses")
	t.check(pulses[1][0] > pulses[0][0] and pulses[1][1] > pulses[0][1], "strong is stronger")
	_restore()


func test_game_events_pulse() -> void:
	var game := Game.create_map("engen", 1)
	Haptics.watch(game)
	_setup(true, true)
	var tower := game.build(Vector2i(5, 3), "arrow")
	t.check(tower != null, "built")
	t.eq(pulses.size(), 1, "light tap on build")
	t.eq(pulses[0][0], Haptics.LIGHT.ms, "light")
	Haptics._last.clear()
	game.upgrade(Vector2i(5, 3))
	Haptics._last.clear()
	game.sell(Vector2i(5, 3))
	t.eq(pulses.size(), 3, "upgrade and sell tap too")
	var creep := Creep.new(1, 10.0, 1.0, 1, Vector2i.ZERO)
	creep.kind = "normal"
	game.creep_killed.emit(creep)
	t.eq(pulses.size(), 3, "an ordinary kill is quiet")
	creep.kind = "boss"
	game.creep_killed.emit(creep)
	t.eq(pulses[-1][0], Haptics.STRONG.ms, "boss death is strong")
	Haptics._last.clear()
	game.creep_leaked.emit(creep)
	t.eq(pulses.size(), 5, "a leak is strong")
	_restore()


func test_the_setting_is_read() -> void:
	var s := UserSettings.new("user://test_haptics.cfg")
	s.vibration = false
	Haptics.load_setting(s)
	t.check(not Haptics.enabled, "off")
	s.vibration = true
	Haptics.load_setting(s)
	t.check(Haptics.enabled, "on")
