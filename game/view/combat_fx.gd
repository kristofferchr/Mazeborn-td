class_name CombatFx
extends Node3D
## Combat effects on the board: projectiles in flight (models, glows, trails),
## lightning bolts, impacts per tower kind and element, muzzle flashes,
## status marks on creeps (stun stars, frost, flames, poison) and creep deaths.
## Reads the game state and its signals only.
##
## Cheap by design for the Compatibility renderer and many towers at 2x:
## - glows, sparks, rings and smoke are sprites in two batches (FxSprites:
##   additive and blended), trails and bolts are one strip mesh (FxRibbons),
##   so they cost about three draw calls in all;
## - projectile models come from small per-model pools (MAX_MESHES), shots and
##   bolts are reused objects, and every batch has a fixed size;
## - mesh debris goes through the pooled Effects bursts.
## `time_scale` 0 freezes the effects (tools/vfx.gd uses it to inspect them).

const ADD_SPRITES := 640
const MIX_SPRITES := 256
const MAX_MESHES := 64  # projectile models per kind
const MAX_BOLTS := 40
const TRAIL_POINTS := 10
const TRAIL_STEP := 0.07  # cells between trail points
const TRAIL_FADE := 0.14  # seconds a trail lingers after the hit
const BOLT_LIFE := 0.24
const BOLT_REROLL := 0.045  # seconds between new bolt shapes (2-3 frames)
const HOP_DELAY := 0.06  # seconds between the jumps of a chain
const LIGHTNING := Color(1.0, 0.85, 0.25)
const UP := Vector3.UP
## Longest trail per shot style in cells (default 0.6).
const TRAIL_LENGTH := {"arrow": 0.5, "wind": 0.9, "fire": 0.8, "meteor": 1.3, "earth": 0.0}
## Projectile model per shot style.
const MODELS := {
	"arrow": "arrow", "earth": "boulder", "meteor": "meteor", "ice": "shard", "wind": "blade"
}

var game: Game
var board: BoardView
var effects: Effects
var time_scale := 1.0
var glow: FxSprites  # additive sprites
var dust: FxSprites  # blended sprites
var ribbons: FxRibbons
var _shots: Dictionary = {}  # projectile id -> Shot
var _live: Array[Shot] = []  # in flight or with a fading trail
var _spare: Array[Shot] = []
var _bolts: Array[Bolt] = []
var _spare_bolts: Array[Bolt] = []
var _pools: Dictionary = {}  # model -> Array of hidden MeshInstance3D
var _made: Dictionary = {}  # model -> how many were made
var _rng := RandomNumberGenerator.new()
var _frame := 0
var _time := 0.0
var _hops := 0  # chain jumps so far of the last lightning attack
var _last_end := Vector3.ZERO  # end of the last bolt, where the next jump starts
var _pts := PackedVector3Array()  # scratch polyline
var _line := PackedVector3Array()  # scratch polyline


## A projectile's look while it flies, and its trail after it hit.
class Shot:
	var id := 0
	var style := ""
	var model := ""
	var node: MeshInstance3D
	var start := Vector2.ZERO
	var h0 := 0.0
	var pos := Vector3.ZERO
	var dir := Vector3.FORWARD
	var trail := PackedVector3Array()
	var frame := 0
	var fading := -1.0  # seconds since the hit; -1 while in flight
	var roll := 0.0
	var size := 1.0
	var phase := 0.0
	var reveal := false
	var trail_length := 0.6


## A lightning bolt between two points; the end follows its creep.
class Bolt:
	var a := Vector3.ZERO
	var b := Vector3.ZERO
	var creep: Creep
	var age := 0.0  # negative while it waits for its jump
	var reroll := 0.0
	var started := false
	var main := PackedVector3Array()
	var branch := PackedVector3Array()
	var branch2 := PackedVector3Array()


## Look of a shot: the tower kind, or the element for Elemental towers
## ("meteor" for the heavy fire node).
static func shot_style(kind: String, element: String, stats: Dictionary) -> String:
	if kind == "elemental":
		if element == "fire" and float(stats.get("splash_radius", 0.0)) >= 1.75:
			return "meteor"
		return element if element != "" else "elemental"
	return kind if kind in ["arrow", "earth", "wind"] else "arrow"


## Colour of a tower's shots: the element's colour, or the kind's.
static func shot_color(kind: String, element: String) -> Color:
	if kind == "elemental":
		return BoardView.ELEMENT_COLORS.get(element, BoardView.ELEMENT_COLORS[""])
	return BoardView.tower_color(kind)


func setup(p_game: Game, p_board: BoardView, p_effects: Effects) -> void:
	game = p_game
	board = p_board
	effects = p_effects
	_rng.seed = 12345
	dust = FxSprites.new()
	dust.setup(MIX_SPRITES, FxArt.sprite_material("fx_mix"))
	add_child(dust)
	ribbons = FxRibbons.new()
	var rm := ShaderMaterial.new()
	rm.shader = load("res://view/shaders/fx_ribbon.gdshader")
	ribbons.setup(rm)
	add_child(ribbons)
	glow = FxSprites.new()
	glow.setup(ADD_SPRITES, FxArt.sprite_material("fx_add"))
	add_child(glow)
	game.tower_fired.connect(_on_tower_fired)
	game.projectile_hit.connect(_on_projectile_hit)
	game.chain_hit.connect(_on_chain_hit)
	game.creep_killed.connect(_on_creep_killed)


