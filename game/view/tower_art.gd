class_name TowerArt
extends RefCounted
## Tower models. Every tower stands on an octagonal stone foundation that
## fills most of its cell, with a trim in the kind's colour, and grows wider
## and taller with the level. On top: a KayKit building per kind and level,
## starting small and growing, plus details that set the kinds apart: a banner
## on arrow towers, boulders on earth towers, turning sails and a wind ring on
## wind towers, and a stone spire with a floating, turning element crystal on
## elemental towers. Meta "top" is the height shots start from.

const MEDIEVAL := "res://assets/kaykit_medieval/"
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
const BOULDERS := ["rock_single_C", "rock_single_E", "rock_single_B"]
const FLAGS := {"arrow": "flag_yellow", "earth": "flag_green", "wind": "flag_blue"}

static var _scenes: Dictionary = {}  # path -> PackedScene
static var _tops: Dictionary = {}  # model file -> height at scale 1
static var _mats: Dictionary = {}  # key -> material
static var _meshes: Dictionary = {}  # key -> Mesh


## A tower of `kind` at `level` (0..2) and element, at the origin.
static func build(kind: String, level: int, element: String) -> Node3D:
	level = clampi(level, 0, 2)
	var root := Node3D.new()
	var base := _plinth(root, kind, level)
	var top := base
	if kind == "elemental":
		top = _spire(root, base, level, element)
	else:
		var art: Array = MODELS.get(kind, MODELS.arrow)[level]
		var file := str(art[0])
		var s := float(art[1])
		var model := _scene(MEDIEVAL + file + ".gltf").instantiate() as Node3D
		model.scale = Vector3.ONE * s
		model.position.y = base
		root.add_child(model)
		top = base + _model_top(file, model) * s
		match kind:
			"earth":
				_boulders(root, base, level)
				if level == 2:
					_flag(root, "earth", Vector3(0.12, top - 0.02, 0.05), 1.3)
			"wind":
				_spin_sails(model)
				if level >= 1:
					_wind_ring(root, base + (top - base) * 0.45, 0.34 + 0.04 * level)
			_:
				_flag(root, kind, Vector3(0.0, top - 0.02, 0.0), 1.3 + 0.25 * level)
	root.set_meta("top", top)
	return root


## Octagonal two-tier stone foundation with a coloured trim; returns its height.
## Level 2 gets four corner stones.
static func _plinth(root: Node3D, kind: String, level: int) -> float:
	var r: float = PLINTH[level].x
	var h: float = PLINTH[level].y
	var low := h * 0.5
	_part(root, _prism(r + 0.04, r + 0.01, low, 8), _mat("stone_dark", STONE_DARK), 0.0)
	_part(root, _prism(r - 0.02, r - 0.05, h - low, 8), _mat("stone_light", STONE_LIGHT), low)
	var trim := BoardView.tower_color(kind).darkened(0.15)
	_part(root, _prism(r + 0.015, r + 0.015, 0.03, 8), _mat("trim_" + kind, trim), low - 0.015)
	if level == 2:
		for k in 4:
			var a := TAU * k / 4.0 + TAU / 8.0
			var p := _part(
				root, _prism(0.06, 0.045, 0.12, 4, PI / 4.0), _mat("stone_light", STONE_LIGHT), h
			)
			p.position += Vector3(cos(a), 0.0, sin(a)) * (r - 0.05)
	return h


## Elemental: a tapered stone spire with an element band (and at higher levels
## a crown of fins) and a turning crystal above it. Returns the crystal top.
static func _spire(root: Node3D, base: float, level: int, element: String) -> float:
	var color: Color = BoardView.ELEMENT_COLORS.get(element, BoardView.ELEMENT_COLORS[""])
	var tall := 0.62 + 0.31 * level
	var r := 0.19 + 0.035 * level
	_part(root, _prism(r, r * 0.62, tall, 6), _mat("arcane", ARCANE_STONE), base)
	var band := _part(
		root, _prism(r * 0.86, r * 0.84, 0.05, 6), _glow_mat(color, 0.6), base + tall * 0.55
	)
	band.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var crown := base + tall
	if level >= 1:
		for k in 3 + level:
			var a := TAU * k / (3 + level)
			var fin := _part(
				root, _prism(0.045, 0.012, 0.2 + 0.05 * level, 4), _mat("arcane", ARCANE_STONE), 0.0
			)
			fin.position = Vector3(cos(a) * r * 0.62, crown - 0.04, sin(a) * r * 0.62)
			fin.rotation = Vector3(sin(a) * 0.28, 0.0, -cos(a) * 0.28)
	var size := 0.19 + 0.07 * level
	var pivot := Node3D.new()
	pivot.position.y = crown + 0.12 + size * 0.4
	root.add_child(pivot)
	var crystal := MeshInstance3D.new()
	crystal.mesh = _crystal(size * 0.42, size * 1.6)
	crystal.material_override = _glow_mat(color, 0.65)
	crystal.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pivot.add_child(crystal)
	var spin := crystal.create_tween().set_loops()
	spin.tween_property(crystal, "rotation:y", TAU, 3.0).from(0.0)
	var bob := pivot.create_tween().set_loops()
	var y := pivot.position.y
	bob.tween_property(pivot, "position:y", y + 0.08, 0.9).set_trans(Tween.TRANS_SINE)
	bob.tween_property(pivot, "position:y", y, 0.9).set_trans(Tween.TRANS_SINE)
	if level == 2:
		var orbit := Node3D.new()
		pivot.add_child(orbit)
		for k in 3:
			var shard := MeshInstance3D.new()
			shard.mesh = _crystal(0.04, 0.16)
			shard.material_override = crystal.material_override
			shard.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var a := TAU * k / 3.0
			shard.position = Vector3(cos(a), 0.0, sin(a)) * (size * 0.9 + 0.08)
			orbit.add_child(shard)
		var turn := orbit.create_tween().set_loops()
		turn.tween_property(orbit, "rotation:y", -TAU, 2.2).from(0.0)
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 0.6 + 0.3 * level
	light.omni_range = 1.6
	pivot.add_child(light)
	return pivot.position.y + size


