extends RefCounted
## Tests for view/wave_overview.gd (the list of waves left) and the endless
## toggle of view/map_select.gd.

var t: Object  # test runner (check/eq)


func _overview(g: Game) -> WaveOverview:
	var o := WaveOverview.new()
	o.setup(g)
	return o


func test_classic_lists_every_wave_left() -> void:
	var g := Game.create_default()
	var o := _overview(g)
	t.eq(o.listed_waves().size(), g.waves.size(), "all waves before the first")
	g.wave = 4
	var left := o.listed_waves()
	t.eq(left[0], 5, "starts with the next wave")
	t.eq(left[-1], g.waves.size(), "ends with the last")
	o.refresh()
	var titles: Array[String] = []
	for l: Label in o.find_children("*", "Label", true, false):
		if l.text.begins_with("Bølge "):
			titles.append(l.text)
	t.eq(titles.size(), left.size(), "a card each: %s" % [titles])
	t.eq(titles[0], "Bølge 5", "first card")
	o.free()


func test_endless_lists_waves_ahead() -> void:
	var g := Game.create_default(1, {"mode": "endless"})
	g.wave = 18
	var o := _overview(g)
	var listed := o.listed_waves()
	t.eq(listed.size(), WaveOverview.ENDLESS_AHEAD, "a fixed number ahead")
	t.check(20 in listed, "includes boss wave 20")
	o.free()


func test_map_select_endless_toggle_sets_the_mode() -> void:
	var m := MapSelect.new()
	t.eq(m.options(), {}, "classic by default")
	m.endless = true
	t.eq(m.options(), {"mode": "endless"}, "endless")
	m.free()
