extends RefCounted
## Tests for core/onboarding.gd: the guided first round's steps, skipping and
## when it is offered.

const S := Onboarding.Step

var t: Object  # test runner (check/eq)


func _start() -> Array:
	var game := Game.create_map(Onboarding.MAP, 1, Onboarding.options())
	var ob := Onboarding.new()
	ob.attach(game)
	return [game, ob]


## Builds the suggested wall next to the first tower until the maze step ends.
func _build_wall(game: Game, ob: Onboarding) -> void:
	for i in 6:
		if ob.step != S.MAZE:
			return
		var wall := Onboarding.suggest_wall(game, ob.first_tower, 1)
		if wall.is_empty() or game.build(wall[0], "arrow") == null:
			return


func test_steps_follow_the_players_actions_in_order() -> void:
	var r := _start()
	var game: Game = r[0]
	var ob: Onboarding = r[1]
	var seen: Array[int] = []
	var done: Array[bool] = []
	ob.step_changed.connect(func(s: int) -> void: seen.append(s))
	ob.finished.connect(func(skipped: bool) -> void: done.append(skipped))
	t.eq(ob.step, S.BUILD, "starts with building")
	game.upgrade(Vector2i(1, 1))  # nothing there: no step
	t.eq(ob.step, S.BUILD, "still building")
	var cell := Onboarding.suggest_cell(game)
	t.check(cell != Onboarding.NO_CELL and cell in game.grid.path(0), "suggests a path cell")
	t.check(game.build(cell, "arrow") != null, "built")
	t.eq(ob.step, S.MAZE, "then the maze")
	t.eq(ob.first_tower, cell, "remembers the first tower")
	var before := ob.path_length
	_build_wall(game, ob)
	t.eq(ob.step, S.START, "a wall made the path longer")
	t.check(ob.path_length >= before + Onboarding.MAZE_GAIN, "longer by %d" % ob.gain())
	t.check(game.start_wave(), "wave started")
	t.eq(ob.step, S.TOWER, "then upgrade or sell")
	game.gold = 500
	t.check(game.upgrade(cell), "upgraded")
	t.eq(ob.step, S.COUNTDOWN, "then the countdown")
	t.check(done.is_empty(), "not finished yet")
	game.run_wave()
	t.check(game.countdown_active(), "counting down to wave 2")
	t.check(game.start_wave(), "Send nå")
	t.eq(ob.step, S.DONE, "done")
	t.eq(done, [false] as Array[bool], "finished, not skipped")
	t.eq(seen, [S.MAZE, S.START, S.TOWER, S.COUNTDOWN, S.DONE] as Array[int], "every step once")


func test_skip_ends_it_at_once() -> void:
	var r := _start()
	var game: Game = r[0]
	var ob: Onboarding = r[1]
	var done: Array[bool] = []
	ob.finished.connect(func(skipped: bool) -> void: done.append(skipped))
	ob.skip()
	t.eq(ob.step, S.DONE, "done")
	t.check(not ob.is_active(), "inactive")
	ob.skip()
	game.build(Onboarding.suggest_cell(game), "arrow")
	t.eq(ob.step, S.DONE, "stays done")
	t.eq(done, [true] as Array[bool], "finished once, skipped")


func test_steps_already_done_are_passed_over() -> void:
	var r := _start()
	var game: Game = r[0]
	var ob: Onboarding = r[1]
	var cell := Onboarding.suggest_cell(game)
	game.build(cell, "arrow")
	game.gold = 500
	game.upgrade(cell)  # upgrading during the maze step
	game.start_wave()  # and starting the wave early
	t.eq(ob.step, S.MAZE, "the maze step still waits")
	_build_wall(game, ob)
	t.eq(ob.step, S.COUNTDOWN, "start and tower were done already")


func test_maze_step_ends_after_enough_towers_even_without_a_longer_path() -> void:
	var r := _start()
	var game: Game = r[0]
	var ob: Onboarding = r[1]
	game.gold = 500
	game.build(Vector2i(2, 0), "arrow")  # far from the path
	t.eq(ob.step, S.MAZE, "maze")
	for x in range(4, 4 + Onboarding.MAZE_TOWERS):
		game.build(Vector2i(x, 0), "arrow")
	t.eq(ob.gain(), 0, "the path did not change")
	t.eq(ob.step, S.START, "not stuck")


func test_suggested_wall_crosses_the_path_and_leaves_a_way() -> void:
	var game := Game.create_map(Onboarding.MAP, 1)
	var cell := Onboarding.suggest_cell(game)
	game.build(cell, "arrow")
	var wall := Onboarding.suggest_wall(game, cell, 4)
	t.eq(wall.size(), 4, "four cells")
	var length := game.grid.path(0).size()
	game.gold = 500
	for c in wall:
		t.eq(c.x, cell.x, "same column")
		t.check(game.build(c, "arrow") != null, "buildable %s" % c)
	t.check(game.grid.path(0).size() >= length + Onboarding.MAZE_GAIN, "a longer path")
	t.eq(Onboarding.suggest_wall(game, Onboarding.NO_CELL).size(), 0, "no tower, no wall")


func test_offered_only_to_new_players() -> void:
	var empty := Progress.new("user://test_onboarding_progress.cfg")
	t.check(Onboarding.should_offer(false, empty), "a new player")
	t.check(not Onboarding.should_offer(true, empty), "already played or skipped")
	var played := Progress.new("user://test_onboarding_progress.cfg")
	played.record("klofta", "normal", {"won": true, "lives": 20, "wave": 12, "waves": 12})
	t.check(not Onboarding.should_offer(false, played), "has played before")
	t.check(Onboarding.is_tutorial(Onboarding.options()), "the guided round's options")
	t.check(not Onboarding.is_tutorial({"difficulty": "hard"}), "an ordinary round")
	var g := Game.create_map(Onboarding.MAP, 1, Onboarding.options())
	t.check(Onboarding.is_tutorial(g.options), "the game keeps the key")
	t.eq(Progress.mode_of(g.options), Progress.CLASSIC, "a classic round")
