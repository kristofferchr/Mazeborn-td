extends RefCounted
## Tests for maps (data/maps/, core/maps.gd): loading, rocks, several spawns and
## that the bot can win every map.

const MAP_IDS: Array[String] = ["engen", "klofta", "tvillingportene", "steinroysa"]

var t: Object  # test runner (check/eq)


func test_maps_load_in_order() -> void:
	t.eq(Maps.ids(), MAP_IDS, "map ids in order")
	for id in Maps.ids():
		var m := Maps.load_map(id)
		t.eq(m.id, id, "id")
		t.check(str(m.get("name", "")) != "", "%s has a name" % id)
		t.check(str(m.get("description", "")) != "", "%s has a description" % id)
		var g := Maps.grid(m)
		t.check(g.size.x >= 10 and g.size.y >= 6, "%s has a size" % id)
		t.check(g.in_bounds(g.goal), "%s goal inside" % id)
		t.check(not g.spawns.is_empty(), "%s has a spawn" % id)
		for s in g.spawns:
			t.check(g.in_bounds(s) and not g.is_rock(s), "%s spawn %s inside and free" % [id, s])


func test_default_game_is_engen() -> void:
	var g := Game.create_default()
	t.eq(g.map.id, "engen", "default map")
	t.eq(g.grid.size, Vector2i(18, 12), "size")
	t.eq(g.grid.spawns, [Vector2i(0, 5)] as Array[Vector2i], "spawns")
	t.eq(g.grid.goal, Vector2i(17, 6), "goal")
	t.eq(g.grid.rocks.size(), 0, "no rocks")
	t.eq(Game.default_grid().path().size(), 19, "default grid path")


func test_rectangles_expand_to_cells() -> void:
	var m := {"blocked": [[1, 2], [3, 4, 2, 3], [1, 2]]}
	var cells := Maps.blocked_of(m)
	t.eq(cells.size(), 7, "1 cell + 2x3 rectangle, no duplicates")
	t.check(Vector2i(4, 6) in cells, "rectangle corner")
	t.check(Vector2i(5, 4) not in cells, "outside the rectangle")


func test_every_spawn_has_a_path_on_every_map() -> void:
	for id in MAP_IDS:
		var g := Game.create_map(id).grid
		for i in g.spawns.size():
			var p := g.path(i)
			t.check(not p.is_empty(), "%s spawn %d has a path" % [id, i])
			if p.is_empty():
				continue
			t.eq(p[0], g.spawns[i], "%s path starts at spawn %d" % [id, i])
			t.eq(p[-1], g.goal, "%s path ends at the goal" % id)
			for c in p:
				t.check(not g.is_rock(c), "%s path avoids rock %s" % [id, c])


func test_blocked_cells_reject_building() -> void:
	for id in MAP_IDS:
		var game := Game.create_map(id)
		game.gold = 10000
		for cell: Vector2i in game.grid.rocks:
			t.check(game.grid.is_blocked(cell), "%s rock %s blocks" % [id, cell])
			t.check(not game.can_build(cell, "arrow"), "%s cannot build on rock %s" % [id, cell])
			game.grid.remove(cell)
			t.check(game.grid.is_rock(cell), "%s remove keeps rock %s" % [id, cell])
	t.check(Game.create_map("klofta").grid.rocks.size() > 0, "Kløfta has rocks")


func test_building_cannot_cut_off_any_spawn() -> void:
	# Two spawns on the left; walling in the lower one must be refused even
	# though the upper one still reaches the goal.
	var spawns: Array[Vector2i] = [Vector2i(0, 0), Vector2i(0, 4)]
	var g := Grid.create(Vector2i(5, 5), spawns, Vector2i(4, 2))
	t.check(g.build(Vector2i(0, 3)), "above the lower spawn")
	t.check(not g.can_build(Vector2i(1, 4)), "would cut off the lower spawn")
	t.check(not g.can_build(Vector2i(0, 4)), "spawn itself")
	t.check(not g.path(1).is_empty(), "lower spawn still has a path")


func test_filling_a_map_keeps_every_spawn_connected() -> void:
	for id in MAP_IDS:
		var g := Game.create_map(id).grid
		for x in g.size.x:
			for y in g.size.y:
				g.build(Vector2i(x, y))
		for i in g.spawns.size():
			t.check(not g.path(i).is_empty(), "%s spawn %d still connected" % [id, i])


