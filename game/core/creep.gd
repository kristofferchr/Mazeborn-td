class_name Creep
extends RefCounted
## A creep walking the maze (or flying straight to the goal). Positions are in
## grid units; the centre of cell (x, y) is (x + 0.5, y + 0.5).

var id: int
var kind: String
var hp: float
var max_hp: float
var speed: float  # cells per second, before slow
var armor: int  # flat reduction of each hit (not poison)
var flying: bool
var bounty: int
var pos: Vector2
var prev_pos: Vector2  # position at the start of the last tick (for interpolation)
var path: Array[Vector2i] = []
var next_index := 0  # index in path of the cell the creep walks towards
var prev_cell: Vector2i  # cell the creep is walking from
var slow := 0.0  # current slow (0..1), strongest one wins
var slow_time := 0.0
var poison: Array[Vector2] = []  # stacks of (damage per second, seconds left)
var burn_time := 0.0  # seconds left of a fire effect (poison stacks from fire; for the view)
var stun_time := 0.0  # seconds left stunned (stands still)


func _init(
	p_id: int, p_hp: float, p_speed: float, p_bounty: int, start: Vector2i, p_kind := "normal"
) -> void:
	id = p_id
	kind = p_kind
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
## Flying creeps ignore the maze and occupy nothing.
func occupied_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if flying:
		return cells
	cells.append(prev_cell)
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


## Damage from a hit, reduced by armor unless it pierces (always at least 1).
func hit(amount: float, pierce := false) -> float:
	var dealt := maxf(amount - (0 if pierce else armor), 1.0)
	hp -= dealt
	return dealt


func apply_slow(amount: float, seconds: float) -> void:
	if amount > slow or (is_equal_approx(amount, slow) and seconds > slow_time):
		slow = amount
		slow_time = seconds
	elif is_equal_approx(amount, slow):
		slow_time = maxf(slow_time, seconds)


## Adds a poison stack; at most max_stacks, the oldest is replaced.
func apply_poison(dps: float, seconds: float, max_stacks: int) -> void:
	if poison.size() >= max_stacks:
		poison.remove_at(0)
	poison.append(Vector2(dps, seconds))


func apply_stun(seconds: float) -> void:
	stun_time = maxf(stun_time, seconds)


## Pushes the creep back along its way: towards the cell it came from (never
## past it), or for a flyer straight away from the goal.
func knock_back(distance: float) -> void:
	if flying:
		var away := pos - Grid.center(target_cell())
		if away.length() > 0.001:
			pos += away.normalized() * distance
		return
	pos = pos.move_toward(Grid.center(prev_cell), distance)


## Ticks stun, slow and poison; returns the poison damage dealt (ignores armor).
func tick_effects(dt: float) -> float:
	stun_time = maxf(stun_time - dt, 0.0)
	burn_time = maxf(burn_time - dt, 0.0)
	if slow_time > 0.0:
		slow_time -= dt
		if slow_time <= 0.0:
			slow = 0.0
			slow_time = 0.0
	var damage := 0.0
	for i in range(poison.size() - 1, -1, -1):
		var p := poison[i]
		var t := minf(dt, p.y)
		damage += p.x * t
		p.y -= dt
		if p.y <= 0.0:
			poison.remove_at(i)
		else:
			poison[i] = p
	hp -= damage
	return damage


func current_speed() -> float:
	return 0.0 if stun_time > 0.0 else speed * (1.0 - slow)


## Moves the creep; returns true when it reached the end of its path.
func advance(dt: float) -> bool:
	prev_pos = pos
	var step := current_speed() * dt
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
