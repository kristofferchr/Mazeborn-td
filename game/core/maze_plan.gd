class_name MazePlan
extends RefCounted
## A simple serpentine maze (walls of towers across the map with a gap at one
## end), used by the menu backdrop, the balance bot and the screenshot demo.
## Works on any map: rocks are skipped (they are part of the wall for free),
## cells that would cut a spawn off are left open, and each wall puts its gap at
## the end that makes the creeps walk the farthest from all spawns.

const STEP := 3  # columns between walls


static func serpentine(grid: Grid) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var sim := grid.duplicate_grid()
	var i := 0
	for x in range(STEP, grid.size.x - 1, STEP):
		var free: Array[Vector2i] = []
		for y in grid.size.y:
			var cell := Vector2i(x, y)
			if not sim.is_blocked(cell) and not sim.is_spawn(cell) and cell != sim.goal:
				free.append(cell)
		if free.size() < 2:
			continue
		# Gap at the bottom on even walls and at the top on odd ones, unless
		# the other end makes a longer maze.
		var best: Array[Vector2i] = []
		var best_grid: Grid = null
		var best_len := -1
		for gap_bottom: bool in [i % 2 == 0, i % 2 != 0]:
			var trial := sim.duplicate_grid()
			var cells := free.slice(0, free.size() - 1) if gap_bottom else free.slice(1)
			if not gap_bottom:
				cells.reverse()
			var wall: Array[Vector2i] = []
			for cell: Vector2i in cells:
				if trial.build(cell):
					wall.append(cell)
			var length := total_length(trial)
			if length > best_len:
				best = wall
				best_grid = trial
				best_len = length
		out.append_array(best)
		sim = best_grid
		i += 1
	return out


## Sum of the path lengths from every spawn.
static func total_length(grid: Grid) -> int:
	var n := 0
	for i in grid.spawns.size():
		n += grid.path(i).size()
	return n
