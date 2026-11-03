extends SceneTree
## Bot that builds a serpentine maze and plays the default round. For balancing.
## Usage: scripts/godot.sh --headless --path game -s res://tools/balance.gd


func _initialize() -> void:
	var g := Game.create_default(3)
	while not g.is_over():
		for c in MazePlan.serpentine(g.grid):
			if g.gold < g.tower_cost():
				break
			if g.tower_at(c) == null:
				g.build(c)
		g.start_wave()
		g.run_wave()
		print(
			(
				"wave %d: lives %d gold %d towers %d path %d"
				% [g.wave, g.lives, g.gold, g.towers.size(), g.grid.path().size()]
			)
		)
	print("result: ", Game.Phase.keys()[g.phase])
	quit()
