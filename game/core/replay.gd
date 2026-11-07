class_name Replay
extends RefCounted
## A recorded round. The simulation is deterministic, so the map id, the
## options, the seed and the player actions with their ticks (Game.apply) are
## all it takes to play a round again step for step. `result` is the state at
## the end of the recording (state_of), so a replay checks itself: play() it
## into a fresh game (new_game) and compare (diff).
##
## File (JSON, one action per line): {"format": "mazeborn-replay",
## "version": 1, "map": id, "options": {...}, "seed": n, "actions": [{"tick":
## n, "type": ...}, ...], "result": {...}}. On the device the last round is
## user://replays/last.replay.json, and the last KEEP rounds are kept next to
## it (store). Pure apart from the thin file helpers (save_file, load_file,
## store, history).
##
## The file also names the build it was recorded on ("platform", "engine",
## "app_version"; see build_differences). A replay is only guaranteed to play
## out the same on the same platform and build: float math (FMA, rounding) can
## differ between arm64 and x86 and between engine versions.

const FORMAT := "mazeborn-replay"
const VERSION := 1
const DIR := "user://replays"
const LAST := "last.replay.json"
const EXT := ".replay.json"
const KEEP := 10  # rounds kept besides last.replay.json
const MAX_TICKS := 30 * 60 * 60 * 4  # a replay without an end stops after 4 hours
const MAX_SEED := 1 << 53  # larger seeds do not survive JSON (doubles)
const BUILD_KEYS: Array[String] = ["platform", "engine", "app_version"]

var map_id := ""
var options: Dictionary = {}
var seed_value := 0
var actions: Array[Dictionary] = []
var result: Dictionary = {}  # state_of the game when it was recorded
var rejected: Array[int] = []  # indices of the actions the last play() could not apply
var build: Dictionary = {}  # platform, engine, app_version it was recorded on


## The build running now: {"platform", "engine", "app_version"}.
static func current_build() -> Dictionary:
	return {
		"platform": OS.get_name(),
		"engine": str(Engine.get_version_info().string),
		"app_version": str(ProjectSettings.get_setting("application/config/version", "")),
	}


## The replay of a game so far: its map, options, seed, actions and state.
static func record(game: Game) -> Replay:
	var r := Replay.new()
	r.map_id = str(game.map.get("id", ""))
	r.options = game.options.duplicate(true)
	r.seed_value = game.seed_value
	r.actions = game.actions.duplicate(true)
	r.result = state_of(game)
	r.build = current_build()
	return r


## "platform: iOS != Linux" for each way the recording build differs from
## `now` (default: the running build); empty if it is the same.
func build_differences(now := current_build()) -> Array[String]:
	var out: Array[String] = []
	for key in BUILD_KEYS:
		if not build.has(key) or str(build[key]) != str(now.get(key, "")):
			out.append("%s: %s != %s" % [key, build.get(key, "?"), now.get(key, "")])
	return out


## What a replay must reproduce: gold, lives, waves, phase, ticks and every
## tower ("x,y kind node targeting", sorted).
static func state_of(game: Game) -> Dictionary:
	var towers: Array[String] = []
	for cell: Vector2i in game.towers:
		var tower: Tower = game.towers[cell]
		towers.append(
			"%d,%d %s %s %s" % [cell.x, cell.y, tower.kind, tower.node_id, tower.targeting_name()]
		)
	towers.sort()
	return {
		"gold": game.gold,
		"lives": game.lives,
		"wave": game.wave,
		"cleared": game.cleared,
		"phase": str(Game.Phase.keys()[game.phase]).to_lower(),
		"ticks": game.ticks,
		"towers": towers,
	}


## A fresh game for this replay (its map, seed and options).
func new_game() -> Game:
	return Game.create_map(map_id, seed_value, options)


## Tick where the recording ended (-1 if the replay has no result).
func end_tick() -> int:
	return int(result.get("ticks", -1))


