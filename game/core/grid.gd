class_name Grid
extends RefCounted
## Build grid and creep paths for a mazing tower defense.
## Pure 2D logic (no nodes) so it can be tested headless; the 3D view reads it.
## A grid has one or more spawns, one goal and optional rocks: terrain cells
## that are neither walkable nor buildable. Towers may never cut any spawn off
## from the goal.

var size: Vector2i
var spawn: Vector2i  # the first spawn (spawns[0])
var spawns: Array[Vector2i] = []
var goal: Vector2i
var rocks: Dictionary = {}  # Vector2i -> true
var _astar := AStarGrid2D.new()


func _init(p_size: Vector2i, p_spawn: Vector2i, p_goal: Vector2i) -> void:
	size = p_size
	spawn = p_spawn
	spawns.append(p_spawn)
	goal = p_goal
	_astar.region = Rect2i(Vector2i.ZERO, size)
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	_astar.update()


## Grid with several spawns and rocks (cells that block walking and building).
static func create(
	p_size: Vector2i, p_spawns: Array[Vector2i], p_goal: Vector2i, p_rocks: Array[Vector2i] = []
) -> Grid:
	var g := Grid.new(p_size, p_spawns[0], p_goal)
	for i in range(1, p_spawns.size()):
		g.add_spawn(p_spawns[i])
	for cell in p_rocks:
		g.add_rock(cell)
	return g


func add_spawn(cell: Vector2i) -> void:
	if cell not in spawns:
		spawns.append(cell)


## Marks a cell as rock. Spawns, the goal and cells outside are left alone.
func add_rock(cell: Vector2i) -> void:
	if not in_bounds(cell) or cell in spawns or cell == goal:
		return
	rocks[cell] = true
	_astar.set_point_solid(cell, true)


## True for a tower or a rock on the cell.
func is_blocked(cell: Vector2i) -> bool:
	return _astar.is_in_boundsv(cell) and _astar.is_point_solid(cell)


func is_rock(cell: Vector2i) -> bool:
	return rocks.has(cell)


func is_spawn(cell: Vector2i) -> bool:
	return cell in spawns


## World-ish position of a cell's centre in grid units.
static func center(cell: Vector2i) -> Vector2:
	return Vector2(cell) + Vector2(0.5, 0.5)


func in_bounds(cell: Vector2i) -> bool:
	return _astar.is_in_boundsv(cell)


## True if a tower may be built on cell: inside the grid, free (no tower or
## rock), not a spawn or the goal, and every spawn still has a path to the goal
## afterwards (no full blocking). `keep_open` are extra cells (where creeps
## walk) that must still reach the goal.
func can_build(cell: Vector2i, keep_open: Array[Vector2i] = []) -> bool:
	if not _astar.is_in_boundsv(cell) or is_blocked(cell) or cell in spawns or cell == goal:
		return false
	if cell in keep_open:
		return false
	_astar.set_point_solid(cell, true)
	var ok := true
	for from in spawns + keep_open:
		if _astar.get_id_path(from, goal).is_empty():
			ok = false
			break
	_astar.set_point_solid(cell, false)
	return ok


func build(cell: Vector2i, keep_open: Array[Vector2i] = []) -> bool:
	if not can_build(cell, keep_open):
		return false
	_astar.set_point_solid(cell, true)
	return true


## Removes a tower. Rocks stay.
func remove(cell: Vector2i) -> void:
	if _astar.is_in_boundsv(cell) and not is_rock(cell):
		_astar.set_point_solid(cell, false)


## Cells the creeps walk from spawn number `index` to the goal (inclusive).
func path(index := 0) -> Array[Vector2i]:
	return _astar.get_id_path(spawns[index], goal)


## Shortest path from any free cell to the goal (inclusive), or empty.
func path_from(cell: Vector2i) -> Array[Vector2i]:
	if not _astar.is_in_boundsv(cell) or is_blocked(cell):
		return []
	return _astar.get_id_path(cell, goal)


## A copy with the same spawns, goal, rocks and towers (for planning).
func duplicate_grid() -> Grid:
	var g := Grid.create(size, spawns, goal)
	for x in size.x:
		for y in size.y:
			var cell := Vector2i(x, y)
			if is_rock(cell):
				g.add_rock(cell)
			elif is_blocked(cell):
				g._astar.set_point_solid(cell, true)
	return g
