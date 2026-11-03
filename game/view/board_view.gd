class_name BoardView
extends Node3D
## 3D view of a Game. Only reads the game state and its signals.
## Cell (x, y) is drawn at world (x + 0.5, 0, y + 0.5). Models: see CREDITS.md.

const TOWER_COLORS := {
	"stone": Color(0.62, 0.58, 0.52),
	"cannon": Color(0.42, 0.36, 0.3),
	"frost": Color(0.55, 0.8, 0.95),
	"poison": Color(0.35, 0.75, 0.25),
	"air": Color(0.95, 0.78, 0.3),
}
const MEDIEVAL := "res://assets/kaykit_medieval/"
## Tower model per kind: KayKit file, scale (fits one cell) and where shots start.
const TOWER_MODELS := {
	"stone": {"file": "building_tower_A_red.gltf", "scale": 0.82, "top": 1.7},
	"cannon": {"file": "building_tower_catapult_yellow.gltf", "scale": 0.73, "top": 1.3},
	"frost": {"file": "building_tower_B_blue.gltf", "scale": 0.69, "top": 1.6},
	"poison": {"file": "building_tower_B_green.gltf", "scale": 0.69, "top": 1.6},
	"air": {"file": "building_archeryrange_yellow.gltf", "scale": 0.57, "top": 1.0},
}
const CANNON_BALL := "res://assets/kaykit_medieval/projectile_catapult.gltf"
const TREE_MODELS := [
	"tree_single_A.gltf",
	"tree_single_B.gltf",
	"trees_A_small.gltf",
	"trees_A_medium.gltf",
	"trees_B_medium.gltf",
]
const BASE_SPEED := 1.7  # creep speed (cells/s) that plays the walk animation at 1x
const DEATH_TIME := 1.0  # seconds the death animation plays before the body sinks
const POISON_TINT := Color(0.3, 0.9, 0.2, 0.45)
const SLOW_TINT := Color(0.5, 0.8, 1.0, 0.5)
const FLY_HEIGHT := 1.1
const OK_COLOR := Color(0.35, 1.0, 0.55)
const BAD_COLOR := Color(1.0, 0.3, 0.25)
const SPAWN_COLOR := Color(0.85, 0.3, 1.0)
const GOAL_COLOR := Color(0.35, 0.7, 1.0)
const PLATEAU := 0.6  # height of the playfield above the land around it
const SHADERS := "res://view/shaders/"

var game: Game
var _towers: Dictionary = {}  # Vector2i -> Node3D
var _creeps: Dictionary = {}  # creep id -> Node3D
var _creep_models: Dictionary = {}  # creep id -> CreepArt id
var _scenes: Dictionary = {}  # path -> PackedScene
var _path: MeshInstance3D
var _ground: ShaderMaterial
var _ghosts: Dictionary = {}  # kind -> translucent preview model
var _ghost_ok := {}  # kind -> last preview colour state
var _cell: MeshInstance3D
var _ring: MeshInstance3D
var _projectiles: Dictionary = {}  # projectile id -> Node3D
var _grid_alpha := 0.05


static func cell_pos(cell: Vector2i, height := 0.0) -> Vector3:
	return Vector3(cell.x + 0.5, height, cell.y + 0.5)


## Extra size of a creep on top of its model size: the boss is bigger, the rest
## grow a little with health.
static func creep_scale(creep: Creep) -> float:
	if creep.kind == "boss":
		return 1.4
	return clampf(0.95 + creep.max_hp / 4000.0, 1.0, 1.15)


## Height of the top of a creep above its position (for the health bar).
func creep_top(creep: Creep) -> float:
	return CreepArt.top(_creep_models.get(creep.id, CreepArt.DEFAULT)) * creep_scale(creep)


