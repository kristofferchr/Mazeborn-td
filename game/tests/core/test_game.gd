extends RefCounted
## Tests for core/game.gd: economy, waves, creeps, towers and determinism.

var t: Object  # test runner (check/eq)


func _config(waves: Array, gold := 100) -> Dictionary:
	return {
		"start_gold": gold,
		"lives": 20,
		"tower":
		{
			"cost": 10,
			"refund": 0.75,
			"range": 2.5,
			"damage_min": 10,
			"damage_max": 10,
			"cooldown": 0.5,
		},
		"waves": waves,
	}


func _wave(count: int, hp: float, speed := 2.0, bounty := 1) -> Dictionary:
	return {"count": count, "hp": hp, "speed": speed, "interval": 0.5, "bounty": bounty}


## 7x3 corridor, spawn left, goal right.
func _game(waves: Array, gold := 100, seed_value := 1) -> Game:
	var grid := Grid.new(Vector2i(7, 3), Vector2i(0, 1), Vector2i(6, 1))
	return Game.new(_config(waves, gold), grid, seed_value)


func test_build_costs_gold_and_sell_refunds_75_percent() -> void:
	var g := _game([_wave(1, 10)], 25)
	t.check(g.build(Vector2i(3, 0)) != null, "build")
	t.eq(g.gold, 15, "gold after build")
	t.check(g.build(Vector2i(3, 2)) != null, "second build")
	t.eq(g.gold, 5, "gold after second build")
	t.check(g.build(Vector2i(4, 0)) == null, "not enough gold")
	t.eq(g.sell(Vector2i(3, 0)), 7, "refund is floor(75 %)")
	t.eq(g.gold, 12, "gold after sell")
	t.check(g.tower_at(Vector2i(3, 0)) == null, "tower removed")
	t.check(not g.grid.is_blocked(Vector2i(3, 0)), "cell reopened")
	t.eq(g.sell(Vector2i(3, 0)), 0, "nothing to sell")


func test_blocking_build_is_rejected_and_costs_nothing() -> void:
	var g := _game([_wave(1, 10)])
	g.build(Vector2i(3, 0))
	g.build(Vector2i(3, 1))
	t.check(g.build(Vector2i(3, 2)) == null, "would block the path")
	t.eq(g.gold, 80, "only two towers paid")


func test_creeps_leak_and_cost_lives_without_towers() -> void:
	var g := _game([_wave(5, 10)])
	var leaked := [0]
	g.creep_leaked.connect(func(_c: Creep) -> void: leaked[0] += 1)
	t.check(g.start_wave(), "start wave")
	t.check(not g.start_wave(), "cannot start while a wave runs")
	g.run_wave()
	t.eq(leaked[0], 5, "all leaked")
	t.eq(g.lives, 15, "lives lost")
	t.eq(g.phase, Game.Phase.WON, "last wave survived means victory")


func test_losing_all_lives_ends_the_game() -> void:
	var g := _game([_wave(25, 10)])
	var result := [null]
	g.game_over.connect(func(won: bool) -> void: result[0] = won)
	g.start_wave()
	g.run_wave()
	t.eq(g.phase, Game.Phase.LOST, "lost")
	t.eq(g.lives, 0, "no lives")
	t.eq(result[0], false, "game_over(false) emitted")
	t.check(g.build(Vector2i(3, 0)) == null, "no building after the end")


func test_tower_kills_and_pays_bounty() -> void:
	var g := _game([_wave(3, 20, 1.0, 5)], 10)
	var tower := g.build(Vector2i(3, 0))
	t.check(tower != null, "build")
	g.start_wave()
	g.run_wave()
	t.eq(g.lives, 20, "nothing leaked")
	t.eq(g.gold, 15, "3 kills x 5 gold")
	t.eq(g.phase, Game.Phase.WON, "won")


func test_creeps_follow_new_path_from_current_cell() -> void:
	var g := _game([_wave(1, 1000, 1.0)])
	g.start_wave()
	for i in 30:  # one second: the creep walks from (0,1) towards (1,1)/(2,1)
		g.step()
	var creep: Creep = g.creeps[0]
	var from := creep.target_cell()
	t.check(not g.can_build(from), "cannot build where a creep walks")
	t.check(g.build(Vector2i(4, 1)) != null, "block the straight line")
	t.eq(creep.path[0], from, "new path starts at the current cell")
	t.check(Vector2i(4, 1) not in creep.path, "new path avoids the tower")
	t.eq(creep.path[-1], Vector2i(6, 1), "still ends at the goal")
	var visited: Array[Vector2i] = []
	while not g.creeps.is_empty():
		g.step()
		if not g.creeps.is_empty() and creep.prev_cell not in visited:
			visited.append(creep.prev_cell)
	t.check(Vector2i(4, 1) not in visited, "never walked through the tower")
	t.eq(g.lives, 19, "reached the goal")


func test_cannot_trap_creep_in_a_pocket() -> void:
	var g := _game([_wave(1, 10)])
	var creep_at: Array[Vector2i] = [Vector2i(2, 0)]
	g.build(Vector2i(1, 0))
	g.build(Vector2i(3, 0))
	t.check(g.grid.can_build(Vector2i(2, 1)), "fine without creeps")
	t.check(not g.grid.can_build(Vector2i(2, 1), creep_at), "would trap the creep")


func test_targeting_first_and_closest() -> void:
	var tower := Tower.new(Vector2i(3, 0), _config([]).tower)
	tower.attack_range = 10.0
	var near := Creep.new(1, 10, 1, 1, Vector2i(3, 1))
	near.set_path([Vector2i(3, 1), Vector2i(4, 1), Vector2i(5, 1), Vector2i(6, 1)])
	var ahead := Creep.new(2, 10, 1, 1, Vector2i(5, 2))
	ahead.set_path([Vector2i(5, 2), Vector2i(6, 2)])
	var creeps: Array[Creep] = [near, ahead]
	t.eq(tower.pick_target(creeps), ahead, "first in path")
	tower.targeting = Tower.Targeting.CLOSEST
	t.eq(tower.pick_target(creeps), near, "closest")


func test_wave_simulation_is_deterministic_with_seed() -> void:
	var a := _summary(7)
	var b := _summary(7)
	t.eq(a, b, "same seed gives same result")
	t.eq(a, [15, 15, Game.Phase.BUILD], "known setup: gold, lives, phase")


func _summary(seed_value: int) -> Array:
	var g := _game([_wave(10, 30, 1.5, 3), _wave(1, 10)], 20, seed_value)
	g.tower_stats.damage_min = 5
	g.tower_stats.damage_max = 15
	g.build(Vector2i(2, 0))
	g.build(Vector2i(4, 2))
	g.start_wave()
	g.run_wave()
	return [g.gold, g.lives, g.phase]


func test_default_config_loads() -> void:
	var g := Game.create_default()
	t.check(g.waves.size() >= 5, "has waves")
	t.check(g.gold >= g.tower_cost(), "can afford a tower")
	t.eq(g.lives, 20, "lives")
	t.check(not g.grid.path().is_empty(), "map has a path")


func test_simulate_uses_fixed_steps() -> void:
	var g := _game([_wave(1, 10)])
	g.simulate(Game.DT * 2.5)
	t.eq(g.ticks, 2, "two whole steps")
	g.simulate(Game.DT * 0.6)
	t.eq(g.ticks, 3, "remainder carried over")
