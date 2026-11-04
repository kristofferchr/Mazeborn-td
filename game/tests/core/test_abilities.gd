extends RefCounted
## Tests for creep abilities (heal, shield, split, immune, invisible) and boss
## mechanics (summon, enrage, invulnerable phases), all from data.

var t: Object  # test runner (check/eq)
var _base: Object = load("res://tests/core/test_game.gd").new()


## A test game (7x3 corridor) with extra creep kinds.
func _game_with(kinds: Dictionary, waves: Array = []) -> Game:
	var g: Game = _base._game(waves if not waves.is_empty() else [_base._wave(1, 10)])
	g.creep_defs.merge(kinds, true)
	return g


## A creep of a kind standing still (speed 0) on a cell, on its way to the goal.
func _creep(g: Game, kind: String, cell: Vector2i, hp := 100.0, speed := 0.0) -> Creep:
	var c := g.new_creep(kind, hp, 1, {"speed": speed}, cell)
	c.set_path(g.grid.path_from(cell))
	g.creeps.append(c)
	return c


func _steps(g: Game, n: int) -> void:
	for i in n:
		g.step()


func test_healer_heals_creeps_in_radius_but_not_above_max() -> void:
	var g := _game_with(
		{"healer": {"abilities": {"heal": {"interval": 1.0, "radius": 1.5, "amount": 10}}}}
	)
	var healer := _creep(g, "healer", Vector2i(2, 1))
	var near := _creep(g, "normal", Vector2i(3, 1))
	var far := _creep(g, "normal", Vector2i(5, 1))
	near.hp = 50.0
	far.hp = 50.0
	healer.hp = 95.0
	var pulses := [0]
	g.creep_healed.connect(func(_h: Creep, r: float) -> void: pulses[0] += int(r == 1.5))
	_steps(g, 25)
	t.eq(near.hp, 50.0, "nothing before the first pulse")
	_steps(g, 10)
	t.eq(near.hp, 60.0, "healed 10 after one second")
	t.eq(far.hp, 50.0, "out of radius")
	t.eq(healer.hp, 100.0, "heals itself, but only up to max hp")
	t.eq(pulses[0], 1, "one pulse reported with its radius")
	_steps(g, 30)
	t.eq(near.hp, 70.0, "heals again every second")


func test_heal_percent_scales_with_max_hp() -> void:
	var g := _game_with(
		{"healer": {"abilities": {"heal": {"interval": 0.5, "radius": 2.0, "percent": 0.1}}}}
	)
	_creep(g, "healer", Vector2i(2, 1))
	var big := _creep(g, "normal", Vector2i(3, 1), 400.0)
	big.hp = 100.0
	_steps(g, 16)
	t.eq(big.hp, 140.0, "10 % of 400")


func test_shield_absorbs_hits_and_poison_before_hp() -> void:
	var c := Creep.new(1, 100.0, 1.0, 1, Vector2i(0, 1))
	c.armor = 2
	c.setup_abilities({"shield": {"amount": 10, "percent": 0.1}})
	t.eq(c.shield, 20.0, "10 + 10 % of 100")
	t.eq(c.hit(17), 15.0, "armor first, then the shield takes it")
	t.eq(c.hp, 100.0, "hp untouched")
	t.eq(c.shield, 5.0, "shield left")
	c.hit(12)
	t.eq(c.shield, 0.0, "shield broken")
	t.eq(c.hp, 95.0, "the rest went to hp")
	var d := Creep.new(2, 100.0, 1.0, 1, Vector2i(0, 1))
	d.setup_abilities({"shield": {"amount": 15}})
	d.apply_poison(10, 2.0, 1)
	for i in 30:
		d.tick_effects(Game.DT)
	t.check(absf(d.shield - 5.0) < 0.01, "poison eats the shield first: %s" % d.shield)
	t.eq(d.hp, 100.0, "hp untouched by poison so far")
	for i in 30:
		d.tick_effects(Game.DT)
	t.check(absf(d.hp - 95.0) < 0.01, "then hp: %s" % d.hp)


