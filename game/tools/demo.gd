extends Node
## Screenshot scene: the real game with a mixed maze, mid-way through wave 6.
## Usage: scripts/screenshot.sh out.png res://tools/demo.tscn 30 2532x1170


func _ready() -> void:
	var main: Node = load("res://main.tscn").instantiate()
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
	game.start_wave()
	game.simulate(9.0)
	main.speed = 0.0  # freeze mid-wave for the screenshot
	main.selected = Vector2i(9, 4)
