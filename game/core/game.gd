class_name Game
extends RefCounted
## One round of Mazeborn TD: maze, economy, waves, creeps and towers.
## Pure 2D logic with a fixed time step and a seeded RNG, so a whole round can
## be simulated deterministically in tests. The 3D view only reads this state
## and listens to the signals.

signal gold_changed(gold: int)
signal lives_changed(lives: int)
signal path_changed
signal tower_built(tower: Tower)
signal tower_sold(tower: Tower, refund: int)
signal tower_fired(tower: Tower, creep: Creep, damage: int)
signal creep_spawned(creep: Creep)
signal creep_killed(creep: Creep)
signal creep_leaked(creep: Creep)
signal wave_started(number: int)
signal wave_cleared(number: int)
signal game_over(won: bool)

enum Phase { BUILD, WAVE, WON, LOST }

const DT := 1.0 / 30.0  # fixed simulation step in seconds
const DEFAULT_CONFIG := "res://data/waves.json"

var grid: Grid
var phase := Phase.BUILD
var gold: int
var lives: int
var wave := 0  # number of the current or last started wave (1-based)
var waves: Array[Dictionary] = []
var tower_stats: Dictionary
var refund_rate: float
var creeps: Array[Creep] = []
var towers: Dictionary = {}  # Vector2i -> Tower
var ticks := 0
var rng := RandomNumberGenerator.new()

var _accumulator := 0.0
var _to_spawn := 0
var _spawn_timer := 0.0
var _next_creep_id := 1


func _init(config: Dictionary, p_grid: Grid, seed_value := 1) -> void:
	grid = p_grid
	rng.seed = seed_value
	gold = int(config.start_gold)
	lives = int(config.lives)
	tower_stats = config.tower
	refund_rate = float(config.tower.refund)
	for w: Dictionary in config.waves:
		waves.append(w)


## Standard map (spawn left, goal right) with the waves from data/waves.json.
static func create_default(seed_value := 1) -> Game:
	return Game.new(load_config(DEFAULT_CONFIG), default_grid(), seed_value)


static func default_grid() -> Grid:
	return Grid.new(Vector2i(18, 12), Vector2i(0, 5), Vector2i(17, 6))


static func load_config(res_path: String) -> Dictionary:
	var json := load(res_path) as JSON
	return json.data


# --- Building -----------------------------------------------------------------


func tower_cost() -> int:
	return int(tower_stats.cost)


func refund_for(tower: Tower) -> int:
	return int(floor(tower.cost * refund_rate))


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


func can_build(cell: Vector2i) -> bool:
	return not is_over() and gold >= tower_cost() and grid.can_build(cell, creep_cells())


func build(cell: Vector2i) -> Tower:
	if not can_build(cell) or not grid.build(cell, creep_cells()):
		return null
	var tower := Tower.new(cell, tower_stats)
	towers[cell] = tower
	_add_gold(-tower.cost)
	_repath()
	tower_built.emit(tower)
	return tower


## Sells the tower on cell for a partial refund. Returns the refund (0 if none).
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


func can_start_wave() -> bool:
	return phase == Phase.BUILD and wave < waves.size()


func start_wave() -> bool:
	if not can_start_wave():
		return false
	wave += 1
	phase = Phase.WAVE
	_to_spawn = int(current_wave().count)
	_spawn_timer = 0.0
	wave_started.emit(wave)
	return true


func current_wave() -> Dictionary:
	return waves[clampi(wave - 1, 0, waves.size() - 1)]


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
	_move_creeps()
	if phase == Phase.LOST:
		return
	_fire_towers()
	_check_wave_end()


func _spawn() -> void:
	if phase != Phase.WAVE or _to_spawn <= 0:
		return
	_spawn_timer -= DT
	if _spawn_timer > 0.0:
		return
	var w := current_wave()
	var creep := Creep.new(_next_creep_id, float(w.hp), float(w.speed), int(w.bounty), grid.spawn)
	_next_creep_id += 1
	creep.set_path(grid.path())
	creeps.append(creep)
	_to_spawn -= 1
	_spawn_timer += float(w.interval)
	creep_spawned.emit(creep)


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
		tower.reload = tower.cooldown
		var damage := rng.randi_range(tower.damage_min, tower.damage_max)
		target.hp -= damage
		tower_fired.emit(tower, target, damage)
		if not target.alive():
			creeps.erase(target)
			_add_gold(target.bounty)
			creep_killed.emit(target)


func _check_wave_end() -> void:
	if phase != Phase.WAVE or _to_spawn > 0 or not creeps.is_empty():
		return
	wave_cleared.emit(wave)
	if wave >= waves.size():
		phase = Phase.WON
		game_over.emit(true)
	else:
		phase = Phase.BUILD


func _repath() -> void:
	for creep in creeps:
		creep.set_path(grid.path_from(creep.target_cell()))
	path_changed.emit()


func _add_gold(amount: int) -> void:
	gold += amount
	gold_changed.emit(gold)
