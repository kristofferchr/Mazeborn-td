class_name Tower
extends RefCounted
## A tower on one grid cell. Its stats come from data/towers.json, where each
## kind is a tree of nodes: the root is what you build, and each node lists the
## upgrades that follow it in "next". Arrow, Earth and Wind are a straight line;
## Elemental branches into four elements with two specialisations each.

enum Targeting { FIRST, CLOSEST }

var cell: Vector2i
var kind: String
var node_id: String  # current node in the kind's upgrade tree
var level := 0  # depth in the tree (0 = as built)
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
	node_id = str(def.root)
	var targets: Array = def.get("targets", ["ground"])
	hits_ground = "ground" in targets
	hits_air = "air" in targets
	invested = int(stats().cost)


## Stats of the current node.
func stats() -> Dictionary:
	return _def.nodes[node_id]


func node(id: String) -> Dictionary:
	return _def.nodes.get(id, {})


func display_name() -> String:
	return str(stats().get("name", _def.get("name", kind)))


## Element of the current node ("fire", "ice", "lightning", "nature" or "").
func element() -> String:
	return str(stats().get("element", ""))


## Ids of the upgrades available from the current node.
func upgrade_options() -> Array[String]:
	var out: Array[String] = []
	for id: Variant in stats().get("next", []):
		out.append(str(id))
	return out


func can_upgrade(option := "") -> bool:
	var options := upgrade_options()
	return not options.is_empty() and (option == "" or option in options)


## Gold for an upgrade (the first option by default), or -1 if not available.
func upgrade_cost(option := "") -> int:
	if not can_upgrade(option):
		return -1
	return int(node(_pick(option)).cost)


func upgrade(option := "") -> void:
	if not can_upgrade(option):
		return
	node_id = _pick(option)
	level += 1
	invested += int(stats().cost)


## Highest level reachable in this kind's tree (0 for a tower without upgrades).
func max_level() -> int:
	return _depth(str(_def.root))


func attack_range() -> float:
	return float(stats().range)


func cooldown() -> float:
	return float(stats().cooldown)


func can_hit(creep: Creep) -> bool:
	return hits_air if creep.flying else hits_ground


## True if the tower lets all towers target invisible creeps in its range.
func reveals() -> bool:
	return bool(stats().get("reveal", false))


func in_range(creep: Creep) -> bool:
	return Grid.center(cell).distance_to(creep.pos) <= attack_range()


## Picks a target among the living creeps in range it can hit, or null.
func pick_target(creeps: Array[Creep]) -> Creep:
	var targets := pick_targets(creeps, 1)
	return targets[0] if not targets.is_empty() else null


## Up to n targets in range, best first by the targeting mode. Invisible
## creeps count only while revealed.
func pick_targets(creeps: Array[Creep], n: int) -> Array[Creep]:
	var scored: Array = []
	for c in creeps:
		if not c.alive() or not can_hit(c) or not c.targetable() or not in_range(c):
			continue
		var score: float
		if targeting == Targeting.FIRST:
			score = c.remaining()
		else:
			score = Grid.center(cell).distance_to(c.pos)
		scored.append([score, c.id, c])
	scored.sort()  # by score, then id: deterministic
	var out: Array[Creep] = []
	for i in mini(n, scored.size()):
		out.append(scored[i][2])
	return out


func _pick(option: String) -> String:
	return option if option != "" else upgrade_options()[0]


func _depth(id: String) -> int:
	var best := 0
	for next: Variant in node(id).get("next", []):
		best = maxi(best, 1 + _depth(str(next)))
	return best
