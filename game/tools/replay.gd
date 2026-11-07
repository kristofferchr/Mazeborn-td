extends SceneTree
## Plays a replay (core/replay.gd) headless and prints the map, the options,
## lives and gold after each wave and the final state, then checks it against
## the result in the file (exit code 1 if it differs or an action is rejected).
## With --record the bot (tools/bot.gd) plays a round and saves it as a replay,
## e.g. to make the regression replays in tests/replays/ again after a balance
## change: classic rounds send waves early; endless stops after max_waves.
## Paths may be relative to the directory the command runs in, or user://.
## It also prints the build the replay was recorded on and warns when it is not
## this one: a match is only guaranteed on the same platform and build (float
## math such as FMA can differ between arm64 and x86).
## Usage: scripts/godot.sh --headless --path game -s res://tools/replay.gd -- <file>
##   ... -- --record <out> <map> <seed> [difficulty] [classic|endless] [max_waves]


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		printerr(
			"usage: -- <file.replay.json> | --record <out> <map> <seed> [level] [mode] [waves]"
		)
		quit(2)
		return
	if args[0] == "--record":
		quit(_record(args.slice(1)))
	else:
		quit(_play(_resolve(args[0])))


func _play(path: String) -> int:
	if not FileAccess.file_exists(path):
		printerr("no such file: %s" % path)
		return 2
	var text := FileAccess.get_file_as_string(path)
	var r := Replay.from_json(text)
	if r == null:
		printerr("not a replay: %s" % Replay.error_of(JSON.parse_string(text)))
		return 2
	var g := r.new_game()
	print("replay  %s" % path)
	print(
		(
			"map     %s (%s)   %s   seed %d   %d actions   ends at tick %d"
			% [
				g.map.get("name", r.map_id),
				r.map_id,
				_options(r.options),
				r.seed_value,
				r.actions.size(),
				r.end_tick(),
			]
		)
	)
	print(
		(
			"build   %s   engine %s   app %s"
			% [
				r.build.get("platform", "?"),
				r.build.get("engine", "?"),
				r.build.get("app_version", "?")
			]
		)
	)
	var other := r.build_differences()
	if not other.is_empty():
		print(
			"WARNING recorded on another build, it may not play out the same: " + ", ".join(other)
		)
	var on_cleared := func(n: int) -> void:
		print(
			(
				"wave %3d cleared   lives %2d   gold %5d   towers %2d   tick %6d"
				% [n, g.lives, g.gold, g.towers.size(), g.ticks]
			)
		)
	var on_over := func(won: bool) -> void:
		if not won:
			print("wave %3d lost      lives  0   gold %5d   tick %6d" % [g.wave, g.gold, g.ticks])
	g.wave_cleared.connect(on_cleared)
	g.game_over.connect(on_over)
	var ok := r.play(g)
	# The callbacks hold the game: let go of them, or it is never freed.
	g.wave_cleared.disconnect(on_cleared)
	g.game_over.disconnect(on_over)
	var s := Replay.state_of(g)
	print(
		(
			"end     %s   wave %d   cleared %d   lives %d/%d   gold %d   ticks %d   towers %d"
			% [s.phase, s.wave, s.cleared, s.lives, g.start_lives, s.gold, s.ticks, s.towers.size()]
		)
	)
	for i in r.rejected:
		print("rejected action %d: %s" % [i, r.actions[i]])
	var diff := r.diff(g)
	if r.result.is_empty():
		print("check   no recorded result to compare with")
	elif diff.is_empty():
		print("check   same as the recording")
	else:
		print("check   differs from the recording:\n  " + "\n  ".join(diff))
	return 0 if ok and (diff.is_empty() or r.result.is_empty()) else 1


## The bot plays a round and it is saved as a replay. A few targeting switches
## (one per wave) put every kind of action in it.
func _record(args: Array[String]) -> int:
	if args.size() < 3:
		printerr("usage: --record <out> <map> <seed> [difficulty] [classic|endless] [max_waves]")
		return 2
	var out := _resolve(args[0], false)
	if not args[2].is_valid_int() or not Replay.valid_seed(args[2].to_int()):
		printerr("the seed must be a whole number up to 2^53: %s" % args[2])
		return 2
	if args.size() > 3 and not Difficulty.exists(args[3]):
		printerr("unknown difficulty: %s" % args[3])
		return 2
	var options := {
		"difficulty": args[3] if args.size() > 3 else Difficulty.DEFAULT,
		"mode": args[4] if args.size() > 4 else Progress.CLASSIC,
	}
	var max_waves := int(args[5]) if args.size() > 5 else 0
	var g := Game.create_map(args[1], args[2].to_int(), options)
	var bot := Bot.new(g, true)
	bot.play(
		func(b: Bot) -> void:
			var cells: Array = b.game.towers.keys()
			if not cells.is_empty():
				var cell: Vector2i = cells[b.game.wave % cells.size()]
				var mode := "closest" if b.game.wave % 2 == 0 else "first"
				b.game.apply({"type": "target", "cell": cell, "mode": mode}),
		max_waves
	)
	var err := Replay.record(g).save_file(out)
	print("recorded %s: %s (%s)" % [out, Replay.state_of(g), error_string(err)])
	return 0 if err == OK else 1


func _options(options: Dictionary) -> String:
	var parts: Array[String] = []
	for key: String in options:
		parts.append("%s=%s" % [key, options[key]])
	return " ".join(parts)


## A path as given on the command line: res:// and user:// as they are, others
## relative to the directory the command was started in (Godot itself runs in
## the project directory).
func _resolve(path: String, must_exist := true) -> String:
	if path.begins_with("res://") or path.begins_with("user://") or path.is_absolute_path():
		return path
	var cwd := OS.get_environment("PWD")
	if cwd != "" and (not must_exist or FileAccess.file_exists(cwd.path_join(path))):
		return cwd.path_join(path)
	return path
