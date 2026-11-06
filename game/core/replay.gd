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

const FORMAT := "mazeborn-replay"
const VERSION := 1
const DIR := "user://replays"
const LAST := "last.replay.json"
const EXT := ".replay.json"
const KEEP := 10  # rounds kept besides last.replay.json
const MAX_TICKS := 30 * 60 * 60 * 4  # a replay without an end stops after 4 hours

var map_id := ""
var options: Dictionary = {}
var seed_value := 0
var actions: Array[Dictionary] = []
var result: Dictionary = {}  # state_of the game when it was recorded
var rejected: Array[int] = []  # indices of the actions the last play() could not apply


## The replay of a game so far: its map, options, seed, actions and state.
static func record(game: Game) -> Replay:
	var r := Replay.new()
	r.map_id = str(game.map.get("id", ""))
	r.options = game.options.duplicate(true)
	r.seed_value = game.seed_value
	r.actions = game.actions.duplicate(true)
	r.result = state_of(game)
	return r


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
	return {
		"format": FORMAT,
		"version": VERSION,
		"map": map_id,
		"options": options,
		"seed": seed_value,
		"actions": actions,
		"result": result,
	}


## JSON with one action per line, so files diff well.
func to_json() -> String:
	var lines: Array[String] = []
	for a in actions:
		lines.append("    " + JSON.stringify(a, "", false))
	var head := []
	for key: String in ["format", "version", "map", "options", "seed"]:
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
	r.seed_value = int(d.seed)
	for a: Dictionary in d.actions:
		r.actions.append(a)
	var res: Variant = d.get("result", {})
	r.result = res if res is Dictionary else {}
	return r


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
	if not (d.get("seed") is float or d.get("seed") is int):
		return "no seed"
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
## latter. stamp defaults to the local time ("20261106-143005-123").
static func store(replay: Replay, dir := DIR, stamp := "") -> Error:
	var err := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	if err != OK:
		return err
	var text := replay.to_json()
	err = SafeConfig.save_text(text, dir.path_join(LAST))
	if err != OK:
		return err
	if stamp == "":
		var now := Time.get_unix_time_from_system()
		stamp = (
			"%s-%03d"
			% [
				Time.get_datetime_string_from_system().replace("-", "").replace(":", "").replace(
					"T", "-"
				),
				int(fmod(now, 1.0) * 1000.0),
			]
		)
	var base := "%s-%s" % [stamp, replay.map_id]
	var path := dir.path_join(base + EXT)
	var n := 2
	while FileAccess.file_exists(path):
		path = dir.path_join("%s-%d%s" % [base, n, EXT])
		n += 1
	err = SafeConfig.save_text(text, path)
	var kept := history(dir)
	for i in maxi(kept.size() - KEEP, 0):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(kept[i]))
	return err


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
	if v is float and is_finite(v) and v == floorf(v) and absf(v) < 9.0e15:
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
