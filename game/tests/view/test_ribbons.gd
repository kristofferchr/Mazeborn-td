extends RefCounted
## Tests for the path ribbons in view/board_view.gd: a ribbon only merges into
## an earlier one where both walk the same cells to the goal.

var t: Object  # test runner (check/eq)


func _cells(points: Array) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for p: Array in points:
		out.append(Vector2i(p[0], p[1]))
	return out


func test_path_that_joins_stops_at_the_join() -> void:
	var a := _cells([[0, 0], [1, 0], [2, 0], [3, 0]])
	var b := _cells([[0, 2], [1, 2], [1, 1], [1, 0], [2, 0], [3, 0]])
	t.eq(BoardView.ribbon_cuts([a, b]), [4, 4] as Array[int], "second ribbon ends at (1, 0)")


func test_path_that_crosses_and_leaves_is_drawn_in_full() -> void:
	var a := _cells([[0, 0], [1, 0], [2, 0], [3, 0]])
	var b := _cells([[1, 2], [1, 1], [1, 0], [1, -1], [2, -1], [3, -1], [3, 0]])
	t.eq(BoardView.ribbon_cuts([a, b]), [4, 7] as Array[int], "no shared rest: full ribbon")


func test_ribbons_match_the_creep_paths_on_random_mazes() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for n in 60:
		var g := Game.create_map("tvillingportene").grid
		for i in 60:
			g.build(Vector2i(rng.randi_range(0, g.size.x - 1), rng.randi_range(0, g.size.y - 1)))
		var paths: Array = []
		for i in g.spawns.size():
			paths.append(g.path(i))
		var cuts := BoardView.ribbon_cuts(paths)
		for i in paths.size():
			var path: Array[Vector2i] = paths[i]
			# The drawn part plus the rest of the ribbon it joins is the real path.
			var drawn := path.slice(0, cuts[i])
			var walked := drawn.duplicate()
			if cuts[i] < path.size():
				for j in range(i):
					var other: Array[Vector2i] = paths[j]
					var k := other.find(drawn[-1])
					if k >= 0 and other.slice(k) == path.slice(cuts[i] - 1):
						walked.append_array(other.slice(k + 1))
						break
			t.eq(walked, path, "maze %d spawn %d ribbon follows the creeps" % [n, i])
