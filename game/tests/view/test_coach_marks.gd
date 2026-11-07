extends RefCounted
## Tests for view/coach_marks.gd in a guided round: taps go through the card
## except on "Hopp over", which keeps "done" in the settings; ordinary rounds
## have no coach; the guided round leaves the menu choices alone.

const ROUND := preload("res://round.tscn")
const MAIN := preload("res://main.tscn")
const TEMP := "user://test_coach_settings.cfg"

var t: Object  # test runner (check/eq)


func _round(options: Dictionary) -> Round:
	var round := ROUND.instantiate() as Round
	round.map_id = Onboarding.MAP
	round.options = options
	round.progress_path = ""
	(t as SceneTree).root.add_child(round)
	return round


func _coach(round: Round) -> CoachMarks:
	var found := round.hud.find_children("*", "CoachMarks", true, false)
	return found[0] as CoachMarks if found.size() > 0 else null


func _free(round: Round) -> void:
	(t as SceneTree).root.remove_child(round)
	round.free()
	for p: String in [TEMP, TEMP + ".tmp", TEMP + ".bak"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


func test_ordinary_rounds_have_no_coach() -> void:
	var round := _round({})
	t.check(_coach(round) == null, "no coach marks")
	_free(round)


func test_taps_go_through_the_card_and_skip_is_kept() -> void:
	var round := _round(Onboarding.options())
	var coach := _coach(round)
	t.check(coach != null, "coach marks in the guided round")
	if coach == null:
		_free(round)
		return
	coach.settings_path = TEMP
	coach._process(0.1)
	t.check(coach._card.is_visible_in_tree(), "the card shows")
	var skip := coach._skip.get_global_rect().get_center()
	t.check(round.hud.is_over_ui(skip), "a tap on Hopp over is not for the map")
	var body := coach._body.get_global_rect().get_center()
	t.check(not round.hud.is_over_ui(body), "a tap on the text reaches the map")
	t.eq(coach._card.mouse_filter, Control.MOUSE_FILTER_IGNORE, "the card lets taps through")
	t.eq(coach._title.text, "Bygg et tårn", "first step")
	round.selected = Onboarding.suggest_cell(round.game)
	round._process(0.0)  # the HUD shows the build menu
	coach._process(0.1)
	t.check(coach._body.text.contains("«Bygg»"), "the text follows the preview")
	t.check(coach._ring.has_area(), "rings the build button")
	t.eq(coach._card.custom_minimum_size.x, CoachMarks.COMPACT_WIDTH, "small by the panel")
	t.check(not UserSettings.open(TEMP).tutorial_done, "not done yet")
	coach._skip.pressed.emit()
	t.check(not coach.visible, "gone after Hopp over")
	t.check(UserSettings.open(TEMP).tutorial_done, "done is kept")
	round.selected = Round.NO_CELL
	round._process(0.0)
	t.check(not round.hud.is_over_ui(skip), "the map gets taps there again")
	_free(round)


func test_finishing_shows_a_notice() -> void:
	var round := _round(Onboarding.options())
	var coach := _coach(round)
	coach.settings_path = TEMP
	coach.onboarding._go(Onboarding.Step.DONE)
	t.check(round.hud._notice.is_busy(), "a closing notice")
	t.check(UserSettings.open(TEMP).tutorial_done, "done is kept")
	_free(round)


func test_coach_layer_is_under_the_menus() -> void:
	var round := _round(Onboarding.options())
	var coach := _coach(round)
	for menu: Control in [round.hud._end, round.hud._pause_menu, round.hud._settings]:
		t.check(coach.get_index() < menu.get_index(), "under %s" % menu.get_class())
	_free(round)


func test_guided_round_keeps_the_menu_choices() -> void:
	var path := UserSettings.PATH
	var had := FileAccess.file_exists(path)
	var old := FileAccess.get_file_as_bytes(path) if had else PackedByteArray()
	var s := UserSettings.open()
	s.map_id = "klofta"
	s.difficulty = "hard"
	s.mode = Progress.ENDLESS
	s.save()
	var main: Node = MAIN.instantiate()
	(t as SceneTree).root.add_child(main)
	main.call("play", Onboarding.MAP, Onboarding.options())
	var r := UserSettings.open()
	t.eq(
		[r.map_id, r.difficulty, r.mode], ["klofta", "hard", "endless"], "kept by the guided round"
	)
	var round: Round = main.get("current_round")
	var retry: Callable = round.retry_requested.get_connections()[0].callable
	retry.call()  # "Prøv igjen"
	r = UserSettings.open()
	t.eq([r.map_id, r.difficulty, r.mode], ["klofta", "hard", "endless"], "and by Prøv igjen")
	(t as SceneTree).root.remove_child(main)
	main.free()
	if had:
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_buffer(old)
		f.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_countdown_step_promises_no_gold() -> void:
	var round := _round(Onboarding.options())
	var coach := _coach(round)
	coach.settings_path = TEMP
	coach.onboarding._go(Onboarding.Step.COUNTDOWN)
	coach._process(0.1)
	t.eq(coach._title.text, "Nedtelling og «Send nå»", "countdown step")
	t.check(coach._body.text.contains("med en gang"), "says it sends at once")
	t.check(not coach._body.text.contains("gull"), "no bonus gold: %s" % coach._body.text)
	_free(round)
