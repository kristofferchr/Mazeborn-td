extends RefCounted
## Tests for player actions (Game.apply) and replays (core/replay.gd): a round
## played by the bot plays back to the same end, the JSON round trip, invalid
## actions, the files on the device and the committed regression replays in
## tests/replays/ (each holds its expected result).

const REPLAYS_DIR := "res://tests/replays"
const TEMP_DIR := "user://test_replays"

var t: Object  # test runner (check/eq)


## A round on a map played by the bot (in endless at most max_waves waves),
## with a few targeting switches so every kind of action is in it.
func _bot_round(map_id: String, seed_value: int, options: Dictionary, max_waves := 0) -> Game:
	var g := Game.create_map(map_id, seed_value, options)
	var bot := Bot.new(g, true)
	var switch := func(b: Bot) -> void:
		var cells: Array = b.game.towers.keys()
		if not cells.is_empty():
			var cell: Vector2i = cells[b.game.wave % cells.size()]
			var mode := "closest" if b.game.wave % 2 == 0 else "first"
			b.game.apply({"type": "target", "cell": cell, "mode": mode})
	bot.play(switch, max_waves)
	return g


## Plays a replay into a fresh game and checks that it ends the same way.
func _check_plays_back(r: Replay, what: String) -> Game:
	var g := r.new_game()
	t.check(r.play(g), "%s: every action accepted (rejected %s)" % [what, r.rejected])
	t.eq(r.diff(g), [] as Array[String], "%s: same end state" % what)
	t.eq(g.actions.size(), r.actions.size(), "%s: same actions" % what)
	return g


func _types(g: Game) -> Array[String]:
	var out: Array[String] = []
	for a in g.actions:
		out.append(str(a.type))
	return out


func test_apply_performs_and_records_actions() -> void:
	var g := Game.create_map("engen", 3)
	var cell := Vector2i(5, 3)
	t.check(g.apply({"type": "build", "cell": cell, "kind": "arrow"}), "build")
	t.check(g.tower_at(cell) != null, "tower built")
	t.check(g.apply({"type": "target", "cell": [5, 3], "mode": "closest"}), "target ([x, y] cell)")
	t.eq(g.tower_at(cell).targeting, Tower.Targeting.CLOSEST, "targeting set")
	t.check(g.apply({"type": "start_wave"}), "start wave")
	for i in 60:
		g.step()
	g.gold = 1000
	t.check(g.apply({"type": "upgrade", "cell": cell}), "upgrade (first option)")
	t.eq(g.tower_at(cell).level, 1, "upgraded")
	var took := g.tower_at(cell).node_id
	t.check(g.apply({"type": "sell", "cell": cell}), "sell")
	t.check(g.tower_at(cell) == null, "sold")
	t.eq(_types(g), ["build", "target", "start_wave", "upgrade", "sell"] as Array[String], "types")
	t.eq(g.actions[0], {"tick": 0, "type": "build", "cell": [5, 3], "kind": "arrow"}, "build entry")
	t.eq(g.actions[1].mode, "closest", "target mode recorded")
	t.eq(g.actions[3].tick, 60, "stamped with the tick (2 s)")
	t.eq(g.actions[3].option, took, "the first option is recorded by its id")


func test_upgrade_records_the_option_it_took() -> void:
	var g := Game.create_map("engen", 3)
	g.gold = 5000
	var cell := Vector2i(5, 3)
	g.apply({"type": "build", "cell": cell, "kind": "elemental"})
	var options := g.tower_at(cell).upgrade_options()
	t.check(options.size() > 1, "elemental branches")
	t.check(g.apply({"type": "upgrade", "cell": cell}), "upgrade without an option")
	t.eq(g.actions[-1].option, options[0], "the resolved first option")
	var next := g.tower_at(cell).upgrade_options()
	t.check(g.apply({"type": "upgrade", "cell": cell, "option": next[-1]}), "a named option")
	t.eq(g.actions[-1].option, next[-1], "the named option")
	t.eq(g.tower_at(cell).node_id, next[-1], "and took it")
	var before := g.actions.size()
	g.gold = 0
	t.check(not g.apply({"type": "upgrade", "cell": cell}), "too little gold")
	t.eq(g.actions.size(), before, "not recorded")


