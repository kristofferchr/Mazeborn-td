class_name BoardView
extends Node3D
## 3D view of a Game. Only reads the game state and its signals.
## Cell (x, y) is drawn at world (x + 0.5, 0, y + 0.5). The land is built by
## TerrainView and the tower models by TowerArt. Models: see CREDITS.md.

const TOWER_COLORS := {
	"arrow": Color(0.95, 0.75, 0.3),
	"earth": Color(0.55, 0.45, 0.32),
	"wind": Color(0.75, 0.9, 1.0),
	"elemental": Color(0.7, 0.45, 1.0),
}
const ELEMENT_COLORS := {
	"": Color(0.7, 0.45, 1.0),
	"fire": Color(1.0, 0.45, 0.15),
	"ice": Color(0.55, 0.85, 1.0),
	"lightning": Color(1.0, 0.92, 0.35),
	"nature": Color(0.45, 0.9, 0.35),
}
const BASE_SPEED := 1.7  # creep speed (cells/s) that plays the walk animation at 1x
const DEATH_TIME := 1.0  # seconds the death animation plays before the body sinks
const POISON_TINT := Color(0.3, 0.9, 0.2, 0.45)
const BURN_TINT := Color(1.0, 0.45, 0.1, 0.5)
const STUN_TINT := Color(1.0, 1.0, 0.7, 0.6)
const SLOW_TINT := Color(0.5, 0.8, 1.0, 0.5)
const ENRAGE_TINT := Color(1.0, 0.12, 0.08, 0.45)
const SHIMMER_TINT := Color(1.0, 0.85, 0.3)  # invulnerable phase (alpha pulses)
const HEAL_COLOR := Color(0.4, 1.0, 0.5)
const SHIELD_COLOR := Color(0.4, 0.65, 1.0)
const SUMMON_COLOR := Color(0.75, 0.4, 1.0)
const SPLIT_COLOR := Color(0.6, 0.95, 0.4)
const HIDDEN_ALPHA := 0.3  # how much of an invisible creep shows while hidden
const REVEALED_ALPHA := 0.65  # ... and while a tower reveals it
const FLY_HEIGHT := 1.1
const OK_COLOR := Color(0.35, 1.0, 0.55)
const BAD_COLOR := Color(1.0, 0.3, 0.25)
const SPAWN_COLOR := Color(0.85, 0.3, 1.0)
const GOAL_COLOR := Color(0.35, 0.7, 1.0)
const SHADERS := "res://view/shaders/"

var game: Game
var effects: Effects  # particle bursts
var combat: CombatFx  # projectiles, bolts, impacts and status marks
var terrain: TerrainView  # ground, cliffs, rocks, portals and the land around
var _towers: Dictionary = {}  # Vector2i -> Node3D
var _creeps: Dictionary = {}  # creep id -> Node3D
var _creep_models: Dictionary = {}  # creep id -> CreepArt id
var _scenes: Dictionary = {}  # path -> PackedScene
var _paths: Array[MeshInstance3D] = []  # one ribbon per spawn
var _ground: ShaderMaterial
var _ghosts: Dictionary = {}  # kind -> translucent preview model
var _ghost_ok := {}  # kind -> last preview colour state
var _cell: MeshInstance3D
var _ring: MeshInstance3D
var _overlays: Dictionary = {}  # status -> shared overlay material
var _grid_alpha := 0.05


static func cell_pos(cell: Vector2i, height := 0.0) -> Vector3:
	return Vector3(cell.x + 0.5, height, cell.y + 0.5)