func test_splitter_leaves_children_that_walk_on_and_count_for_the_wave() -> void:
	var g := _game_with(
		{
			"splitter":
			{
				"abilities":
				{
					"split":
					{"count": 2, "creep": "spawnling", "hp_percent": 0.3, "speed": 3.0, "bounty": 2}
				}
			},
			"spawnling": {"speed": 2.0},
		},
		[_base._wave(1, 100, 1.0, 5, "splitter")]
	)
	var splits := [0]
	g.creep_split.connect(func(_p: Creep, kids: Array[Creep]) -> void: splits[0] += kids.size())
	g.start_wave()
	_steps(g, 40)
	var parent: Creep = g.creeps[0]
	var cell := parent.prev_cell
	var at := parent.pos
	parent.hit(1000)
	g.step()
	t.eq(g.gold, 105, "parent bounty paid")
	t.eq(g.creeps.size(), 2, "two children")
	t.eq(splits[0], 2, "split reported with its children")
	for c in g.creeps:
		t.eq(c.kind, "spawnling", "child kind")
		t.eq(c.max_hp, 30.0, "30 % of the parent's hp")
		t.eq(c.speed, 3.0, "speed from the split data")
		t.eq(c.bounty, 2, "own bounty")
		t.eq(c.path, parent.path, "the parent's path")
		t.check(c.prev_cell == cell or c.prev_cell == parent.target_cell(), "from its cell")
		t.check(c.pos.distance_to(at) < 0.5, "where the parent died")
	t.eq(g.phase, Game.Phase.WAVE, "wave goes on while children live")
	for c in g.creeps:
		c.hit(1000)
	g.step()
	t.eq(g.gold, 109, "children pay their own bounty")
	t.eq(g.phase, Game.Phase.WON, "wave over when the children are gone")


func test_split_children_reach_the_goal() -> void:
	var g := _game_with(
		{"splitter": {"abilities": {"split": {"count": 3, "creep": "normal", "hp": 5}}}},
		[_base._wave(1, 100, 1.0, 1, "splitter")]
	)
	g.start_wave()
	_steps(g, 60)
	g.creeps[0].hit(1000)
	g.run_wave()
	t.eq(g.lives, 17, "three children leaked")


func test_immune_ignores_slow_stun_and_knockback() -> void:
	var c := Creep.new(1, 100.0, 2.0, 1, Vector2i(0, 1))
	c.set_path([Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1)])
	c.setup_abilities({"immune": true})
	for i in 12:
		c.advance(Game.DT)
	var at := c.pos
	c.apply_slow(0.5, 2.0)
	c.apply_stun(1.0)
	c.knock_back(0.5)
	t.eq(c.slow, 0.0, "not slowed")
	t.eq(c.stun_time, 0.0, "not stunned")
	t.eq(c.pos, at, "not pushed back")
	t.eq(c.current_speed(), 2.0, "full speed")


func test_immune_list_only_blocks_the_listed_effects() -> void:
	var c := Creep.new(1, 100.0, 2.0, 1, Vector2i(0, 1))
	c.setup_abilities({"immune": ["stun"]})
	c.apply_stun(1.0)
	c.apply_slow(0.5, 2.0)
	t.eq(c.stun_time, 0.0, "not stunned")
	t.eq(c.slow, 0.5, "still slowed")


func test_invisible_creeps_need_a_revealing_tower() -> void:
	var g := _game_with({"ghost": {"abilities": {"invisible": true}}})
	g.tower_defs["seer"] = _base._linear([_base._level(10, 1, {"reveal": true, "range": 1.5})])
	g.build(Vector2i(3, 0))
	var ghost := _creep(g, "ghost", Vector2i(3, 1))
	_steps(g, 3)
	t.eq(ghost.hp, 100.0, "towers cannot see it")
	t.check(not ghost.revealed, "not revealed")
	t.check(g.build(Vector2i(4, 0), "seer") != null, "build a revealing tower")
	g.step()
	t.check(ghost.revealed, "revealed in range of the seer")
	t.eq(ghost.hp, 89.0, "both towers hit it: 10 + 1")
	ghost.pos = Vector2(2.5, 1.5)  # in range of the first tower, not of the seer
	_steps(g, 30)
	t.check(not ghost.revealed, "hidden again out of range")
	t.eq(ghost.hp, 89.0, "no more hits")


