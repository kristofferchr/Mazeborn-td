class_name Game
extends RefCounted
## One round of Mazeborn TD: maze, economy, waves, creeps and towers.
## Pure 2D logic with a fixed time step and a seeded RNG, so a whole round can
## be simulated deterministically in tests. The 3D view only reads this state
## and listens to the signals.
##
## Config: start_gold, lives, wave_bonus, early_bonus, interest_rate,
## interest_max, the countdown (build_time ...), endless and waves
## (data/waves.json), towers (data/towers.json), creeps (data/creeps.json) and
## hp_scale (creep health, a map rule).
##
## Wave flow: the first wave waits for the player. After a wave is cleared the
## next one starts by itself when the countdown (build_time seconds, see
## build_time_for) runs out. Sending it earlier pays early_gold_per_second for
## the time left, and sending it while a wave still runs also pays the flat
## early_bonus (see early_gold).
##
## Options (create_map): "mode": "endless" never wins; after the scripted waves
## come generated ones forever (see endless_wave). Unknown keys are kept in
## `options` for other features. The board comes
## from a map (data/maps/, see Maps); creeps take turns between its spawns.
## Creep abilities are data too: a creep kind lists them under "abilities" and a
## wave group may override them (see Creep.setup_abilities, _heal, _spawn_children).

signal gold_changed(gold: int)
signal lives_changed(lives: int)
signal path_changed
signal tower_built(tower: Tower)
signal tower_upgraded(tower: Tower)
signal tower_sold(tower: Tower, refund: int)
signal tower_fired(tower: Tower, creep: Creep, damage: int)
signal chain_hit(from: Vector2, creep: Creep)  # a lightning hop to another creep
signal projectile_hit(projectile: Projectile, creep: Creep)  # creep is null on a miss
signal gold_bonus(amount: int, reason: String)  # wave bonus, interest, early send
signal creep_spawned(creep: Creep)
signal creep_killed(creep: Creep)
signal creep_leaked(creep: Creep)
signal creep_healed(healer: Creep, radius: float)  # a heal pulse that healed someone
signal creep_split(parent: Creep, children: Array[Creep])  # spawned when the parent died
signal creep_summoned(summoner: Creep, children: Array[Creep])
signal boss_phase(creep: Creep, phase: int)  # an invulnerable phase began (1-based)
signal boss_enraged(creep: Creep)
signal wave_started(number: int)
signal wave_cleared(number: int)
signal countdown_started(number: int, seconds: float)  # wave `number` starts in `seconds`
signal countdown_tick(seconds_left: int)  # the countdown passed a whole second
signal game_over(won: bool)

enum Phase { BUILD, WAVE, WON, LOST }

const DT := 1.0 / 30.0  # fixed simulation step in seconds
const WAVES_FILE := "res://data/waves.json"
const TOWERS_FILE := "res://data/towers.json"
const CREEPS_FILE := "res://data/creeps.json"
## Tag in the next-wave card for an ability a wave group adds to its creeps.
const ABILITY_TAGS := {
	"heal": "Helbreder",
	"shield": "Skjold",
	"split": "Deler seg",
	"immune": "Immun",
	"invisible": "Usynlig",
}

var grid: Grid
var map: Dictionary = {}  # the map definition (data/maps/), {} for a custom grid
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
var hp_scale: float  # creep health multiplier (a map rule, 1.0 by default)
var build_time: float  # countdown before a wave, 0 = no countdown (waits for the player)
var build_time_min: float
var build_time_step: float  # seconds less per wave, down to build_time_min
var early_gold_per_second: float  # paid for the countdown time skipped by sending early
var options: Dictionary = {}  # round options ("mode" ...); unknown keys are kept
var endless := false  # "mode": "endless": waves go on forever and the round is never won
var endless_config: Dictionary = {}
var seed_value: int
var ticks := 0
var countdown_ticks := 0  # steps left until the next wave starts by itself
var countdown_total_ticks := 0
var rng := RandomNumberGenerator.new()

var _accumulator := 0.0
var _queue: Array[Dictionary] = []  # groups left to spawn: {group, left}
var _spawn_timer := 0.0
var _next_creep_id := 1
var _spawned := 0  # ground and air creeps spawned so far (picks the spawn)
var _next_projectile_id := 1
var _generated: Dictionary = {}  # wave number -> endless wave (cache)
var _endless_kinds: Array[String] = []
var _models: Dictionary = {}  # creep kind -> models used by the scripted waves