## Earth: boulders leaning against the foundation.
static func _boulders(root: Node3D, base: float, level: int) -> void:
	var m := _mat("earth_stone", EARTH_STONE)
	for k in 2 + level:
		var a := TAU * (k + 0.3) / (2 + level) + 0.6
		var file: String = BOULDERS[k % BOULDERS.size()]
		var rock := _scene(MEDIEVAL + file + ".gltf").instantiate() as Node3D
		rock.scale = Vector3.ONE * (0.9 + 0.25 * level)
		rock.rotation.y = a * 2.0
		var r: float = PLINTH[level].x
		rock.position = Vector3(cos(a) * r * 0.9, base * 0.3, sin(a) * r * 0.9)
		for mi: MeshInstance3D in rock.find_children("*", "MeshInstance3D", true, false):
			mi.material_override = m
		root.add_child(rock)


## A KayKit banner on a pole, its bottom at `at`.
static func _flag(root: Node3D, kind: String, at: Vector3, s: float) -> void:
	var flag := (
		_scene(MEDIEVAL + str(FLAGS.get(kind, "flag_red")) + ".gltf").instantiate() as Node3D
	)
	flag.scale = Vector3.ONE * s
	flag.position = at
	flag.rotation.y = -PI / 4.0
	root.add_child(flag)


## Wind: the windmill sails turn.
static func _spin_sails(model: Node3D) -> void:
	for n: Node in model.find_children("*fan*", "Node3D", true, false):
		var fan := n as Node3D
		var tw := fan.create_tween().set_loops()
		tw.tween_property(fan, "rotation:z", fan.rotation.z - TAU, 1.8).from(fan.rotation.z)


## Wind: a pale, tilted ring of air turning around the tower.
static func _wind_ring(root: Node3D, y: float, radius: float) -> void:
	var pivot := Node3D.new()
	pivot.position.y = y
	pivot.rotation.x = 0.25
	root.add_child(pivot)
	var ring := MeshInstance3D.new()
	var t := TorusMesh.new()
	t.inner_radius = radius
	t.outer_radius = radius + 0.025
	t.rings = 32
	t.ring_segments = 4
	ring.mesh = t
	ring.material_override = _mat("wind_ring", Color(0.85, 0.95, 1.0, 0.45), true)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pivot.add_child(ring)
	var wobble := pivot.create_tween().set_loops()
	wobble.tween_property(pivot, "rotation:y", TAU, 2.5).from(0.0)


static func _part(root: Node3D, mesh: Mesh, m: Material, y: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position.y = y
	root.add_child(mi)
	return mi


static func _prism(bottom_r: float, top_r: float, h: float, sides: int, turn := PI / 8.0) -> Mesh:
	var key := "p%.3f_%.3f_%.3f_%d_%.2f" % [bottom_r, top_r, h, sides, turn]
	if not _meshes.has(key):
		_meshes[key] = TerrainMeshes.prism(bottom_r, top_r, h, sides, turn)
	return _meshes[key]


static func _crystal(radius: float, h: float) -> Mesh:
	var key := "c%.3f_%.3f" % [radius, h]
	if not _meshes.has(key):
		_meshes[key] = TerrainMeshes.crystal(radius, h)
	return _meshes[key]


static func _mat(key: String, color: Color, unshaded := false) -> StandardMaterial3D:
	if not _mats.has(key):
		var m := BoardView.mat(color, unshaded)
		m.roughness = 0.9
		_mats[key] = m
	return _mats[key]


## Bright, self-lit material in an element colour (shows through the glow).
static func _glow_mat(color: Color, energy: float) -> StandardMaterial3D:
	var key := "glow_%s_%.1f" % [color.to_html(), energy]
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color.darkened(0.15)
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = energy
		m.roughness = 0.3
		_mats[key] = m
	return _mats[key]


static func _scene(path: String) -> PackedScene:
	if not _scenes.has(path):
		_scenes[path] = load(path)
	return _scenes[path]


## Height of a model (cached per file).
static func _model_top(file: String, model: Node3D) -> float:
	if not _tops.has(file):
		var top := 0.0
		for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
			var box := mi.transform * mi.get_aabb()
			var p: Node = mi.get_parent()
			while p and p != model:
				box = (p as Node3D).transform * box if p is Node3D else box
				p = p.get_parent()
			top = maxf(top, box.end.y)
		_tops[file] = top
	return _tops[file]
