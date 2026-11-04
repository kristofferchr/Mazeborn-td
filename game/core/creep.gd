class_name Creep
extends RefCounted
## A creep walking the maze (or flying straight to the goal). Positions are in
## grid units; the centre of cell (x, y) is (x + 0.5, y + 0.5).
## Abilities come from data/creeps.json (see setup_abilities): a shield that
## takes damage first, immunity to slow/stun/knockback, invisibility, and for
## bosses enrage and invulnerable phases. Healing, splitting and summoning are
## run by Game, which owns the other creeps.

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
var model := ""  # model id for the view ("" = the default of the kind)
var boss := false
var abilities: Dictionary = {}  # ability -> parameters (see setup_abilities)
var shield := 0.0  # absorbs damage (poison too) before hp
var max_shield := 0.0
var immune: Array[String] = []  # effects without effect: "slow", "stun", "knockback"
var invisible := false  # only towers can target it while a revealing tower sees it
var revealed := false  # set each tick by Game
var enraged := false
var phase := 0  # invulnerable phases started so far
var invulnerable_time := 0.0  # seconds left without taking damage
var timers: Dictionary = {}  # ability -> seconds to its next use
var phase_started := false  # set when a phase begins, cleared by Game after its signal
var enrage_started := false  # likewise for enrage


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


## Reads abilities from the data:
##   "shield": {"amount", "percent"}  shield = amount + percent of max hp
##   "immune": true (all) or a list of "slow", "stun", "knockback"
##   "invisible": true
##   "enrage": {"below": 0.5, "speed": 1.6}  faster below a share of max hp
##   "phases": {"at": [0.66, 0.33], "time": 2.0}  invulnerable at each share
##   "heal", "split", "summon": parameters used by Game (timers start here)
func setup_abilities(p_abilities: Dictionary) -> void:
	abilities = p_abilities
	if abilities.has("shield"):
		max_shield = Creep.scaled(abilities.shield, max_hp)
		shield = max_shield
	var imm: Variant = abilities.get("immune", false)
	immune.clear()
	if imm is Array:
		for e: Variant in imm:
			immune.append(str(e))
	elif imm:
		immune.assign(["slow", "stun", "knockback"])
	invisible = bool(abilities.get("invisible", false))
	for a: String in ["heal", "summon"]:
		if abilities.has(a):
			timers[a] = float(abilities[a].get("interval", 3.0))


## "amount" plus "percent" of base, from ability parameters.
static func scaled(params: Dictionary, base: float) -> float:
	return float(params.get("amount", 0.0)) + float(params.get("percent", 0.0)) * base


func is_immune(effect: String) -> bool:
	return effect in immune


## True if towers may pick it as a target.
func targetable() -> bool:
	return not invisible or revealed


## Counts down an ability's timer; true (and restarts it) when it is due.
func ability_ready(ability: String, dt: float) -> bool:
	if not timers.has(ability):
		return false
	timers[ability] -= dt
	if timers[ability] > 0.0:
		return false
	timers[ability] += float(abilities[ability].get("interval", 3.0))
	return true


## Heals up to max hp; returns the hp gained.
func heal(value: float) -> float:
	if not alive():
		return 0.0
	var gained := minf(value, max_hp - hp)
	if gained <= 0.0:
		return 0.0
	hp += gained
	return gained


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
func hit(value: float, pierce := false) -> float:
	return take_damage(maxf(value - (0 if pierce else armor), 1.0))


## Damage after armor: nothing while invulnerable, then the shield, then hp.
## A phase threshold stops the hp there and starts an invulnerable phase, so
## one big hit cannot skip it. Returns the damage taken (shield and hp).
func take_damage(value: float) -> float:
	if value <= 0.0 or invulnerable_time > 0.0 or not alive():
		return 0.0
	var absorbed := minf(shield, value)
	shield -= absorbed
	var rest := value - absorbed
	if rest <= 0.0:
		return absorbed
	var before := hp
	var phases: Dictionary = abilities.get("phases", {})
	var at: Array = phases.get("at", [])
	if phase < at.size() and hp - rest <= float(at[phase]) * max_hp:
		hp = minf(hp, float(at[phase]) * max_hp)
		phase += 1
		invulnerable_time = float(phases.get("time", 2.0))
		phase_started = true
	else:
		hp -= rest
	if abilities.has("enrage") and not enraged and alive():
		if hp < float(abilities.enrage.get("below", 0.5)) * max_hp:
			enraged = true
			enrage_started = true
	return absorbed + before - hp


func apply_slow(amount: float, seconds: float) -> void:
	if is_immune("slow"):
		return
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
	if is_immune("stun"):
		return
	stun_time = maxf(stun_time, seconds)


## Pushes the creep back along its way: towards the cell it came from (never
## past it), or for a flyer straight away from the goal.
func knock_back(distance: float) -> void:
	if is_immune("knockback"):
		return
	if flying:
		var away := pos - Grid.center(target_cell())
		if away.length() > 0.001:
			pos += away.normalized() * distance
		return
	pos = pos.move_toward(Grid.center(prev_cell), distance)


## Ticks stun, slow, poison and invulnerability; returns the poison damage
## dealt (ignores armor, not the shield).
func tick_effects(dt: float) -> float:
	stun_time = maxf(stun_time - dt, 0.0)
	invulnerable_time = maxf(invulnerable_time - dt, 0.0)
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
	return take_damage(damage)


func current_speed() -> float:
	if stun_time > 0.0:
		return 0.0
	var factor := float(abilities.enrage.get("speed", 1.6)) if enraged else 1.0
	return speed * (1.0 - slow) * factor


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