func test_rocks_on_spawn_or_goal_are_ignored() -> void:
	var rocks: Array[Vector2i] = [Vector2i(0, 1), Vector2i(4, 1), Vector2i(2, 0)]
	var spawns: Array[Vector2i] = [Vector2i(0, 1)]
	var g := Grid.create(Vector2i(5, 3), spawns, Vector2i(4, 1), rocks)
	t.eq(g.rocks.size(), 1, "only the free cell becomes rock")
	t.eq(g.path().size(), 5, "straight path under the rock")


func test_creeps_take_turns_between_spawns() -> void:
	var game := Game.create_map("tvillingportene")
	var starts: Array[Vector2i] = []
	game.creep_spawned.connect(func(c: Creep) -> void: starts.append(c.prev_cell))
	game.start_wave()
	while starts.size() < 4 and game.ticks < 10000:
		game.step()
	var s := game.grid.spawns
	t.eq(starts.slice(0, 4), [s[0], s[1], s[0], s[1]] as Array[Vector2i], "alternating spawns")
	for c in game.creeps:
		t.eq(c.path[-1], game.grid.goal, "creep %d walks to the goal" % c.id)


func test_a_wave_reaches_the_goal_from_every_spawn() -> void:
	var game := Game.create_map("tvillingportene")
	game.lives = 1000
	var leaked_from := {}
	var start_of := {}
	game.creep_spawned.connect(func(c: Creep) -> void: start_of[c.id] = c.prev_cell)
	game.creep_leaked.connect(func(c: Creep) -> void: leaked_from[start_of[c.id]] = true)
	game.start_wave()
	game.run_wave()
	t.eq(game.phase, Game.Phase.BUILD, "wave over")
	for s in game.grid.spawns:
		t.check(leaked_from.has(s), "creeps from %s reached the goal" % s)


func test_map_rules_override_the_config() -> void:
	t.eq(Game.create_map("klofta").hp_scale, 1.1, "Kløfta creeps are tougher")
	t.eq(Game.create_map("engen").hp_scale, 1.0, "default health")
	var game := Game.create_map("klofta")
	game.start_wave()
	game.step()
	t.eq(game.creeps[0].max_hp, 35.0 * 1.1, "scaled health")
	t.eq(game.creep_hp(game.waves[0].groups[0]), 35.0 * 1.1, "creep_hp for the HUD")


func test_maze_plan_skips_rocks_and_keeps_paths() -> void:
	for id in MAP_IDS:
		var g := Game.create_map(id).grid
		var plan := MazePlan.serpentine(g)
		t.check(plan.size() > 15, "%s plan has walls" % id)
		for cell in plan:
			t.check(not g.is_rock(cell), "%s plan avoids rock %s" % [id, cell])
			t.check(g.build(cell), "%s plan cell %s can be built in order" % [id, cell])


## Both bots: one that lets every countdown run out (no early gold) and one
## that sends each wave as soon as it has built.
func test_bot_wins_every_map() -> void:
	for id in MAP_IDS:
		for send_early: bool in [false, true]:
			var game := Game.create_map(id, 3)
			var won := Bot.new(game, send_early).play()
			t.check(
				won,
				(
					"bot (send early %s) wins %s (wave %d, lives %d)"
					% [send_early, id, game.wave, game.lives]
				)
			)


func test_split_children_follow_their_parent_from_the_second_spawn() -> void:
	var game := Game.create_map("tvillingportene")
	var group := {"creep": "normal", "count": 2, "hp": 10, "interval": 0.1, "bounty": 1}
	group.abilities = {"split": {"count": 2, "hp": 5}}
	game.waves[0] = {"groups": [group]}
	game.start_wave()
	while game.creeps.size() < 2 and game.ticks < 1000:
		game.step()
	var parent := game.creeps[1]
	t.eq(parent.path[0], game.grid.spawns[1], "second creep starts at the second spawn")
	for i in 20:
		game.step()
	var path := parent.path.duplicate()
	parent.hp = 0.0
	game._reap()
	var children := game.creeps.filter(func(c: Creep) -> bool: return c.id > parent.id)
	t.eq(children.size(), 2, "two children")
	for c: Creep in children:
		t.eq(c.path, path, "child walks the parent's path")
		t.eq(c.max_hp, 5.0, "flat child health (hp_scale 1)")


func test_split_children_follow_the_map_hp_scale() -> void:
	var game := Game.create_map("klofta")
	var parent := game.new_creep("normal", 100.0, 1, {}, game.grid.spawn)
	parent.set_path(game.grid.path())
	var children := game._spawn_children(parent, {"count": 1, "hp": 10, "hp_percent": 0.1})
	t.eq(children[0].max_hp, 10.0 * 1.1 + 10.0, "flat part scaled, percent of the parent")
