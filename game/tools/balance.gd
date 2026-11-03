extends SceneTree
## Bot that builds a serpentine maze with mixed tower kinds, adds air towers
## before flying waves and upgrades once the maze is done. For balancing.
## Usage: scripts/godot.sh --headless --path game -s res://tools/balance.gd [-- seed]

const AIR_FOR_FLYERS := 6


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var g := Game.create_default(int(args[0]) if args.size() > 0 else 3)
	var leaked_by_wave := {}
	g.creep_leaked.connect(
		func(_c: Creep) -> void: leaked_by_wave[g.wave] = 1 + leaked_by_wave.get(g.wave, 0)
	)
	while not g.is_over():
		_spend(g)
		g.start_wave()
		g.run_wave()
		var levels := 0
		for cell: Vector2i in g.towers:
			levels += g.towers[cell].level
		print(
			(
				"wave %2d %-22s lives %2d leaked %2d gold %3d towers %2d upgrades %2d path %d"
				% [
					g.wave,
					", ".join(g.wave_tags(g.waves[g.wave - 1])),
					g.lives,
					leaked_by_wave.get(g.wave, 0),
					g.gold,
					g.towers.size(),
					levels,
					g.grid.path().size(),
				]
			)
		)
	print("result: ", Game.Phase.keys()[g.phase])
	quit()


func _spend(g: Game) -> void:
	if "Flygende" in g.wave_tags(g.next_wave()):
		_air_towers(g)
	# Build the maze; after two walls, alternate between building and upgrading.
	var plan := MazePlan.serpentine(g.grid)
	var build_next := true
	while true:
		var did := false
		if build_next or g.towers.size() < 22:
			did = _build_next(g, plan)
		if not did:
			did = _upgrade_cheapest(g)
		if not did and not build_next:
			did = _build_next(g, plan)
		if not did:
			return
		build_next = not build_next


func _build_next(g: Game, plan: Array[Vector2i]) -> bool:
	for i in plan.size():
		if g.tower_at(plan[i]) == null:
			var kind := _kind_for(i)
			return g.can_afford(kind) and g.build(plan[i], kind) != null
	return false


func _upgrade_cheapest(g: Game) -> bool:
	var best := Vector2i(-1, -1)
	var best_cost := 1 << 30
	for cell: Vector2i in g.towers:
		var tower: Tower = g.towers[cell]
		if tower.can_upgrade() and tower.upgrade_cost() < best_cost:
			best = cell
			best_cost = tower.upgrade_cost()
	return best.x >= 0 and g.upgrade(best)


## Stone for the first wall (cheap mazing), then a mix along the maze.
func _kind_for(i: int) -> String:
	if i < 11:
		return "stone"
	if i % 5 == 2:
		return "cannon"
	if i % 7 == 3:
		return "frost"
	if i % 9 == 4:
		return "poison"
	return "stone"


## Air towers next to the straight line flyers take from spawn to goal.
func _air_towers(g: Game) -> void:
	var have := 0
	for cell: Vector2i in g.towers:
		if g.towers[cell].kind == "air":
			have += 1
	var a := Grid.center(g.grid.spawn)
	var b := Grid.center(g.grid.goal)
	var cells: Array[Vector2i] = []
	for x in g.grid.size.x:
		for y in g.grid.size.y:
			cells.append(Vector2i(x, y))
	cells.sort_custom(
		func(p: Vector2i, q: Vector2i) -> bool:
			return _line_dist(Grid.center(p), a, b) < _line_dist(Grid.center(q), a, b)
	)
	for cell in cells:
		if have >= AIR_FOR_FLYERS or not g.can_afford("air"):
			return
		if cell.x % 3 == 0 and g.build(cell, "air") != null:
			have += 1


func _line_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return p.distance_to(a + ab * t)
