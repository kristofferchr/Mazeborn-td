extends RefCounted
## Tests for view/creep_art.gd: every wave has a model with walk and death animations.

var t: Object  # test runner (check/eq)


func test_every_wave_group_names_a_known_model() -> void:
	var config := Game.default_config()
	for i in config.waves.size():
		for g: Dictionary in config.waves[i].groups:
			var id := str(g.get("model", ""))
			t.check(CreepArt.MODELS.has(id), "wave %d: unknown model '%s'" % [i + 1, id])


func test_children_of_splits_and_summons_name_known_models() -> void:
	var config := Game.default_config()
	for kind: String in config.creeps:
		var abilities: Dictionary = config.creeps[kind].get("abilities", {})
		for a: String in ["split", "summon"]:
			if abilities.has(a) and abilities[a].has("model"):
				var id := str(abilities[a].model)
				t.check(CreepArt.MODELS.has(id), "%s %s: unknown model '%s'" % [kind, a, id])
	for kind: String in config.creeps:
		t.check(CreepArt.KIND_MODELS.has(kind), "%s has a default model" % kind)


func test_model_of_prefers_the_creeps_own_model() -> void:
	var waves: Array[Dictionary] = [{"groups": [{"creep": "normal", "model": "trex"}]}]
	var c := Creep.new(1, 10.0, 1.0, 1, Vector2i.ZERO)
	t.eq(CreepArt.model_of(c, waves, 1), "trex", "from the wave")
	c.model = "slime"
	t.eq(CreepArt.model_of(c, waves, 1), "slime", "its own")


func test_model_for_uses_the_latest_wave_with_the_kind() -> void:
	var waves: Array[Dictionary] = [
		{"groups": [{"creep": "fast", "model": "spider"}]},
		{"groups": [{"creep": "normal", "model": "slime"}, {"creep": "fast", "model": "wasp"}]},
		{"groups": [{"creep": "normal", "model": "trex"}]},
	]
	t.eq(CreepArt.model_for("fast", waves, 1), "spider", "wave 1")
	t.eq(CreepArt.model_for("fast", waves, 2), "wasp", "wave 2")
	t.eq(CreepArt.model_for("fast", waves, 3), "wasp", "fast still spawning in wave 3")
	t.eq(CreepArt.model_for("normal", waves, 3), "trex", "wave 3")
	t.eq(CreepArt.model_for("boss", waves, 3), CreepArt.KIND_MODELS.boss, "kind default")
	t.eq(CreepArt.model_for("normal", waves, 0), CreepArt.KIND_MODELS.normal, "before wave 1")
	for kind: String in CreepArt.KIND_MODELS:
		t.check(CreepArt.MODELS.has(CreepArt.KIND_MODELS[kind]), "default for %s" % kind)


func test_models_have_walk_and_death_animations() -> void:
	for id: String in CreepArt.MODELS:
		var body := CreepArt.instantiate(id)
		var player := CreepArt.player(body)
		t.check(player != null, "%s: no AnimationPlayer" % id)
		if player:
			var m := CreepArt.info(id)
			t.check(CreepArt.find_animation(player, m.walk) != "", "%s: no '%s'" % [id, m.walk])
			t.check(CreepArt.find_animation(player, m.death) != "", "%s: no '%s'" % [id, m.death])
		body.free()


func test_models_fit_their_size() -> void:
	for id: String in CreepArt.MODELS:
		var m := CreepArt.info(id)
		t.check(float(m.size) >= 1.0 and float(m.size) <= 2.0, "%s: size %s" % [id, m.size])
		t.check(CreepArt.top(id) > 0.5, "%s: top %s" % [id, CreepArt.top(id)])