func test_build_is_recorded_and_compared() -> void:
	var r := Replay.from_json(Replay.record(Game.create_map("engen", 1)).to_json())
	t.eq(r.build, Replay.current_build(), "platform, engine and app version kept")
	t.eq(r.build_differences(), [] as Array[String], "the same build")
	var other := Replay.current_build()
	other.platform = "iOS" if other.platform != "iOS" else "Linux"
	other.engine = "0.0"
	t.eq(r.build_differences(other).size(), 2, "another platform and engine")
	var old := Replay.record(Game.create_map("engen", 1)).to_dict()
	for key: String in Replay.BUILD_KEYS:
		old.erase(key)
	var r_old := Replay.from_json(JSON.stringify(old))
	t.check(r_old != null, "a replay without build info still loads")
	t.eq(r_old.build_differences().size(), 3, "and is reported as unknown")


func test_invalid_actions_are_rejected_and_not_recorded() -> void:
	var g := Game.create_map("klofta", 3)
	var rock: Vector2i = g.grid.rocks.keys()[0]
	var before := Replay.state_of(g)
	var bad: Array[Dictionary] = [
		{},
		{"type": "explode"},
		{"type": "build", "cell": rock, "kind": "arrow"},
		{"type": "build", "cell": g.grid.spawns[0], "kind": "arrow"},
		{"type": "build", "cell": g.grid.goal, "kind": "arrow"},
		{"type": "build", "cell": [-1, 2], "kind": "arrow"},
		{"type": "build", "cell": "3,3", "kind": "arrow"},
		{"type": "build", "cell": [3, 3], "kind": "dragon"},
		{"type": "build", "cell": [3, 3]},
		{"type": "sell", "cell": [3, 3]},
		{"type": "upgrade", "cell": [3, 3]},
		{"type": "target", "cell": [3, 3], "mode": "closest"},
	]
	for a in bad:
		t.check(not g.apply(a), "rejected: %s" % a)
	t.check(g.apply({"type": "build", "cell": [3, 3], "kind": "arrow"}), "a valid build")
	t.check(not g.apply({"type": "build", "cell": [3, 3], "kind": "arrow"}), "occupied")
	t.check(not g.apply({"type": "upgrade", "cell": [3, 3], "option": "nope"}), "unknown option")
	t.check(not g.apply({"type": "target", "cell": [3, 3], "mode": "weakest"}), "unknown mode")
	g.gold = 0
	t.check(not g.apply({"type": "upgrade", "cell": [3, 3]}), "too little gold")
	t.check(not g.apply({"type": "build", "cell": [4, 3], "kind": "arrow"}), "too little gold")
	t.eq(g.actions.size(), 1, "only the valid action is recorded")
	g.phase = Game.Phase.LOST
	for a: Dictionary in [
		{"type": "start_wave"},
		{"type": "sell", "cell": [3, 3]},
		{"type": "target", "cell": [3, 3], "mode": "closest"},
	]:
		t.check(not g.apply(a), "rejected once the round is over: %s" % a)
	t.eq(g.actions.size(), 1, "still one action")
	t.eq(before.ticks, g.ticks, "no time passed")


func test_bot_round_plays_back_the_same() -> void:
	var g := _bot_round("klofta", 7, {"difficulty": "normal"})
	t.check(g.is_over(), "the bot finished the round")
	var types := _types(g)
	for type: String in ["build", "upgrade", "start_wave", "target"]:
		t.check(type in types, "the round has a %s action" % type)
	var r := Replay.record(g)
	t.eq(r.map_id, "klofta", "map")
	t.eq(r.seed_value, 7, "seed")
	t.eq(r.end_tick(), g.ticks, "end tick")
	var back := _check_plays_back(Replay.from_json(r.to_json()), "klofta")
	t.eq(back.phase, g.phase, "same phase")
	t.eq(back.gold, g.gold, "same gold")
	t.eq(back.actions, g.actions, "the replayed game records the same actions")


