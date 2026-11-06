extends RefCounted
## Tests for view/coach_marks.gd in a guided round: taps on the card are not
## for the map, "Hopp over" keeps "done" in the settings, ordinary rounds have
## no coach.

const ROUND := preload("res://round.tscn")
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


func test_card_taps_stay_off_the_map_and_skip_is_kept() -> void:
	var round := _round(Onboarding.options())
	var coach := _coach(round)
	t.check(coach != null, "coach marks in the guided round")
	if coach == null:
		_free(round)
		return
	coach.settings_path = TEMP
	coach._process(0.1)
	t.check(coach._card.is_visible_in_tree(), "the card shows")
	var centre := coach._card.get_global_rect().get_center()
	t.check(round.hud.is_over_ui(centre), "a tap on the card is not for the map")
	t.eq(coach._title.text, "Bygg et tårn", "first step")
	round.selected = Onboarding.suggest_cell(round.game)
	round._process(0.0)  # the HUD shows the build menu
	coach._process(0.1)
	t.check(coach._body.text.contains("«Bygg»"), "the text follows the preview")
	t.check(coach._ring.has_area(), "rings the build button")
	t.check(not UserSettings.open(TEMP).tutorial_done, "not done yet")
	coach._skip.pressed.emit()
	t.check(not coach.visible, "gone after Hopp over")
	t.check(UserSettings.open(TEMP).tutorial_done, "done is kept")
	round.selected = Round.NO_CELL
	round._process(0.0)
	t.check(not round.hud.is_over_ui(centre), "the map gets taps there again")
	_free(round)


func test_finishing_shows_a_notice() -> void:
	var round := _round(Onboarding.options())
	var coach := _coach(round)
	coach.settings_path = TEMP
	coach.onboarding._go(Onboarding.Step.DONE)
	t.check(round.hud._notice.is_busy(), "a closing notice")
	t.check(UserSettings.open(TEMP).tutorial_done, "done is kept")
	_free(round)
