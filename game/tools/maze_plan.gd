class_name MazePlan
extends RefCounted
## A simple serpentine maze (walls of towers with alternating gaps), used by the
## balance bot and the screenshot demo.


static func serpentine(grid: Grid) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var i := 0
	for x in range(3, grid.size.x - 1, 3):
		var ys: Array = range(0, grid.size.y - 1) if i % 2 == 0 else range(grid.size.y - 1, 0, -1)
		for y: int in ys:
			out.append(Vector2i(x, y))
		i += 1
	return out