static func mat(color: Color, unshaded := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	if color.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


func setup(p_game: Game) -> void:
	game = p_game
	_build_world()
	_path = MeshInstance3D.new()
	_path.material_override = _shader("path")
	_path.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_path)
	_cell = _shaded_plane(Vector2.ONE, "cell")
	_ring = _shaded_plane(Vector2(2, 2), "ring")
	for n: MeshInstance3D in [_cell, _ring]:
		n.visible = false
		add_child(n)
	game.path_changed.connect(_draw_path)
	game.tower_built.connect(_on_tower_built)
	game.tower_upgraded.connect(_on_tower_upgraded)
	game.tower_sold.connect(_on_tower_sold)
	game.tower_fired.connect(_on_tower_fired)
	game.projectile_hit.connect(_on_projectile_hit)
	game.creep_spawned.connect(_on_creep_spawned)
	game.creep_killed.connect(_on_creep_removed.bind(true))
	game.creep_leaked.connect(_on_creep_removed.bind(false))
	_draw_path()


## Interpolated world position of a creep (between the last two ticks).
## Flying creeps hover above the ground.
func creep_world_pos(creep: Creep) -> Vector3:
	var p := creep.prev_pos.lerp(creep.pos, clampf(game.alpha(), 0.0, 1.0))
	return Vector3(p.x, FLY_HEIGHT if creep.flying else 0.0, p.y)


## Shows the build preview (a translucent tower, green or red) for build_kind,
## the selected tower with its range, or nothing. The grid shows while selecting.
func show_selection(cell: Vector2i, has_selection: bool, build_kind: String) -> void:
	var tower := game.tower_at(cell) if has_selection else null
	_cell.visible = has_selection
	_ring.visible = has_selection
	for kind: String in _ghosts:
		_ghosts[kind].visible = false
	_set_grid_alpha(0.16 if has_selection and tower == null else 0.05)
	if not has_selection:
		return
	var ok := tower != null or game.can_build(cell, build_kind)
	var color := Color(1.0, 0.85, 0.35) if tower else (OK_COLOR if ok else BAD_COLOR)
	(_cell.material_override as ShaderMaterial).set_shader_parameter("color", color)
	(_ring.material_override as ShaderMaterial).set_shader_parameter("color", color)
	_cell.position = cell_pos(cell, 0.03)
	_ring.position = cell_pos(cell, 0.025)
	var r := tower.attack_range() if tower else float(game.tower_level_stats(build_kind).range)
	_ring.scale = Vector3(r, 1.0, r)
	if tower == null:
		var ghost := _ghost(build_kind)
		ghost.visible = true
		ghost.position = cell_pos(cell)
		if _ghost_ok.get(build_kind) != ok:
			_ghost_ok[build_kind] = ok
			var m := mat(Color(color, 0.45), true)
			for mesh: MeshInstance3D in ghost.find_children("*", "MeshInstance3D", true, false):
				mesh.material_override = m


func _ghost(kind: String) -> Node3D:
	if not _ghosts.has(kind):
		var ghost := tower_preview(kind)
		for mesh: MeshInstance3D in ghost.find_children("*", "MeshInstance3D", true, false):
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(ghost)
		_ghosts[kind] = ghost
	return _ghosts[kind]


func _set_grid_alpha(a: float) -> void:
	_grid_alpha = move_toward(_grid_alpha, a, 0.015)
	_ground.set_shader_parameter("grid_alpha", _grid_alpha)