func test_endless_on_hard_plays_back_the_same() -> void:
	var g := _bot_round("tvillingportene", 11, {"difficulty": "hard", "mode": "endless"}, 14)
	t.check(not g.is_over() or g.phase == Game.Phase.LOST, "endless is never won")
	var r := Replay.from_json(Replay.record(g).to_json())
	t.eq(r.options.difficulty, "hard", "difficulty kept")
	t.eq(r.options.mode, "endless", "mode kept")
	var back := _check_plays_back(r, "endless hard")
	t.check(back.endless, "the replayed game is endless")
	t.eq(back.score(), g.score(), "same score")


func test_easy_difficulty_plays_back_the_same() -> void:
	var g := _bot_round("steinroysa", 2, {"difficulty": "easy"})
	_check_plays_back(Replay.from_json(Replay.record(g).to_json()), "easy")


func test_sending_early_during_a_wave_plays_back_the_same() -> void:
	var g := Game.create_map("engen", 9)
	var bot := Bot.new(g)
	for n in 3:
		bot.spend()
		t.check(g.apply({"type": "start_wave"}), "wave %d" % (n + 1))
		while not g.can_send_early() and not g.is_over():
			g.step()
		var gold := g.gold
		t.check(g.apply({"type": "start_wave"}), "sent wave %d early" % (n + 2))
		t.check(g.gold > gold, "early gold paid")
		g.run_wave()
	var back := _check_plays_back(Replay.from_json(Replay.record(g).to_json()), "early")
	t.eq(back.wave, g.wave, "same wave")


func test_json_round_trip() -> void:
	var g := _bot_round("engen", 5, {"difficulty": "extreme", "mode": "classic"}, 4)
	var r := Replay.record(g)
	var text := r.to_json()
	var back := Replay.from_json(text)
	t.check(back != null, "parses")
	t.eq(back.to_json(), text, "the same JSON again")
	t.eq(back.map_id, r.map_id, "map")
	t.eq(back.seed_value, r.seed_value, "seed")
	t.eq(back.options, r.options, "options")
	t.eq(back.actions.size(), r.actions.size(), "actions")
	t.eq(back.actions[0].tick is int, true, "ticks are ints again")
	t.eq(back.actions[0].cell, r.actions[0].cell, "cells are [x, y] ints again")
	var data: Dictionary = JSON.parse_string(text)
	t.eq(data.format, Replay.FORMAT, "format")
	t.eq(int(data.version), Replay.VERSION, "version")
	t.eq(text.count("\n    {"), r.actions.size(), "one action per line")


func test_invalid_actions_are_rejected_the_same_way_in_a_replay() -> void:
	var g := _bot_round("engen", 4, {}, 3)
	var r := Replay.record(g)
	var first: Dictionary = r.actions[0]
	# Building the first cell again, and a made-up action, cannot work.
	var again := first.duplicate(true)
	again.tick = int(r.actions[-1].tick)
	r.actions.insert(r.actions.size() - 1, again)
	r.actions.insert(1, {"tick": int(first.tick), "type": "sell", "cell": [0, 0]})
	var back := r.new_game()
	t.check(not r.play(back), "a replay with invalid actions reports them")
	t.eq(r.rejected, [1, r.actions.size() - 2] as Array[int], "the invalid ones are rejected")
	t.eq(r.diff(back), [] as Array[String], "and change nothing")
	t.eq(back.actions.size(), g.actions.size(), "they are not recorded again")


