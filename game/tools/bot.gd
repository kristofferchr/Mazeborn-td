class_name Bot
extends RefCounted
## Bot that builds a serpentine maze (MazePlan) with mixed tower kinds, adds air
## towers before flying waves, upgrades arrows along the maze to sharpshooters
## (they reveal invisible creeps) before invisible waves and upgrades once the
## maze is done. Used by the balance tool, the map tests and to record replays:
## every move goes through Game.apply, so it is recorded like a player's.

const AIR_FOR_FLYERS := 6
const REVEAL_EVERY := 8  # a revealing tower every this many towers along the maze

var game: Game
var plan: Array[Vector2i]
var leaked_by_wave := {}  # wave number -> creeps that got through
## Send each wave as soon as the bot has built instead of letting the
## countdown run out (no gold for it, only less time between waves).
var send_early := false


func _init(p_game: Game, p_send_early := false) -> void:
	game = p_game
	send_early = p_send_early
	plan = MazePlan.serpentine(game.grid)


## Plays the whole round, in endless at most `max_waves` waves (0: no limit).
## `on_wave` is called after each wave (with this bot).
func play(on_wave := Callable(), max_waves := 0) -> bool:
	while not game.is_over() and (max_waves <= 0 or game.wave < max_waves):
		play_wave()
		if on_wave.is_valid():
			on_wave.call(self)
	return game.phase == Game.Phase.WON


## Spends the gold during the build phase (no gold comes in then, so building
## at once is the same as building during the countdown), then starts the
## next wave: the first one and with send_early at once, else when the
## countdown runs out. Runs the wave to its end. Leaks are counted from the
## lives (no signal, so the bot and the game do not keep each other alive).
func play_wave() -> void:
	spend()
	var lives := game.lives
	if game.wave == 0 or send_early or not game.countdown_active():
		game.apply({"type": "start_wave"})
	else:
		while game.countdown_active():
			game.step()
	game.run_wave()
	leaked_by_wave[game.wave] = lives - game.lives


func spend() -> void:
	if "Flygende" in game.wave_tags(game.next_wave()):
		_air_towers()
	if "Usynlig" in game.wave_tags(game.next_wave()):
		_revealers()
	# Build the maze; after two walls, alternate between building and upgrading.
	var build_next := true
	while true:
		var did := false
		if build_next or game.towers.size() < 22:
			did = _build_next()
		if not did:
			did = _upgrade_cheapest()
		if not did and not build_next:
			did = _build_next()
		if not did:
			return
		build_next = not build_next


func upgrades() -> int:
	var levels := 0
	for cell: Vector2i in game.towers:
		levels += game.towers[cell].level
	return levels


## Builds on the next free cell of the plan. Cells that can no longer be built
## (they would cut off a spawn) are skipped.
func _build_next() -> bool:
	for i in plan.size():
		if game.tower_at(plan[i]) != null or not game.grid.can_build(plan[i]):
			continue
		var kind := _kind_for(i)
		return game.can_afford(kind) and _build(plan[i], kind)
	return false


## Cheapest upgrade first. Elemental towers take their element by position in
## the maze (so a round tries all of them) and the first specialisation.
func _upgrade_cheapest() -> bool:
	var best := Vector2i(-1, -1)
	var best_option := ""
	var best_cost := 1 << 30
	for cell: Vector2i in game.towers:
		var tower: Tower = game.towers[cell]
		var options := tower.upgrade_options()
		if options.is_empty():
			continue
		var option := (
			options[(cell.x + cell.y) % options.size()] if tower.level == 0 else options[0]
		)
		if tower.upgrade_cost(option) < best_cost:
			best = cell
			best_option = option
			best_cost = tower.upgrade_cost(option)
	return best.x >= 0 and _upgrade(best, best_option)


## Upgrades arrows spread along the maze until they reveal invisible creeps.
func _revealers() -> void:
	for i in range(REVEAL_EVERY / 2, plan.size(), REVEAL_EVERY):
		for j in range(i, mini(i + 3, plan.size())):
			var tower := game.tower_at(plan[j])
			if tower != null and tower.kind == "arrow":
				while not tower.reveals() and _upgrade(plan[j]):
					pass
				break


## Arrow for the first wall (cheap mazing), then a mix along the maze.
func _kind_for(i: int) -> String:
	if i < 11:
		return "arrow"
	if i % 5 == 2:
		return "earth"
	if i % 6 == 3:
		return "elemental"
	return "arrow"


## Air towers on the maze cells closest to the straight lines flyers take from
## the spawns to the goal.
func _air_towers() -> void:
	var have := 0
	for cell: Vector2i in game.towers:
		if game.towers[cell].kind == "wind":
			have += 1
	var cells: Array[Vector2i] = []
	for cell in plan:
		if game.tower_at(cell) == null:
			cells.append(cell)
	cells.sort_custom(func(p: Vector2i, q: Vector2i) -> bool: return _air_dist(p) < _air_dist(q))
	for cell in cells:
		if have >= AIR_FOR_FLYERS or not game.can_afford("wind"):
			return
		if _build(cell, "wind"):
			have += 1


## Distance from a cell to the nearest flight line.
func _air_dist(cell: Vector2i) -> float:
	var p := Grid.center(cell)
	var b := Grid.center(game.grid.goal)
	var best := INF
	for s in game.grid.spawns:
		var a := Grid.center(s)
		var ab := b - a
		var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		best = minf(best, p.distance_to(a + ab * t))
	return best


func _build(cell: Vector2i, kind: String) -> bool:
	return game.apply({"type": "build", "cell": cell, "kind": kind})


func _upgrade(cell: Vector2i, option := "") -> bool:
	return game.apply({"type": "upgrade", "cell": cell, "option": option})