## Shots and bolts on screen (in flight, fading or waiting), for tests.
func active() -> Vector2i:
	return Vector2i(_live.size(), _bolts.size())


## Projectile models made so far (all pools), for tests.
func models_made() -> int:
	var n := 0
	for k: String in _made:
		n += int(_made[k])
	return n


func _process(delta: float) -> void:
	update(delta)


## One frame of effects (also called by tests).
func update(delta: float) -> void:
	var dt := delta * time_scale
	_time += dt
	glow.step(dt)
	dust.step(dt)
	ribbons.begin()
	_update_shots(dt)
	_update_bolts(dt)
	_update_creeps(dt)
	ribbons.end()
	glow.commit()
	dust.commit()


func hit_point(creep: Creep) -> Vector3:
	return board.creep_world_pos(creep) + Vector3(0.0, board.creep_top(creep) * 0.5, 0.0)


# --- Projectiles -------------------------------------------------------------


func _update_shots(dt: float) -> void:
	_frame += 1
	var a := clampf(game.alpha(), 0.0, 1.0)
	for p in game.projectiles:
		var s: Shot = _shots.get(p.id)
		if s == null:
			s = _start_shot(p)
		s.frame = _frame
		_fly(s, p, a, dt)
	for i in range(_live.size() - 1, -1, -1):
		var s := _live[i]
		if s.frame != _frame:
			if s.fading < 0.0:
				_land(s)
				s.fading = 0.0
			s.fading += dt
			if s.fading >= TRAIL_FADE:
				_live[i] = _live[_live.size() - 1]
				_live.pop_back()
				_spare.append(s)
				continue
		_draw_shot(s, dt)


func _start_shot(p: Projectile) -> Shot:
	var s: Shot = _spare.pop_back() if not _spare.is_empty() else Shot.new()
	s.id = p.id
	s.style = shot_style(p.kind, p.element, p.stats)
	s.model = MODELS.get(s.style, "")
	s.node = _take_model(s.model) if s.model != "" else null
	s.start = p.pos
	var cell := Vector2i(floori(p.pos.x), floori(p.pos.y))
	s.h0 = board.tower_top(cell)
	s.pos = Vector3(p.pos.x, s.h0, p.pos.y)
	s.dir = Vector3.FORWARD
	s.trail.resize(0)
	s.trail.append(s.pos)
	s.fading = -1.0
	s.roll = _rng.randf() * TAU
	s.phase = _rng.randf() * TAU
	s.size = clampf(0.85 + float(p.stats.get("damage_max", 10)) / 250.0, 0.9, 1.5)
	s.reveal = bool(p.stats.get("reveal", false))
	s.trail_length = float(TRAIL_LENGTH.get(s.style, 0.6))
	if s.style == "earth":
		s.size = minf(s.size, 1.15)
	_shots[p.id] = s
	_live.append(s)
	return s


## Flight path: interpolated between ticks, from the tower top down to the
## target, heavy shots on a high arc.
func _fly(s: Shot, p: Projectile, a: float, dt: float) -> void:
	var flat := p.prev_pos.lerp(p.pos, a)
	var done := s.start.distance_to(flat)
	var left := flat.distance_to(p.target_pos)
	var f := clampf(done / (done + left + 0.0001), 0.0, 1.0)
	var h1 := board.creep_top(p.target) * 0.5 + (BoardView.FLY_HEIGHT if p.target.flying else 0.0)
	var high := s.style == "earth" or p.stats.has("splash_radius")
	var arc := (0.35 if high else 0.1) * (done + left) * sin(PI * f)
	var pos := Vector3(flat.x, lerpf(s.h0, h1, f) + arc, flat.y)
	var step := pos - s.pos
	if step.length_squared() > 0.000001:
		s.dir = step.normalized()
	s.pos = pos
	var n := s.trail.size()
	if n >= 2 and s.trail[n - 2].distance_to(pos) < TRAIL_STEP:
		s.trail[n - 1] = pos
	else:
		s.trail.append(pos)
		if s.trail.size() > TRAIL_POINTS:
			s.trail.remove_at(0)
	_trim(s.trail, s.trail_length)
	if s.node:
		s.node.position = pos
		var up := UP if absf(s.dir.y) < 0.98 else Vector3.RIGHT
		var basis := Basis.looking_at(s.dir, up)
		match s.style:
			"earth", "meteor":
				s.roll += dt * 9.0
				basis = Basis(Vector3(0.6, 0.3, 0.75).normalized(), s.roll)
			"wind":
				s.roll += dt * 24.0
				basis = basis * Basis(Vector3.BACK, s.roll)
			"ice":
				s.roll += dt * 6.0
				basis = basis * Basis(Vector3.BACK, s.roll)
		s.node.basis = basis.scaled(Vector3.ONE * s.size)


## Cuts a trail (oldest point first) to `length` cells behind its head.
static func _trim(trail: PackedVector3Array, length: float) -> void:
	var total := 0.0
	for i in range(trail.size() - 1, 0, -1):
		var seg := trail[i].distance_to(trail[i - 1])
		if total + seg > length:
			var keep := maxf(length - total, 0.0)
			trail[i - 1] = trail[i] + (trail[i - 1] - trail[i]) * (keep / maxf(seg, 0.0001))
			for j in i - 1:
				trail.remove_at(0)
			return
		total += seg


