extends RefCounted
## Tests for the combat effects (CombatFx, FxSprites, FxRibbons, FxArt): every
## shot has a look, the batches have a ceiling, and a busy fight reuses its
## nodes instead of leaking them.

var t: Object  # test runner (check/eq, and the SceneTree)


func test_every_shot_has_a_style() -> void:
	var known := ["arrow", "earth", "wind", "elemental", "fire", "meteor", "ice", "lightning"]
	known.append("nature")
	var config := Game.default_config()
	for kind: String in config.towers.towers:
		for id: String in config.towers.towers[kind].nodes:
			var node: Dictionary = config.towers.towers[kind].nodes[id]
			var style := CombatFx.shot_style(kind, str(node.get("element", "")), node)
			t.check(style in known, "%s/%s: %s" % [kind, id, style])
	var meteor: Dictionary = config.towers.towers.elemental.nodes.meteor
	t.eq(CombatFx.shot_style("elemental", "fire", meteor), "meteor", "meteor")


func test_sprites_stop_at_capacity_and_expire() -> void:
	var s := FxSprites.new()
	s.setup(8, null)
	var added := 0
	for i in 20:
		if s.spawn(Vector3.ZERO, Vector3.UP, 0.5, 0.1, 0.2, Color.WHITE, FxArt.GLOW):
			added += 1
	t.eq(added, 8, "only capacity particles")
	t.eq(s.free_slots(), 0, "full")
	s.step(0.1)
	for i in 5:
		s.draw(Vector3.ZERO, 0.1, Color.WHITE, FxArt.STAR)
	t.eq(s.drawn(), 8, "one-frame sprites dropped when full")
	s.step(0.5)
	t.eq(s.count, 0, "all expired")
	t.check(s.flat(Vector3.ZERO, 1.0, 0.1, 1.0, Color.WHITE, FxArt.RING), "room again")
	s.free()


func test_ribbons_skip_short_lines_and_count_vertices() -> void:
	var r := FxRibbons.new()
	r.setup(null)
	r.begin()
	r.strip(PackedVector3Array([Vector3.ZERO]), 0.1, 0.1, Color.WHITE, Color.WHITE)
	t.eq(r.vertex_count(), 0, "one point draws nothing")
	r.strip(
		PackedVector3Array([Vector3.ZERO, Vector3.ONE, Vector3(2, 0, 0)]),
		0,
		1,
		Color.WHITE,
		Color.WHITE
	)
	r.end()
	t.eq(r.vertex_count(), 12, "two quads")
	r.free()


func test_trim_cuts_a_trail_to_its_length() -> void:
	var trail := PackedVector3Array([Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(2, 0, 0)])
	CombatFx._trim(trail, 1.5)
	t.eq(trail.size(), 3, "points kept")
	t.check(trail[0].is_equal_approx(Vector3(0.5, 0, 0)), "tail moved up: %s" % trail[0])
	CombatFx._trim(trail, 0.5)
	t.eq(trail.size(), 2, "older point dropped")
	t.check(trail[0].is_equal_approx(Vector3(1.5, 0, 0)), "tail at 0.5: %s" % trail[0])


func test_art_is_made_once() -> void:
	var atlas := FxArt.atlas()
	t.check(atlas == FxArt.atlas(), "shared atlas")
	for name: String in ["arrow", "boulder", "meteor", "shard", "blade"]:
		var m := FxArt.mesh(name)
		t.check(m.get_surface_count() == 1, "%s has one surface" % name)
		t.check(m == FxArt.mesh(name), "%s is shared" % name)


## A long fight with every tower kind: projectile models are drawn in one
## batch per model, shots and bolts are bounded by the caps, and nothing is
## left once it is over.
func test_busy_fight_reuses_nodes() -> void:
	var game := Game.create_map(Maps.DEFAULT, 3)
	var board := BoardView.new()
	(t as SceneTree).root.add_child(board)
	board.setup(game)
	var fx := board.combat
	var kinds := ["arrow", "earth", "wind", "elemental"]
	var elements := ["fire", "ice", "lightning", "nature"]
	var k := 0
	for cell in MazePlan.serpentine(game.grid):
		game.gold = 100000
		var kind: String = kinds[k % kinds.size()]
		if game.build(cell, kind) and kind == "elemental":
			game.upgrade(cell, elements[(k / 4) % elements.size()])
			game.upgrade(cell, ["chainlightning", "meteor", "blizzard", "roots"][(k / 4) % 4])
		k += 1
	var children_after_setup := fx.get_child_count()
	var most := Vector2i.ZERO
	var models := 0
	var hits: Array[int] = [0]  # lambdas capture locals by value
	game.projectile_hit.connect(func(_p: Projectile, _c: Creep) -> void: hits[0] += 1)
	for wave in 3:
		game.lives = 999
		game.start_wave()
		for i in 1800:
			if game.phase != Game.Phase.WAVE:
				break
			game.step()
			fx.update(Game.DT)
			most = Vector2i(maxi(most.x, fx.active().x), maxi(most.y, fx.active().y))
			models = maxi(models, fx.models_drawn())
	var shots := hits[0]
	t.check(shots > 100, "a busy fight (%d hits)" % shots)
	t.check(most.y <= CombatFx.MAX_BOLTS, "bolts capped (%d)" % most.y)
	t.check(models > 0, "models drawn")
	var batches := fx.get_child_count() - children_after_setup
	t.check(batches <= CombatFx.MODELS.size(), "one batch per model (%d)" % batches)
	game.projectiles.clear()
	for i in 90:
		fx.update(Game.DT)
	t.eq(fx.active(), Vector2i.ZERO, "no shots or bolts left")
	t.eq(fx.models_drawn(), 0, "no models drawn")
	t.eq(fx.glow.count + fx.dust.count, 0, "particles gone")
	board.free()
