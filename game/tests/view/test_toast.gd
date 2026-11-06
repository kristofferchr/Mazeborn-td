extends RefCounted
## Tests for view/toast.gd and the record notice in an endless round.

var t: Object  # test runner (check/eq)


func test_toasts_queue_and_show_one_at_a_time() -> void:
	var toast := Toast.new()
	(t as SceneTree).root.add_child(toast)
	t.check(not toast.is_busy(), "idle")
	t.check(toast.show_toast("Rekord!", "Bølge 13"), "shown")
	t.eq(toast.current.title, "Rekord!", "on screen")
	t.check(toast.show_toast("To"), "queued")
	t.eq(toast.queue.size(), 1, "one waiting")
	for i in Toast.MAX_QUEUE:
		toast.show_toast("Flere %d" % i)
	t.eq(toast.queue.size(), Toast.MAX_QUEUE, "the queue is capped")
	toast._next()
	t.eq(toast.current.title, "To", "the next one follows")
	t.eq(toast.mouse_filter, Control.MOUSE_FILTER_IGNORE, "never takes taps")
	toast.queue.clear()
	toast._next()
	t.check(not toast.is_busy(), "done")
	toast.free()


func test_endless_round_toasts_once_when_passing_the_best_wave() -> void:
	var path := "user://test_toast_progress.cfg"
	var p := Progress.new(path)
	p.record("engen", "normal", {"wave": 2, "mode": "endless"})
	p.save()
	var round := (load("res://round.tscn") as PackedScene).instantiate() as Round
	round.map_id = "engen"
	round.options = {"mode": "endless"}
	round.progress_path = path
	(t as SceneTree).root.add_child(round)
	var game := round.game
	var toast := round.hud._toast
	var shown: Array[String] = []
	for number in [1, 2, 3, 4]:
		game.cleared = number
		game.wave_cleared.emit(number)
		if toast.is_busy():
			shown.append(str(toast.current.title))
			toast.queue.clear()
			toast._next()
	t.eq(shown, ["Rekord!"] as Array[String], "one notice, after wave 3")
	(t as SceneTree).root.remove_child(round)
	round.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
