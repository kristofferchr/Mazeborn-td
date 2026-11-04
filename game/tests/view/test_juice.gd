extends RefCounted
## Tests for the view's juice: particle styles, damage numbers, banners and
## the camera shake.

var t: Object  # test runner (check/eq)


func test_every_tower_kind_and_element_has_a_hit_style() -> void:
	var config := Game.default_config()
	for kind: String in config.towers.towers:
		t.check(Effects.STYLES.has(kind), "no hit style for %s" % kind)
		for node: Dictionary in config.towers.towers[kind].nodes.values():
			var element := str(node.get("element", ""))
			var style := Effects.hit_style(kind, element)
			t.check(Effects.STYLES.has(style), "%s/%s: %s" % [kind, element, style])
			if element != "":
				t.eq(style, element, "%s/%s uses its element" % [kind, element])
	for style: String in ["puff", "coins", "dust", "sparkle"]:
		t.check(Effects.STYLES.has(style), "no %s style" % style)


func test_bigger_hits_get_bigger_numbers() -> void:
	var small := HudFx.number_size(8, 100)
	var medium := HudFx.number_size(30, 100)
	var large := HudFx.number_size(60, 100)
	t.check(small < medium and medium < large, "%d < %d < %d" % [small, medium, large])
	t.eq(HudFx.number_size(300, 5000), large, "a huge hit on a boss")
	t.eq(HudFx.number_size(1, 0), large, "no division by zero")


func test_wave_title_lists_the_tags() -> void:
	var none: Array[String] = []
	var tags: Array[String] = ["Flygende"]
	var two: Array[String] = ["Rask", "Boss"]
	t.eq(HudFx.wave_title(3, none), "Bølge 3", "no tags")
	t.eq(HudFx.wave_title(5, tags), "Bølge 5 — Flygende", "one tag")
	t.eq(HudFx.wave_title(10, two), "Bølge 10 — Rask, Boss", "two tags")


func test_shake_fades_and_leaves_pan_and_zoom_alone() -> void:
	var cam := CameraRig.new()
	cam.setup(Rect2(0, 0, 18, 12), 19.0)
	var focus := cam.focus
	var pos := cam.position
	cam.shake(0.6)
	cam.shake(0.2)  # a weaker shake does not cut a stronger one short
	t.eq(cam.trauma, 0.6, "strongest shake wins")
	cam._process(0.05)
	t.check(absf(cam.h_offset) + absf(cam.v_offset) > 0.0, "the camera moves")
	for i in 60:
		cam._process(0.05)
	t.eq(cam.trauma, 0.0, "trauma gone")
	t.eq(cam.h_offset, 0.0, "h_offset reset")
	t.eq(cam.v_offset, 0.0, "v_offset reset")
	t.eq(cam.focus, focus, "focus unchanged")
	t.eq(cam.position, pos, "position unchanged")
	cam.free()
