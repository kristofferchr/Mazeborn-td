class_name Game
extends RefCounted
## One round of Mazeborn TD: maze, economy, waves, creeps and towers.
## Pure 2D logic with a fixed time step and a seeded RNG, so a whole round can
## be simulated deterministically in tests. The 3D view only reads this state
## and listens to the signals.
##
## Config: start_gold, lives, wave_bonus, early_bonus and waves (data/waves.json),
## towers (data/towers.json) and creeps (data/creeps.json).

signal gold_changed(gold: int)
signal lives_changed(lives: int)
signal path_changed
signal tower_built(tower: Tower)
signal tower_upgraded(tower: Tower)
signal tower_sold(tower: Tower, refund: int)
signal tower_fired(tower: Tower, creep: Creep, damage: int)
signal projectile_hit(projectile: Projectile, creep: Creep)  # creep is null on a miss
signal gold_bonus(amount: int, reason: String)  # wave bonus, interest, early send
signal creep_spawned(creep: Creep)
signal creep_killed(creep: Creep)
signal creep_leaked(creep: Creep)
signal wave_started(number: int)
signal wave_cleared(number: int)
signal game_over(won: bool)

enum Phase { BUILD, WAVE, WON, LOST }

const DT := 1.0 / 30.0  # fixed simulation step in seconds
const WAVES_FILE := "res://data/waves.json"
const TOWERS_FILE := "res://data/towers.json"
const CREEPS_FILE := "res://data/creeps.json"

var grid: Grid
var phase := Phase.BUILD
var gold: int
var lives: int
var wave := 0  # number of the last started wave (1-based)
var waves: Array[Dictionary] = []
var tower_defs: Dictionary  # kind -> definition with levels
var tower_order: Array[String] = []
var creep_defs: Dictionary  # kind -> definition
var refund_rate: float
var wave_bonus: int
var early_bonus: int
var creeps: Array[Creep] = []
var towers: Dictionary = {}  # Vector2i -> Tower
var projectiles: Array[Projectile] = []
var interest_rate: float  # share of unspent gold paid when a wave is cleared
var interest_max: int
var ticks := 0
var rng := RandomNumberGenerator.new()

var _accumulator := 0.0
var _queue: Array[Dictionary] = []  # groups left to spawn: {group, left}
var _spawn_timer := 0.0
var _next_creep_id := 1
var _next_projectile_id := 1


func _init(config: Dictionary, p_grid: Grid, seed_value := 1) -> void:
	grid = p_grid
	rng.seed = seed_value
	gold = int(config.start_gold)
	lives = int(config.lives)
	wave_bonus = int(config.get("wave_bonus", 0))
	early_bonus = int(config.get("early_bonus", 0))
	interest_rate = float(config.get("interest_rate", 0.0))
	interest_max = int(config.get("interest_max", 0))
	tower_defs = config.towers.towers
	refund_rate = float(config.towers.refund)
	for kind: Variant in config.towers.get("order", tower_defs.keys()):
		tower_order.append(str(kind))
	creep_defs = config.creeps
	for w: Dictionary in config.waves:
		waves.append(w)


## Standard map (spawn left, goal right) with the data in data/.
static func create_default(seed_value := 1) -> Game:
	return Game.new(default_config(), default_grid(), seed_value)


static func default_config() -> Dictionary:
	var config: Dictionary = load_json(WAVES_FILE)
	config.towers = load_json(TOWERS_FILE)
	config.creeps = load_json(CREEPS_FILE)
	return config


static func default_grid() -> Grid:
	return Grid.new(Vector2i(18, 12), Vector2i(0, 5), Vector2i(17, 6))


static func load_json(res_path: String) -> Dictionary:
	var json := load(res_path) as JSON
	return (json.data as Dictionary).duplicate(true)


# --- Building -----------------------------------------------------------------


func build_cost(kind: String) -> int:
	return int(tower_defs[kind].levels[0].cost)


func tower_name(kind: String) -> String:
	return str(tower_defs[kind].get("name", kind))


## Stats of a tower kind at a level (for previews).
func tower_level_stats(kind: String, level := 0) -> Dictionary:
	return tower_defs[kind].levels[level]


func refund_for(tower: Tower) -> int:
	return int(floor(tower.invested * refund_rate))


func tower_at(cell: Vector2i) -> Tower:
	return towers.get(cell)


## Cells the creeps stand on or walk towards; nothing may be built there.
func creep_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for c in creeps:
		for cell in c.occupied_cells():
			if cell not in cells:
				cells.append(cell)
	return cells