func _process(_delta: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	for creep in game.creeps:
		var node: Node3D = _creeps.get(creep.id)
		if node == null:
			continue
		var p := creep_world_pos(creep)
		if creep.flying:
			p.y += sin(t * 4.0 + creep.id) * 0.08
		var dir := Vector3(creep.pos.x - creep.prev_pos.x, 0.0, creep.pos.y - creep.prev_pos.y)
		node.position = p
		if dir.length_squared() > 0.000001:
			node.rotation.y = atan2(dir.x, dir.z)
		_tint(node, creep)
	_update_projectiles()


## Overlay tint: blue while slowed, green while poisoned, none otherwise.
func _tint(node: Node3D, creep: Creep) -> void:
	var tint := Color(0, 0, 0, 0)
	if creep.slow > 0.0:
		tint = SLOW_TINT
	elif not creep.poison.is_empty():
		tint = POISON_TINT
	if tint == node.get_meta("tint", Color(0, 0, 0, 0)):
		return
	node.set_meta("tint", tint)
	var overlay: StandardMaterial3D = null
	if tint.a > 0.0:
		overlay = mat(tint, true)
	for m: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		m.material_overlay = overlay


func _build_world() -> void:
	var size := Vector2(game.grid.size)
	var noise := _noise_texture()
	# Playfield on a raised plateau with a stone trim.
	_ground = _shader("ground")
	_ground.set_shader_parameter("noise", noise)
	_ground.set_shader_parameter("field_size", size)
	var field := MeshInstance3D.new()
	field.mesh = _plane(size)
	field.material_override = _ground
	field.position = Vector3(size.x / 2.0, 0.0, size.y / 2.0)
	add_child(field)
	var trim := _mesh(_box(Vector3(size.x + 0.5, PLATEAU, size.y + 0.5)), Color(0.5, 0.48, 0.44))
	trim.position = Vector3(size.x / 2.0, -PLATEAU / 2.0 - 0.01, size.y / 2.0)
	(trim.material_override as StandardMaterial3D).roughness = 0.9
	add_child(trim)
	var cliff := _mesh(_box(Vector3(size.x + 1.1, 0.25, size.y + 1.1)), Color(0.33, 0.3, 0.26))
	cliff.position = Vector3(size.x / 2.0, -PLATEAU + 0.12, size.y / 2.0)
	add_child(cliff)
	# Land around it.
	var outer_mat := _shader("outer")
	outer_mat.set_shader_parameter("noise", noise)
	var outer := MeshInstance3D.new()
	outer.mesh = _plane(size + Vector2(80, 80))
	outer.material_override = outer_mat
	outer.position = Vector3(size.x / 2.0, -PLATEAU, size.y / 2.0)
	add_child(outer)
	_portal(game.grid.spawn, SPAWN_COLOR, 1.0, false)
	_portal(game.grid.goal, GOAL_COLOR, -1.0, true)
	_trees()


func _noise_texture() -> NoiseTexture2D:
	var n := FastNoiseLite.new()
	n.seed = 7
	n.frequency = 0.02
	n.fractal_octaves = 3
	var tex := NoiseTexture2D.new()
	tex.width = 256
	tex.height = 256
	tex.seamless = true
	tex.generate_mipmaps = true
	tex.noise = n
	return tex


## Glowing swirl on the cell, a soft light and (for the goal) a beam of light.
func _portal(cell: Vector2i, color: Color, direction: float, beam: bool) -> void:
	var disk := _shaded_plane(Vector2(1.5, 1.5), "portal")
	var m := disk.material_override as ShaderMaterial
	m.set_shader_parameter("color", color)
	m.set_shader_parameter("direction", direction)
	disk.position = cell_pos(cell, 0.02)
	add_child(disk)
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 1.6
	light.omni_range = 2.6
	light.position = cell_pos(cell, 0.6)
	add_child(light)
	if beam:
		var b := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.45
		cyl.bottom_radius = 0.5
		cyl.height = 3.0
		cyl.cap_top = false
		cyl.cap_bottom = false
		b.mesh = cyl
		var bm := _shader("beam")
		bm.set_shader_parameter("color", color)
		b.material_override = bm
		b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		b.position = cell_pos(cell, 1.5)
		add_child(b)


func _shader(shader_name: String) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(SHADERS + shader_name + ".gdshader")
	return m


func _shaded_plane(size: Vector2, shader: String) -> MeshInstance3D:
	var n := MeshInstance3D.new()
	n.mesh = _plane(size)
	n.material_override = _shader(shader)
	n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return n


## Trees around the playfield (decoration only, fixed seed).
func _trees() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var size := Vector2(game.grid.size)
	for i in 140:
		var p := Vector2(rng.randf_range(-8.0, size.x + 8.0), rng.randf_range(-6.0, size.y + 6.0))
		if p.x > -1.6 and p.x < size.x + 1.6 and p.y > -1.6 and p.y < size.y + 1.6:
			continue
		var file: String = TREE_MODELS[rng.randi() % TREE_MODELS.size()]
		var tree := _scene(MEDIEVAL + file).instantiate() as Node3D
		tree.scale = Vector3.ONE * rng.randf_range(1.1, 1.6)
		tree.rotation.y = rng.randf() * TAU
		tree.position = Vector3(p.x, -PLATEAU, p.y)
		add_child(tree)


func _scene(path: String) -> PackedScene:
	if not _scenes.has(path):
		_scenes[path] = load(path)
	return _scenes[path]


## Ribbon along the creep path (mitred strip through the cell centres).
func _draw_path() -> void:
	var path := game.grid.path()
	if path.size() < 2:
		_path.mesh = null
		return
	var pts: Array[Vector2] = []
	for c in path:
		pts.append(Grid.center(c))
	var half := 0.22
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var dist := 0.0
	for i in pts.size():
		var prev := pts[maxi(i - 1, 0)]
		var next := pts[mini(i + 1, pts.size() - 1)]
		var dir := (next - prev).normalized()
		var normal := Vector2(-dir.y, dir.x)
		var miter := half
		if i > 0 and i < pts.size() - 1:
			var d1 := (pts[i] - prev).normalized()
			miter = half / maxf(normal.dot(Vector2(-d1.y, d1.x)), 0.5)
		if i > 0:
			dist += pts[i].distance_to(pts[i - 1])
		for side: float in [-1.0, 1.0]:
			var p := pts[i] + normal * miter * side
			verts.append(Vector3(p.x, 0.015, p.y))
			uvs.append(Vector2(dist, (side + 1.0) / 2.0))
	var idx := PackedInt32Array()
	for i in pts.size() - 1:
		var a := i * 2
		idx.append_array([a, a + 1, a + 2, a + 1, a + 3, a + 2])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_path.mesh = mesh


## Main colour of a tower kind (also used by the HUD buttons).
static func tower_color(kind: String) -> Color:
	return TOWER_COLORS.get(kind, Color(0.62, 0.58, 0.52))


func _on_tower_built(tower: Tower) -> void:
	var root := _tower_model(tower)
	add_child(root)
	_towers[tower.cell] = root
	var full := root.scale
	root.set_meta("full", full)
	root.scale = Vector3(full.x, 0.1, full.z)
	create_tween().tween_property(root, "scale", full, 0.15)


func _on_tower_upgraded(tower: Tower) -> void:
	var old: Node3D = _towers.get(tower.cell)
	if old:
		old.queue_free()
	var root := _tower_model(tower)
	add_child(root)
	_towers[tower.cell] = root
	var full := root.scale
	root.set_meta("full", full)
	root.scale = full * 1.25
	create_tween().tween_property(root, "scale", full, 0.2)


## The KayKit model of a tower kind at the origin (also used for the build
## preview and the HUD thumbnails).
func tower_preview(kind: String) -> Node3D:
	var root := Node3D.new()
	var def: Dictionary = TOWER_MODELS.get(kind, TOWER_MODELS.stone)
	var model := _scene(MEDIEVAL + str(def.file)).instantiate() as Node3D
	model.scale = Vector3.ONE * float(def.scale)
	root.add_child(model)
	root.set_meta("top", float(def.top))
	return root


## Tower model with gold rings at the base for the level.
func _tower_model(tower: Tower) -> Node3D:
	var root := tower_preview(tower.kind)
	root.position = cell_pos(tower.cell)
	var def: Dictionary = TOWER_MODELS.get(tower.kind, TOWER_MODELS.stone)

	for i in tower.level:
		var ring := _part(root, _torus(0.5, 0.57), Color(1.0, 0.8, 0.25))
		ring.position.y = 0.12 + i * 0.14
	root.set_meta("top", float(def.top))
	root.scale = Vector3.ONE * (1.0 + 0.08 * tower.level)
	return root


func _part(parent: Node3D, mesh: Mesh, color: Color, pos := Vector3.ZERO) -> MeshInstance3D:
	var m := _mesh(mesh, color)
	m.position = pos
	parent.add_child(m)
	return m


func _on_tower_sold(tower: Tower, _refund: int) -> void:
	var node: Node3D = _towers.get(tower.cell)
	_towers.erase(tower.cell)
	if node:
		node.queue_free()


## A short recoil on the tower. Shots with flight time are drawn from
## game.projectiles; instant hits get a quick bolt.
func _on_tower_fired(tower: Tower, creep: Creep, _damage: int) -> void:
	var node_t: Node3D = _towers.get(tower.cell)
	if node_t:
		var base: Vector3 = node_t.get_meta("full", node_t.scale)
		var tw := create_tween()
		tw.tween_property(node_t, "scale", base * Vector3(1.06, 0.94, 1.06), 0.05)
		tw.tween_property(node_t, "scale", base, 0.1)
	if tower.stats().has("projectile_speed"):
		return
	var bolt := _mesh(_sphere(0.1), tower_color(tower.kind).lightened(0.3), true)
	bolt.position = cell_pos(tower.cell, _tower_top(tower.cell))
	add_child(bolt)
	var tw2 := create_tween()
	tw2.tween_property(bolt, "position", _hit_point(creep), 0.1)
	tw2.tween_callback(bolt.queue_free)
	_flash(creep)


func _tower_top(cell: Vector2i) -> float:
	var node_t: Node3D = _towers.get(cell)
	if node_t == null:
		return 1.45
	return node_t.get_meta("top", 1.45) * node_t.get_meta("full", node_t.scale).y


func _hit_point(creep: Creep) -> Vector3:
	return creep_world_pos(creep) + Vector3(0.0, creep_top(creep) * 0.5, 0.0)


## Squash the creep model briefly when it is hit.
func _flash(creep: Creep) -> void:
	var node: Node3D = _creeps.get(creep.id)
	if node and creep.alive():
		var body := node.get_node("Body") as Node3D
		var flash := create_tween()
		flash.tween_property(body, "scale", Vector3(1.25, 0.8, 1.25), 0.05)
		flash.tween_property(body, "scale", Vector3.ONE, 0.08)


## Draws the projectiles in flight: interpolated, from the tower top down to
## the target, cannon balls on a high arc.
func _update_projectiles() -> void:
	var a := clampf(game.alpha(), 0.0, 1.0)
	var alive := {}
	for p in game.projectiles:
		alive[p.id] = true
		var node: Node3D = _projectiles.get(p.id)
		if node == null:
			node = _projectile_node(p)
			add_child(node)
			_projectiles[p.id] = node
		var pos := p.prev_pos.lerp(p.pos, a)
		var done: float = node.get_meta("start").distance_to(pos)
		var left := pos.distance_to(p.target_pos)
		var f := clampf(done / (done + left + 0.0001), 0.0, 1.0)
		var h0: float = node.get_meta("h0")
		var h1 := creep_top(p.target) * 0.5 + (FLY_HEIGHT if p.target.flying else 0.0)
		var arc := (0.35 if p.kind == "cannon" else 0.1) * (done + left) * sin(PI * f)
		node.position = Vector3(pos.x, lerpf(h0, h1, f) + arc, pos.y)
	for id: int in _projectiles.keys():
		if not alive.has(id):
			_projectiles[id].queue_free()
			_projectiles.erase(id)


func _projectile_node(p: Projectile) -> Node3D:
	var node: Node3D
	if p.kind == "cannon":
		node = _scene(CANNON_BALL).instantiate() as Node3D
	else:
		var color := tower_color(p.kind)
		var glow := _mesh(_sphere(0.09), color.lightened(0.45), true)
		glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var halo := _mesh(_sphere(0.18), Color(color.lightened(0.3), 0.35), true)
		halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		glow.add_child(halo)
		node = glow
	node.set_meta("start", p.pos)
	node.set_meta("h0", _tower_top(Vector2i(floori(p.pos.x), floori(p.pos.y))))
	return node


func _on_projectile_hit(p: Projectile, creep: Creep) -> void:
	if p.stats.has("splash_radius"):
		_splash(Vector3(p.pos.x, 0.0, p.pos.y), float(p.stats.splash_radius), Color(1, 0.8, 0.5))
	if creep:
		_flash(creep)


## Expanding ring where a cannon ball lands.
func _splash(at: Vector3, radius: float, color: Color) -> void:
	var ring := _mesh(_ring_mesh(0.85, 1.0), Color(color, 0.8), true)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.position = Vector3(at.x, 0.08, at.z)
	ring.scale = Vector3(0.2, 1.0, 0.2)
	add_child(ring)
	var tw := create_tween()
	tw.tween_interval(0.1)
	tw.tween_property(ring, "scale", Vector3(radius, 1.0, radius), 0.18)
	tw.tween_callback(ring.queue_free)


func _on_creep_spawned(creep: Creep) -> void:
	var model_id := CreepArt.model_for(creep.kind, game.waves, game.wave)
	var root := Node3D.new()
	var body := CreepArt.instantiate(model_id)
	root.add_child(body)
	root.scale = Vector3.ONE * creep_scale(creep)
	root.position = creep_world_pos(creep)
	add_child(root)
	_creeps[creep.id] = root
	_creep_models[creep.id] = model_id
	var player := CreepArt.player(body)
	if player:
		var walk := CreepArt.find_animation(player, CreepArt.info(model_id).walk)
		if walk != "":
			player.get_animation(walk).loop_mode = Animation.LOOP_LINEAR
			player.play(walk)
			player.speed_scale = creep.speed / BASE_SPEED
			# Spread the phase so a wave does not walk in lockstep.
			player.seek(fposmod(creep.id * 0.37, player.current_animation_length))


func _on_creep_removed(creep: Creep, killed: bool) -> void:
	var node: Node3D = _creeps.get(creep.id)
	var model_id: String = _creep_models.get(creep.id, CreepArt.DEFAULT)
	_creeps.erase(creep.id)
	_creep_models.erase(creep.id)
	if node == null:
		return
	if not killed:
		node.queue_free()
		return
	for m: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		m.material_overlay = null
	var tw := create_tween()
	var player := CreepArt.player(node)
	var death := CreepArt.find_animation(player, CreepArt.info(model_id).death) if player else ""
	if death != "":
		player.speed_scale = 1.0
		player.play(death)
		tw.tween_interval(DEATH_TIME)
	tw.tween_property(node, "scale", Vector3(1.0, 0.05, 1.0) * node.scale.x, 0.25)
	tw.tween_callback(node.queue_free)


func _mesh(mesh: Mesh, color: Color, unshaded := false) -> MeshInstance3D:
	var n := MeshInstance3D.new()
	n.mesh = mesh
	n.material_override = mat(color, unshaded)
	return n


func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


func _plane(size: Vector2) -> PlaneMesh:
	var p := PlaneMesh.new()
	p.size = size
	return p


func _sphere(radius: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0
	s.radial_segments = 16
	s.rings = 8
	return s


func _torus(inner: float, outer: float) -> TorusMesh:
	var t := TorusMesh.new()
	t.inner_radius = inner
	t.outer_radius = outer
	return t


## Thin flat ring on the ground.
func _ring_mesh(inner: float, outer: float) -> TorusMesh:
	var t := _torus(inner, outer)
	t.rings = 48
	t.ring_segments = 4
	return t