## Points evenly spread along a polyline, into `out`.
static func _resample(line: PackedVector3Array, n: int, out: PackedVector3Array) -> void:
	out.resize(n)
	var total := 0.0
	for i in range(1, line.size()):
		total += line[i].distance_to(line[i - 1])
	var seg := 0
	var walked := 0.0
	for k in n:
		var want := total * k / (n - 1)
		while seg < line.size() - 2 and walked + line[seg].distance_to(line[seg + 1]) < want:
			walked += line[seg].distance_to(line[seg + 1])
			seg += 1
		var d := line[seg].distance_to(line[seg + 1])
		var f := clampf((want - walked) / maxf(d, 0.0001), 0.0, 1.0)
		out[k] = line[seg].lerp(line[seg + 1], f)


func _land(s: Shot) -> void:
	_shots.erase(s.id)
	if s.node:
		_give_model(s.model, s.node)
		s.node = null


func _take_model(model: String) -> MeshInstance3D:
	var pool: Array = _pools.get(model, [])
	_pools[model] = pool
	if not pool.is_empty():
		var reused: MeshInstance3D = pool.pop_back()
		reused.visible = true
		return reused
	if int(_made.get(model, 0)) >= MAX_MESHES:
		return null
	_made[model] = int(_made.get(model, 0)) + 1
	var node := MeshInstance3D.new()
	node.mesh = FxArt.mesh(model)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	return node


func _give_model(model: String, node: MeshInstance3D) -> void:
	node.visible = false
	(_pools[model] as Array).append(node)


## Glows, trail and trail particles of one shot.
func _draw_shot(s: Shot, dt: float) -> void:
	var k := 1.0 if s.fading < 0.0 else 1.0 - s.fading / TRAIL_FADE
	var flying := s.fading < 0.0
	var p := s.pos
	var t := _time * 30.0 + s.phase
	var sz := s.size
	if s.fading >= 0.0:
		dt = 0.0  # no new trail particles after the hit
	match s.style:
		"arrow":
			_trail(s, 0.05, Color(1.0, 0.95, 0.82, 0.32 * k))
			if flying:
				var gleam := Color(1.0, 0.85, 0.45, 0.5) if s.reveal else Color(1, 0.9, 0.7, 0.18)
				glow.draw(p, 0.22 if s.reveal else 0.16, gleam, FxArt.GLOW)
		"earth":
			for i in _count(14.0, dt):
				var off := _rand_dir() * 0.08
				var c := Color(0.62, 0.55, 0.45, 0.4)
				dust.spawn(
					p + off, off, 0.45, 0.1 * sz, 0.3 * sz, c, FxArt.SMOKE, Vector3(0.3, 2.0, 1.0)
				)
		"meteor", "fire":
			_draw_fire(s, k, t, dt, s.style == "meteor")
		"ice":
			_trail(s, 0.1 * sz, Color(0.65, 0.9, 1.0, 0.5 * k))
			if flying:
				glow.draw(p, 0.42 * sz, Color(0.5, 0.82, 1.0, 0.55), FxArt.GLOW)
			for i in _count(16.0, dt):
				var v := _rand_dir() * 0.3 - s.dir * 0.4
				var c := Color(0.8, 0.95, 1.0, 0.9)
				glow.spawn(p, v, 0.45, 0.11, 0.03, c, FxArt.FLAKE, Vector3(-1.0, 1.0, 4.0))
		"lightning":
			_draw_storm(s, k, t)
		"nature":
			_draw_nature(s, k, t, dt)
		"wind":
			_draw_wind(s, k)
		_:
			var c := shot_color("elemental", "")
			_trail(s, 0.1, Color(c, 0.5 * k))
			if flying:
				glow.draw(p, 0.24, Color(0.95, 0.8, 1.0, 0.9), FxArt.GLOW)
				glow.draw(p, 0.5 + 0.05 * sin(t), Color(c, 0.55), FxArt.GLOW)
			for i in _count(10.0, dt):
				glow.spawn(p, _rand_dir() * 0.4, 0.35, 0.12, 0.02, c, FxArt.FLARE)


## A plain trail strip: thin and clear at the tail, `width` at the head.
func _trail(s: Shot, width: float, color: Color) -> void:
	ribbons.strip(s.trail, 0.0, width, Color(color, 0.0), color)


func _draw_fire(s: Shot, k: float, t: float, dt: float, meteor: bool) -> void:
	var p := s.pos
	var sz := s.size * (1.6 if meteor else 1.0)
	_trail(s, 0.22 * sz, Color(1.0, 0.45, 0.12, 0.55 * k))
	if s.fading < 0.0:
		var flick := 1.0 + 0.12 * sin(t * 1.3) + 0.08 * sin(t * 2.9)
		if not meteor:
			glow.draw(p, 0.24 * sz, Color(1.0, 0.7, 0.3, 0.9), FxArt.GLOW)
		glow.draw(p, 0.55 * sz * flick, Color(1.0, 0.3, 0.05, 0.6), FxArt.GLOW)
		glow.draw(p + UP * 0.05, 0.4 * sz * flick, Color(1.0, 0.4, 0.08, 0.55), FxArt.FLAME)
	for i in _count(36.0 if meteor else 26.0, dt):
		var v := _rand_dir() * 0.4 - s.dir * 0.6 + UP * 0.5
		var c := Color(1.0, _rng.randf_range(0.25, 0.6), 0.05, 0.9)
		var size := _rng.randf_range(0.06, 0.11) * sz
		glow.spawn(
			p + _rand_dir() * 0.06, v, 0.4, size, 0.02, c, FxArt.GLOW, Vector3(0.8, 2.0, 0.0)
		)
	if meteor:
		for i in _count(12.0, dt):
			var c := Color(0.2, 0.17, 0.15, 0.45)
			dust.spawn(
				p,
				UP * 0.5 + _rand_dir() * 0.2,
				0.6,
				0.2,
				0.5,
				c,
				FxArt.SMOKE,
				Vector3(0.3, 1.5, 0.0)
			)


