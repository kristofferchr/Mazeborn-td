extends RefCounted
## Tests for upgrade trees (Elemental) and the effects of the new towers:
## stun, knockback, extra damage to flyers, chain lightning, multishot,
## splash effects and armor pierce.

var t: Object  # test runner (check/eq)
var _base: Object = load("res://tests/core/test_game.gd").new()


## A test game with one extra tower kind "x" built from the given nodes.
func _game_with(nodes: Dictionary, gold := 500, targets := ["ground", "air"]) -> Game:
	var g: Game = _base._game([_base._wave(1, 10)], gold)
	g.tower_defs["x"] = {"name": "X", "root": "root", "targets": targets, "nodes": nodes}
	return g


func _stats(damage: int, extra := {}) -> Dictionary:
	return _base._level(10, damage, extra)


func _creep(g: Game, cell: Vector2i, hp := 100.0, kind := "normal") -> Creep:
	var c := Creep.new(100 + g.creeps.size(), hp, 0.0, 1, cell, kind)
	c.set_path(g.grid.path_from(cell))
	c.flying = kind == "flying"
	c.armor = int(g.creep_defs[kind].get("armor", 0))
	g.creeps.append(c)
	return c


func _tree() -> Dictionary:
	var root := _stats(10, {"next": ["fire", "ice"]})
	var fire := _stats(20, {"cost": 40, "element": "fire", "next": ["inferno", "meteor"]})
	return {
		"root": root,
		"fire": fire,
		"ice": _stats(15, {"cost": 40, "element": "ice"}),
		"inferno": _stats(40, {"cost": 90, "element": "fire"}),
		"meteor": _stats(80, {"cost": 90, "element": "fire"}),
	}


func test_upgrade_tree_offers_branches_and_follows_the_choice() -> void:
	var g := _game_with(_tree())
	var tower := g.build(Vector2i(3, 0), "x")
	t.eq(tower.upgrade_options(), ["fire", "ice"] as Array[String], "two branches")
	t.eq(tower.max_level(), 2, "tree is two upgrades deep")
	t.check(not g.can_upgrade(Vector2i(3, 0), "meteor"), "cannot skip a level")
	t.check(g.upgrade(Vector2i(3, 0), "fire"), "choose fire")
	t.eq(tower.element(), "fire", "element of the branch")
	t.eq(tower.level, 1, "level 1")
	t.eq(tower.upgrade_options(), ["inferno", "meteor"] as Array[String], "fire specialisations")
	t.check(g.upgrade(Vector2i(3, 0), "meteor"), "choose meteor")
	t.check(not tower.can_upgrade(), "end of the tree")
	t.eq(tower.invested, 140, "10 + 40 + 90")
	t.eq(g.sell(Vector2i(3, 0)), 105, "75 % of all gold invested")


func test_default_elemental_has_four_branches_of_two() -> void:
	var g := Game.create_default()
	var def: Dictionary = g.tower_defs.elemental
	var branches: Array = def.nodes[def.root].next
	t.eq(branches.size(), 4, "fire, ice, lightning, nature")
	for b: String in branches:
		t.eq(def.nodes[b].get("next", []).size(), 2, "%s has two specialisations" % b)
		for spec: String in def.nodes[b].next:
			t.check(not def.nodes[spec].has("next"), "%s is a final form" % spec)


func test_stun_stops_the_creep_for_a_while() -> void:
	var c := Creep.new(1, 100, 2.0, 1, Vector2i(0, 1))
	c.set_path([Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1)])
	c.apply_stun(0.5)
	var start := c.pos
	for i in 10:
		c.tick_effects(Game.DT)
		c.advance(Game.DT)
	t.eq(c.pos, start, "stands still while stunned")
	for i in 10:
		c.tick_effects(Game.DT)
		c.advance(Game.DT)
	t.check(c.pos.x > start.x, "walks again after the stun")


func test_knockback_pushes_back_but_not_past_the_last_cell() -> void:
	var c := Creep.new(1, 100, 2.0, 1, Vector2i(0, 1))
	c.set_path([Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1)])
	for i in 12:
		c.advance(Game.DT)  # 0.8 cells: between (0,1) and (1,1)... then past (1,1)
	var before := c.pos.x
	c.knock_back(0.2)
	t.check(absf(c.pos.x - (before - 0.2)) < 0.001, "pushed back 0.2 cells")
	c.knock_back(5.0)
	t.eq(c.pos, Grid.center(c.prev_cell), "stops at the cell it came from")


func test_wind_does_extra_damage_to_flyers() -> void:
	var g := _game_with({"root": _stats(10, {"air_multiplier": 2.5})})
	g.build(Vector2i(3, 0), "x")
	var flyer := _creep(g, Vector2i(3, 1), 100.0, "flying")
	g.step()
	t.eq(flyer.hp, 75.0, "10 x 2.5")


func test_chain_lightning_hops_to_the_nearest_creeps() -> void:
	var g := _game_with({"root": _stats(20, {"chain": 2, "chain_range": 1.5, "chain_factor": 0.5})})
	g.build(Vector2i(3, 0), "x")
	var a := _creep(g, Vector2i(3, 1))
	var b := _creep(g, Vector2i(4, 1))
	var c := _creep(g, Vector2i(5, 1))
	var far := _creep(g, Vector2i(5, 2))
	far.pos = Vector2(6.5, 2.5)  # out of hop range from c
	var hops := [0]
	g.chain_hit.connect(func(_f: Vector2, _c: Creep) -> void: hops[0] += 1)
	g.step()
	var hit := [a.hp, b.hp, c.hp]
	hit.sort()
	t.eq(hit, [80.0, 90.0, 95.0], "20, then 10, then 5")
	t.eq(far.hp, 100.0, "two hops only")
	t.eq(hops[0], 2, "two hops reported")


func test_multishot_hits_several_targets() -> void:
	var g := _game_with({"root": _stats(10, {"multishot": 3})})
	g.build(Vector2i(3, 0), "x")
	var cs: Array[Creep] = [
		_creep(g, Vector2i(2, 1)),
		_creep(g, Vector2i(3, 1)),
		_creep(g, Vector2i(4, 1)),
		_creep(g, Vector2i(4, 2)),
	]
	g.step()
	var hit := 0
	for c in cs:
		hit += int(c.hp < 100.0)
	t.eq(hit, 3, "three of four creeps hit")


func test_splash_effects_slow_every_creep_in_the_area() -> void:
	var g := _game_with(
		{
			"root":
			_stats(
				10,
				{
					"slow": 0.5,
					"slow_time": 2.0,
					"splash_radius": 1.5,
					"splash_factor": 0.5,
					"splash_effects": true,
				}
			)
		}
	)
	g.build(Vector2i(3, 0), "x")
	var a := _creep(g, Vector2i(3, 1))
	var b := _creep(g, Vector2i(4, 1))
	g.step()
	t.eq(a.slow, 0.5, "target slowed")
	t.eq(b.slow, 0.5, "neighbour slowed too")


func test_armor_pierce_ignores_armor() -> void:
	var g := _game_with({"root": _stats(10, {"armor_pierce": true})})
	g.build(Vector2i(3, 0), "x")
	var c := _creep(g, Vector2i(3, 1), 100.0, "armored")
	g.step()
	t.eq(c.hp, 90.0, "full 10 despite 4 armor")
