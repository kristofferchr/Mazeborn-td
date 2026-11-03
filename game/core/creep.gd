class_name Creep
extends RefCounted
## A creep walking the maze. Positions are in grid units; the centre of cell
## (x, y) is (x + 0.5, y + 0.5).

var id: int
var hp: float
var max_hp: float
var speed: float  # cells per second
var bounty: int
var pos: Vector2
var prev_pos: Vector2  # position at the start of the last tick (for interpolation)
var path: Array[Vector2i] = []
var next_index := 0  # index in path of the cell the creep walks towards
var prev_cell: Vector2i  # cell the creep is walking from


func _init(p_id: int, p_hp: float, p_speed: float, p_bounty: int, start: Vector2i) -> void:
	id = p_id
	hp = p_hp
	max_hp = p_hp
	speed = p_speed
	bounty = p_bounty
	pos = Grid.center(start)
	prev_pos = pos
	prev_cell = start


func alive() -> bool:
	return hp > 0.0


func target_cell() -> Vector2i:
	return path[next_index] if next_index < path.size() else prev_cell


## Cells that must stay walkable while the creep is on its way between them.
func occupied_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = [prev_cell]
	if target_cell() != prev_cell:
		cells.append(target_cell())
	return cells


## Distance (in cells) left to the goal along the current path.
func remaining() -> float:
	if next_index >= path.size():
		return 0.0
	return (path.size() - 1 - next_index) + pos.distance_to(Grid.center(path[next_index]))


## Follow a new path that starts at the cell the creep is walking towards.
func set_path(p_path: Array[Vector2i]) -> void:
	path = p_path
	next_index = 0


## Moves the creep; returns true when it reached the end of its path.
func advance(dt: float) -> bool:
	prev_pos = pos
	var step := speed * dt
	while step > 0.0 and next_index < path.size():
		var target := Grid.center(path[next_index])
		var d := pos.distance_to(target)
		if d > step:
			pos = pos.move_toward(target, step)
			return false
		pos = target
		step -= d
		prev_cell = path[next_index]
		next_index += 1
	return next_index >= path.size()