func _init(config: Dictionary, p_grid: Grid, p_seed := 1, p_options := {}) -> void:
	grid = p_grid
	seed_value = p_seed
	rng.seed = p_seed
	options = p_options.duplicate(true) if p_options is Dictionary else {}
	endless = str(options.get("mode", "classic")) == "endless"
	gold = int(config.start_gold)
	lives = int(config.lives)
	wave_bonus = int(config.get("wave_bonus", 0))
	early_bonus = int(config.get("early_bonus", 0))
	interest_rate = float(config.get("interest_rate", 0.0))
	interest_max = int(config.get("interest_max", 0))
	hp_scale = float(config.get("hp_scale", 1.0))
	build_time = float(config.get("build_time", 0.0))
	build_time_min = float(config.get("build_time_min", 0.0))
	build_time_step = float(config.get("build_time_step", 0.0))
	early_gold_per_second = float(config.get("early_gold_per_second", 0.0))
	var ec: Variant = config.get("endless", {})
	endless_config = ec if ec is Dictionary else {}
	tower_defs = config.towers.towers
	refund_rate = float(config.towers.refund)
	for kind: Variant in config.towers.get("order", tower_defs.keys()):
		tower_order.append(str(kind))
	creep_defs = config.creeps
	for w: Dictionary in config.waves:
		waves.append(w)
	_setup_endless()


## The default map (Engen: spawn left, goal right) with the data in data/.
static func create_default(p_seed := 1, p_options := {}) -> Game:
	return create_map(Maps.DEFAULT, p_seed, p_options)


## A round on the map with this id (data/maps/<id>.json). The map's "rules"
## override the shared config (start gold, lives ...). `p_options` are the
## round options ("mode": "endless" ...), see Game.
static func create_map(map_id: String, p_seed := 1, p_options := {}) -> Game:
	var m := Maps.load_map(map_id)
	var config := default_config()
	config.merge(m.get("rules", {}), true)
	var g := Game.new(config, Maps.grid(m), p_seed, p_options)
	g.map = m
	return g


static func default_config() -> Dictionary:
	var config: Dictionary = load_json(WAVES_FILE)
	config.towers = load_json(TOWERS_FILE)
	config.creeps = load_json(CREEPS_FILE)
	return config


static func default_grid() -> Grid:
	return Maps.grid(Maps.load_map(Maps.DEFAULT))


static func load_json(res_path: String) -> Dictionary:
	var json := load(res_path) as JSON
	return (json.data as Dictionary).duplicate(true)


# --- Building -----------------------------------------------------------------


func build_cost(kind: String) -> int:
	return int(tower_base_stats(kind).cost)


func tower_name(kind: String) -> String:
	return str(tower_defs[kind].get("name", kind))


## Stats of a kind as built (the root of its upgrade tree), for previews.
func tower_base_stats(kind: String) -> Dictionary:
	var def: Dictionary = tower_defs[kind]
	return def.nodes[def.root]


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


## True if the tower on cell can take the upgrade `option` (an id from
## tower.upgrade_options(); "" is the first one) and the player can pay for it.
func can_upgrade(cell: Vector2i, option := "") -> bool:
	var tower := tower_at(cell)
	return (
		tower != null
		and not is_over()
		and tower.can_upgrade(option)
		and gold >= tower.upgrade_cost(option)
	)


func upgrade(cell: Vector2i, option := "") -> bool:
	if not can_upgrade(cell, option):
		return false
	var tower := tower_at(cell)
	_add_gold(-tower.upgrade_cost(option))
	tower.upgrade(option)
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
	if is_over() or not has_wave(wave + 1):
		return false
	return phase == Phase.BUILD or _queue.is_empty()


## True while a wave runs and the next can be sent early (see early_gold).
func can_send_early() -> bool:
	return phase == Phase.WAVE and can_start_wave()


## Starts the next wave. Before the countdown runs out this pays early_gold.
func start_wave() -> bool:
	if not can_start_wave():
		return false
	var bonus := early_gold()
	if bonus > 0:
		_add_gold(bonus)
		gold_bonus.emit(bonus, "early")
	countdown_ticks = 0
	wave += 1
	phase = Phase.WAVE
	for group: Dictionary in wave_groups(wave_data(wave)):
		_queue.append({"group": group, "left": int(group.count)})
	if _spawn_timer < 0.0:
		_spawn_timer = 0.0
	wave_started.emit(wave)
	return true