## Extra size of a creep on top of its model size: "scale" from the creep data
## (bosses are bigger, spawnlings small), else a little bigger with health.
func creep_scale(creep: Creep) -> float:
	var s := float(game.creep_defs.get(creep.kind, {}).get("scale", 0.0))
	if s > 0.0:
		return s
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
	for i in game.grid.spawns.size():
		var ribbon := MeshInstance3D.new()
		ribbon.material_override = _shader("path")
		ribbon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(ribbon)
		_paths.append(ribbon)
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
	game.chain_hit.connect(_on_chain_hit)
	game.creep_spawned.connect(_on_creep_spawned)
	game.creep_killed.connect(_on_creep_removed.bind(true))
	game.creep_leaked.connect(_on_creep_removed.bind(false))
	game.creep_healed.connect(
		func(c: Creep, r: float) -> void: _splash(creep_world_pos(c), r, HEAL_COLOR)
	)
	game.creep_summoned.connect(
		func(c: Creep, _kids: Array[Creep]) -> void: _splash(creep_world_pos(c), 1.4, SUMMON_COLOR)
	)
	game.creep_split.connect(
		func(c: Creep, _kids: Array[Creep]) -> void: _splash(creep_world_pos(c), 0.9, SPLIT_COLOR)
	)
	game.boss_phase.connect(
		func(c: Creep, _n: int) -> void: _splash(creep_world_pos(c), 1.8, SHIMMER_TINT)
	)
	game.boss_enraged.connect(
		func(c: Creep) -> void: _splash(creep_world_pos(c), 1.5, Color(ENRAGE_TINT, 1.0))
	)
	for key: String in ["stun", "slow", "burn", "poison", "enrage", "shimmer"]:
		var tint: Color = {
			"stun": STUN_TINT,
			"slow": SLOW_TINT,
			"burn": BURN_TINT,
			"poison": POISON_TINT,
			"enrage": ENRAGE_TINT,
			"shimmer": Color(SHIMMER_TINT, 0.5),
		}[key]
		_overlays[key] = mat(tint, true)
	effects = Effects.new()
	add_child(effects)
	effects.setup(game, self)
	combat = CombatFx.new()
	add_child(combat)
	combat.setup(game, self, effects)
	_draw_path()


## Interpolated world position of a creep (between the last two ticks).
## Flying creeps hover above the ground.
func creep_world_pos(creep: Creep) -> Vector3:
	var p := creep.prev_pos.lerp(creep.pos, clampf(game.alpha(), 0.0, 1.0))
	return Vector3(p.x, FLY_HEIGHT if creep.flying else 0.0, p.y)


## Shows the build preview (a translucent tower, green if `buildable`, else red)
## for build_kind, the selected tower with its range, or nothing. The grid
## shows while selecting.
func show_selection(
	cell: Vector2i, has_selection: bool, build_kind: String, buildable: bool
) -> void:
	var tower := game.tower_at(cell) if has_selection else null
	_cell.visible = has_selection
	_ring.visible = has_selection
	for kind: String in _ghosts:
		_ghosts[kind].visible = false
	_set_grid_alpha(0.16 if has_selection and tower == null else 0.05)
	if not has_selection:
		return
	var ok := tower != null or buildable
	var color := Color(1.0, 0.85, 0.35) if tower else (OK_COLOR if ok else BAD_COLOR)
	(_cell.material_override as ShaderMaterial).set_shader_parameter("color", color)
	(_ring.material_override as ShaderMaterial).set_shader_parameter("color", color)
	_cell.position = cell_pos(cell, 0.03)
	_ring.position = cell_pos(cell, 0.025)
	var r := tower.attack_range() if tower else float(game.tower_base_stats(build_kind).range)
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
	(_overlays.shimmer as StandardMaterial3D).albedo_color.a = 0.35 + 0.3 * sin(t * 18.0)
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
		_fade(node, creep)
		var bubble: Node3D = node.get_node_or_null("Shield")
		if bubble:
			bubble.visible = creep.shield > 0.0


