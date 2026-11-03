class_name Projectile
extends RefCounted
## A shot in flight from a tower to a creep. It homes on its target and hits
## when it arrives; if the target dies or leaks first, it flies on to the last
## known position (a cannon ball still splashes there, other shots fizzle).

var id: int
var kind: String  # tower kind that fired it
var pos: Vector2
var prev_pos: Vector2  # position at the start of the last tick (for interpolation)
var target: Creep
var target_pos: Vector2
var speed: float  # cells per second
var damage: int
var stats: Dictionary  # tower stats at the moment it fired
var hits_ground: bool
var hits_air: bool


func _init(p_id: int, tower: Tower, p_target: Creep, p_damage: int) -> void:
	id = p_id
	kind = tower.kind
	pos = Grid.center(tower.cell)
	prev_pos = pos
	target = p_target
	target_pos = p_target.pos
	stats = tower.stats()
	speed = float(stats.projectile_speed)
	damage = p_damage
	hits_ground = tower.hits_ground
	hits_air = tower.hits_air


## Moves towards the target; returns true when it arrives.
func advance(dt: float, target_alive: bool) -> bool:
	prev_pos = pos
	if target_alive:
		target_pos = target.pos
	var step := speed * dt
	if pos.distance_to(target_pos) <= step:
		pos = target_pos
		return true
	pos = pos.move_toward(target_pos, step)
	return false


func can_hit(creep: Creep) -> bool:
	return hits_air if creep.flying else hits_ground