## Storm shots: a crackling ball with a jagged trail.
func _draw_storm(s: Shot, k: float, t: float) -> void:
	var p := s.pos
	_pts.resize(s.trail.size())
	for i in s.trail.size():
		var j := 0.0 if i == s.trail.size() - 1 else 0.05
		_pts[i] = s.trail[i] + _rand_dir() * j
	ribbons.strip(_pts, 0.0, 0.1, Color(LIGHTNING, 0.0), Color(LIGHTNING, 0.8 * k), 0.6)
	if s.fading >= 0.0:
		return
	glow.draw(p, 0.22, Color(1, 1, 0.9, 1), FxArt.GLOW)
	glow.draw(p, 0.5 + 0.08 * sin(t * 2.0), Color(LIGHTNING, 0.6), FxArt.GLOW)
	for arc in 2:
		_pts.resize(4)
		var d := _rand_dir() * 0.28
		for i in 4:
			_pts[i] = p + d * (i / 3.0) + (_rand_dir() * 0.04 if i > 0 else Vector3.ZERO)
		ribbons.strip(_pts, 0.04, 0.02, Color(LIGHTNING, 0.9), Color(LIGHTNING, 0.6), 1.0)


## Nature shots: a green orb with motes circling it, shedding motes and leaves.
func _draw_nature(s: Shot, k: float, t: float, dt: float) -> void:
	var p := s.pos
	var c := BoardView.ELEMENT_COLORS.nature
	_trail(s, 0.08, Color(c, 0.35 * k))
	if s.fading < 0.0:
		glow.draw(p, 0.3, Color(0.9, 1.0, 0.65, 1.0), FxArt.GLOW)
		glow.draw(p, 0.62, Color(0.55, 1.0, 0.3, 0.6), FxArt.GLOW)
		var side := s.dir.cross(UP).normalized() if absf(s.dir.y) < 0.98 else Vector3.RIGHT
		var other := s.dir.cross(side)
		for i in 3:
			var ang := t * 0.3 + i * TAU / 3.0
			var off := (side * cos(ang) + other * sin(ang)) * 0.16
			glow.draw(p + off, 0.12, Color(0.7, 1.0, 0.45, 0.9), FxArt.GLOW)
	for i in _count(20.0, dt):
		var v := UP * 0.4 + _rand_dir() * 0.2
		glow.spawn(
			p, v, 0.55, 0.09, 0.02, Color(0.6, 1.0, 0.4, 0.8), FxArt.GLOW, Vector3(0.3, 1.5, 0.0)
		)
	for i in _count(4.0, dt):
		var leaf := Color(0.3, 0.7, 0.22, 0.95)
		var spin := _rng.randf_range(-7.0, 7.0)
		dust.spawn(
			p, _rand_dir() * 0.5, 0.7, 0.11, 0.09, leaf, FxArt.LEAF, Vector3(-1.5, 2.0, spin)
		)


## Wind shots: a spinning blade (the model) in two spiral strands of air.
func _draw_wind(s: Shot, k: float) -> void:
	if s.trail.size() < 2:
		return
	ribbons.strip(s.trail, 0.0, 0.16, Color(0.9, 0.97, 1.0, 0.0), Color(0.9, 0.97, 1.0, 0.14 * k))
	var side := s.dir.cross(UP).normalized() if absf(s.dir.y) < 0.98 else Vector3.RIGHT
	var other := s.dir.cross(side)
	var n := 14
	_resample(s.trail, n, _line)
	_pts.resize(n)
	for strand in 2:
		for i in n:
			var f := float(i) / (n - 1)
			var ang := _time * 20.0 - i * 0.9 + strand * PI + s.phase
			var r := 0.03 + 0.09 * (1.0 - f)
			_pts[i] = _line[i] + (side * cos(ang) + other * sin(ang)) * r
		ribbons.strip(_pts, 0.0, 0.05, Color(0.85, 0.97, 1.0, 0.0), Color(0.9, 0.98, 1, 0.5 * k))
	if s.fading < 0.0:
		glow.draw(s.pos, 0.34, Color(0.8, 0.95, 1.0, 0.3), FxArt.GLOW)


# --- Impacts -----------------------------------------------------------------