func test_play_until_a_tick() -> void:
	var g := _bot_round("engen", 6, {}, 5)
	var r := Replay.record(g)
	var mid := r.end_tick() / 2
	var part := r.new_game()
	r.play(part, mid)
	t.eq(part.ticks, mid, "stopped at the tick")
	var expected := 0
	for a in r.actions:
		if int(a.tick) <= mid:
			expected += 1
	t.eq(part.actions.size(), expected, "the actions up to the tick")
	t.check(not r.diff(part).is_empty(), "not the end yet")
	var whole := r.new_game()
	r.play(whole)
	t.eq(r.diff(whole), [] as Array[String], "a fresh game plays to the end")


func test_replay_errors() -> void:
	t.check(Replay.from_json("not json") == null, "not JSON")
	t.check(Replay.from_json("[1, 2]") == null, "not an object")
	var good := Replay.record(Game.create_map("engen", 1)).to_dict()
	t.eq(Replay.error_of(JSON.parse_string(JSON.stringify(good))), "", "a recorded replay is valid")
	var cases := {
		"format": "something",
		"version": Replay.VERSION + 1,
		"map": "atlantis",
		"options": "hard",
		"seed": "abc",
		"actions": {},
	}
	for key: String in cases:
		var d := good.duplicate(true)
		d[key] = cases[key]
		t.check(Replay.error_of(d) != "", "bad %s is an error" % key)
	for bad_seed: Variant in [1.5, -0.25, 9007199254740994.0, 1e20, -1e17, true, null]:
		var d := good.duplicate(true)
		d.seed = bad_seed
		t.check(Replay.error_of(d) != "", "seed %s is an error" % bad_seed)
	for ok_seed: Variant in [0, 7, -3, 4294967295, 1 << 53]:
		var d := good.duplicate(true)
		d.seed = ok_seed
		t.eq(Replay.error_of(d), "", "seed %s is fine" % ok_seed)
		var r := Replay.from_json(JSON.stringify(d))
		t.eq(r.seed_value if r else null, ok_seed, "seed %s survives JSON" % ok_seed)
	t.check(Replay.valid_seed(Replay.MAX_SEED), "2^53 is the largest seed")
	t.check(not Replay.valid_seed(Replay.MAX_SEED + 1), "above 2^53")
	for level: Variant in ["nightmare", "", 3, null]:
		var d := good.duplicate(true)
		d.options = {"difficulty": level, "mode": "classic"}
		t.check(Replay.error_of(d) != "", "difficulty %s is an error" % level)
	for level in Difficulty.ids():
		var d := good.duplicate(true)
		d.options = {"difficulty": level}
		t.eq(Replay.error_of(d), "", "difficulty %s is fine" % level)
	var no_level := good.duplicate(true)
	no_level.options = {}
	t.eq(Replay.error_of(no_level), "", "no difficulty means the default")
	var d := good.duplicate(true)
	d.actions = [{"type": "start_wave"}]
	t.check(Replay.error_of(d) != "", "an action without a tick")
	d.actions = [{"tick": 3}]
	t.check(Replay.error_of(d) != "", "an action without a type")


func test_store_keeps_the_last_round_and_rotates() -> void:
	_clear(TEMP_DIR)
	var g := _bot_round("engen", 8, {}, 2)
	var r := Replay.record(g)
	for i in Replay.KEEP + 3:
		t.eq(Replay.store(r, TEMP_DIR, "20260101-0000%02d-000" % i), OK, "stored %d" % i)
	var kept := Replay.history(TEMP_DIR)
	t.eq(kept.size(), Replay.KEEP, "keeps the last rounds")
	t.check(kept[0].get_file().begins_with("20260101-000003"), "the oldest are gone")
	t.check(kept[-1].get_file().begins_with("20260101-000012"), "the newest is kept")
	var last := Replay.load_file(TEMP_DIR.path_join(Replay.LAST))
	t.check(last != null, "last.replay.json loads")
	if last:
		t.eq(last.to_json(), r.to_json(), "last.replay.json is the round")
	t.eq(Replay.store(r, TEMP_DIR, "20260101-000012-000"), OK, "same stamp again")
	t.eq(Replay.history(TEMP_DIR).size(), Replay.KEEP, "still rotated")
	t.check(Replay.history(TEMP_DIR)[-1].get_file().begins_with("20260101-000012-000-01-"), "last")
	var before := Replay.history(TEMP_DIR)
	var paused := Replay.record(Game.create_map("klofta", 2))
	t.eq(Replay.store(paused, TEMP_DIR, "", false), OK, "a round in progress")
	t.eq(Replay.history(TEMP_DIR), before, "goes only to last.replay.json")
	t.eq(Replay.load_file(TEMP_DIR.path_join(Replay.LAST)).map_id, "klofta", "which has it")
	for f in DirAccess.get_files_at(TEMP_DIR):
		t.check(not f.ends_with(".tmp"), "no temp file left: %s" % f)
	t.check(Replay.load_file(TEMP_DIR.path_join("missing.replay.json")) == null, "missing file")
	_clear(TEMP_DIR)


