class_name Effects
extends Node3D
## One-shot particle bursts for the board: hits per tower kind and element,
## a puff and popping coins when a creep dies, dust when a tower is built or
## sold and a sparkle on upgrades. Each style has a small pool of emitters that
## are reused round-robin, so a busy wave costs the same as a quiet one.
## CPUParticles3D, which the Compatibility renderer supports.

const POOL := 6  # emitters per style
## Style: colour, particle count, size, speed, gravity (y), lifetime, upward
## spread in degrees (180 = all directions), mesh ("sphere", "box", "coin").
const STYLES := {
	"arrow": [Color(1.0, 0.85, 0.55), 5, 0.05, 2.2, -6.0, 0.3, 180.0, "box"],
	"earth": [Color(0.55, 0.43, 0.3), 10, 0.1, 3.0, -12.0, 0.6, 70.0, "box"],
	"wind": [Color(0.86, 0.95, 1.0), 7, 0.08, 2.6, 0.5, 0.35, 180.0, "sphere"],
	"elemental": [Color(0.8, 0.55, 1.0), 7, 0.06, 2.4, 0.0, 0.35, 180.0, "sphere"],
	"fire": [Color(1.0, 0.5, 0.12), 10, 0.08, 1.8, 2.5, 0.5, 90.0, "sphere"],
	"ice": [Color(0.7, 0.92, 1.0), 9, 0.06, 2.6, -8.0, 0.45, 120.0, "box"],
	"lightning": [Color(1.0, 0.95, 0.5), 8, 0.04, 4.0, -2.0, 0.22, 180.0, "box"],
	"nature": [Color(0.5, 0.95, 0.35), 8, 0.06, 1.6, -1.5, 0.6, 120.0, "box"],
	"puff": [Color(0.85, 0.83, 0.8), 12, 0.15, 1.6, 0.6, 0.55, 180.0, "sphere"],
	"coins": [Color(1.0, 0.8, 0.25), 4, 0.09, 3.2, -11.0, 0.65, 25.0, "coin"],
	"dust": [Color(0.62, 0.55, 0.45), 16, 0.13, 1.8, -0.5, 0.6, 85.0, "sphere"],
	"sparkle": [Color(1.0, 0.88, 0.45), 18, 0.06, 1.4, 2.0, 0.9, 50.0, "box"],
}

var game: Game
var board: BoardView
var _pools: Dictionary = {}  # style -> Array of CPUParticles3D
var _next: Dictionary = {}  # style -> index of the emitter to use next


## Hit style for a tower kind and element.
static func hit_style(kind: String, element := "") -> String:
	if element != "" and STYLES.has(element):
		return element
	return kind if STYLES.has(kind) else "arrow"


func setup(p_game: Game, p_board: BoardView) -> void:
	game = p_game
	board = p_board
	game.projectile_hit.connect(_on_projectile_hit)
	game.tower_fired.connect(_on_tower_fired)
	game.chain_hit.connect(func(_from: Vector2, c: Creep) -> void: burst("lightning", _at(c)))
	game.creep_killed.connect(_on_creep_killed)
	game.tower_built.connect(func(t: Tower) -> void: burst("dust", BoardView.cell_pos(t.cell)))
	game.tower_sold.connect(
		func(t: Tower, _r: int) -> void: burst("dust", BoardView.cell_pos(t.cell), 1.2)
	)
	game.tower_upgraded.connect(_on_tower_upgraded)


## Emits one burst of a style at a world position (scale grows the burst).
func burst(style: String, at: Vector3, scale_by := 1.0, color := Color(0, 0, 0, 0)) -> void:
	var p := _emitter(style)
	p.position = at
	p.scale_amount_min = 0.7 * scale_by
	p.scale_amount_max = 1.2 * scale_by
	var spec: Array = STYLES[style]
	p.initial_velocity_max = float(spec[3]) * sqrt(scale_by)
	var m := (p.mesh as PrimitiveMesh).material as StandardMaterial3D
	m.albedo_color = color if color.a > 0.0 else spec[0]
	p.restart()


func _emitter(style: String) -> CPUParticles3D:
	if not _pools.has(style):
		_pools[style] = []
		_next[style] = 0
	var pool: Array = _pools[style]
	if pool.size() < POOL:
		var made := _make(style)
		add_child(made)
		pool.append(made)
		return made
	var i: int = _next[style]
	_next[style] = (i + 1) % POOL
	return pool[i]


func _make(style: String) -> CPUParticles3D:
	var spec: Array = STYLES[style]
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.explosiveness = 0.95
	p.amount = int(spec[1])
	p.lifetime = float(spec[5])
	p.local_coords = false
	p.direction = Vector3.UP
	p.spread = float(spec[6])
	p.initial_velocity_min = float(spec[3]) * 0.45
	p.initial_velocity_max = float(spec[3])
	p.gravity = Vector3(0, float(spec[4]), 0)
	p.damping_min = 1.0
	p.damping_max = 2.0
	p.angular_velocity_min = -360.0
	p.angular_velocity_max = 360.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.12
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 1.0))
	curve.add_point(Vector2(0.6, 0.8))
	curve.add_point(Vector2(1.0, 0.0))
	p.scale_amount_curve = curve
	p.mesh = _particle_mesh(str(spec[7]), float(spec[2]))
	(p.mesh as PrimitiveMesh).material = BoardView.mat(spec[0], true)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if style == "dust" or style == "puff":
		p.emission_sphere_radius = 0.3
	return p


func _particle_mesh(kind: String, size: float) -> PrimitiveMesh:
	match kind:
		"box":
			var b := BoxMesh.new()
			b.size = Vector3.ONE * size
			return b
		"coin":
			var c := CylinderMesh.new()
			c.top_radius = size
			c.bottom_radius = size
			c.height = size * 0.35
			c.radial_segments = 10
			c.rings = 1
			return c
	var s := SphereMesh.new()
	s.radius = size * 0.5
	s.height = size
	s.radial_segments = 6
	s.rings = 3
	return s


func _at(creep: Creep) -> Vector3:
	return board.creep_world_pos(creep) + Vector3(0, board.creep_top(creep) * 0.5, 0)


func _on_projectile_hit(p: Projectile, creep: Creep) -> void:
	var style := hit_style(p.kind, p.element)
	if creep:
		burst(style, _at(creep))
	if p.stats.has("splash_radius"):
		var r := float(p.stats.splash_radius)
		burst(style, Vector3(p.pos.x, 0.1, p.pos.y), clampf(r, 1.0, 1.6))


## Instant hits (lightning without a projectile) burst on the target.
func _on_tower_fired(tower: Tower, creep: Creep, _damage: int) -> void:
	if not tower.stats().has("projectile_speed"):
		burst(hit_style(tower.kind, tower.element()), _at(creep))


func _on_creep_killed(creep: Creep) -> void:
	var boss := creep.kind == "boss"
	burst("puff", _at(creep), 1.8 if boss else 1.0)
	burst("coins", _at(creep) + Vector3(0, 0.2, 0), 1.3 if boss else 1.0)


func _on_tower_upgraded(tower: Tower) -> void:
	var color := Color(0, 0, 0, 0)
	if tower.element() != "":
		color = BoardView.ELEMENT_COLORS.get(tower.element(), color).lightened(0.3)
	burst("sparkle", BoardView.cell_pos(tower.cell, 0.4), 1.0, color)
	burst("dust", BoardView.cell_pos(tower.cell), 0.8)