func test_summoner_calls_creeps_on_its_timer() -> void:
	var g := _game_with(
		{
			"summoner":
			{
				"abilities":
				{"summon": {"interval": 1.0, "count": 2, "creep": "normal", "hp": 30, "bounty": 2}}
			}
		}
	)
	var boss := _creep(g, "summoner", Vector2i(2, 1), 500.0)
	var summoned: Array[Creep] = []
	g.creep_summoned.connect(
		func(_b: Creep, kids: Array[Creep]) -> void: summoned.append_array(kids)
	)
	_steps(g, 25)
	t.eq(g.creeps.size(), 1, "nothing yet")
	_steps(g, 6)
	t.eq(g.creeps.size(), 3, "two summoned after a second")
	t.eq(summoned.size(), 2, "summon reported")
	for c in summoned:
		t.eq(c.hp, 30.0, "hp from the data")
		t.eq(c.path, boss.path, "walks the boss's path")
		t.check(c.pos.distance_to(boss.pos) < 0.5, "next to the boss")
	_steps(g, 30)
	t.eq(g.creeps.size(), 5, "and again a second later")


func test_enrage_speeds_up_below_half_health() -> void:
	var g := _game_with({"brute": {"abilities": {"enrage": {"below": 0.5, "speed": 1.6}}}})
	var c := _creep(g, "brute", Vector2i(2, 1), 100.0, 2.0)
	var enraged := [0]
	g.boss_enraged.connect(func(_c: Creep) -> void: enraged[0] += 1)
	c.hit(40)
	t.eq(c.current_speed(), 2.0, "normal speed at 60 %")
	c.hit(15)
	t.check(c.enraged, "enraged at 45 %")
	t.check(absf(c.current_speed() - 3.2) < 0.001, "x1.6 speed")
	c.apply_slow(0.5, 1.0)
	t.check(absf(c.current_speed() - 1.6) < 0.001, "slow still works on top")
	g.step()
	c.hit(5)
	g.step()
	t.eq(enraged[0], 1, "reported once")


func test_phases_stop_at_each_threshold_and_make_the_boss_invulnerable() -> void:
	var g := _game_with({"boss2": {"abilities": {"phases": {"at": [0.5, 0.25], "time": 2.0}}}})
	var c := _creep(g, "boss2", Vector2i(2, 1), 100.0)
	var phases: Array[int] = []
	g.boss_phase.connect(func(_c: Creep, n: int) -> void: phases.append(n))
	c.hit(20)
	t.eq(c.hp, 80.0, "normal damage above the first threshold")
	c.hit(500)
	t.eq(c.hp, 50.0, "a big hit stops at 50 %")
	t.eq(c.invulnerable_time, 2.0, "invulnerable for two seconds")
	g.step()
	t.eq(phases, [1] as Array[int], "phase 1 reported")
	t.eq(c.hit(30), 0.0, "no damage while invulnerable")
	c.apply_poison(50, 1.0, 1)
	_steps(g, 20)
	t.eq(c.hp, 50.0, "poison does nothing either")
	_steps(g, 45)
	t.eq(c.invulnerable_time, 0.0, "phase over")
	c.hit(10)
	t.eq(c.hp, 40.0, "takes damage again")
	c.hit(500)
	t.eq(c.hp, 25.0, "second threshold")
	g.step()
	t.eq(phases, [1, 2] as Array[int], "phase 2 reported")
	_steps(g, 61)
	c.hit(500)
	t.check(not c.alive(), "no more phases: dies")


func test_wave_group_overrides_abilities_and_shows_their_tags() -> void:
	var merged := Game.merge_abilities(
		{"heal": {"interval": 2.0, "radius": 1.0}, "immune": true},
		{"heal": {"radius": 3.0}, "immune": false, "invisible": true}
	)
	t.eq(merged, {"heal": {"interval": 2.0, "radius": 3.0}, "invisible": true}, "merged")
	var w: Dictionary = _base._wave(1, 50)
	w["abilities"] = {"invisible": true, "shield": {"amount": 20}}
	var g := _game_with({}, [w])
	g.start_wave()
	g.step()
	var c: Creep = g.creeps[0]
	t.check(c.invisible, "invisible from the group")
	t.eq(c.shield, 20.0, "shield from the group")
	t.eq(g.wave_tags(w), ["Usynlig", "Skjold"] as Array[String], "ability tags")


