class_name TowerArt
extends RefCounted
## Tower models. Every tower stands on an octagonal stone foundation that
## fills most of its cell, with a trim in the kind's colour, and grows wider
## and taller with the level. On top: a KayKit building per kind and level,
## starting small and growing, plus details that set the kinds apart: a banner
## on arrow towers, boulders on earth towers, turning sails and a wind ring on
## wind towers, and a stone spire with a floating, turning element crystal on
## elemental towers. Meta "top" is the height shots start from.
##
## Cheap to draw: all static parts of a tower are merged into one mesh (vertex
## colours, see shaders/tower.gdshader) and cached per kind, level and element,
## and the moving parts turn in the vertex shader. A tower is at most three
## mesh instances: the body, plus sails and a wind ring, or a crystal.

const MEDIEVAL := "res://assets/kaykit_medieval/"
const SHADER := "res://view/shaders/tower.gdshader"
## Model and scale per kind and level.
const MODELS := {
	"arrow":
	[
		["building_tower_base_yellow", 0.54],
		["building_tower_A_yellow", 0.73],
		["building_tower_B_yellow", 0.85],
	],
	"earth":
	[
		["building_mine_green", 0.47],
		["building_tower_catapult_green", 0.73],
		["building_castle_green", 0.51],
	],
	"wind":
	[
		["building_windmill_blue", 0.58],
		["building_windmill_blue", 0.79],
		["building_windmill_blue", 0.92],
	],
}
## Foundation radius and height per level.
const PLINTH := [Vector2(0.34, 0.08), Vector2(0.39, 0.13), Vector2(0.44, 0.19)]
const STONE_DARK := Color(0.34, 0.32, 0.31)
const STONE_LIGHT := Color(0.54, 0.51, 0.47)
const ARCANE_STONE := Color(0.36, 0.35, 0.44)
const EARTH_STONE := Color(0.52, 0.44, 0.34)
const TEXTURED := Color(1, 1, 1, 0)  # vertex colour that keeps the atlas texture
const BOULDERS := ["rock_single_C", "rock_single_B"]
const FLAGS := {"arrow": "flag_yellow", "earth": "flag_green", "wind": "flag_blue"}
## Shader settings of the materials: [spin, spin axis, bob].
const MOTIONS := {
	"body": [0.0, Vector3.UP, 0.0],
	"sails": [-3.5, Vector3.BACK, 0.0],
	"ring": [2.5, Vector3.UP, 0.0],
	"crystal": [2.1, Vector3.UP, 0.04],
}

static var _cache: Dictionary = {}  # "kind|level|element" -> {parts, top}
static var _mats: Dictionary = {}  # motion -> ShaderMaterial
static var _meshes: Dictionary = {}  # model file -> [Mesh, Transform3D] per mesh node
static var _tops: Dictionary = {}  # model file -> height at scale 1


## Collects mesh pieces with a transform and a vertex colour into one mesh.
class Builder:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()

	func add(mesh: Mesh, xf: Transform3D, color: Color) -> void:
		var nb := xf.basis.inverse().transposed()
		for s in mesh.get_surface_count():
			var arr := mesh.surface_get_arrays(s)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var n: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			var uv: Variant = arr[Mesh.ARRAY_TEX_UV]
			var idx: Variant = arr[Mesh.ARRAY_INDEX]
			var start := verts.size()
			for i in v.size():
				verts.append(xf * v[i])
				normals.append((nb * n[i]).normalized())
				uvs.append((uv as PackedVector2Array)[i] if uv != null else Vector2.ZERO)
				colors.append(color)
			if idx != null:
				for j: int in idx:
					indices.append(start + j)
			else:
				for j in v.size():
					indices.append(start + j)

	func commit() -> ArrayMesh:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_COLOR] = colors
		arrays[Mesh.ARRAY_INDEX] = indices
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return mesh


