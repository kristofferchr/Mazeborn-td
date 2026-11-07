extends RefCounted
## Tests for view/notice.gd and the record notice in an endless round.

var t: Object  # test runner (check/eq)


func test_notices_queue_and_show_one_at_a_time() -> void:
	var notice := Notice.new()
	(t as SceneTree).root.add_child(notice)
	t.check(not notice.is_busy(), "idle")
	t.check(notice.show_notice("Rekord!", "Bølge 13"), "shown")
	t.eq(notice.current.title, "Rekord!", "on screen")
	t.check(notice.show_notice("To"), "queued")
	t.eq(notice.queue.size(), 1, "one waiting")
	for i in Notice.MAX_QUEUE:
		notice.show_notice("Flere %d" % i)
	t.eq(notice.queue.size(), Notice.MAX_QUEUE, "the queue is capped")
	notice._next()
	t.eq(notice.current.title, "To", "the next one follows")
	t.eq(notice.mouse_filter, Control.MOUSE_FILTER_IGNORE, "never takes taps")
	notice.queue.clear()
	notice._next()
	t.check(not notice.is_busy(), "done")
	notice.free()


func test_endless_round_notices_once_when_passing_the_best_wave() -> void:
	var path := "user://test_notice_progress.cfg"
	var p := Progress.new(path)
	p.record("engen", "normal", {"wave": 2, "mode": "endless"})
	p.save()
	var round := (load("res://round.tscn") as PackedScene).instantiate() as Round
	round.map_id = "engen"
	round.options = {"mode": "endless"}
	round.progress_path = path
	(t as SceneTree).root.add_child(round)
	var game := round.game
	var notice := round.hud._notice
	var shown: Array[String] = []
	for number in [1, 2, 3, 4]:
		game.cleared = number
		game.wave_cleared.emit(number)
		if notice.is_busy():
			shown.append(str(notice.current.title))
			notice.queue.clear()
			notice._next()
	t.eq(shown, ["Rekord!"] as Array[String], "one notice, after wave 3")
	(t as SceneTree).root.remove_child(round)
	round.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
