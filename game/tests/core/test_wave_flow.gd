extends RefCounted
## Tests for the wave flow (countdown between waves, sending early for no gold)
## and the endless mode (generated waves, never won).

var t: Object  # test runner (check/eq)
var _base: Object = load("res://tests/core/test_game.gd").new()


## The 7x3 test corridor with a countdown of `seconds` between waves.
func _flow_game(waves: Array, seconds := 10.0, options := {}) -> Game:
	var config: Dictionary = _base._config(waves)
	config.build_time = seconds
	var grid := Grid.new(Vector2i(7, 3), Vector2i(0, 1), Vector2i(6, 1))
	return Game.new(config, grid, 1, options)


func _steps(g: Game, n: int) -> void:
	for i in n:
		g.step()


## Steps through the build phase until the next wave starts (or max steps).
func _wait_for_wave(g: Game, max_steps := 100000) -> int:
	var n := 0
	while g.phase == Game.Phase.BUILD and n < max_steps:
		g.step()
		n += 1
	return n


func _endless_game(seed_value := 1) -> Game:
	return Game.create_map("engen", seed_value, {"mode": "endless"})


func test_first_wave_waits_for_the_player() -> void:
	var g := _flow_game([_base._wave(1, 10), _base._wave(1, 10)])
	_steps(g, roundi(60.0 / Game.DT))
	t.eq(g.phase, Game.Phase.BUILD, "no auto start before the first wave")
	t.eq(g.wave, 0, "still before wave 1")
	t.check(not g.countdown_active(), "no countdown before the first wave")


func test_next_wave_starts_by_itself_after_the_build_time() -> void:
	var g := _flow_game([_base._wave(1, 10), _base._wave(1, 10), _base._wave(1, 10)])
	var started: Array[int] = []
	var countdowns: Array = []
	g.wave_started.connect(func(n: int) -> void: started.append(n))
	g.countdown_started.connect(func(n: int, s: float) -> void: countdowns.append([n, s]))
	g.start_wave()
	g.run_wave()
	t.eq(g.phase, Game.Phase.BUILD, "wave 1 cleared")
	t.check(g.countdown_active(), "countdown runs")
	t.eq(countdowns, [[2, 10.0]], "countdown_started for wave 2")
	t.check(absf(g.countdown() - 10.0) < 0.001, "10 s left, got %f" % g.countdown())
	t.eq(g.countdown_fraction(), 1.0, "full ring")
	var gold := g.gold
	var steps := _wait_for_wave(g)
	t.eq(steps, roundi(10.0 / Game.DT), "starts after exactly 10 s of steps")
	t.eq(g.wave, 2, "wave 2 started by itself")
	t.eq(g.gold, gold, "no early gold when the countdown ran out")
	t.eq(started, [1, 2], "wave_started for both")


func test_countdown_ticks_each_second() -> void:
	var g := _flow_game([_base._wave(1, 10), _base._wave(1, 10)], 4.0)
	var ticks: Array[int] = []
	g.countdown_tick.connect(func(s: int) -> void: ticks.append(s))
	g.start_wave()
	g.run_wave()
	_wait_for_wave(g)
	t.eq(ticks, [3, 2, 1, 0] as Array[int], "a tick per whole second")


func test_sending_during_the_countdown_pays_no_gold() -> void:
	var g := _flow_game([_base._wave(1, 10), _base._wave(1, 10)], 20.0)
	g.start_wave()
	g.run_wave()
	_steps(g, roundi(2.0 / Game.DT))  # 18 s left
	var bonus: Array = []
	g.gold_bonus.connect(func(a: int, r: String) -> void: bonus.append([a, r]))
	var gold := g.gold
	t.check(g.start_wave(), "send now")
	t.eq(g.wave, 2, "wave 2 started")
	t.eq(g.gold, gold, "no gold for sending early")
	t.eq(bonus, [], "no gold_bonus")
	t.check(not g.countdown_active(), "countdown stopped")


func test_sending_while_a_wave_runs_pays_no_gold() -> void:
	var g := _flow_game([_base._wave(1, 1000, 0.5), _base._wave(1, 10)], 20.0)
	g.start_wave()
	g.step()  # the only creep has spawned
	t.check(g.can_send_early(), "may send while the wave runs")
	var gold := g.gold
	g.start_wave()
	t.eq(g.gold, gold, "no gold for sending early")
	t.eq(g.wave, 2, "both waves run")
	g.run_wave()
	t.eq(g.phase, Game.Phase.WON, "clearing both wins")


func test_without_build_time_the_old_flow_is_kept() -> void:
	var g: Game = _base._game([_base._wave(1, 10), _base._wave(1, 10)])
	g.start_wave()
	g.run_wave()
	_steps(g, roundi(60.0 / Game.DT))
	t.eq(g.phase, Game.Phase.BUILD, "waits for the player")