## Gold for starting the next wave now: early_gold_per_second for the countdown
## time skipped (all of it while a wave still runs), plus the flat early_bonus
## when the current wave is still running. 0 for the first wave.
func early_gold() -> int:
	if not can_start_wave() or wave == 0:
		return 0
	if phase == Phase.WAVE:
		var skipped := roundi(build_time_for(wave + 1) / DT)
		return early_bonus + _gold_for_ticks(skipped)
	return _gold_for_ticks(countdown_ticks)


func _gold_for_ticks(n: int) -> int:
	return floori(n * DT * early_gold_per_second + 0.0001)


## Countdown in seconds before wave `number` (2 or later) starts by itself: the
## wave's own "build_time", else build_time minus build_time_step per wave
## after the second, never below build_time_min. 0 means no countdown.
func build_time_for(number: int) -> float:
	var w := wave_data(number)
	if w.has("build_time"):
		return float(w.build_time)
	if build_time <= 0.0:
		return 0.0
	return maxf(build_time - build_time_step * maxi(number - 2, 0), build_time_min)


## True while the countdown to the next wave runs.
func countdown_active() -> bool:
	return phase == Phase.BUILD and countdown_ticks > 0


## Seconds left of the countdown (0 when it does not run).
func countdown() -> float:
	return countdown_ticks * DT if countdown_active() else 0.0


## Share of the countdown left, from 1 (just started) to 0.
func countdown_fraction() -> float:
	if not countdown_active() or countdown_total_ticks <= 0:
		return 0.0
	return float(countdown_ticks) / countdown_total_ticks


func _start_countdown() -> void:
	countdown_ticks = 0
	countdown_total_ticks = 0
	var seconds := build_time_for(wave + 1)
	if seconds <= 0.0 or not can_start_wave():
		return
	countdown_ticks = maxi(roundi(seconds / DT), 1)
	countdown_total_ticks = countdown_ticks
	countdown_started.emit(wave + 1, seconds)


func _tick_countdown() -> void:
	if not countdown_active():
		return
	var before := ceili(countdown_ticks * DT - 0.0001)
	countdown_ticks -= 1
	var after := ceili(countdown_ticks * DT - 0.0001)
	if after < before:
		countdown_tick.emit(after)
	if countdown_ticks == 0:
		start_wave()


## The wave after the last started one, or {} when there are no more waves.
func next_wave() -> Dictionary:
	return wave_data(wave + 1)


## Wave `number` (1-based): a scripted one, then in endless generated ones.
## {} when there is no such wave.
func wave_data(number: int) -> Dictionary:
	if number >= 1 and number <= waves.size():
		return waves[number - 1]
	if endless and number > waves.size():
		return endless_wave(number)
	return {}


func has_wave(number: int) -> bool:
	return not wave_data(number).is_empty()


## True for the last wave of a classic round (clearing it wins). Never in endless.
func is_final_wave(number: int) -> bool:
	return not endless and number >= waves.size()


## The score of an endless round: the wave reached.
func score() -> int:
	return wave


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


## Labels for a wave: the tags of its creep kinds ("Rask", "Flygende" ...),
## of abilities its groups add, and its own tags from the data.
func wave_tags(w: Dictionary) -> Array[String]:
	var tags: Array[String] = []
	for g in wave_groups(w):
		var group_tags: Array[String] = [
			str(_creep_def(str(g.get("creep", "normal"))).get("tag", ""))
		]
		var over: Dictionary = g.get("abilities", {})
		for ability: String in over:
			var tag := str(ABILITY_TAGS.get(ability, ""))
			if over[ability] == null or (over[ability] is bool and not over[ability]):
				group_tags.erase(tag)  # the group removes this ability
			else:
				group_tags.append(tag)
		for tag in group_tags:
			if tag != "" and tag not in tags:
				tags.append(tag)
	for tag: Variant in w.get("tags", []):
		if str(tag) not in tags:
			tags.append(str(tag))
	return tags


func is_over() -> bool:
	return phase == Phase.WON or phase == Phase.LOST


# --- Endless ------------------------------------------------------------------