func test_history_sorts_by_time_and_duplicates() -> void:
	_clear(TEMP_DIR)
	var r := Replay.record(Game.create_map("engen", 1))
	# Same millisecond for maps whose names sort the other way, then later ones.
	for stamp: String in ["20260101-000000-500", "20260101-000000-500", "20260101-000000-500"]:
		Replay.store(r, TEMP_DIR, stamp)
	r.map_id = "aaa"
	Replay.store(r, TEMP_DIR, "20260101-000000-500")
	Replay.store(r, TEMP_DIR, "20260101-000001-000")
	var names: Array[String] = []
	for path in Replay.history(TEMP_DIR):
		names.append(path.get_file())
	(
		t
		. eq(
			names,
			(
				[
					"20260101-000000-500-00-engen.replay.json",
					"20260101-000000-500-01-engen.replay.json",
					"20260101-000000-500-02-engen.replay.json",
					"20260101-000000-500-03-aaa.replay.json",
					"20260101-000001-000-00-aaa.replay.json",
				]
				as Array[String]
			),
			"in the order they were stored"
		)
	)
	_clear(TEMP_DIR)


func test_stamp_is_utc_from_one_time_value() -> void:
	t.eq(Replay.stamp_of(0.0), "19700101-000000-000", "the epoch in UTC")
	t.eq(Replay.stamp_of(1794268799.9996), "20261109-235959-999", "ms from the same value")
	t.eq(Replay.stamp_of(1794268800.0), "20261110-000000-000", "the next second")
	t.check(Replay.stamp_of(1.25) < Replay.stamp_of(2.0), "sorts by time")


func test_committed_replays_play_back_to_their_result() -> void:
	var files: Array[String] = []
	for f in DirAccess.get_files_at(REPLAYS_DIR):
		if f.ends_with(Replay.EXT):
			files.append(REPLAYS_DIR.path_join(f))
	t.check(files.size() >= 2, "regression replays found (%d)" % files.size())
	var modes := {}
	for path in files:
		var r := Replay.load_file(path)
		t.check(r != null, "%s loads" % path)
		if r == null:
			continue
		t.check(not r.result.is_empty(), "%s has its expected result" % path)
		modes[str(r.options.get("mode", "classic"))] = true
		modes[str(r.options.get("difficulty", "normal"))] = true
		_check_plays_back(r, path.get_file())
	t.check(modes.has("endless") and modes.has("classic"), "both modes are covered")
	t.check(modes.has("hard") or modes.has("easy") or modes.has("extreme"), "a non-normal level")


func test_round_uses_only_apply() -> void:
	var text := FileAccess.get_file_as_string("res://round.gd")
	for call: String in ["game.build(", "game.sell(", "game.upgrade(", "game.start_wave("]:
		t.check(not text.contains(call), "round.gd calls %s directly" % call)
	var assign := RegEx.create_from_string("\\.targeting\\s*=[^=]")
	t.check(assign.search(text) == null, "round.gd sets the targeting directly")
	t.check(text.contains("game.apply("), "round.gd uses Game.apply")


func _clear(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(dir.path_join(f)))
