extends RefCounted
## Tests for tower kinds, upgrades, creep kinds, mixed waves and bonuses.

var t: Object  # test runner (check/eq)
var _base: Object = load("res://tests/core/test_game.gd").new()


func _game(waves: Array, gold := 100) -> Game:
	return _base._game(waves, gold)


func _wave(count: int, hp: float, speed := 2.0, bounty := 1, creep := "normal") -> Dictionary:
	return _base._wave(count, hp, speed, bounty, creep)


## A creep standing still at cell, already in the game (for direct effect tests).
func _creep(g: Game, cell: Vector2i, hp := 100.0, kind := "normal") -> Creep:
	var c := Creep.new(g.creeps.size() + 100, hp, 0.0, 1, cell, kind)
	c.set_path(g.grid.path_from(cell))
	c.flying = kind == "flying"
	c.armor = int(g.creep_defs[kind].get("armor", 0))
	g.creeps.append(c)
	return c


func test_upgrade_costs_gold_and_raises_damage() -> void:
	var g := _game([_wave(1, 10)], 40)
	g.build(Vector2i(3, 0))
	var tower := g.tower_at(Vector2i(3, 0))
	t.eq(tower.upgrade_cost(), 20, "upgrade price from data")
	t.check(g.upgrade(Vector2i(3, 0)), "upgrade")
	t.eq(g.gold, 10, "paid 10 + 20")
	t.eq(tower.level, 1, "level 2")
	t.eq(int(tower.stats().damage_min), 30, "stronger")
	t.check(not g.can_upgrade(Vector2i(3, 0)), "max level")
	t.eq(g.sell(Vector2i(3, 0)), 22, "75 % of 30 invested")


func test_upgrade_needs_gold() -> void:
	var g := _game([_wave(1, 10)], 25)
	g.build(Vector2i(3, 0))
	t.check(not g.upgrade(Vector2i(3, 0)), "15 gold is not enough")
	t.eq(g.gold, 15, "nothing paid")


func test_kinds_have_their_own_cost() -> void:
	var g := _game([_wave(1, 10)], 30)
	t.check(g.build(Vector2i(3, 0), "cannon") != null, "cannon")
	t.eq(g.gold, 10, "cannon costs 20")
	t.check(not g.can_build(Vector2i(3, 2), "cannon"), "cannot afford a second")
	t.check(g.can_build(Vector2i(3, 2), "stone"), "but a stone tower")


func test_cannon_splash_hits_neighbours() -> void:
	var g := _game([_wave(1, 10)])
	g.build(Vector2i(3, 0), "cannon")
	var a := _creep(g, Vector2i(3, 1))
	var b := _creep(g, Vector2i(4, 1))
	var far := _creep(g, Vector2i(6, 2))
	g.step()
	t.eq(a.hp + b.hp, 100.0 - 20.0 + 100.0 - 10.0, "20 to the target, 50 % splash")
	t.eq(far.hp, 100.0, "out of splash radius")


func test_frost_slows_and_wears_off() -> void:
	var g := _game([_wave(1, 10)])
	var c := _creep(g, Vector2i(3, 1))
	c.speed = 2.0
	c.apply_slow(0.5, 1.0)
	t.eq(c.current_speed(), 1.0, "half speed")
	c.apply_slow(0.3, 5.0)
	t.eq(c.slow, 0.5, "strongest slow wins")
	for i in 31:
		c.tick_effects(Game.DT)
	t.eq(c.current_speed(), 2.0, "back to full speed after a second")


func test_frost_tower_applies_slow() -> void:
	var g := _game([_wave(1, 10)])
	g.build(Vector2i(3, 0), "frost")
	var c := _creep(g, Vector2i(3, 1))
	g.step()
	t.eq(c.slow, 0.5, "slowed by the tower")


func test_poison_stacks_and_ignores_armor() -> void:
	var g := _game([_wave(1, 10)])
	var c := _creep(g, Vector2i(3, 1), 100.0, "armored")
	c.apply_poison(10, 2.0, 2)
	c.apply_poison(10, 2.0, 2)
	c.apply_poison(10, 2.0, 2)
	t.eq(c.poison.size(), 2, "capped at max stacks")
	for i in 30:
		c.tick_effects(Game.DT)
	t.check(absf(c.hp - 80.0) < 0.01, "2 stacks x 10/s for 1 s, armor ignored: %s" % c.hp)
	for i in 45:
		c.tick_effects(Game.DT)
	t.check(absf(c.hp - 60.0) < 0.01, "stops after 2 s: %s" % c.hp)
	t.check(c.poison.is_empty(), "stacks expired")


