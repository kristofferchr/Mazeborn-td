extends Node
## Screenshot scene: the real game with a mixed maze, mid-way through wave 6.
## Usage: scripts/screenshot.sh out.png res://tools/demo.tscn 30 2532x1170


func _ready() -> void:
	var main: Node = load("res://main.tscn").instantiate()
	add_child(main)
	var game: Game = main.game
	game.rng.seed = 1
	game.gold = 400
	var kinds := ["stone", "stone", "cannon", "stone", "frost", "stone", "poison", "air"]
	var plan := MazePlan.serpentine(game.grid)
	for i in plan.size():
		if game.gold >= 60:
			game.build(plan[i], kinds[i % kinds.size()] if i >= 4 else "stone")
	for c: Vector2i in [plan[2], plan[13], plan[14]]:
		game.upgrade(c)
		game.upgrade(c)
	game.gold = 150
	for i in 5:
		game.start_wave()
		game.run_wave()
	game.start_wave()
	game.simulate(9.0)
	main.speed = 0.0  # freeze mid-wave for the screenshot
	main.selected = Vector2i(9, 4)