func test_build_time_gets_shorter_and_waves_may_set_their_own() -> void:
	var config := Game.default_config()
	var g := Game.create_default()
	t.eq(g.build_time_for(2), float(config.build_time), "wave 2 has the full build time")
	t.check(g.build_time_for(12) < g.build_time_for(2), "late waves have less time")
	t.check(g.build_time_for(40) >= float(config.build_time_min), "never below the minimum")
	var h := _flow_game([_base._wave(1, 10), {"groups": [_base._wave(1, 10)], "build_time": 3}])
	t.eq(h.build_time_for(2), 3.0, "a wave's own build_time")


func test_countdown_flow_is_deterministic() -> void:
	t.eq(_flow_summary(5), _flow_summary(5), "same seed gives the same round")


func _flow_summary(seed_value: int) -> Array:
	var config: Dictionary = _base._config(
		[_base._wave(8, 30, 1.5, 3), _base._wave(8, 40, 1.5, 3), _base._wave(8, 50, 1.5, 3)], 40
	)
	config.build_time = 7.0
	var grid := Grid.new(Vector2i(7, 3), Vector2i(0, 1), Vector2i(6, 1))
	var g := Game.new(config, grid, seed_value)
	g.tower_base_stats("stone").damage_min = 3
	g.tower_base_stats("stone").damage_max = 12
	g.build(Vector2i(2, 0))
	g.build(Vector2i(4, 2))
	g.start_wave()
	var log: Array = []
	var on_start := func(n: int) -> void: log.append([n, g.ticks, g.gold])
	g.wave_started.connect(on_start)
	for i in roundi(120.0 / Game.DT):
		g.simulate(Game.DT * 1.3)  # uneven frames: still whole steps
	g.wave_started.disconnect(on_start)  # the lambda holds the game
	t.check(log.size() >= 2, "later waves started by themselves: %s" % [log])
	return [log, g.gold, g.lives, g.phase, g.ticks]


# --- Endless ------------------------------------------------------------------


func test_options_default_to_classic_and_keep_unknown_keys() -> void:
	var g := Game.create_map("engen", 1, {"difficulty": "hard"})
	t.check(not g.endless, "classic by default")
	t.eq(g.options.get("difficulty"), "hard", "unknown option kept")
	t.check(not Game.create_map("engen").endless, "no options")
	t.check(not Game.create_map("engen", 1, {"mode": 3}).endless, "odd values are classic")
	t.check(Game.create_map("engen", 1, {"mode": "endless"}).endless, "endless")


func test_endless_waves_follow_the_scripted_ones() -> void:
	var g := _endless_game()
	var n := g.waves.size()
	t.eq(g.wave_data(n), g.waves[n - 1], "scripted waves first")
	t.check(g.has_wave(n + 1), "a wave after the last scripted one")
	t.check(g.has_wave(n + 200), "and forever")
	t.check(not g.is_final_wave(n), "no final wave")
	t.check(not Game.create_default().has_wave(n + 1), "classic ends")
	for i in range(n + 1, n + 30):
		var w := g.wave_data(i)
		t.check(g.wave_count(w) > 0, "wave %d has creeps" % i)
		for grp in Game.wave_groups(w):
			t.check(g.creep_defs.has(str(grp.creep)), "known kind %s" % grp.creep)
			t.check(int(grp.bounty) >= 1, "bounty")
			t.check(float(grp.interval) > 0.0, "interval")


func test_endless_generation_is_deterministic_per_seed() -> void:
	var a := _endless_game(7)
	var b := _endless_game(7)
	var c := _endless_game(8)
	var n := a.waves.size()
	var differs := false
	for i in range(n + 1, n + 25):
		t.eq(a.wave_data(i), b.wave_data(i), "same seed, same wave %d" % i)
		differs = differs or a.wave_data(i) != c.wave_data(i)
	t.check(differs, "another seed gives other waves")
	# Asking for a far wave first gives the same as walking there.
	var d := _endless_game(7)
	t.eq(d.wave_data(n + 24), a.wave_data(n + 24), "independent of the order")
	var state := a.rng.state
	a.wave_data(n + 99)
	t.eq(a.rng.state, state, "the round's rng is untouched")


func test_endless_hp_grows_and_bounty_grows_slower() -> void:
	var g := _endless_game()
	var n := g.waves.size()
	var first := _normal_group(g, n + 1)
	var later := _normal_group(g, n + 1 + g.endless_config.kinds.size())  # same main kind
	t.eq(first.creep, later.creep, "the kinds cycle")
	var hp_ratio := float(later.hp) / float(first.hp)
	var bounty_ratio := float(later.bounty) / float(first.bounty)
	t.check(hp_ratio > 2.0, "hp grows, got ×%.2f" % hp_ratio)
	t.check(bounty_ratio < hp_ratio, "bounty grows slower (×%.2f)" % bounty_ratio)
	t.check(bounty_ratio > 1.0, "bounty grows")


func _normal_group(g: Game, number: int) -> Dictionary:
	return Game.wave_groups(g.wave_data(number))[0]