func _on_projectile_hit(p: Projectile, creep: Creep) -> void:
	var s: Shot = _shots.get(p.id)
	var dir := s.dir if s else Vector3.FORWARD
	var at := hit_point(creep) if creep else (s.pos if s else Vector3(p.pos.x, 0.3, p.pos.y))
	var ground := Vector3(p.pos.x, 0.04, p.pos.y)
	var radius := float(p.stats.get("splash_radius", 0.0))
	var style := shot_style(p.kind, p.element, p.stats)
	match style:
		"arrow":
			_hit_arrow(at, dir)
			effects.burst("arrow", at, 0.8)
		"earth":
			_hit_earth(at, ground, maxf(radius, 0.8))
		"wind":
			_hit_wind(at, dir)
		"fire", "meteor":
			_hit_fire(at, ground, radius)
		"ice":
			_hit_ice(at, ground, radius, p.stats.has("stun"))
		"lightning":
			_hit_lightning(at)
		"nature":
			_hit_nature(at, ground, p.stats.has("stun"))
		_:
			var c := shot_color("elemental", "")
			glow.spawn(at, Vector3.ZERO, 0.14, 0.4, 0.9, Color(c, 0.9), FxArt.FLARE)
			_sparks(at, 6, c, 2.2)
	if creep and p.stats.has("stun"):
		var c := Color(1.0, 0.95, 0.5, 0.9)
		glow.spawn(
			at + UP * 0.25, Vector3.ZERO, 0.3, 0.25, 0.8, c, FxArt.STAR, Vector3(0.0, 0.0, 6.0)
		)


func _hit_arrow(at: Vector3, dir: Vector3) -> void:
	glow.spawn(at, Vector3.ZERO, 0.1, 0.35, 0.55, Color(1.0, 0.9, 0.6, 0.9), FxArt.FLARE)
	for i in 5:
		var v := -dir * 1.2 + _rand_dir() * 2.2 + UP * 1.0
		glow.spawn(
			at, v, 0.25, 0.07, 0.02, Color(1.0, 0.8, 0.4), FxArt.SPARK, Vector3(-8.0, 2.0, 0.0)
		)


## Boulder: dust shockwave, a crater, dust clouds and rock debris.
func _hit_earth(at: Vector3, ground: Vector3, radius: float) -> void:
	var tan := Color(0.68, 0.6, 0.48, 0.7)
	var crater := Color(0.16, 0.12, 0.09, 0.5)
	var r := radius
	dust.flat(ground, 1.8, r * 0.75, r * 0.85, crater, FxArt.SCORCH, _ang())
	dust.flat(ground, 0.45, 0.3, r * 2.3, tan, FxArt.SHOCK)
	for i in 10:
		var d := Vector3.FORWARD.rotated(UP, TAU * i / 10.0 + _rng.randf() * 0.4)
		var v := d * _rng.randf_range(1.6, 2.6) * r + UP * 0.3
		var c := Color(tan, 0.55)
		dust.spawn(
			ground + d * 0.2 + UP * 0.1, v, 0.7, 0.24, 0.6, c, FxArt.SMOKE, Vector3(0.2, 3.0, 1.0)
		)
	glow.spawn(at, Vector3.ZERO, 0.12, 0.5, 1.0, Color(1.0, 0.85, 0.6, 0.6), FxArt.GLOW)
	effects.burst("earth", ground + UP * 0.1, clampf(r, 1.0, 1.6))


## Gust: a swirl and a puff of air pushed along the shot (knockback).
func _hit_wind(at: Vector3, dir: Vector3) -> void:
	var c := Color(0.85, 0.97, 1.0, 0.7)
	glow.spawn(at, Vector3.ZERO, 0.3, 0.25, 0.85, c, FxArt.SWIRL, Vector3(0.0, 0.0, 14.0))
	var push := Vector3(dir.x, 0.0, dir.z).normalized()
	for i in 6:
		var v := push * _rng.randf_range(2.0, 3.2) + _rand_dir() * 0.7 + UP * 0.3
		var puff := Color(0.93, 0.97, 1.0, 0.5)
		dust.spawn(
			at + _rand_dir() * 0.08, v, 0.45, 0.12, 0.42, puff, FxArt.SMOKE, Vector3(0.0, 4.0, 2.0)
		)
	effects.burst("wind", at, 0.7)


## Fireball: a flash, a ball of flame, flying embers, smoke, and on splash a
## fire ring and a scorch mark.
func _hit_fire(at: Vector3, ground: Vector3, radius: float) -> void:
	var sc := maxf(radius, 0.8)
	glow.spawn(at, Vector3.ZERO, 0.12, 0.5 * sc, 1.2 * sc, Color(1.0, 0.7, 0.35, 0.9), FxArt.FLARE)
	for i in 7:
		var v := _rand_dir() * 1.4 * sc + UP * 0.6
		var c := Color(1.0, _rng.randf_range(0.2, 0.45), 0.04, 0.6)
		glow.spawn(at, v, 0.38, 0.25 * sc, 0.6 * sc, c, FxArt.GLOW, Vector3(1.0, 3.0, 0.0))
	for i in 3:
		var c := Color(1.0, 0.4, 0.08, 0.7)
		glow.spawn(
			at,
			UP * 1.2 + _rand_dir() * 0.5,
			0.4,
			0.32 * sc,
			0.15,
			c,
			FxArt.FLAME,
			Vector3(0.0, 2.0, 0.0)
		)
	for i in 12:
		var v := _rand_dir() * 3.0 + UP * 2.0
		var c := Color(1.0, _rng.randf_range(0.5, 0.8), 0.25)
		var life := _rng.randf_range(0.5, 0.9)
		glow.spawn(at, v, life, 0.08, 0.02, c, FxArt.SPARK, Vector3(-5.0, 1.0, 0.0))
	for i in 3:
		var c := Color(0.18, 0.16, 0.15, 0.45)
		var v := UP * 0.6 + _rand_dir() * 0.3
		dust.spawn(
			at + UP * 0.2, v, 0.9, 0.3 * sc, 0.8 * sc, c, FxArt.SMOKE, Vector3(0.3, 1.5, 0.8)
		)
	if radius > 0.0:
		var ring := Color(1.0, 0.5, 0.15, 0.85)
		var scorch := Color(0.08, 0.06, 0.05, 0.5)
		var rot := _ang()
		dust.flat(ground, 2.2, radius * 0.7, radius * 0.8, scorch, FxArt.SCORCH, rot)
		glow.flat(ground, 0.32, 0.3, radius * 2.2, ring, FxArt.SHOCK)