## Kinds the endless waves cycle through ("kinds" in the endless config, else
## every non-boss kind with a tag or "normal", in data order) and the models
## the scripted waves use for each kind.
func _setup_endless() -> void:
	for w in waves:
		for g in wave_groups(w):
			var kind := str(g.get("creep", "normal"))
			if not _models.has(kind):
				_models[kind] = []
			var models: Array = _models[kind]
			if g.has("model") and str(g.model) not in models:
				models.append(str(g.model))
	var listed: Variant = endless_config.get("kinds")
	if listed is Array:
		for k: Variant in listed:
			if creep_defs.has(str(k)):
				_endless_kinds.append(str(k))
	if _endless_kinds.is_empty():
		for k: String in creep_defs:
			var def: Dictionary = creep_defs[k]
			if not def.get("boss", false) and (k == "normal" or def.has("tag")):
				_endless_kinds.append(k)
	if _endless_kinds.is_empty():
		_endless_kinds.append("normal")


## Generated wave `number` of an endless round (after the scripted waves). The
## same seed always gives the same waves, and generating one never touches the
## round's rng. The main group cycles through the kinds, a second group of a
## random kind joins most waves and every few waves a group gains an ability.
## Health grows by hp_growth per wave and bounty by the slower bounty_growth.
## Every boss_every-th wave is a boss (cycling boss_kinds) with an escort.
func endless_wave(number: int) -> Dictionary:
	if _generated.has(number):
		return _generated[number]
	var ec := endless_config
	var k := number - waves.size()  # 1 for the first generated wave
	var r := RandomNumberGenerator.new()
	r.seed = hash("endless:%d:%d" % [seed_value, number])
	var hp := float(ec.get("hp", 700.0)) * pow(float(ec.get("hp_growth", 1.12)), k - 1)
	var bounty := float(ec.get("bounty", 9.0)) * pow(float(ec.get("bounty_growth", 1.05)), k - 1)
	var kind_hp: Dictionary = ec.get("kind_hp", {})
	var count_range: Array = ec.get("count", [10, 16])
	var main := _endless_kinds[(k - 1) % _endless_kinds.size()]
	var groups: Array = []
	var boss_every := int(ec.get("boss_every", 5))
	var boss_kinds: Array = (ec.get("boss_kinds", ["boss", "miniboss"]) as Array).filter(
		func(b: Variant) -> bool: return creep_defs.has(str(b))
	)
	if boss_every > 0 and number % boss_every == 0 and not boss_kinds.is_empty():
		var boss_kind := str(boss_kinds[(number / boss_every) % boss_kinds.size()])
		var boss := _endless_group(boss_kind, 1, hp * float(ec.get("boss_hp", 16.0)), bounty, r)
		boss.bounty = roundi(bounty * float(ec.get("boss_bounty", 15.0)))
		boss.interval = 1.5
		groups.append(_endless_group(main, int(ec.get("escort", 6)), hp, bounty, r, kind_hp))
		groups.append(boss)
	else:
		var count := r.randi_range(int(count_range[0]), int(count_range[-1]))
		var first := _endless_group(main, count, hp, bounty, r, kind_hp)
		groups.append(first)
		if r.randf() < float(ec.get("mix_chance", 0.6)):
			var other := _endless_kinds[r.randi_range(0, _endless_kinds.size() - 1)]
			if other != main:
				first.count = maxi(roundi(count * 0.65), 1)
				groups.append(
					_endless_group(other, maxi(roundi(count * 0.45), 1), hp, bounty, r, kind_hp)
				)
		var extra: Array = ec.get("abilities", [])
		var every := int(ec.get("ability_every", 3))
		if not extra.is_empty() and every > 0 and k % every == 0:
			var add: Dictionary = extra[(k / every - 1) % extra.size()]
			var g: Dictionary = groups[r.randi_range(0, groups.size() - 1)]
			g.abilities = add.duplicate(true)
	var w := {"groups": groups, "endless": true}
	_generated[number] = w
	return w


## One group of an endless wave; its model is one the scripted waves use for
## the kind.
func _endless_group(
	kind: String, count: int, hp: float, bounty: float, r: RandomNumberGenerator, kind_hp := {}
) -> Dictionary:
	var def := _creep_def(kind)
	var fast := float(def.get("speed", 1.7)) > 2.2
	var g := {
		"creep": kind,
		"count": count,
		"hp": roundi(hp * float(kind_hp.get(kind, 1.0))),
		"interval": 0.5 if fast else 0.8,
		"bounty": maxi(roundi(bounty), 1),
	}
	var models: Array = _models.get(kind, [])
	if not models.is_empty():
		g.model = str(models[r.randi_range(0, models.size() - 1)])
	return g


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
	_tick_countdown()
	_spawn()
	_use_abilities()
	_tick_effects()
	_move_creeps()
	if phase == Phase.LOST:
		return
	_reveal()
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
	var from := spawn_for(_spawned)
	_spawned += 1
	var creep := new_creep(kind, creep_hp(g), int(g.bounty), g, from)
	if creep.flying:
		creep.set_path([grid.goal])
	else:
		creep.set_path(grid.path_from(from))
	creeps.append(creep)
	entry.left -= 1
	if entry.left <= 0:
		_queue.remove_at(0)
	_spawn_timer += float(g.interval)
	creep_spawned.emit(creep)


