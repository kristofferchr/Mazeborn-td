class_name Tower
extends RefCounted
## A tower on one grid cell. Hits its target instantly when the cooldown is ready.

enum Targeting { FIRST, CLOSEST }

var cell: Vector2i
var cost: int
var attack_range: float
var damage_min: int
var damage_max: int
var cooldown: float
var targeting := Targeting.FIRST
var reload := 0.0  # seconds until the tower may fire again
var target_id := -1


func _init(p_cell: Vector2i, stats: Dictionary) -> void:
	cell = p_cell
	cost = int(stats.cost)
	attack_range = float(stats.range)
	damage_min = int(stats.damage_min)
	damage_max = int(stats.damage_max)
	cooldown = float(stats.cooldown)


func in_range(creep: Creep) -> bool:
	return Grid.center(cell).distance_to(creep.pos) <= attack_range


## Picks a target among the living creeps in range, or null.
func pick_target(creeps: Array[Creep]) -> Creep:
	var best: Creep = null
	var best_score := INF
	for c in creeps:
		if not c.alive() or not in_range(c):
			continue
		var score: float
		if targeting == Targeting.FIRST:
			score = c.remaining()
		else:
			score = Grid.center(cell).distance_to(c.pos)
		if score < best_score:
			best = c
			best_score = score
	return best