## Frost burst: a pale flash, flakes and shards; on splash a frost ring and
## a frosted patch with flakes over the area.
func _hit_ice(at: Vector3, ground: Vector3, radius: float, lance: bool) -> void:
	var sc := 1.4 if lance else 1.0
	glow.spawn(at, Vector3.ZERO, 0.16, 0.4, 1.0 * sc, Color(0.6, 0.9, 1.0, 0.9), FxArt.GLOW)
	glow.spawn(at, Vector3.ZERO, 0.1, 0.3, 0.6 * sc, Color(0.9, 0.97, 1.0, 0.9), FxArt.FLARE)
	for i in 8:
		var v := _rand_dir() * 2.2 + UP * 0.6
		var c := Color(0.8, 0.95, 1.0)
		glow.spawn(at, v, 0.55, 0.14, 0.05, c, FxArt.FLAKE, Vector3(-3.0, 2.0, 6.0))
	for i in 6:
		var c := Color(0.6, 0.9, 1.0)
		glow.spawn(at, _rand_dir() * 3.0, 0.35, 0.13, 0.06, c, FxArt.SHARD, Vector3(-6.0, 1.0, 0.0))
	effects.burst("ice", at, 0.8)
	if radius > 0.0:
		var ring := Color(0.6, 0.9, 1.0, 0.8)
		var frost := Color(0.82, 0.93, 1.0, 0.35)
		dust.flat(ground, 1.6, radius * 1.4, radius * 1.6, frost, FxArt.SMOKE, _ang())
		glow.flat(ground, 0.35, 0.3, radius * 2.2, ring, FxArt.SHOCK)
		for i in 10:
			var off := Vector3(_rng.randf_range(-1, 1), 0.0, _rng.randf_range(-1, 1)) * radius
			var c := Color(0.85, 0.96, 1.0)
			var at2 := ground + off + UP * _rng.randf_range(0.4, 0.9)
			glow.spawn(at2, UP * -0.6, 0.7, 0.12, 0.05, c, FxArt.FLAKE, Vector3(0.0, 0.5, 3.0))


func _hit_lightning(at: Vector3) -> void:
	glow.spawn(at, Vector3.ZERO, 0.12, 0.5, 0.9, Color(1.0, 0.97, 0.8), FxArt.FLARE)
	glow.spawn(at, Vector3.ZERO, 0.16, 0.4, 0.8, Color(LIGHTNING, 0.7), FxArt.GLOW)
	_sparks(at, 7, LIGHTNING, 3.0)


## Leaf burst and green motes; Roots (stun) also gets a ring on the ground.
func _hit_nature(at: Vector3, ground: Vector3, roots: bool) -> void:
	var c := BoardView.ELEMENT_COLORS.nature
	glow.spawn(at, Vector3.ZERO, 0.16, 0.4, 0.8, Color(c, 0.8), FxArt.GLOW)
	for i in 9:
		var v := _rand_dir() * 2.0 + UP * 1.2
		var leaf := Color(0.25, 0.6, 0.2).lerp(Color(0.6, 0.85, 0.3), _rng.randf())
		var spin := _rng.randf_range(-8.0, 8.0)
		dust.spawn(at, v, 0.9, 0.14, 0.1, leaf, FxArt.LEAF, Vector3(-2.5, 2.5, spin))
	for i in 6:
		var v := _rand_dir() * 1.2 + UP * 0.5
		glow.spawn(at, v, 0.6, 0.1, 0.02, Color(0.6, 1.0, 0.4), FxArt.GLOW, Vector3(0.5, 2.0, 0.0))
	if roots:
		var ring := Color(0.45, 0.9, 0.3, 0.8)
		glow.flat(ground, 0.4, 0.2, 1.3, ring, FxArt.SHOCK)


func _sparks(at: Vector3, n: int, color: Color, speed: float) -> void:
	for i in n:
		var v := _rand_dir() * speed + UP * 0.8
		glow.spawn(at, v, 0.28, 0.08, 0.02, color, FxArt.SPARK, Vector3(-6.0, 2.0, 0.0))


# --- Firing and lightning -----------------------------------------------------


