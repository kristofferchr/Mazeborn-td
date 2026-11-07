extends Node
## Screenshot scene: the real game with a mixed maze, mid-way through wave 6.
## Skips the map select and plays the default map, or the map in env DEMO_MAP.
## Env DEMO_STATE picks another moment: "countdown" (between waves 5 and 6,
## the start button counting down), "overview" (the same with the wave
## overview open) or "endless" (endless mode, mid-way through boss wave 20).
## Env REPLAY=<file> instead shows a recorded round (core/replay.gd) at tick
## REPLAY_TICK (default: its end; a path may be relative to the directory the
## command runs in, or user://replays/last.replay.json).
## Usage: [DEMO_MAP=klofta] [DEMO_STATE=overview] \
##   scripts/screenshot.sh out.png res://tools/demo.tscn 30 2532x1170
##   REPLAY=game/tests/replays/klofta-normal-classic.replay.json REPLAY_TICK=4000 \
##   scripts/screenshot.sh out.png res://tools/demo.tscn 30 2532x1170

const ROUND := preload("res://round.tscn")


func _ready() -> void:
	if OS.get_environment("REPLAY") != "":
		_show_replay(OS.get_environment("REPLAY"), OS.get_environment("REPLAY_TICK"))
		return
	var state := OS.get_environment("DEMO_STATE")
	var main: Node = ROUND.instantiate()
	main.replay_dir = ""  # the moves below are made up: no replay
	var map_id := OS.get_environment("DEMO_MAP")
	if map_id != "":
		main.map_id = map_id
	if state == "endless":
		main.options = {"mode": "endless"}
	add_child(main)
	var game: Game = main.game
	game.rng.seed = 1
	game.gold = 400
	var kinds := ["arrow", "arrow", "earth", "arrow", "elemental", "arrow", "wind", "elemental"]
	var plan := MazePlan.serpentine(game.grid)
	for i in plan.size():
		if game.gold >= 60:
			game.build(plan[i], kinds[i % kinds.size()] if i >= 4 else "arrow")
	# A mix of levels and elements, so every look shows up.
	var elements := ["fire", "ice", "lightning", "nature"]
	var k := 0
	for cell: Vector2i in game.towers.keys():
		var tower: Tower = game.towers[cell]
		game.gold = 1000
		if tower.kind == "elemental":
			game.upgrade(cell, elements[k % elements.size()])
			if k % 2 == 0:
				game.upgrade(cell)
		elif k % 3 == 1:
			game.upgrade(cell)
		elif k % 5 == 2:
			game.upgrade(cell)
			game.upgrade(cell)
		k += 1
	game.gold = 150
	for i in 5:
		game.start_wave()
		game.run_wave()
	main.speed = 0.0  # frozen for the screenshot
	if state == "countdown" or state == "overview":
		for i in roundi(3.0 / Game.DT):  # a few seconds into the countdown
			game.step()
		if state == "overview":
			main.hud.toggle_overview()
		return
	if state == "endless":
		game.wave = 19  # skip ahead: the next wave is the boss of wave 20
		game.lives = 14
	game.start_wave()
	if state == "endless":
		game.simulate(8.0)  # the boss walks in behind its escort
		return
	game.simulate(9.0)
	# Show the build preview on a free cell near the middle.
	var cell := Vector2i(9, 4)
	while cell.x < game.grid.size.x - 1 and not game.grid.can_build(cell):
		cell.x += 1
	main.selected = cell


## The round of a replay, played up to a tick (or its end) and frozen there.
func _show_replay(path: String, tick_text: String) -> void:
	if not path.begins_with("res://") and not path.begins_with("user://"):
		if not path.is_absolute_path():
			path = OS.get_environment("PWD").path_join(path)
	var replay := Replay.load_file(path)
	if replay == null:
		push_error("not a replay: %s" % path)
		return
	var round := ROUND.instantiate() as Round
	round.map_id = replay.map_id
	round.options = replay.options
	round.seed_value = replay.seed_value
	round.progress_path = ""
	round.replay_dir = ""
	add_child(round)
	var tick := int(tick_text) if tick_text.is_valid_int() else -1
	if not replay.play(round.game, tick):
		push_warning("replay: rejected actions %s" % [replay.rejected])
	round.speed = 0.0  # frozen for the screenshot
	print("replay at tick %d: %s" % [round.game.ticks, Replay.state_of(round.game)])
