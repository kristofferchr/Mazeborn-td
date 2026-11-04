extends RefCounted
## Tests for projectiles with flight time and interest on unspent gold.

var t: Object  # test runner (check/eq)
var _base: Object = load("res://tests/core/test_game.gd").new()


func _game(gold := 100) -> Game:
	var g: Game = _base._game([_base._wave(1, 10)], gold)
	for kind: String in g.tower_defs:
		g.tower_base_stats(kind)["projectile_speed"] = 3.0
	return g


func _creep(g: Game, cell: Vector2i, hp := 100.0) -> Creep:
	var c := Creep.new(100 + g.creeps.size(), hp, 0.0, 1, cell)
	c.set_path(g.grid.path_from(cell))
	g.creeps.append(c)
	return c


func test_projectile_hits_after_its_flight_time() -> void:
	var g := _game()
	g.build(Vector2i(3, 0))
	var c := _creep(g, Vector2i(3, 2))  # 2 cells away at 3 cells/s: about 20 ticks
	g.step()
	t.eq(g.projectiles.size(), 1, "shot in flight")
	for i in 15:
		g.step()
	t.eq(c.hp, 100.0, "still flying after half a second")
	for i in 8:
		g.step()
	t.eq(c.hp, 90.0, "hit on arrival")
	t.eq(g.projectiles.size(), 1, "only the second shot is in flight")


func test_projectile_homes_on_a_moving_target() -> void:
	var g := _game()
	g.build(Vector2i(3, 0))
	var c := _creep(g, Vector2i(2, 1))
	c.speed = 1.0
	g.step()
	var hit := [false]
	g.projectile_hit.connect(func(_p: Projectile, cr: Creep) -> void: hit[0] = cr == c)
	for i in 60:
		g.step()
	t.check(hit[0], "followed the creep and hit it")


func test_shot_at_a_dead_creep_fizzles() -> void:
	var g := _game()
	g.build(Vector2i(3, 0))
	var target := _creep(g, Vector2i(3, 1))
	g.step()
	var misses := [0]
	g.projectile_hit.connect(func(_p: Projectile, cr: Creep) -> void: misses[0] += int(cr == null))
	g.creeps.erase(target)  # leaked or killed by something else before the shot lands
	for i in 15:
		g.step()
	t.eq(misses[0], 1, "the shot fizzled")
	t.eq(target.hp, 100.0, "no damage")


func test_cannon_ball_splashes_where_its_dead_target_was() -> void:
	var g := _game()
	g.tower_base_stats("cannon").cooldown = 100.0  # one shot only
	g.build(Vector2i(4, 0), "cannon")
	var a := _creep(g, Vector2i(3, 1))
	var b := _creep(g, Vector2i(4, 1))
	g.step()
	var ball: Projectile = g.projectiles[0]
	var other := b if ball.target == a else a
	ball.target.hp = 0.0
	g.creeps.erase(ball.target)
	for i in 30:
		g.step()
	t.eq(other.hp, 90.0, "50 % splash of 20 at the last known position")


func test_interest_on_unspent_gold_is_capped() -> void:
	var g: Game = _base._game([_base._wave(1, 10)], 100)
	g.interest_rate = 0.05
	g.interest_max = 15
	g.start_wave()
	g.run_wave()
	t.eq(g.gold, 105, "5 % of 100, no bounty (leaked)")
	g = _base._game([_base._wave(1, 10)], 1000)
	g.interest_rate = 0.05
	g.interest_max = 15
	g.start_wave()
	g.run_wave()
	t.eq(g.gold, 1015, "capped at 15")


func test_default_towers_fire_projectiles_except_lightning() -> void:
	var g := Game.create_default()
	for kind in g.tower_order:
		for id: String in g.tower_defs[kind].nodes:
			var node: Dictionary = g.tower_defs[kind].nodes[id]
			# Lightning hits instantly; everything else flies.
			t.check(
				node.has("projectile_speed") or node.has("chain"), "%s has a projectile speed" % id
			)
	t.check(g.interest_rate > 0.0 and g.interest_max > 0, "interest configured")