func can_afford(kind: String) -> bool:
	return tower_defs.has(kind) and gold >= build_cost(kind)


func can_build(cell: Vector2i, kind := "stone") -> bool:
	return not is_over() and can_afford(kind) and grid.can_build(cell, creep_cells())


func build(cell: Vector2i, kind := "stone") -> Tower:
	if not can_build(cell, kind) or not grid.build(cell, creep_cells()):
		return null
	var tower := Tower.new(cell, kind, tower_defs[kind])
	towers[cell] = tower
	_add_gold(-tower.invested)
	_repath()
	tower_built.emit(tower)
	return tower


func can_upgrade(cell: Vector2i) -> bool:
	var tower := tower_at(cell)
	return tower != null and not is_over() and tower.can_upgrade() and gold >= tower.upgrade_cost()


func upgrade(cell: Vector2i) -> bool:
	if not can_upgrade(cell):
		return false
	var tower := tower_at(cell)
	_add_gold(-tower.upgrade_cost())
	tower.upgrade()
	tower_upgraded.emit(tower)
	return true


## Sells the tower on cell for 75 % of all gold put into it. Returns the refund.
func sell(cell: Vector2i) -> int:
	var tower := tower_at(cell)
	if tower == null or is_over():
		return 0
	towers.erase(cell)
	grid.remove(cell)
	var refund := refund_for(tower)
	_add_gold(refund)
	_repath()
	tower_sold.emit(tower, refund)
	return refund


# --- Waves --------------------------------------------------------------------


## A new wave may start between waves, or early once the current one has spawned.
func can_start_wave() -> bool:
	if is_over() or wave >= waves.size():
		return false
	return phase == Phase.BUILD or _queue.is_empty()


## True while a wave runs and the next can be sent early for early_bonus gold.
func can_send_early() -> bool:
	return phase == Phase.WAVE and can_start_wave()


func start_wave() -> bool:
	if not can_start_wave():
		return false
	if phase == Phase.WAVE and early_bonus > 0:
		_add_gold(early_bonus)
		gold_bonus.emit(early_bonus, "early")
	wave += 1
	phase = Phase.WAVE
	for group: Dictionary in wave_groups(waves[wave - 1]):
		_queue.append({"group": group, "left": int(group.count)})
	if _spawn_timer < 0.0:
		_spawn_timer = 0.0
	wave_started.emit(wave)
	return true


## The wave after the last started one, or {} when there are no more waves.
func next_wave() -> Dictionary:
	return waves[wave] if wave < waves.size() else {}


