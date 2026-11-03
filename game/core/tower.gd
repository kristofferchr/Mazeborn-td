class_name Tower
extends RefCounted
## A tower on one grid cell. Its stats come from data/towers.json (one entry
## per kind and level). Hits are instant; splash, slow and poison are effects.

enum Targeting { FIRST, CLOSEST }

var cell: Vector2i
var kind: String
var level := 0  # index into the kind's levels
var invested := 0  # gold spent on building and upgrades
var targeting := Targeting.FIRST
var reload := 0.0  # seconds until the tower may fire again
var target_id := -1
var hits_ground := true
var hits_air := false
var _def: Dictionary


func _init(p_cell: Vector2i, p_kind: String, def: Dictionary) -> void:
	cell = p_cell
	kind = p_kind
	_def = def
	var targets: Array = def.get("targets", ["ground"])
	hits_ground = "ground" in targets
	hits_air = "air" in targets
	invested = int(stats().cost)


## Stats for the current level.
func stats() -> Dictionary:
	return _def.levels[level]


func display_name() -> String:
	return str(_def.get("name", kind))


func max_level() -> int:
	return _def.levels.size() - 1


func can_upgrade() -> bool:
	return level < max_level()


## Gold for the next level, or -1 at max level.
func upgrade_cost() -> int:
	return int(_def.levels[level + 1].cost) if can_upgrade() else -1


func upgrade() -> void:
	if not can_upgrade():
		return
	level += 1
	invested += int(stats().cost)


func attack_range() -> float:
	return float(stats().range)


func cooldown() -> float:
	return float(stats().cooldown)


func can_hit(creep: Creep) -> bool:
	return hits_air if creep.flying else hits_ground


func in_range(creep: Creep) -> bool:
	return Grid.center(cell).distance_to(creep.pos) <= attack_range()


## Picks a target among the living creeps in range it can hit, or null.
func pick_target(creeps: Array[Creep]) -> Creep:
	var best: Creep = null
	var best_score := INF
	for c in creeps:
		if not c.alive() or not can_hit(c) or not in_range(c):
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