## A muzzle flash on the tower top; instant hits (lightning) get a bolt.
func _on_tower_fired(tower: Tower, creep: Creep, _damage: int) -> void:
	var top := BoardView.cell_pos(tower.cell, board.tower_top(tower.cell))
	if not tower.stats().has("projectile_speed"):
		_hops = 0  # chain jumps of this attack follow
		_add_bolt(top, creep, 0.0)
		return
	match tower.kind:
		"arrow":
			glow.spawn(top, Vector3.ZERO, 0.09, 0.25, 0.4, Color(1.0, 0.9, 0.6, 0.6), FxArt.FLARE)
		"earth":
			for i in 3:
				var c := Color(0.66, 0.58, 0.46, 0.5)
				var v := _rand_dir() * 0.6 + UP * 0.4
				dust.spawn(top, v, 0.45, 0.15, 0.4, c, FxArt.SMOKE, Vector3(0.0, 3.0, 1.0))
		"wind":
			var c := Color(0.85, 0.97, 1.0, 0.5)
			glow.spawn(top, Vector3.ZERO, 0.22, 0.2, 0.6, c, FxArt.SWIRL, Vector3(0.0, 0.0, 12.0))
		_:
			var c := shot_color(tower.kind, tower.element())
			glow.spawn(top, Vector3.ZERO, 0.14, 0.3, 0.6, Color(c, 0.8), FxArt.GLOW)
			glow.spawn(top, Vector3.ZERO, 0.08, 0.2, 0.45, Color(1, 1, 1, 0.6), FxArt.FLARE)


## The chain jumps of an attack all come right after it fires; each later
## jump starts a little later, so the lightning visibly hops along.
func _on_chain_hit(from: Vector2, creep: Creep) -> void:
	_hops += 1
	var start := Vector3(from.x, _last_end.y, from.y)
	_add_bolt(start, creep, _hops * HOP_DELAY)


func _add_bolt(a: Vector3, creep: Creep, delay: float) -> void:
	var end := hit_point(creep)
	_last_end = end
	if _bolts.size() >= MAX_BOLTS:
		return
	var bo: Bolt = _spare_bolts.pop_back() if not _spare_bolts.is_empty() else Bolt.new()
	bo.a = a
	bo.b = end
	bo.creep = creep
	bo.age = -delay
	bo.reroll = 0.0
	bo.started = false
	bo.main.resize(0)
	_bolts.append(bo)


func _update_bolts(dt: float) -> void:
	for i in range(_bolts.size() - 1, -1, -1):
		var bo := _bolts[i]
		bo.age += dt
		if bo.age >= BOLT_LIFE:
			bo.creep = null
			_bolts[i] = _bolts[_bolts.size() - 1]
			_bolts.pop_back()
			_spare_bolts.append(bo)
			continue
		if bo.age < 0.0:
			continue
		if bo.creep and bo.creep.alive() and bo.creep in game.creeps:
			bo.b = hit_point(bo.creep)
		if not bo.started:
			bo.started = true
			_hit_lightning(bo.b)
			glow.spawn(bo.a, Vector3.ZERO, 0.12, 0.35, 0.6, Color(1, 0.97, 0.8), FxArt.FLARE)
		bo.reroll -= dt
		if bo.reroll <= 0.0 or bo.main.is_empty():
			_shape_bolt(bo)
			bo.reroll = BOLT_REROLL
		_draw_bolt(bo)


## A bright core in a wider glow, with forks, and flashes at both ends.
func _draw_bolt(bo: Bolt) -> void:
	var f := bo.age / BOLT_LIFE
	var k := 1.0 - f * f
	var flick := _rng.randf_range(0.75, 1.0)
	var g := Color(LIGHTNING, 0.4 * k * flick)
	var c := Color(1.0, 0.98, 0.85, k)
	ribbons.strip(bo.main, 0.26, 0.26, g, g)
	ribbons.strip(bo.main, 0.07, 0.07, c, c, 1.0)
	for br: PackedVector3Array in [bo.branch, bo.branch2]:
		if br.size() > 1:
			ribbons.strip(br, 0.16, 0.02, g, Color(g, 0.0))
			ribbons.strip(br, 0.045, 0.01, c, Color(c, 0.2), 1.0)
	glow.draw(bo.a, 0.4 * flick, Color(1.0, 0.9, 0.6, 0.7 * k), FxArt.FLARE, _time * 3.0)
	glow.draw(bo.b, 0.65 * flick, Color(1.0, 0.9, 0.6, 0.8 * k), FxArt.FLARE, -_time * 3.0)
	glow.draw(bo.b, 0.55, Color(LIGHTNING, 0.45 * k), FxArt.GLOW)


## New jagged shape: midpoint displacement over 17 points, and one or two forks.
func _shape_bolt(bo: Bolt) -> void:
	var n := 17
	var d := bo.b - bo.a
	var length := d.length()
	bo.main.resize(n)
	bo.main[0] = bo.a
	bo.main[n - 1] = bo.b
	var amp := minf(length * 0.28, 0.7)
	var step := n - 1
	while step > 1:
		var h := step / 2
		for i in range(h, n, step):
			var mid := (bo.main[i - h] + bo.main[i + h]) * 0.5
			bo.main[i] = mid + _perp(d) * _rng.randf_range(-amp, amp)
		amp *= 0.58
		step = h
	_fork(bo.branch, bo, d, length)
	if _rng.randf() < 0.5:
		_fork(bo.branch2, bo, d, length)
	else:
		bo.branch2.resize(0)


func _fork(br: PackedVector3Array, bo: Bolt, d: Vector3, length: float) -> void:
	var from := bo.main[_rng.randi_range(4, 12)]
	var dir := (d.normalized() + _perp(d) * 0.9).normalized()
	var len := length * _rng.randf_range(0.18, 0.35)
	br.resize(5)
	for i in 5:
		var jitter := _perp(d) * _rng.randf_range(-0.05, 0.05) if i > 0 else Vector3.ZERO
		br[i] = from + dir * len * (i / 4.0) + jitter


# --- Creeps --------------------------------------------------------------------