## A tower of `kind` at `level` (0..2) and element, at the origin.
static func build(kind: String, level: int, element: String) -> Node3D:
	level = clampi(level, 0, 2)
	var key := "%s|%d|%s" % [kind, level, element]
	if not _cache.has(key):
		_cache[key] = _make(kind, level, element)
	var art: Dictionary = _cache[key]
	var root := Node3D.new()
	for part: Array in art.parts:
		var mi := MeshInstance3D.new()
		mi.mesh = part[0]
		mi.transform = part[1]
		mi.material_override = _material(part[2])
		if not part[3]:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
	root.set_meta("top", art.top)
	return root


## Builds the meshes of a tower: [[mesh, transform, motion, casts shadow]...].
static func _make(kind: String, level: int, element: String) -> Dictionary:
	var body := Builder.new()
	var parts: Array = []
	var base := _plinth(body, kind, level)
	var top := base
	if kind == "elemental":
		top = _spire(body, parts, base, level, element)
	else:
		var art: Array = MODELS.get(kind, MODELS.arrow)[level]
		var file := str(art[0])
		var s := float(art[1])
		var place := Transform3D(Basis.from_scale(Vector3.ONE * s), Vector3(0.0, base, 0.0))
		for piece: Array in _model(file):
			var mesh: Mesh = piece[0]
			var xf: Transform3D = place * piece[1]
			if kind == "wind" and "fan" in mesh.resource_name + str(piece[2]):
				var sails := Builder.new()
				sails.add(mesh, Transform3D.IDENTITY, TEXTURED)
				parts.append([sails.commit(), xf, "sails", true])
			else:
				body.add(mesh, xf, TEXTURED)
		top = base + float(_tops[file]) * s
		match kind:
			"earth":
				_boulders(body, base, level)
				if level == 2:
					_flag(body, "earth", Vector3(0.12, top - 0.02, 0.05), 1.3)
			"wind":
				if level >= 1:
					var torus := TorusMesh.new()
					var radius := 0.34 + 0.04 * level
					torus.inner_radius = radius
					torus.outer_radius = radius + 0.02
					torus.rings = 32
					torus.ring_segments = 4
					var ring := Builder.new()
					ring.add(torus, Transform3D.IDENTITY, Color(0.75, 0.9, 1.0, 0.5))
					var at := Vector3(0.0, base + (top - base) * 0.45, 0.0)
					var tilt := Transform3D(Basis(Vector3.RIGHT, 0.25), at)
					parts.append([ring.commit(), tilt, "ring", false])
			_:
				_flag(body, kind, Vector3(0.0, top - 0.02, 0.0), 1.3 + 0.25 * level)
	parts.push_front([body.commit(), Transform3D.IDENTITY, "body", true])
	return {"parts": parts, "top": top}


## Octagonal two-tier stone foundation with a coloured trim; returns its height.
## Level 2 gets four corner stones.
static func _plinth(body: Builder, kind: String, level: int) -> float:
	var r: float = PLINTH[level].x
	var h: float = PLINTH[level].y
	var low := h * 0.5
	body.add(_prism(r + 0.04, r + 0.01, low, 8), Transform3D.IDENTITY, STONE_DARK)
	body.add(_prism(r - 0.02, r - 0.05, h - low, 8), _at(Vector3(0, low, 0)), STONE_LIGHT)
	var trim := BoardView.tower_color(kind).darkened(0.15)
	body.add(_prism(r + 0.015, r + 0.015, 0.03, 8), _at(Vector3(0, low - 0.015, 0)), trim)
	if level == 2:
		var corner := _prism(0.06, 0.045, 0.12, 4, PI / 4.0)
		for k in 4:
			var a := TAU * k / 4.0 + TAU / 8.0
			body.add(corner, _at(Vector3(cos(a) * (r - 0.05), h, sin(a) * (r - 0.05))), STONE_LIGHT)
	return h


