extends SceneTree
## Lets the bot (tools/bot.gd) play a round on one map or on every map and
## prints each wave. For balancing.
## Usage: scripts/godot.sh --headless --path game -s res://tools/balance.gd [-- map|all [seed]]


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var which := args[0] if args.size() > 0 else "all"
	var seed_value := int(args[1]) if args.size() > 1 else 3
	var ids := Maps.ids()
	if which != "all":
		ids = [which] as Array[String]
	var summary: Array[String] = []
	for id in ids:
		summary.append(_play(id, seed_value))
	print("\n".join(summary))
	quit()


func _play(id: String, seed_value: int) -> String:
	var g := Game.create_map(id, seed_value)
	print("== %s (%s)" % [g.map.get("name", id), id])
	var bot := Bot.new(g)
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
						", ".join(g.wave_tags(g.waves[g.wave - 1])),
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
			leaked_kinds.clear()
	)
	g.creep_leaked.disconnect(count_leak)
	print(_board(g))
	var result := "%-16s %-4s lives %2d" % [id, Game.Phase.keys()[g.phase], g.lives]
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