## Plays the actions into `game` (a fresh one from new_game()): steps to each
## action's tick and applies it, then steps on to the end of the recording, or
## only up to until_tick (>= 0). Without a recorded end it runs until the round
## is over (at most MAX_TICKS). Returns true if every action was accepted;
## `rejected` lists the ones that were not (the replay does not fit the game).
func play(game: Game, until_tick := -1) -> bool:
	rejected.clear()
	var end := until_tick if until_tick >= 0 else end_tick()
	for i in actions.size():
		var a := actions[i]
		var tick := int(a.get("tick", 0))
		if end >= 0 and tick > end:
			break
		_step_to(game, tick)
		if not game.apply(a):
			rejected.append(i)
	_step_to(game, end if end >= 0 else MAX_TICKS)
	return rejected.is_empty()


## Differences between the game's state and the recorded result
## ("gold: 120 != 95"); empty when the replay played out the same.
func diff(game: Game) -> Array[String]:
	var out: Array[String] = []
	var now := state_of(game)
	for key: String in now:
		if not _same(now[key], result.get(key)):
			out.append("%s: %s != %s" % [key, now[key], result.get(key)])
	return out


func to_dict() -> Dictionary:
	var d := {
		"format": FORMAT,
		"version": VERSION,
		"map": map_id,
		"options": options,
		"seed": seed_value,
		"actions": actions,
		"result": result,
	}
	for key in BUILD_KEYS:
		d[key] = str(build.get(key, ""))
	return d


## JSON with one action per line, so files diff well.
func to_json() -> String:
	var lines: Array[String] = []
	for a in actions:
		lines.append("    " + JSON.stringify(a, "", false))
	var head := []
	for key: String in ["format", "version"] + BUILD_KEYS + ["map", "options", "seed"]:
		head.append('  "%s": %s' % [key, JSON.stringify(to_dict()[key], "", false)])
	return (
		'{\n%s,\n  "actions": [\n%s\n  ],\n  "result": %s\n}\n'
		% [",\n".join(head), ",\n".join(lines), JSON.stringify(result, "", false)]
	)


## A replay from JSON text, or null if it is not one (see error_of).
static func from_json(text: String) -> Replay:
	var data: Variant = _ints(JSON.parse_string(text))
	if error_of(data) != "":
		return null
	var d: Dictionary = data
	var r := Replay.new()
	r.map_id = str(d.map)
	r.options = (d.options as Dictionary).duplicate(true)
	r.seed_value = int(d.seed)  # whole and within 2^53 (error_of)
	for a: Dictionary in d.actions:
		r.actions.append(a)
	var res: Variant = d.get("result", {})
	r.result = res if res is Dictionary else {}
	for key in BUILD_KEYS:
		if d.has(key):
			r.build[key] = str(d[key])
	return r


## True for a seed a replay can keep: a whole number up to 2^53 either way.
static func valid_seed(v: Variant) -> bool:
	if v is float:
		return is_finite(v) and v == floorf(v) and absf(v) <= float(MAX_SEED)
	return v is int and absi(v) <= MAX_SEED


## Why parsed JSON is not a replay this version can play ("" if it is one).
static func error_of(data: Variant) -> String:
	if not data is Dictionary:
		return "not a JSON object"
	var d: Dictionary = data
	if d.get("format") != FORMAT:
		return "not a %s file" % FORMAT
	if not (d.get("version") is float or d.get("version") is int):
		return "no version"
	if int(d.version) < 1 or int(d.version) > VERSION:
		return "version %s is not supported (up to %d)" % [d.version, VERSION]
	if not d.get("map") is String or not Maps.exists(str(d.map)):
		return "unknown map %s" % d.get("map")
	if not d.get("options") is Dictionary:
		return "no options"
	var level: Variant = (d.options as Dictionary).get("difficulty", Difficulty.DEFAULT)
	if not level is String or not Difficulty.exists(level):
		return "unknown difficulty %s" % level
	if not valid_seed(d.get("seed")):
		return "the seed %s is not a whole number up to 2^53" % d.get("seed")
	if not d.get("actions") is Array:
		return "no actions"
	for a: Variant in d.actions:
		if not a is Dictionary or not (a as Dictionary).get("type") is String:
			return "an action without a type: %s" % a
		var tick: Variant = (a as Dictionary).get("tick")
		if not (tick is float or tick is int) or float(tick) < 0.0:
			return "an action without a tick: %s" % a
	return ""