func test_endless_has_a_boss_every_fifth_wave() -> void:
	var g := _endless_game(3)
	var n := g.waves.size()
	for i in range(n + 1, n + 40):
		var tags := g.wave_tags(g.wave_data(i))
		t.eq("Boss" in tags, i % 5 == 0, "wave %d boss: %s" % [i, tags])
	var kinds: Array[String] = []
	for i in [15, 20]:
		for grp in Game.wave_groups(g.wave_data(i)):
			if g.creep_defs[str(grp.creep)].get("boss", false):
				kinds.append(str(grp.creep))
	t.eq(kinds.size(), 2, "one boss per boss wave")
	t.check(kinds[0] != kinds[1], "boss kinds alternate: %s" % [kinds])


func test_endless_round_is_never_won() -> void:
	var config: Dictionary = _base._config([_base._wave(2, 10)])
	config.endless = {"hp": 10, "count": [2, 3], "kinds": ["normal", "armored"]}
	var grid := Grid.new(Vector2i(7, 3), Vector2i(0, 1), Vector2i(6, 1))
	var g := Game.new(config, grid, 1, {"mode": "endless"})
	g.tower_base_stats("stone").damage_min = 100000
	g.tower_base_stats("stone").damage_max = 100000
	g.tower_base_stats("stone").range = 9.0
	g.build(Vector2i(3, 0))
	var over := [false]
	g.game_over.connect(func(_won: bool) -> void: over[0] = true)
	for i in 30:
		t.check(g.start_wave(), "wave %d starts" % (i + 1))
		g.run_wave()
		t.eq(g.phase, Game.Phase.BUILD, "wave %d cleared, not won" % (i + 1))
	t.check(not over[0], "no game over")
	t.eq(g.score(), 30, "score is the wave reached")


func test_endless_round_ends_when_lives_run_out() -> void:
	var g := _endless_game()
	g.lives = 3
	while g.phase != Game.Phase.LOST and g.wave < 40:
		g.start_wave()
		g.run_wave()
	t.eq(g.phase, Game.Phase.LOST, "lost without towers")
	t.eq(g.score(), 0, "no wave cleared")


func test_score_counts_cleared_waves_not_waves_sent_early() -> void:
	var config: Dictionary = _base._config([_base._wave(2, 10)])
	config.endless = {"hp": 10, "count": [2, 2], "kinds": ["normal"], "boss_every": 0}
	var grid := Grid.new(Vector2i(7, 3), Vector2i(0, 1), Vector2i(6, 1))
	var g := Game.new(config, grid, 1, {"mode": "endless"})
	g.tower_base_stats("stone").damage_min = 100000
	g.tower_base_stats("stone").damage_max = 100000
	g.tower_base_stats("stone").range = 9.0
	g.build(Vector2i(3, 0))
	for i in 3:
		g.start_wave()
		g.run_wave()
	t.eq(g.score(), 3, "three waves cleared")
	g.sell(Vector2i(3, 0))
	g.lives = 3
	g.start_wave()
	while g.phase == Game.Phase.WAVE:
		g.step()
		g.start_wave()  # keep sending early while losing
	t.eq(g.phase, Game.Phase.LOST, "lost")
	t.check(g.wave > 4, "several waves sent early (wave %d)" % g.wave)
	t.eq(g.score(), 3, "the score stays at the last cleared wave")


func test_far_endless_waves_stay_positive_and_capped() -> void:
	var g := _endless_game()
	var last := 0.0
	for n: int in [100, 330, 400, 1000, 5000]:
		for grp in Game.wave_groups(g.wave_data(n)):
			t.check(int(grp.hp) > 0, "wave %d hp %d" % [n, grp.hp])
			t.check(int(grp.hp) <= int(Game.ENDLESS_HP_CAP), "wave %d hp capped" % n)
			t.check(int(grp.bounty) > 0, "wave %d bounty %d" % [n, grp.bounty])
		var hp := float(Game.wave_groups(g.wave_data(n))[0].hp)
		t.check(hp >= last, "hp never falls (wave %d)" % n)
		last = hp


func test_endless_boss_summons_grow_with_the_wave() -> void:
	var g := _endless_game()
	var hp: Array[int] = []
	for n: int in [20, 30]:  # the big boss (it summons)
		for grp in Game.wave_groups(g.wave_data(n)):
			if str(grp.creep) == "boss":
				hp.append(int(grp.abilities.summon.hp))
	t.eq(hp.size(), 2, "both boss waves summon")
	t.check(hp[1] > hp[0], "summons are tougher later: %s" % [hp])
	t.check(hp[0] > 140, "more than the scripted boss summons: %s" % [hp])
	var boss := g.new_creep("boss", 1000.0, 1, Game.wave_groups(g.wave_data(20))[1], Vector2i(0, 1))
	t.eq(int(boss.abilities.summon.hp), hp[0], "the creep gets the override")
	t.eq(int(boss.abilities.summon.count), 2, "other summon parameters kept")