## Elemental: a tapered stone spire with a glowing element band (and at higher
## levels a crown of fins), and a turning crystal above it (with orbiting
## shards at level 2). Returns the crystal top.
static func _spire(body: Builder, parts: Array, base: float, level: int, element: String) -> float:
	var color: Color = BoardView.ELEMENT_COLORS.get(element, BoardView.ELEMENT_COLORS[""])
	var glow := Color(color, 0.5)
	var tall := 0.62 + 0.31 * level
	var r := 0.19 + 0.035 * level
	body.add(_prism(r, r * 0.62, tall, 6), _at(Vector3(0, base, 0)), ARCANE_STONE)
	body.add(_prism(r * 0.86, r * 0.84, 0.05, 6), _at(Vector3(0, base + tall * 0.55, 0)), glow)
	var crown := base + tall
	if level >= 1:
		var fin := _prism(0.045, 0.012, 0.2 + 0.05 * level, 4)
		for k in 3 + level:
			var a := TAU * k / (3 + level)
			var b := Basis.from_euler(Vector3(sin(a) * 0.28, 0.0, -cos(a) * 0.28))
			var at := Vector3(cos(a) * r * 0.62, crown - 0.04, sin(a) * r * 0.62)
			body.add(fin, Transform3D(b, at), ARCANE_STONE)
	var size := 0.19 + 0.07 * level
	var gem := Builder.new()
	gem.add(TerrainMeshes.crystal(size * 0.42, size * 1.6), Transform3D.IDENTITY, glow)
	if level == 2:
		var shard := TerrainMeshes.crystal(0.04, 0.16)
		for k in 3:
			var a := TAU * k / 3.0
			gem.add(shard, _at(Vector3(cos(a), 0.0, sin(a)) * (size * 0.9 + 0.08)), glow)
	var y := crown + 0.12 + size * 0.4
	parts.append([gem.commit(), _at(Vector3(0, y, 0)), "crystal", false])
	return y + size


## Earth: boulders leaning against the foundation, in the cell's corners so
## they stay inside it.
static func _boulders(body: Builder, base: float, level: int) -> void:
	var dist := 0.27 + 0.015 * level
	for k in 2 + level:
		var a := TAU * k / 4.0 + PI / 4.0 + 0.5
		var piece: Array = _model(BOULDERS[k % BOULDERS.size()])[0]
		var b := Basis(Vector3.UP, a * 2.0).scaled(Vector3.ONE * (0.8 + 0.15 * level))
		var xf := Transform3D(b, Vector3(cos(a) * dist, base * 0.3, sin(a) * dist))
		body.add(piece[0], xf * piece[1], EARTH_STONE)


## A KayKit banner on a pole, its bottom at `at`.
static func _flag(body: Builder, kind: String, at: Vector3, s: float) -> void:
	var piece: Array = _model(str(FLAGS.get(kind, "flag_red")))[0]
	var b := Basis(Vector3.UP, -PI / 4.0).scaled(Vector3.ONE * s)
	body.add(piece[0], Transform3D(b, at) * piece[1], TEXTURED)


static func _at(p: Vector3) -> Transform3D:
	return Transform3D(Basis.IDENTITY, p)


static func _prism(bottom_r: float, top_r: float, h: float, sides: int, turn := PI / 8.0) -> Mesh:
	return TerrainMeshes.prism(bottom_r, top_r, h, sides, turn)


## The meshes of a KayKit model with their transforms in the model and their
## node names (cached), and the model's height in _tops.
static func _model(file: String) -> Array:
	if _meshes.has(file):
		return _meshes[file]
	var scene := (load(MEDIEVAL + file + ".gltf") as PackedScene).instantiate() as Node3D
	var pieces: Array = []
	var top := 0.0
	for mi: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
		var xf := mi.transform
		var p: Node = mi.get_parent()
		while p and p != scene:
			if p is Node3D:
				xf = (p as Node3D).transform * xf
			p = p.get_parent()
		pieces.append([mi.mesh, xf, mi.name])
		top = maxf(top, (xf * mi.get_aabb()).end.y)
	scene.free()
	_meshes[file] = pieces
	_tops[file] = top
	return pieces


static func _material(motion: String) -> ShaderMaterial:
	if not _mats.has(motion):
		var m := ShaderMaterial.new()
		m.shader = load(SHADER)
		m.set_shader_parameter("atlas", load(MEDIEVAL + "hexagons_medieval.png"))
		var spec: Array = MOTIONS[motion]
		m.set_shader_parameter("spin", spec[0])
		m.set_shader_parameter("spin_axis", spec[1])
		m.set_shader_parameter("bob", spec[2])
		_mats[motion] = m
	return _mats[motion]