## Name for a shared file: "mazeborn-<map>-<seed>.replay.json".
func file_name() -> String:
	return "mazeborn-%s-%d%s" % [map_id, seed_value, EXT]


# --- Files ----------------------------------------------------------------------


## Writes the replay to path atomically (SafeConfig.save_text).
func save_file(path: String) -> Error:
	return SafeConfig.save_text(to_json(), path)


## The replay in a file, or null if it is missing or not a replay.
static func load_file(path: String) -> Replay:
	if not FileAccess.file_exists(path):
		return null
	return from_json(FileAccess.get_file_as_string(path))


## Keeps a finished round: as dir/last.replay.json and as
## dir/<stamp>-<map>.replay.json, then removes all but the newest KEEP of the
## latter (with keep false only last.replay.json, for a round in progress).
## stamp defaults to the time in UTC ("20261106-143005-123"). Names
## with the same stamp get a counter before the map, so they sort in order.
static func store(replay: Replay, dir := DIR, stamp := "", keep := true) -> Error:
	var err := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	if err != OK:
		return err
	var text := replay.to_json()
	err = SafeConfig.save_text(text, dir.path_join(LAST))
	if err != OK or not keep:
		return err
	if stamp == "":
		stamp = stamp_of(Time.get_unix_time_from_system())
	var taken := DirAccess.get_files_at(dir)
	var n := 0
	while _has_prefix(taken, "%s-%02d-" % [stamp, n]):
		n += 1
	var path := dir.path_join("%s-%02d-%s%s" % [stamp, n, replay.map_id, EXT])
	err = SafeConfig.save_text(text, path)
	var kept := history(dir)
	for i in maxi(kept.size() - KEEP, 0):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(kept[i]))
	return err


## "20261106-143005-123": a unix time in UTC, the milliseconds from the same value.
static func stamp_of(unix_time: float) -> String:
	var seconds := floori(unix_time)
	var ms := clampi(floori((unix_time - seconds) * 1000.0), 0, 999)
	var date := Time.get_datetime_string_from_unix_time(seconds)  # UTC
	return "%s-%03d" % [date.replace("-", "").replace(":", "").replace("T", "-"), ms]


static func _has_prefix(files: PackedStringArray, prefix: String) -> bool:
	for f in files:
		if f.begins_with(prefix):
			return true
	return false


## The kept rounds in dir (not last.replay.json), oldest first.
static func history(dir := DIR) -> Array[String]:
	var out: Array[String] = []
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(EXT) and f != LAST:
			out.append(dir.path_join(f))
	out.sort()
	return out


## JSON numbers are floats: whole ones become ints again (ticks, cells, gold).
static func _ints(v: Variant) -> Variant:
	if v is float and is_finite(v) and v == floorf(v) and absf(v) <= float(MAX_SEED):
		return int(v)
	if v is Array:
		var out := []
		for x: Variant in v:
			out.append(_ints(x))
		return out
	if v is Dictionary:
		var out := {}
		for k: Variant in v:
			out[k] = _ints(v[k])
		return out
	return v


static func _step_to(game: Game, tick: int) -> void:
	while game.ticks < tick and not game.is_over():
		game.step()


## Values from state_of and from JSON (where every number is a float).
static func _same(a: Variant, b: Variant) -> bool:
	if (a is int or a is float) and (b is int or b is float):
		return float(a) == float(b)
	if a is Array and b is Array:
		if (a as Array).size() != (b as Array).size():
			return false
		for i in (a as Array).size():
			if not _same(a[i], b[i]):
				return false
		return true
	return typeof(a) == typeof(b) and a == b