## Groups of a wave; a wave without "groups" is one group.
static func wave_groups(w: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if w.has("groups"):
		for g: Dictionary in w.groups:
			out.append(g)
	elif not w.is_empty():
		out.append(w)
	return out


func wave_count(w: Dictionary) -> int:
	var n := 0
	for g in wave_groups(w):
		n += int(g.count)
	return n


## Labels for a wave: the tags of its creep kinds ("Rask", "Flygende" ...) and
## its own tags from the data.
func wave_tags(w: Dictionary) -> Array[String]:
	var tags: Array[String] = []
	for g in wave_groups(w):
		var tag := str(_creep_def(str(g.get("creep", "normal"))).get("tag", ""))
		if tag != "" and tag not in tags:
			tags.append(tag)
	for tag: Variant in w.get("tags", []):
		if str(tag) not in tags:
			tags.append(str(tag))
	return tags


func is_over() -> bool:
	return phase == Phase.WON or phase == Phase.LOST


# --- Simulation ---------------------------------------------------------------


## Advances the simulation by dt seconds in fixed steps of DT.
func simulate(dt: float) -> void:
	_accumulator += dt
	while _accumulator >= DT:
		_accumulator -= DT
		step()


## Fraction of a step since the last tick, for smooth interpolation in the view.
func alpha() -> float:
	return _accumulator / DT


## Runs until the current wave is over (or max_seconds). Used by tests.
func run_wave(max_seconds := 600.0) -> void:
	var steps := int(max_seconds / DT)
	while phase == Phase.WAVE and steps > 0:
		step()
		steps -= 1


func step() -> void:
	if is_over():
		return
	ticks += 1
	_spawn()
	_tick_effects()
	_move_creeps()
	if phase == Phase.LOST:
		return
	_move_projectiles()
	_fire_towers()
	_check_wave_end()


func _creep_def(kind: String) -> Dictionary:
	return creep_defs.get(kind, {})


func _spawn() -> void:
	if phase != Phase.WAVE or _queue.is_empty():
		return
	_spawn_timer -= DT
	if _spawn_timer > 0.0:
		return
	var entry: Dictionary = _queue[0]
	var g: Dictionary = entry.group
	var kind := str(g.get("creep", "normal"))
	var def := _creep_def(kind)
	var speed := float(g.get("speed", def.get("speed", 1.7)))
	var creep := Creep.new(_next_creep_id, float(g.hp), speed, int(g.bounty), grid.spawn, kind)
	creep.armor = int(g.get("armor", def.get("armor", 0)))
	creep.flying = bool(def.get("flying", false))
	_next_creep_id += 1
	if creep.flying:
		creep.set_path([grid.goal])
	else:
		creep.set_path(grid.path())
	creeps.append(creep)
	entry.left -= 1
	if entry.left <= 0:
		_queue.remove_at(0)
	_spawn_timer += float(g.interval)
	creep_spawned.emit(creep)


func _tick_effects() -> void:
	for creep in creeps:
		creep.tick_effects(DT)
	_reap()


func _move_creeps() -> void:
	for creep in creeps.duplicate():
		if creep.advance(DT):
			creeps.erase(creep)
			lives = maxi(lives - 1, 0)
			lives_changed.emit(lives)
			creep_leaked.emit(creep)
			if lives == 0:
				phase = Phase.LOST
				game_over.emit(false)
				return


func _fire_towers() -> void:
	for cell: Vector2i in towers:
		var tower: Tower = towers[cell]
		tower.reload = maxf(tower.reload - DT, 0.0)
		if tower.reload > 0.0:
			continue
		var target := tower.pick_target(creeps)
		if target == null:
			tower.target_id = -1
			continue
		tower.target_id = target.id
		tower.reload = tower.cooldown()
		_attack(tower, target)
	_reap()


func _attack(tower: Tower, target: Creep) -> void:
	var s := tower.stats()
	var damage := rng.randi_range(int(s.damage_min), int(s.damage_max))
	tower_fired.emit(tower, target, damage)
	if s.has("projectile_speed"):
		projectiles.append(Projectile.new(_next_projectile_id, tower, target, damage))
		_next_projectile_id += 1
	else:
		_impact(s, damage, target, target.pos, tower.can_hit)


func _move_projectiles() -> void:
	for p in projectiles.duplicate():
		var alive: bool = p.target.alive() and p.target in creeps
		if not p.advance(DT, alive):
			continue
		projectiles.erase(p)
		_impact(p.stats, p.damage, p.target if alive else null, p.pos, p.can_hit)
		projectile_hit.emit(p, p.target if alive else null)
	_reap()


## Damage and effects of a hit on target (may be null: splash only) at `at`.
func _impact(s: Dictionary, damage: int, target: Creep, at: Vector2, can_hit: Callable) -> void:
	if target:
		target.hit(damage)
		if s.has("slow"):
			target.apply_slow(float(s.slow), float(s.slow_time))
		if s.has("poison_dps"):
			target.apply_poison(
				float(s.poison_dps), float(s.poison_time), int(s.get("poison_stacks", 1))
			)
	if s.has("splash_radius"):
		var radius := float(s.splash_radius)
		for other in creeps:
			if other != target and other.alive() and can_hit.call(other):
				if other.pos.distance_to(at) <= radius:
					other.hit(damage * float(s.splash_factor))


## Removes dead creeps and pays their bounty.
func _reap() -> void:
	for creep in creeps.duplicate():
		if not creep.alive():
			creeps.erase(creep)
			_add_gold(creep.bounty)
			creep_killed.emit(creep)


func _check_wave_end() -> void:
	if phase != Phase.WAVE or not _queue.is_empty() or not creeps.is_empty():
		return
	if wave_bonus > 0:
		_add_gold(wave_bonus)
		gold_bonus.emit(wave_bonus, "wave")
	var interest := mini(floori(gold * interest_rate), interest_max)
	if interest > 0:
		_add_gold(interest)
		gold_bonus.emit(interest, "interest")
	wave_cleared.emit(wave)
	if wave >= waves.size():
		phase = Phase.WON
		game_over.emit(true)
	else:
		phase = Phase.BUILD


func _repath() -> void:
	for creep in creeps:
		if not creep.flying:
			creep.set_path(grid.path_from(creep.target_cell()))
	path_changed.emit()


func _add_gold(amount: int) -> void:
	gold += amount
	gold_changed.emit(gold)