func test_default_data_uses_abilities_and_bosses() -> void:
	var g := Game.create_default()
	var boss: Dictionary = g.creep_defs.boss.abilities
	t.check(boss.has("summon") and boss.has("enrage") and boss.has("phases"), "final boss")
	var kinds: Array[String] = []
	for w in g.waves:
		for group in Game.wave_groups(w):
			var kind := str(group.creep)
			kinds.append(kind)
			if g.creep_defs[kind].get("boss", false):
				t.eq(g.creep_defs[kind].abilities.immune, ["stun"], "%s is stun immune" % kind)
	for kind: String in ["healer", "shielded", "splitter", "immune", "invisible"]:
		t.check(kind in kinds, "%s appears in a wave" % kind)
	var mid := false
	for group in Game.wave_groups(g.waves[5]):
		mid = mid or g.creep_defs[str(group.creep)].get("boss", false)
	t.check(mid, "wave 6 has a mid boss")
	var arrow: Dictionary = g.tower_defs.arrow.nodes
	t.check(arrow.arrow3.get("reveal", false), "sharpshooter reveals")
	t.check(g.tower_defs.elemental.nodes.lightning.get("reveal", false), "lightning reveals")


func test_split_children_never_split_again() -> void:
	var g := _game_with({"loop": {"abilities": {"split": {"count": 2, "creep": "loop", "hp": 5}}}})
	var c := _creep(g, "loop", Vector2i(3, 1))
	c.hp = 0.0
	g.step()
	t.eq(g.creeps.size(), 2, "two children")
	for child in g.creeps.duplicate():
		child.hp = 0.0
	g.step()
	t.eq(g.creeps.size(), 0, "the children do not split")


func test_children_keep_flying_from_their_own_kind() -> void:
	var g := _game_with(
		{
			"caller":
			{"abilities": {"summon": {"interval": 0.1, "count": 1, "creep": "flying", "hp": 5}}}
		}
	)
	_creep(g, "caller", Vector2i(2, 1))
	_steps(g, 5)
	var flyers := g.creeps.filter(func(c: Creep) -> bool: return c.kind == "flying")
	t.check(not flyers.is_empty(), "summoned a flyer")
	t.check(flyers.all(func(c: Creep) -> bool: return c.flying), "summons of a flying kind fly")


func test_summons_stop_at_max() -> void:
	var g := _game_with(
		{"caller": {"abilities": {"summon": {"interval": 0.1, "count": 2, "max": 4, "hp": 5}}}}
	)
	var caller := _creep(g, "caller", Vector2i(2, 1))
	_steps(g, 60)
	t.eq(caller.summoned, 4, "summoned exactly max")


func test_group_that_removes_an_ability_drops_its_tag() -> void:
	var g := _game_with({"guard": {"tag": "Skjold", "abilities": {"shield": {"amount": 10}}}})
	var w := {"creep": "guard", "count": 1, "hp": 10, "interval": 1, "bounty": 1}
	t.eq(g.wave_tags(w), ["Skjold"] as Array[String], "kind tag")
	w["abilities"] = {"shield": false}
	t.eq(g.wave_tags(w), [] as Array[String], "removed ability, no tag")


func test_phases_are_sorted_and_zero_is_ignored() -> void:
	var g := _game_with({"b": {"abilities": {"phases": {"at": [0.33, 0.0, 0.66], "time": 1.0}}}})
	var c := _creep(g, "b", Vector2i(3, 1))
	t.eq(c.abilities.phases.at, [0.66, 0.33], "highest first, no zero")


func test_chain_skips_invulnerable_creeps() -> void:
	var g := _game_with({})
	g.tower_defs["x"] = {
		"name": "X",
		"root": "root",
		"targets": ["ground"],
		"nodes": {"root": _base._level(10, 20, {"chain": 1, "chain_range": 3.0})},
	}
	g.build(Vector2i(3, 0), "x")
	var a := _creep(g, "normal", Vector2i(3, 1))
	var boss := _creep(g, "normal", Vector2i(4, 1))
	var other := _creep(g, "normal", Vector2i(5, 1))
	boss.invulnerable_time = 5.0
	g.tower_at(Vector2i(3, 0)).targeting = Tower.Targeting.CLOSEST
	g.step()
	t.eq(a.hp, 80.0, "first target hit")
	t.eq(boss.hp, 100.0, "invulnerable creep skipped")
	t.check(other.hp < 100.0, "the hop went to the next creep")
