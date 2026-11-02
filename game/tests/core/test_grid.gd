extends RefCounted
## Tests for core/grid.gd (mazing rules).

var t: Object  # test runner (check/eq)


func _grid() -> Grid:
	return Grid.new(Vector2i(5, 3), Vector2i(0, 1), Vector2i(4, 1))


func test_open_grid_has_straight_path() -> void:
	var g := _grid()
	t.eq(g.path().size(), 5, "path length")
	t.eq(g.path()[0], Vector2i(0, 1), "path starts at spawn")
	t.eq(g.path()[-1], Vector2i(4, 1), "path ends at goal")


func test_tower_makes_creeps_walk_around() -> void:
	var g := _grid()
	t.check(g.build(Vector2i(2, 1)), "build in the middle")
	t.check(Vector2i(2, 1) not in g.path(), "path avoids tower")
	t.eq(g.path().size(), 7, "detour length")


func test_cannot_fully_block_path() -> void:
	var g := _grid()
	t.check(g.build(Vector2i(2, 0)), "build top")
	t.check(g.build(Vector2i(2, 1)), "build middle")
	t.check(not g.can_build(Vector2i(2, 2)), "last gap must stay open")
	t.check(not g.build(Vector2i(2, 2)), "build rejected")
	t.check(not g.path().is_empty(), "path still exists")


func test_cannot_build_on_spawn_goal_occupied_or_outside() -> void:
	var g := _grid()
	t.check(not g.can_build(Vector2i(0, 1)), "spawn")
	t.check(not g.can_build(Vector2i(4, 1)), "goal")
	t.check(not g.can_build(Vector2i(9, 9)), "outside")
	g.build(Vector2i(1, 0))
	t.check(not g.can_build(Vector2i(1, 0)), "occupied")


func test_remove_reopens_cell() -> void:
	var g := _grid()
	g.build(Vector2i(2, 1))
	g.remove(Vector2i(2, 1))
	t.eq(g.path().size(), 5, "straight again")
