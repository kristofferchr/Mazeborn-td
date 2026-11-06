extends Node
## Screenshot scene for the guided first round (CoachMarks). Env COACH picks
## the moment: build (the first step), build_selected (a cell previewed), maze,
## start, tower, tower_selected, countdown or done (the closing notice).
## Usage: COACH=maze scripts/screenshot.sh out.png res://tools/coach.tscn 40 2532x1170


func _ready() -> void:
	var which := OS.get_environment("COACH")
	if which == "":
		which = "build"
	var round := (load("res://round.tscn") as PackedScene).instantiate() as Round
	round.map_id = Onboarding.MAP
	round.options = Onboarding.options()
	round.progress_path = ""
	add_child(round)
	var game := round.game
	game.rng.seed = 1
	var cell := Onboarding.suggest_cell(game)
	var order := ["build", "maze", "start", "tower", "countdown", "done"]
	var upto := order.find(which.trim_suffix("_selected"))
	if which == "build_selected":
		round.selected = cell
	if upto >= 1:
		game.build(cell, "arrow")
	if upto >= 2:
		var wall := Onboarding.suggest_wall(game, cell, 4)
		for c in wall.slice(0, 3):
			game.build(c, "arrow")
	if upto >= 3:
		game.start_wave()
		game.simulate(7.0)
	if which == "tower_selected":
		round.selected = cell
	if upto >= 4:
		game.gold = maxi(game.gold, 40)
		game.upgrade(cell)
		game.run_wave()
		for i in roundi(4.0 / Game.DT):
			game.step()
	round.speed = 0.0  # frozen for the screenshot
	if upto >= 5:
		# After the slow first frames, so the notice is still on screen.
		for i in 20:
			await get_tree().process_frame
		game.start_wave()
