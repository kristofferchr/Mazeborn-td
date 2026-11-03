class_name BoardView
extends Node3D
## 3D placeholder view of a Game. Only reads the game state and its signals.
## Cell (x, y) is drawn at world (x + 0.5, 0, y + 0.5).

const TOWER_COLOR := Color(0.62, 0.58, 0.52)
const CRYSTAL_COLOR := Color(0.35, 0.75, 1.0)
const CREEP_COLOR := Color(0.85, 0.25, 0.2)
const PATH_COLOR := Color(0.95, 0.85, 0.45, 0.55)
const OK_COLOR := Color(0.3, 1.0, 0.4, 0.5)
const BAD_COLOR := Color(1.0, 0.25, 0.2, 0.5)

var game: Game
var _towers: Dictionary = {}  # Vector2i -> Node3D
var _creeps: Dictionary = {}  # creep id -> Node3D
var _path_root: Node3D
var _ghost: MeshInstance3D
var _ring: MeshInstance3D
var _selection: MeshInstance3D


static func cell_pos(cell: Vector2i, height := 0.0) -> Vector3:
	return Vector3(cell.x + 0.5, height, cell.y + 0.5)


## Placeholder size of a creep: bigger for strong creeps (boss waves).
static func creep_scale(creep: Creep) -> float:
	return clampf(0.8 + creep.max_hp / 1500.0, 0.8, 2.2)


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
	game.tower_sold.connect(_on_tower_sold)
	game.tower_fired.connect(_on_tower_fired)
	game.creep_spawned.connect(_on_creep_spawned)
	game.creep_killed.connect(_on_creep_removed.bind(true))
	game.creep_leaked.connect(_on_creep_removed.bind(false))
	_draw_path()


## Interpolated world position of a creep (between the last two ticks).
func creep_world_pos(creep: Creep) -> Vector3:
	var p := creep.prev_pos.lerp(creep.pos, clampf(game.alpha(), 0.0, 1.0))
	return Vector3(p.x, 0.0, p.y)


## Shows the build preview (green/red), the selected tower, or nothing.
func show_selection(cell: Vector2i, has_selection: bool) -> void:
	var tower := game.tower_at(cell) if has_selection else null
	_ghost.visible = has_selection and tower == null
	_selection.visible = tower != null
	_ring.visible = has_selection
	if not has_selection:
		return
	var ok := game.can_build(cell)
	_ghost.position = cell_pos(cell, 0.45)
	(_ghost.material_override as StandardMaterial3D).albedo_color = OK_COLOR if ok else BAD_COLOR
	_selection.position = cell_pos(cell, 0.03)
	_ring.position = cell_pos(cell, 0.04)
	var r := float(game.tower_stats.range)
	_ring.scale = Vector3(r, 1.0, r)


func _process(_delta: float) -> void:
	for creep in game.creeps:
		var node: Node3D = _creeps.get(creep.id)
		if node == null:
			continue
		var p := creep_world_pos(creep)
		var dir := Vector3(creep.pos.x - creep.prev_pos.x, 0.0, creep.pos.y - creep.prev_pos.y)
		node.position = p
		if dir.length_squared() > 0.000001:
			node.rotation.y = atan2(dir.x, dir.z)


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


## Placeholder trees around the playfield (decoration only, fixed seed).
func _trees() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var size := Vector2(game.grid.size)
	var leaf := mat(Color(0.16, 0.36, 0.17))
	var trunk := mat(Color(0.4, 0.28, 0.18))
	for i in 140:
		var p := Vector2(rng.randf_range(-8.0, size.x + 8.0), rng.randf_range(-6.0, size.y + 6.0))
		if p.x > -1.0 and p.x < size.x + 1.0 and p.y > -1.0 and p.y < size.y + 1.0:
			continue
		var tree := Node3D.new()
		var s := rng.randf_range(0.7, 1.3)
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = 0.55 * s
		cone.height = 1.6 * s
		var c := MeshInstance3D.new()
		c.mesh = cone
		c.material_override = leaf
		c.position.y = 0.4 + cone.height / 2.0
		tree.add_child(c)
		var stem := CylinderMesh.new()
		stem.top_radius = 0.1
		stem.bottom_radius = 0.12
		stem.height = 0.5
		var st := MeshInstance3D.new()
		st.mesh = stem
		st.material_override = trunk
		st.position.y = 0.25
		tree.add_child(st)
		tree.position = Vector3(p.x, 0.0, p.y)
		add_child(tree)


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


func _on_tower_built(tower: Tower) -> void:
	var root := Node3D.new()
	root.position = cell_pos(tower.cell)
	var base := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.28
	cyl.bottom_radius = 0.42
	cyl.height = 1.2
	base.mesh = cyl
	base.material_override = mat(TOWER_COLOR)
	base.position.y = 0.6
	root.add_child(base)
	var top := MeshInstance3D.new()
	var gem := SphereMesh.new()
	gem.radius = 0.2
	gem.height = 0.5
	top.mesh = gem
	top.material_override = mat(CRYSTAL_COLOR)
	top.position.y = 1.45
	root.add_child(top)
	add_child(root)
	_towers[tower.cell] = root
	root.scale = Vector3(1.0, 0.1, 1.0)
	create_tween().tween_property(root, "scale", Vector3.ONE, 0.15)


func _on_tower_sold(tower: Tower, _refund: int) -> void:
	var node: Node3D = _towers.get(tower.cell)
	_towers.erase(tower.cell)
	if node:
		node.queue_free()


func _on_tower_fired(tower: Tower, creep: Creep, _damage: int) -> void:
	var bolt := _mesh(_sphere(0.1), CRYSTAL_COLOR, true)
	bolt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bolt.position = cell_pos(tower.cell, 1.45)
	add_child(bolt)
	var target := creep_world_pos(creep) + Vector3(0.0, 0.35, 0.0)
	var tw := create_tween()
	tw.tween_property(bolt, "position", target, 0.1)
	tw.tween_callback(bolt.queue_free)
	var node: Node3D = _creeps.get(creep.id)
	if node and creep.alive():
		var body := node.get_child(0) as MeshInstance3D
		var flash := create_tween()
		flash.tween_property(body, "scale", Vector3(1.25, 0.8, 1.25), 0.05)
		flash.tween_property(body, "scale", Vector3.ONE, 0.08)


func _on_creep_spawned(creep: Creep) -> void:
	var root := Node3D.new()
	var body := _mesh(_sphere(0.28), CREEP_COLOR)
	body.position.y = 0.3
	root.add_child(body)
	var nose := _mesh(_box(Vector3(0.12, 0.12, 0.2)), Color(0.3, 0.1, 0.08))
	nose.position = Vector3(0.0, 0.34, 0.27)
	root.add_child(nose)
	root.scale = Vector3.ONE * creep_scale(creep)
	root.position = creep_world_pos(creep)
	add_child(root)
	_creeps[creep.id] = root


func _on_creep_removed(creep: Creep, killed: bool) -> void:
	var node: Node3D = _creeps.get(creep.id)
	_creeps.erase(creep.id)
	if node == null:
		return
	if not killed:
		node.queue_free()
		return
	var tw := create_tween()
	tw.tween_property(node, "scale", Vector3(1.4, 0.05, 1.4) * node.scale.x, 0.2)
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
