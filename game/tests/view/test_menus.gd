extends RefCounted
## Tests for the menus: the map select's options and result text, and the
## segmented control.

var t: Object  # test runner (check/eq)


func test_map_select_options() -> void:
	var menu := MapSelect.new()
	t.eq(menu.options(), {"difficulty": "normal", "mode": "classic"}, "defaults")
	menu.difficulty = "extreme"
	menu.endless = true
	var mode := "endless" if MapSelect.SHOW_MODE else "classic"  # hidden: always classic
	t.eq(menu.options(), {"difficulty": "extreme", "mode": mode}, "chosen")
	var g := Game.create_map("engen", 1, menu.options())
	t.eq(g.difficulty, "extreme", "the round gets the difficulty")
	t.eq(g.options.mode, mode, "and the mode")
	menu.free()


func test_best_result_text() -> void:
	t.eq(MapSelect.best_text({}), "Ikke spilt ennå", "not played")
	var won := {"won": true, "lives": 14, "wave": 12, "waves": 12}
	t.eq(MapSelect.best_text(won), "Seier · 14 liv", "won")
	var lost := {"won": false, "lives": 0, "wave": 9, "waves": 12}
	t.eq(MapSelect.best_text(lost), "Bølge 9 av 12", "lost")
	var endless := {"won": false, "lives": 0, "wave": 31, "waves": 0, "mode": "endless"}
	t.eq(MapSelect.best_text(endless), "Rekord: bølge 31", "endless")


func test_segmented_control() -> void:
	var labels: Array[String] = ["A", "B", "C"]
	var s := Segmented.make(labels, 1)
	t.eq(s.selected, 1, "starts on B")
	t.check(s.buttons[1].button_pressed and not s.buttons[0].button_pressed, "B is shown")
	var got: Array[int] = []
	s.changed.connect(func(i: int) -> void: got.append(i))
	s._on_pressed(2)
	s._on_pressed(2)
	t.eq(got, [2] as Array[int], "changed once")
	t.check(s.buttons[2].button_pressed and not s.buttons[1].button_pressed, "C is shown")
	s.select(0)
	t.eq(got.size(), 1, "select sends nothing")
	s.free()
