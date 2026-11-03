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
const PATH_COLOR := Color(0.95, 0.85, 0.45, 0.55)
const OK_COLOR := Color(0.3, 1.0, 0.4, 0.5)
const BAD_COLOR := Color(1.0, 0.25, 0.2, 0.5)

var game: Game
var _towers: Dictionary = {}  # Vector2i -> Node3D
var _creeps: Dictionary = {}  # creep id -> Node3D
var _creep_models: Dictionary = {}  # creep id -> CreepArt id
var _scenes: Dictionary = {}  # path -> PackedScene
var _path_root: Node3D
var _ghost: MeshInstance3D
var _ring: MeshInstance3D
var _selection: MeshInstance3D


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
	_path_root = Node3D.new()
	add_child(_path_root)
	_ghost = _mesh(_box(Vector3(0.9, 0.9, 0.9)), OK_COLOR, true)
	_ring = _mesh(_ring_mesh(0.97, 1.0), Color(1, 1, 1, 0.6), true)
	_selection = _mesh(_ring_mesh(0.45, 0.55), Color(1.0, 0.9, 0.3, 0.9), true)
	for n: MeshInstance3D in [_ghost, _ring, _selection]:
		n.visible = false
		n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(n)
	game.path_changed.connect(_draw_path)
	game.tower_built.connect(_on_tower_built)
	game.tower_upgraded.connect(_on_tower_upgraded)
	game.tower_sold.connect(_on_tower_sold)
	game.tower_fired.connect(_on_tower_fired)
	game.creep_spawned.connect(_on_creep_spawned)
	game.creep_killed.connect(_on_creep_removed.bind(true))
	game.creep_leaked.connect(_on_creep_removed.bind(false))
	_draw_path()


## Interpolated world position of a creep (between the last two ticks).
## Flying creeps hover above the ground.
func creep_world_pos(creep: Creep) -> Vector3:
	var p := creep.prev_pos.lerp(creep.pos, clampf(game.alpha(), 0.0, 1.0))
	return Vector3(p.x, FLY_HEIGHT if creep.flying else 0.0, p.y)


## Shows the build preview (green/red) for build_kind, the selected tower, or nothing.
func show_selection(cell: Vector2i, has_selection: bool, build_kind: String) -> void:
	var tower := game.tower_at(cell) if has_selection else null
	_ghost.visible = has_selection and tower == null
	_selection.visible = tower != null
	_ring.visible = has_selection
	if not has_selection:
		return
	var ok := game.can_build(cell, build_kind)
	_ghost.position = cell_pos(cell, 0.45)
	(_ghost.material_override as StandardMaterial3D).albedo_color = OK_COLOR if ok else BAD_COLOR
	_selection.position = cell_pos(cell, 0.03)
	_ring.position = cell_pos(cell, 0.04)
	var r := tower.attack_range() if tower else float(game.tower_level_stats(build_kind).range)
	_ring.scale = Vector3(r, 1.0, r)


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
	var size := game.grid.size
	# Playfield with a subtle checkerboard so cells are visible.
	var img := Image.create(size.x, size.y, false, Image.FORMAT_RGB8)
	for x in size.x:
		for y in size.y:
			var dark := (x + y) % 2 == 0
			img.set_pixel(x, y, Color(0.33, 0.52, 0.24) if dark else Color(0.36, 0.56, 0.26))
	var field := _mesh(_plane(Vector2(size)), Color.WHITE)
	var m := field.material_override as StandardMaterial3D
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	field.position = Vector3(size.x / 2.0, 0.0, size.y / 2.0)
	add_child(field)
	# Surrounding land and a low border.
	var outer := _mesh(_plane(Vector2(size) + Vector2(40, 40)), Color(0.24, 0.38, 0.18))
	outer.position = Vector3(size.x / 2.0, -0.02, size.y / 2.0)
	add_child(outer)
	for side in 4:
		var horizontal := side < 2
		var length := size.x + 0.6 if horizontal else size.y + 0.6
		var wall := _mesh(
			_box(Vector3(length, 0.3, 0.3) if horizontal else Vector3(0.3, 0.3, length)),
			Color(0.45, 0.42, 0.38)
		)
		match side:
			0:
				wall.position = Vector3(size.x / 2.0, 0.15, -0.15)
			1:
				wall.position = Vector3(size.x / 2.0, 0.15, size.y + 0.15)
			2:
				wall.position = Vector3(-0.15, 0.15, size.y / 2.0)
			3:
				wall.position = Vector3(size.x + 0.15, 0.15, size.y / 2.0)
		add_child(wall)
	# Spawn and goal markers.
	_marker(game.grid.spawn, Color(0.85, 0.3, 0.9))
	_marker(game.grid.goal, Color(0.3, 0.6, 1.0))
	_trees()