## Health of the creeps of a wave group on this map (hp_scale applied).
func creep_hp(group: Dictionary) -> float:
	return float(group.hp) * hp_scale


## Spawn of the n-th creep of the round (0-based): the spawns take turns.
func spawn_for(n: int) -> Vector2i:
	return grid.spawns[n % grid.spawns.size()]


## A creep of a kind from the creep data at a cell. `g` (a wave group, or the
## parameters of a split or summon) may set speed, armor, model and abilities.
func new_creep(kind: String, hp: float, bounty: int, g: Dictionary, cell: Vector2i) -> Creep:
	var def := _creep_def(kind)
	var speed := float(g.get("speed", def.get("speed", 1.7)))
	var creep := Creep.new(_next_creep_id, hp, speed, bounty, cell, kind)
	_next_creep_id += 1
	creep.armor = int(g.get("armor", def.get("armor", 0)))
	creep.flying = bool(def.get("flying", false))
	creep.boss = bool(def.get("boss", false))
	creep.model = str(g.get("model", ""))
	creep.setup_abilities(merge_abilities(def.get("abilities", {}), g.get("abilities", {})))
	return creep


## Abilities of a kind with a group's overrides: parameters are merged per
## ability, and false or null removes one.
static func merge_abilities(base: Dictionary, over: Dictionary) -> Dictionary:
	var out := base.duplicate(true)
	for key: String in over:
		var v: Variant = over[key]
		if v == null or (v is bool and not v):
			out.erase(key)
		elif v is Dictionary and out.get(key) is Dictionary:
			(out[key] as Dictionary).merge((v as Dictionary).duplicate(true), true)
		else:
			out[key] = v
	return out


## Heal pulses and summons, on each creep's own timer.
func _use_abilities() -> void:
	for creep in creeps.duplicate():
		if not creep.alive():
			continue
		if creep.ability_ready("heal", DT):
			_heal(creep, creep.abilities.heal)
		if creep.ability_ready("summon", DT):
			var p: Dictionary = creep.abilities.summon
			# A summoner stops at "max" summons in total, so creeps cannot pile up.
			if creep.summoned < int(p.get("max", 8)):
				var children := _spawn_children(creep, p)
				creep.summoned += children.size()
				creep_summoned.emit(creep, children)


## Heals every creep within "radius" of the healer (itself too) by "amount" plus
## "percent" of its max hp, never above max hp.
func _heal(healer: Creep, p: Dictionary) -> void:
	var radius := float(p.get("radius", 2.0))
	var total := 0.0
	for c in creeps:
		if c.alive() and c.pos.distance_to(healer.pos) <= radius:
			total += c.heal(Creep.scaled(p, c.max_hp))
	if total > 0.0:
		creep_healed.emit(healer, radius)


## Small creeps where `parent` is ("split" when it dies, "summon" while it lives).
## Parameters: count, creep (kind), hp (times hp_scale, plus hp_percent of the
## parent's max hp), speed, bounty and model (default: the parent's). They walk
## on along the parent's path from its current cell, a little behind each other.
func _spawn_children(parent: Creep, p: Dictionary) -> Array[Creep]:
	var kind := str(p.get("creep", "spawnling"))
	# The flat part follows the map's hp_scale; the parent's max hp already does.
	var flat := float(p.get("hp", 0.0)) * hp_scale
	var hp := maxf(flat + float(p.get("hp_percent", 0.0)) * parent.max_hp, 1.0)
	var params := p.duplicate()
	params.model = str(p.get("model", parent.model))
	# Children never split or summon themselves: no endless chains.
	var child_abilities: Dictionary = p.get("abilities", {}).duplicate(true)
	child_abilities.merge({"split": false, "summon": false}, true)
	params.abilities = child_abilities
	var out: Array[Creep] = []
	for i in int(p.get("count", 2)):
		var c := new_creep(kind, hp, int(p.get("bounty", 1)), params, parent.prev_cell)
		c.flying = c.flying or parent.flying  # flyers from the data stay flyers
		c.path = parent.path.duplicate()
		c.next_index = parent.next_index
		c.pos = parent.pos.move_toward(Grid.center(parent.prev_cell), 0.2 * i)
		c.prev_pos = c.pos
		creeps.append(c)
		creep_spawned.emit(c)
		out.append(c)
	return out


