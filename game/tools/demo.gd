extends Node
## Screenshot scene: the real game with a serpentine maze, mid-way through wave 3.
## Usage: scripts/screenshot.sh out.png res://tools/demo.tscn 30 2532x1170


func _ready() -> void:
	var main: Node = load("res://main.tscn").instantiate()
	add_child(main)
	var game: Game = main.game
	game.rng.seed = 1
	game.gold = 400
	for c in MazePlan.serpentine(game.grid):
		if game.gold >= game.tower_cost() + 40:
			game.build(c)
	for i in 2:
		game.start_wave()
		game.run_wave()
	game.start_wave()
	game.simulate(6.0)
	main.speed = 0.0  # freeze mid-wave for the screenshot
	main.selected = Vector2i(9, 4)
