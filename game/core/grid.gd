class_name Grid
extends RefCounted
## Build grid and creep path for a mazing tower defense.
## Pure 2D logic (no nodes) so it can be tested headless; the 3D view reads it.

var size: Vector2i
var spawn: Vector2i
var goal: Vector2i
var _astar := AStarGrid2D.new()


func _init(p_size: Vector2i, p_spawn: Vector2i, p_goal: Vector2i) -> void:
	size = p_size
	spawn = p_spawn
	goal = p_goal
	_astar.region = Rect2i(Vector2i.ZERO, size)
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	_astar.update()


func is_blocked(cell: Vector2i) -> bool:
	return _astar.is_in_boundsv(cell) and _astar.is_point_solid(cell)


## World-ish position of a cell's centre in grid units.
static func center(cell: Vector2i) -> Vector2:
	return Vector2(cell) + Vector2(0.5, 0.5)


func in_bounds(cell: Vector2i) -> bool:
	return _astar.is_in_boundsv(cell)


## True if a tower may be built on cell: inside the grid, free, not the spawn
## or goal, and the creeps still have a path afterwards (no full blocking).
## `keep_open` are extra cells (where creeps walk) that must still reach the goal.
func can_build(cell: Vector2i, keep_open: Array[Vector2i] = []) -> bool:
	if not _astar.is_in_boundsv(cell) or is_blocked(cell) or cell == spawn or cell == goal:
		return false
	if cell in keep_open:
		return false
	_astar.set_point_solid(cell, true)
	var ok := not _astar.get_id_path(spawn, goal).is_empty()
	for from in keep_open:
		if not ok:
			break
		ok = not _astar.get_id_path(from, goal).is_empty()
	_astar.set_point_solid(cell, false)
	return ok


func build(cell: Vector2i, keep_open: Array[Vector2i] = []) -> bool:
	if not can_build(cell, keep_open):
		return false
	_astar.set_point_solid(cell, true)
	return true


func remove(cell: Vector2i) -> void:
	if _astar.is_in_boundsv(cell):
		_astar.set_point_solid(cell, false)


## Cells the creeps walk from spawn to goal (inclusive).
func path() -> Array[Vector2i]:
	return _astar.get_id_path(spawn, goal)


## Shortest path from any free cell to the goal (inclusive), or empty.
func path_from(cell: Vector2i) -> Array[Vector2i]:
	if not _astar.is_in_boundsv(cell) or is_blocked(cell):
		return []
	return _astar.get_id_path(cell, goal)