## Status marks: stars circling stunned creeps, frost on slowed ones, flames
## on burning ones and bubbles on poisoned ones.
func _update_creeps(dt: float) -> void:
	for creep in game.creeps:
		if creep.invisible and not creep.revealed:
			continue
		var stunned := creep.stun_time > 0.0
		var slowed := creep.slow > 0.0
		var burning := creep.burn_time > 0.0
		var poisoned := not creep.poison.is_empty()
		if not (stunned or slowed or burning or poisoned):
			continue
		var at := board.creep_world_pos(creep)
		var top := board.creep_top(creep)
		var s := board.creep_scale(creep)
		if stunned:
			for i in 3:
				var ang := _time * 6.0 + i * TAU / 3.0 + creep.id
				var off := Vector3(cos(ang), 0.0, sin(ang)) * 0.26 * s
				var c := Color(1.0, 0.92, 0.4, 0.95)
				glow.draw(at + off + UP * (top + 0.12), 0.17, c, FxArt.STAR, _time * 4.0)
		if slowed and _rng.randf() < 7.0 * dt:
			var off := Vector3(_rng.randf_range(-0.3, 0.3), 0.0, _rng.randf_range(-0.3, 0.3)) * s
			var p := at + off + UP * _rng.randf_range(0.2, top)
			var c := Color(0.8, 0.94, 1.0, 0.9)
			glow.spawn(p, UP * -0.25, 0.6, 0.12, 0.04, c, FxArt.FLAKE, Vector3(0.0, 0.0, 3.0))
		if burning and _rng.randf() < 10.0 * dt:
			var off := Vector3(_rng.randf_range(-0.25, 0.25), 0.0, _rng.randf_range(-0.25, 0.25))
			var p := at + off * s + UP * top * _rng.randf_range(0.3, 0.8)
			var c := Color(1.0, 0.5, 0.12, 0.8)
			glow.spawn(p, UP * 0.9, 0.4, 0.2, 0.06, c, FxArt.FLAME, Vector3(0.0, 1.0, 0.0))
		elif poisoned and _rng.randf() < 4.0 * dt:
			var off := Vector3(_rng.randf_range(-0.25, 0.25), 0.0, _rng.randf_range(-0.25, 0.25))
			var p := at + off * s + UP * top * 0.6
			glow.spawn(p, UP * 0.5, 0.6, 0.06, 0.12, Color(0.5, 1.0, 0.3, 0.6), FxArt.RING)


## Death: a puff, coins, a soft flash, a ring on the ground and rising wisps;
## bosses get a bigger blast with golden shockwaves.
func _on_creep_killed(creep: Creep) -> void:
	var boss := creep.kind == "boss" or creep.kind == "miniboss"
	var at := hit_point(creep)
	var ground := Vector3(at.x, 0.05, at.z)
	var s := board.creep_scale(creep)
	effects.burst("puff", at, 1.8 if boss else 1.0)
	effects.burst("coins", at + UP * 0.2, 1.3 if boss else 1.0)
	glow.spawn(at, Vector3.ZERO, 0.14, 0.4 * s, 1.1 * s, Color(1.0, 0.95, 0.85, 0.6), FxArt.GLOW)
	var ring := Color(0.88, 0.85, 0.78, 0.5)
	dust.flat(ground, 0.4, 0.2, 1.3 * s, ring, FxArt.SHOCK)
	for i in 5:
		var v := UP * 1.3 + _rand_dir() * 0.3
		var c := Color(0.85, 0.95, 1.0, 0.8)
		glow.spawn(
			at + _rand_dir() * 0.15, v, 0.8, 0.12, 0.03, c, FxArt.GLOW, Vector3(0.5, 1.0, 0.0)
		)
	if not boss:
		return
	var gold := Color(1.0, 0.82, 0.4)
	glow.spawn(at, Vector3.ZERO, 0.25, 1.0, 3.2, gold, FxArt.FLARE)
	glow.flat(ground, 0.5, 0.4, 4.0, Color(gold, 0.9), FxArt.SHOCK)
	glow.flat(ground, 0.75, 0.3, 6.0, Color(gold, 0.6), FxArt.SHOCK)
	for i in 24:
		var v := _rand_dir() * 4.0 + UP * 3.0
		glow.spawn(
			at,
			v,
			_rng.randf_range(0.7, 1.2),
			0.12,
			0.03,
			gold,
			FxArt.SPARK,
			Vector3(-6.0, 1.0, 0.0)
		)
	effects.burst("sparkle", at, 2.0)
	effects.burst("dust", ground, 2.0)


# --- Helpers -----------------------------------------------------------------


## Random unit vector.
func _rand_dir() -> Vector3:
	var v := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1))
	return v.normalized() if v.length_squared() > 0.0001 else UP


## Random unit vector across d.
func _perp(d: Vector3) -> Vector3:
	var n := d.normalized()
	var v := _rand_dir()
	v -= n * v.dot(n)
	return v.normalized() if v.length_squared() > 0.0001 else n.cross(UP).normalized()


func _ang() -> float:
	return _rng.randf() * TAU


## How many particles a rate (per second) gives this frame; fewer when the
## additive batch is getting full, so a busy wave degrades gracefully.
func _count(rate: float, dt: float) -> int:
	if glow.free_slots() < ADD_SPRITES / 4:
		rate *= 0.25
	var x := rate * dt
	var n := int(x)
	return n + (1 if _rng.randf() < x - n else 0)