## Overlay tint: a shimmer while invulnerable, then stun, slow, burn, poison,
## and red while enraged; none otherwise.
func _tint(node: Node3D, creep: Creep) -> void:
	var key := ""
	if creep.invulnerable_time > 0.0:
		key = "shimmer"
	elif creep.stun_time > 0.0:
		key = "stun"
	elif creep.slow > 0.0:
		key = "slow"
	elif creep.burn_time > 0.0:
		key = "burn"
	elif not creep.poison.is_empty():
		key = "poison"
	elif creep.enraged:
		key = "enrage"
	if key == node.get_meta("tint", ""):
		return
	node.set_meta("tint", key)
	var overlay: StandardMaterial3D = _overlays.get(key)
	for m: MeshInstance3D in _body_meshes(node):
		m.material_overlay = overlay


## Invisible creeps are see-through: faint while hidden, clearer while revealed.
## Their materials are swapped for transparent copies (the Compatibility
## renderer ignores GeometryInstance3D.transparency).
func _fade(node: Node3D, creep: Creep) -> void:
	if not creep.invisible:
		return
	var alpha := REVEALED_ALPHA if creep.revealed else HIDDEN_ALPHA
	if is_equal_approx(alpha, node.get_meta("alpha", 1.0)):
		return
	node.set_meta("alpha", alpha)
	for m: MeshInstance3D in _body_meshes(node):
		for i in m.mesh.get_surface_count():
			var faded := m.get_surface_override_material(i) as BaseMaterial3D
			if faded == null or not faded.has_meta("faded"):
				var source := m.get_active_material(i) as BaseMaterial3D
				if source == null:
					continue
				faded = source.duplicate() as BaseMaterial3D
				faded.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				faded.set_meta("faded", true)
				m.set_surface_override_material(i, faded)
			faded.albedo_color.a = alpha


func _body_meshes(node: Node3D) -> Array[Node]:
	return node.get_node("Body").find_children("*", "MeshInstance3D", true, false)


func _build_world() -> void:
	terrain = TerrainView.new()
	add_child(terrain)
	terrain.setup(game)
	_ground = terrain.ground
	for s in game.grid.spawns:
		terrain.add_portal(s, SPAWN_COLOR, 1.0, false)
	terrain.add_portal(game.grid.goal, GOAL_COLOR, -1.0, true)


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


func _scene(path: String) -> PackedScene:
	if not _scenes.has(path):
		_scenes[path] = load(path)
	return _scenes[path]


## Ribbons along the creep paths, one per spawn. Where a path joins an earlier
## one and walks the same cells from there to the goal, it stops at the join,
## so shared stretches are drawn once.
func _draw_path() -> void:
	var paths: Array = []
	for i in _paths.size():
		paths.append(game.grid.path(i))
	var cuts := ribbon_cuts(paths)
	for i in _paths.size():
		var path: Array[Vector2i] = paths[i]
		_paths[i].mesh = _ribbon(path.slice(0, cuts[i]))
	terrain.set_paths(paths)


## How many cells of each path to draw: all of it, or up to and including the
## first cell from which it follows an earlier path to the end.
static func ribbon_cuts(paths: Array) -> Array[int]:
	var cuts: Array[int] = []
	for i in paths.size():
		var path: Array[Vector2i] = paths[i]
		var cut := path.size()
		for j in path.size():
			if _joins(path, j, paths.slice(0, i)):
				cut = j + 1
				break
		cuts.append(cut)
	return cuts


## True if path from index j on is the rest of one of the earlier paths.
static func _joins(path: Array[Vector2i], j: int, earlier: Array) -> bool:
	for other: Array[Vector2i] in earlier:
		var k := other.find(path[j])
		if k >= 0 and other.slice(k) == path.slice(j):
			return true
	return false


## Mitred strip through the cell centres of a path, or null if too short.
func _ribbon(path: Array[Vector2i]) -> ArrayMesh:
	if path.size() < 2:
		return null
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
	return mesh


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


