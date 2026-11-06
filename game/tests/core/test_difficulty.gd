extends RefCounted
## Tests for difficulty levels (core/difficulty.gd, data/difficulty.json) and
## the options of Game.create_map.

var t: Object  # test runner (check/eq)


func test_levels_in_order_with_norwegian_names() -> void:
	t.eq(Difficulty.ids(), ["easy", "normal", "hard", "extreme"] as Array[String], "order")
	var names: Array[String] = []
	for id in Difficulty.ids():
		names.append(Difficulty.display_name(id))
		t.check(str(Difficulty.level(id).get("description", "")) != "", "%s description" % id)
	t.eq(names, ["Lett", "Normal", "Vanskelig", "Ekstrem"] as Array[String], "names")
	t.eq(Difficulty.DEFAULT, "normal", "default level")


func test_normal_is_the_plain_config() -> void:
	var config := Game.default_config()
	for id in Maps.ids():
		var rules: Dictionary = Maps.load_map(id).get("rules", {})
		var plain := Game.create_map(id, 1)
		var normal := Game.create_map(id, 1, {"difficulty": "normal"})
		for g: Game in [plain, normal]:
			t.eq(g.difficulty, "normal", "%s level" % id)
			t.eq(g.gold, int(rules.get("start_gold", config.start_gold)), "%s gold" % id)
			t.eq(g.lives, int(rules.get("lives", config.lives)), "%s lives" % id)
			t.eq(g.start_lives, g.lives, "%s start lives" % id)
			t.eq(g.hp_scale, float(rules.get("hp_scale", 1.0)), "%s hp_scale" % id)
			t.eq(g.bounty_scale, 1.0, "%s bounty_scale" % id)
			t.eq(g.interest_rate, float(config.interest_rate), "%s interest" % id)
			t.eq(g.creep_bounty(3), 3, "%s bounty" % id)
	# Today's numbers on the default map.
	var g := Game.create_map("engen")
	t.eq([g.gold, g.lives, g.hp_scale], [80, 20, 1.0], "Engen on Normal")


func test_every_factor_scales_its_value() -> void:
	var base := Game.create_map("engen", 1)
	for id in Difficulty.ids():
		var g := Game.create_map("engen", 1, {"difficulty": id})
		t.eq(g.difficulty, id, "level id")
		var f := func(key: String) -> float: return Difficulty.factor(id, key)
		t.eq(g.gold, maxi(roundi(base.gold * f.call("start_gold_scale")), 1), "%s gold" % id)
		t.eq(g.lives, maxi(roundi(base.lives * f.call("lives_scale")), 1), "%s lives" % id)
		t.eq(g.start_lives, g.lives, "%s start lives" % id)
		t.check(is_equal_approx(g.hp_scale, f.call("hp_scale")), "%s hp_scale" % id)
		t.check(is_equal_approx(g.bounty_scale, f.call("bounty_scale")), "%s bounty" % id)
		t.check(
			is_equal_approx(g.interest_rate, base.interest_rate * f.call("interest_scale")),
			"%s interest" % id
		)


func test_levels_get_harder() -> void:
	var prev: Game = null
	for id in Difficulty.ids():
		var g := Game.create_map("engen", 1, {"difficulty": id})
		if prev:
			t.check(g.hp_scale > prev.hp_scale, "%s tougher creeps" % id)
			t.check(g.lives < prev.lives, "%s fewer lives" % id)
			t.check(g.gold <= prev.gold, "%s no more gold" % id)
			t.check(g.bounty_scale <= prev.bounty_scale, "%s no more bounty" % id)
		prev = g
	var easy := Game.create_map("engen", 1, {"difficulty": "easy"})
	var extreme := Game.create_map("engen", 1, {"difficulty": "extreme"})
	t.check(easy.gold > 80 and easy.lives > 20 and easy.hp_scale < 1.0, "Lett is easier")
	t.check(extreme.interest_rate < 0.05, "Ekstrem pays less interest")


func test_difficulty_composes_with_the_map_hp_scale() -> void:
	var g := Game.create_map("klofta", 1, {"difficulty": "hard"})
	var expected := 1.1 * Difficulty.factor("hard", "hp_scale")
	t.check(is_equal_approx(g.hp_scale, expected), "Kløfta x Vanskelig: %f" % g.hp_scale)
	g.start_wave()
	g.step()
	t.check(is_equal_approx(g.creeps[0].max_hp, 35.0 * expected), "spawned creep health")


func test_bounty_scale_pays_kills_and_split_children() -> void:
	var g := Game.create_map("engen", 1, {"difficulty": "easy"})
	var f := Difficulty.factor("easy", "bounty_scale")
	g.start_wave()
	g.step()
	t.eq(g.creeps[0].bounty, roundi(3 * f), "first creep bounty")
	var parent := g.new_creep("normal", 100.0, 1, {}, g.grid.spawn)
	parent.set_path(g.grid.path())
	var kids := g._spawn_children(parent, {"count": 1, "hp": 10, "bounty": 4})
	t.eq(kids[0].bounty, roundi(4 * f), "child bounty")
	var poor := Game.create_map("engen", 1, {"difficulty": "extreme"})
	t.eq(poor.creep_bounty(1), 1, "a kill always pays at least 1")
	t.eq(poor.creep_bounty(0), 0, "nothing stays nothing")
	var gold := g.gold
	g.creeps[0].hp = 0.0
	g._reap()
	t.eq(g.gold, gold + roundi(3 * f), "kill pays the scaled bounty")


func test_unknown_level_falls_back_and_options_pass_through() -> void:
	var g := Game.create_map("engen", 1, {"difficulty": "nightmare", "mode": "endless"})
	t.eq(g.difficulty, "normal", "unknown level")
	t.eq(g.options.get("mode"), "endless", "unknown keys are kept")
	t.eq(g.options.difficulty, "normal", "options hold the level used")
	var opts := {"difficulty": "hard"}
	Game.create_map("engen", 1, opts)
	t.eq(opts, {"difficulty": "hard"}, "the caller's options are not changed")
	t.eq(Game.create_map("engen").options, {"difficulty": "normal"}, "default options")