func test_armor_reduces_each_hit_but_not_below_one() -> void:
	var g := _game([_wave(1, 10)])
	var c := _creep(g, Vector2i(3, 1), 100.0, "armored")
	t.eq(c.hit(10), 6.0, "10 - 4 armor")
	t.eq(c.hit(2), 1.0, "at least 1")
	t.eq(c.hp, 93.0, "hp")


func test_flying_creeps_ignore_the_maze() -> void:
	var g := _game([_wave(1, 1000, 2.0, 1, "flying")])
	g.build(Vector2i(2, 1))
	g.build(Vector2i(4, 1))
	g.start_wave()
	g.step()
	var c: Creep = g.creeps[0]
	t.check(c.flying, "flying")
	t.eq(c.path, [g.grid.goal] as Array[Vector2i], "flies straight to the goal")
	t.check(c.occupied_cells().is_empty(), "blocks no building")
	t.check(g.can_build(Vector2i(1, 1)), "can build under it")
	g.run_wave()
	t.eq(g.lives, 19, "reached the goal over the towers")


func test_only_air_towers_hit_flying() -> void:
	var g := _game([_wave(1, 10)])
	var stone := g.build(Vector2i(3, 0), "stone")
	var air := g.build(Vector2i(3, 2), "air")
	var flyer := _creep(g, Vector2i(3, 1), 100.0, "flying")
	var walker := _creep(g, Vector2i(4, 1))
	t.check(not stone.can_hit(flyer) and stone.can_hit(walker), "stone: ground only")
	t.check(air.can_hit(flyer) and not air.can_hit(walker), "air: air only")
	g.step()
	t.eq(flyer.hp, 90.0, "air tower hit the flyer")
	t.eq(walker.hp, 90.0, "stone tower hit the walker")


func test_mixed_wave_spawns_groups_in_order() -> void:
	var w := {"groups": [_wave(2, 10), _wave(1, 50, 2.0, 1, "armored")]}
	var g := _game([w])
	var kinds: Array[String] = []
	g.creep_spawned.connect(func(c: Creep) -> void: kinds.append(c.kind))
	t.eq(g.wave_count(w), 3, "three creeps")
	t.eq(g.wave_tags(w), ["Pansret"] as Array[String], "tags from creep kinds")
	g.start_wave()
	g.run_wave()
	t.eq(kinds, ["normal", "normal", "armored"] as Array[String], "order")


func test_wave_bonus_and_early_send() -> void:
	var g := _game([_wave(2, 10), _wave(1, 10), _wave(1, 10)], 0)
	g.wave_bonus = 5
	g.early_bonus = 3
	g.start_wave()
	t.check(not g.can_send_early(), "not before the wave has spawned")
	g.step()
	t.check(not g.can_send_early(), "still spawning")
	for i in 20:
		g.step()
	t.check(g.can_send_early(), "all spawned")
	t.check(g.start_wave(), "send wave 2 early")
	t.eq(g.gold, 3, "early bonus")
	t.eq(g.wave, 2, "wave 2 running")
	g.run_wave()
	t.eq(g.gold, 8, "one wave bonus once the field is clear")
	t.eq(g.phase, Game.Phase.BUILD, "back to building")


func test_next_wave_is_shown_before_and_during_waves() -> void:
	var first := _wave(3, 10)
	var second := _wave(1, 500, 1.0, 1, "flying")
	second["tags"] = ["Boss"]
	var g := _game([first, second])
	t.eq(g.next_wave(), first, "before the first wave")
	g.start_wave()
	t.eq(g.next_wave(), second, "during wave 1 the next is wave 2")
	g.run_wave()
	t.eq(g.next_wave(), second, "between waves")
	t.eq(g.wave_tags(second), ["Flygende", "Boss"] as Array[String], "creep and wave tags")
	t.eq(g.wave_tags(first), [] as Array[String], "no tags")
	g.start_wave()
	t.eq(g.next_wave(), {}, "no more waves")


func test_default_data_is_consistent() -> void:
	var g := Game.create_default()
	t.eq(g.tower_order, ["arrow", "earth", "wind", "elemental"] as Array[String], "four kinds")
	for kind in g.tower_order:
		var def: Dictionary = g.tower_defs[kind]
		t.check(def.nodes.has(def.root), "%s has its root" % kind)
		for id: String in def.nodes:
			for next: String in def.nodes[id].get("next", []):
				t.check(def.nodes.has(next), "%s -> %s exists" % [id, next])
	t.check(g.can_afford("arrow"), "can afford a tower at start")
	for w in g.waves:
		for group in Game.wave_groups(w):
			t.check(g.creep_defs.has(str(group.creep)), "creep %s defined" % group.creep)
	t.check("Boss" in g.wave_tags(g.waves[-1]), "last wave is the boss")
	t.check("Flygende" in g.wave_tags(g.waves[4]), "wave 5 flies")