## Marks invisible creeps that a revealing tower has in range.
func _reveal() -> void:
	var revealers: Array[Tower] = []
	for cell: Vector2i in towers:
		if towers[cell].reveals():
			revealers.append(towers[cell])
	for c in creeps:
		if not c.invisible:
			continue
		c.revealed = false
		for tower in revealers:
			if tower.in_range(c):
				c.revealed = true
				break


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
	var targets: Array[Creep] = [target]
	if int(s.get("multishot", 1)) > 1:
		targets = tower.pick_targets(creeps, int(s.multishot))
	for t in targets:
		var damage := rng.randi_range(int(s.damage_min), int(s.damage_max))
		tower_fired.emit(tower, t, damage)
		if s.has("projectile_speed"):
			projectiles.append(Projectile.new(_next_projectile_id, tower, t, damage))
			_next_projectile_id += 1
		else:
			_impact(s, damage, t, t.pos, tower.can_hit)


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
	var pierce := bool(s.get("armor_pierce", false))
	if target:
		var amount := float(damage)
		if target.flying:
			amount *= float(s.get("air_multiplier", 1.0))
		target.hit(amount, pierce)
		_apply_effects(s, target)
		if s.has("stun"):
			target.apply_stun(float(s.stun))
		if s.has("knockback"):
			target.knock_back(float(s.knockback))
	if s.has("splash_radius"):
		var radius := float(s.splash_radius)
		for other in creeps:
			if other != target and other.alive() and can_hit.call(other):
				if other.pos.distance_to(at) <= radius:
					other.hit(damage * float(s.splash_factor), pierce)
					if s.get("splash_effects", false):
						_apply_effects(s, other)
	if target and s.has("chain"):
		_chain(s, damage, target, can_hit)


## Slow, poison and burn from a hit.
func _apply_effects(s: Dictionary, c: Creep) -> void:
	if s.has("slow"):
		c.apply_slow(float(s.slow), float(s.slow_time))
	if s.has("poison_dps"):
		c.apply_poison(float(s.poison_dps), float(s.poison_time), int(s.get("poison_stacks", 1)))
		if str(s.get("element", "")) == "fire":
			c.burn_time = maxf(c.burn_time, float(s.poison_time))


## Lightning that hops from the target to the nearest creeps not hit yet.
func _chain(s: Dictionary, damage: int, first: Creep, can_hit: Callable) -> void:
	var done: Array[Creep] = [first]
	var from := first
	var amount := float(damage)
	for i in int(s.chain):
		amount *= float(s.get("chain_factor", 0.7))
		var best: Creep = null
		var best_d := float(s.get("chain_range", 2.0))
		for c in creeps:
			if (
				c in done
				or not c.alive()
				or not c.targetable()
				or c.invulnerable_time > 0.0
				or not can_hit.call(c)
			):
				continue
			var d := c.pos.distance_to(from.pos)
			if d <= best_d:
				best = c
				best_d = d
		if best == null:
			return
		chain_hit.emit(from.pos, best)
		best.hit(amount, bool(s.get("armor_pierce", false)))
		done.append(best)
		from = best


## Removes dead creeps and pays their bounty; splitters leave their children.
## Also reports the boss phases and enrages the last damage started.
func _reap() -> void:
	for creep in creeps.duplicate():
		if not creep.alive():
			creeps.erase(creep)
			_add_gold(creep.bounty)
			creep_killed.emit(creep)
			if creep.abilities.has("split"):
				creep_split.emit(creep, _spawn_children(creep, creep.abilities.split))
			continue
		if creep.phase_started:
			creep.phase_started = false
			boss_phase.emit(creep, creep.phase)
		if creep.enrage_started:
			creep.enrage_started = false
			boss_enraged.emit(creep)


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
	if is_final_wave(wave):
		phase = Phase.WON
		game_over.emit(true)
	else:
		phase = Phase.BUILD
		_start_countdown()


func _repath() -> void:
	for creep in creeps:
		if not creep.flying:
			creep.set_path(grid.path_from(creep.target_cell()))
	path_changed.emit()


func _add_gold(amount: int) -> void:
	gold += amount
	gold_changed.emit(gold)
