extends SceneTree
## Lets the bot (tools/bot.gd) play a round on one map or on every map and
## prints each wave. For balancing. After the seed come, in any order, the
## difficulty (an id from data/difficulty.json, or "all" for every level;
## default: normal) and the mode:
## "wait" (default: classic, the bot lets each countdown run out), "early"
## (classic, the bot sends each wave as soon as it has built, for the early
## gold), "endless" and "endless-early" (endless with either bot, until it
## loses, at most MAX_ENDLESS waves).
## Usage: scripts/godot.sh --headless --path game -s res://tools/balance.gd
##   [-- map|all [seed [difficulty|all] [mode]]]

const MODES: Array[String] = ["wait", "early", "endless", "endless-early"]
const MAX_ENDLESS := 150


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var which := args[0] if args.size() > 0 else "all"
	var seed_value := int(args[1]) if args.size() > 1 else 3
	var level := Difficulty.DEFAULT
	var mode := "wait"
	for a in args.slice(2):
		if a == "all" or Difficulty.exists(a):
			level = a
		elif a in MODES:
			mode = a
	var ids := Maps.ids()
	if which != "all":
		ids = [which] as Array[String]
	var levels := Difficulty.ids() if level == "all" else ([level] as Array[String])
	var summary: Array[String] = []
	for l in levels:
		for id in ids:
			summary.append(_play(id, seed_value, l, mode))
	print("\n".join(summary))
	quit()


func _play(id: String, seed_value: int, level: String, mode: String) -> String:
	var endless := mode.begins_with("endless")
	var options := {"difficulty": level, "mode": "endless" if endless else "classic"}
	var g := Game.create_map(id, seed_value, options)
	print("== %s (%s, %s, %s)" % [g.map.get("name", id), id, level, mode])
	var bot := Bot.new(g, mode.ends_with("early"))
	var leaked_kinds := {}  # kind -> count in the wave just played
	var count_leak := func(c: Creep) -> void: leaked_kinds[c.kind] = 1 + leaked_kinds.get(c.kind, 0)
	g.creep_leaked.connect(count_leak)
	bot.play(
		func(b: Bot) -> void:
			print(
				(
					"wave %2d %-26s lives %2d leaked %2d gold %3d towers %2d upgrades %2d path %s %s"
					% [
						g.wave,
						", ".join(g.wave_tags(g.wave_data(g.wave))),
						g.lives,
						b.leaked_by_wave.get(g.wave, 0),
						g.gold,
						g.towers.size(),
						b.upgrades(),
						_paths(g),
						leaked_kinds if not leaked_kinds.is_empty() else "",
					]
				)
			)
			leaked_kinds.clear(),
		MAX_ENDLESS
	)
	g.creep_leaked.disconnect(count_leak)
	print(_board(g))
	var result := (
		"%-8s %-16s %-13s %-4s lives %2d/%2d wave %3d cleared %3d early gold %3d"
		% [
			level,
			id,
			mode,
			Game.Phase.keys()[g.phase],
			g.lives,
			g.start_lives,
			g.wave,
			g.score(),
			bot.early_gold,
		]
	)
	print("result: ", result)
	return result


func _paths(g: Game) -> String:
	var parts: Array[String] = []
	for i in g.grid.spawns.size():
		parts.append(str(g.grid.path(i).size()))
	return "/".join(parts)


## The board as text: S spawn, G goal, # rock, T tower, * path, . free.
func _board(g: Game) -> String:
	var on_path := {}
	for i in g.grid.spawns.size():
		for c in g.grid.path(i):
			on_path[c] = true
	var rows: Array[String] = []
	for y in g.grid.size.y:
		var row := ""
		for x in g.grid.size.x:
			var c := Vector2i(x, y)
			if g.grid.is_spawn(c):
				row += "S"
			elif c == g.grid.goal:
				row += "G"
			elif g.grid.is_rock(c):
				row += "#"
			elif g.tower_at(c):
				row += "T"
			elif on_path.has(c):
				row += "*"
			else:
				row += "."
		rows.append(row)
	return "\n".join(rows)
