extends Node
## Screenshot scene: the real game with a mixed maze, mid-way through wave 6.
## Skips the map select and plays the default map, or the map in env DEMO_MAP.
## Usage: [DEMO_MAP=klofta] scripts/screenshot.sh out.png res://tools/demo.tscn 30 2532x1170


func _ready() -> void:
	var main: Node = load("res://round.tscn").instantiate()
	var map_id := OS.get_environment("DEMO_MAP")
	if map_id != "":
		main.map_id = map_id
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
	# Show the build preview on a free cell near the middle.
	var cell := Vector2i(9, 4)
	while cell.x < game.grid.size.x - 1 and not game.grid.can_build(cell):
		cell.x += 1
	main.selected = cell