func _marker(cell: Vector2i, color: Color) -> void:
	var tile := _mesh(_box(Vector3(0.95, 0.06, 0.95)), color)
	tile.position = cell_pos(cell, 0.03)
	add_child(tile)
	var portal := _mesh(_torus(0.32, 0.42), color)
	portal.rotation_degrees = Vector3(0, 90, 90)
	portal.position = cell_pos(cell, 0.45)
	add_child(portal)


## Trees around the playfield (decoration only, fixed seed).
func _trees() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var size := Vector2(game.grid.size)
	for i in 140:
		var p := Vector2(rng.randf_range(-8.0, size.x + 8.0), rng.randf_range(-6.0, size.y + 6.0))
		if p.x > -1.0 and p.x < size.x + 1.0 and p.y > -1.0 and p.y < size.y + 1.0:
			continue
		var file: String = TREE_MODELS[rng.randi() % TREE_MODELS.size()]
		var tree := _scene(MEDIEVAL + file).instantiate() as Node3D
		tree.scale = Vector3.ONE * rng.randf_range(1.1, 1.6)
		tree.rotation.y = rng.randf() * TAU
		tree.position = Vector3(p.x, 0.0, p.y)
		add_child(tree)


func _scene(path: String) -> PackedScene:
	if not _scenes.has(path):
		_scenes[path] = load(path)
	return _scenes[path]


func _draw_path() -> void:
	for child in _path_root.get_children():
		child.queue_free()
	var path := game.grid.path()
	var dot_mat := mat(PATH_COLOR, true)
	for i in range(1, path.size() - 1):
		var a := BoardView.cell_pos(path[i], 0.02)
		var dot := MeshInstance3D.new()
		dot.mesh = _box(Vector3(0.22, 0.02, 0.22))
		dot.material_override = dot_mat
		dot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		dot.position = a
		_path_root.add_child(dot)
		# Half-way dash towards the next cell.
		var b := BoardView.cell_pos(path[i + 1], 0.02)
		var dash := dot.duplicate() as MeshInstance3D
		dash.position = a.lerp(b, 0.5)
		dash.scale = Vector3(0.6, 1.0, 0.6)
		_path_root.add_child(dash)


## Main colour of a tower kind (also used by the HUD buttons).
static func tower_color(kind: String) -> Color:
	return TOWER_COLORS.get(kind, Color(0.62, 0.58, 0.52))


func _on_tower_built(tower: Tower) -> void:
	var root := _tower_model(tower)
	add_child(root)
	_towers[tower.cell] = root
	var full := root.scale
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
	root.scale = full * 1.25
	create_tween().tween_property(root, "scale", full, 0.2)


## KayKit model per kind; gold rings at the base show the level.
func _tower_model(tower: Tower) -> Node3D:
	var root := Node3D.new()
	root.position = cell_pos(tower.cell)
	var def: Dictionary = TOWER_MODELS.get(tower.kind, TOWER_MODELS.stone)
	var model := _scene(MEDIEVAL + str(def.file)).instantiate() as Node3D
	model.scale = Vector3.ONE * float(def.scale)
	root.add_child(model)
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


func _on_tower_fired(tower: Tower, creep: Creep, _damage: int) -> void:
	var color := tower_color(tower.kind).lightened(0.3)
	var bolt: Node3D
	if tower.kind == "cannon":
		bolt = _scene(CANNON_BALL).instantiate() as Node3D
	else:
		var glow := _mesh(_sphere(0.1), color, true)
		glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		bolt = glow
	var node_t: Node3D = _towers.get(tower.cell)
	var top: float = node_t.get_meta("top", 1.45) if node_t else 1.45
	bolt.position = cell_pos(tower.cell, top)
	add_child(bolt)
	var target := creep_world_pos(creep) + Vector3(0.0, creep_top(creep) * 0.5, 0.0)
	var tw := create_tween()
	tw.tween_property(bolt, "position", target, 0.1)
	tw.tween_callback(bolt.queue_free)
	var stats := tower.stats()
	if stats.has("splash_radius"):
		_splash(target, float(stats.splash_radius), color)
	var node: Node3D = _creeps.get(creep.id)
	if node and creep.alive():
		var body := node.get_node("Body") as Node3D
		var flash := create_tween()
		flash.tween_property(body, "scale", Vector3(1.25, 0.8, 1.25), 0.05)
		flash.tween_property(body, "scale", Vector3.ONE, 0.08)


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