## Tower model at the origin for a kind, level and element (also used for the
## build preview and the HUD thumbnails). Meta "top" is where shots start.
func tower_preview(kind: String, level := 0, element := "") -> Node3D:
	return TowerArt.build(kind, level, element)


## Tower model on its cell; the model itself shows the level.
func _tower_model(tower: Tower) -> Node3D:
	var root := tower_preview(tower.kind, tower.level, tower.element())
	root.position = cell_pos(tower.cell)
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


## A short recoil on the tower; instant hits (lightning) squash the creep.
## Shots and bolts are drawn by CombatFx.
func _on_tower_fired(tower: Tower, creep: Creep, _damage: int) -> void:
	var node_t: Node3D = _towers.get(tower.cell)
	if node_t:
		var base: Vector3 = node_t.get_meta("full", node_t.scale)
		var tw := create_tween()
		tw.tween_property(node_t, "scale", base * Vector3(1.06, 0.94, 1.06), 0.05)
		tw.tween_property(node_t, "scale", base, 0.1)
	if not tower.stats().has("projectile_speed"):
		_flash(creep)


## Height above the ground where a tower's shots start.
func tower_top(cell: Vector2i) -> float:
	var node_t: Node3D = _towers.get(cell)
	if node_t == null:
		return 1.45
	return node_t.get_meta("top", 1.45) * node_t.get_meta("full", node_t.scale).y


## Squash the creep model briefly when it is hit.
func _flash(creep: Creep) -> void:
	var node: Node3D = _creeps.get(creep.id)
	if node and creep.alive():
		var body := node.get_node("Body") as Node3D
		var flash := create_tween()
		flash.tween_property(body, "scale", Vector3(1.25, 0.8, 1.25), 0.05)
		flash.tween_property(body, "scale", Vector3.ONE, 0.08)


func _on_chain_hit(_from: Vector2, creep: Creep) -> void:
	_flash(creep)


func _on_projectile_hit(_p: Projectile, creep: Creep) -> void:
	if creep:
		_flash(creep)


## Expanding ring on the ground (heal pulses, summons, boss phases).
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
	var model_id := CreepArt.model_of(creep, game.waves, game.wave)
	var root := Node3D.new()
	var body := CreepArt.instantiate(model_id)
	root.add_child(body)
	root.scale = Vector3.ONE * creep_scale(creep)
	_ability_marks(root, creep, CreepArt.top(model_id))
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


## Marks that stay with a creep: a faint ring for a healer's reach and a
## bubble while its shield holds.
func _ability_marks(root: Node3D, creep: Creep, top: float) -> void:
	var s := creep_scale(creep)
	if creep.abilities.has("heal"):
		var r := float(creep.abilities.heal.get("radius", 2.0)) / s
		var ring := _mesh(_ring_mesh(0.9, 1.0), Color(HEAL_COLOR, 0.25), true)
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ring.scale = Vector3(r, 1.0, r)
		ring.position.y = 0.06 / s
		root.add_child(ring)
	if creep.max_shield > 0.0:
		var bubble := _mesh(_sphere(top * 0.62), Color(SHIELD_COLOR, 0.3), true)
		bubble.name = "Shield"
		bubble.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		bubble.position.y = top * 0.5
		root.add_child(bubble)


func _on_creep_removed(creep: Creep, killed: bool) -> void:
	var node: Node3D = _creeps.get(creep.id)
	var model_id: String = _creep_models.get(creep.id, CreepArt.DEFAULT)
	_creeps.erase(creep.id)
	if node == null or not killed:
		_creep_models.erase(creep.id)
		if node:
			node.queue_free()
		return
	# Keep the model id while the body is shown, so effects connected after
	# this handler (death puff, last damage number) still find its height.
	node.tree_exiting.connect(func() -> void: _creep_models.erase(creep.id))
	for m: MeshInstance3D in _body_meshes(node):
		m.material_overlay = null
	for child in node.get_children():
		if child.name != "Body":
			child.queue_free()
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
