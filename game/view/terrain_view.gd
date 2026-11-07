class_name TerrainView
extends Node3D
## The land a Game is played on: the playfield on a grassy plateau with rocky
## cliffs, the rock cells, the portals, and rolling hills with a river, forests
## and small plants around it. Decoration only, with fixed seeds, so a map
## always looks the same. Scattered models share one MultiMesh per model and
## material, which keeps the draw calls low. Cell (x, y) is at world
## (x + 0.5, 0, y + 0.5); the land around the plateau lies at -PLATEAU.

const PLATEAU := 0.8  # height of the playfield above the land around it
const LIP := 0.35  # grass between the outer cells and the cliff edge
const WATER := -PLATEAU - 0.24  # river surface
const REACH := 36.0  # how far the land reaches beyond the playfield
const STEP := 0.75  # spacing of the land mesh
const RIVER_OFF := 8.0  # distance of the river behind the far edge of the map
const MEDIEVAL := "res://assets/kaykit_medieval/"
const SHADERS := "res://view/shaders/"
const MOUNTAINS := ["mountain_A", "mountain_B", "mountain_C"]
const PEBBLES := ["rock_single_A", "rock_single_B", "rock_single_D"]
const BOULDERS := ["rock_single_C", "rock_single_E"]
const SMALL_TREES := ["tree_single_A", "tree_single_B", "trees_B_small", "trees_A_small"]
const BIG_TREES := ["trees_A_medium", "trees_B_medium", "trees_A_large", "trees_B_large"]
## Leaf colours (multiplied with the leaf brightness): greens, a few autumn ones.
const LEAVES := [
	Color(0.36, 0.62, 0.24),
	Color(0.30, 0.55, 0.26),
	Color(0.44, 0.66, 0.24),
	Color(0.26, 0.48, 0.28),
	Color(0.52, 0.64, 0.22),
	Color(0.80, 0.55, 0.20),
	Color(0.72, 0.36, 0.18),
]
const GRASS := [Color(0.34, 0.56, 0.22), Color(0.42, 0.62, 0.24), Color(0.28, 0.48, 0.2)]
const FLOWERS := [
	Color(1.0, 0.86, 0.3), Color(0.98, 0.96, 0.9), Color(0.92, 0.45, 0.62), Color(0.62, 0.66, 1.0)
]
const STONES := [Color(1.0, 1.0, 1.0), Color(0.9, 0.92, 0.95), Color(1.06, 1.0, 0.92)]
const LAND_DARK := Color(0.25, 0.4, 0.17)
const LAND_LIGHT := Color(0.36, 0.5, 0.22)
const BANK := Color(0.52, 0.47, 0.34)
const FOG_TINT := Color(0.12, 0.19, 0.15)

static var _mesh_cache: Dictionary = {}  # model file -> Mesh

var game: Game
var ground: ShaderMaterial  # playfield; BoardView sets its grid_alpha
var _size := Vector2.ZERO
var _noise := FastNoiseLite.new()
var _detail := FastNoiseLite.new()
var _noise_tex: NoiseTexture2D
var _cells: Image
var _cells_tex: ImageTexture
var _batches: Dictionary = {}  # "model|material|shadow" -> [Array[Transform3D], Array[Color]]
var _rock_mat: ShaderMaterial
var _tree_mat: ShaderMaterial
var _plant_mat: ShaderMaterial


func setup(p_game: Game) -> void:
	game = p_game
	_size = Vector2(game.grid.size)
	_noise.seed = 11
	_noise.frequency = 0.055
	_noise.fractal_octaves = 3
	_detail.seed = 5
	_detail.frequency = 0.09
	_noise_tex = _noise_texture()
	_rock_mat = _shader("rock")
	_rock_mat.set_shader_parameter("noise", _noise_tex)
	_rock_mat.set_shader_parameter("floor_y", -PLATEAU - 0.4)
	_tree_mat = _shader("foliage")
	_tree_mat.set_shader_parameter("albedo_tex", load(MEDIEVAL + "hexagons_medieval.png"))
	_plant_mat = _shader("foliage")
	_plant_mat.set_shader_parameter("textured", false)
	_plant_mat.set_shader_parameter("height", 0.22)
	_build_field()
	_build_cliff()
	_build_land()
	_rock_cells()
	_cliff_rocks()
	_trees()
	_plants()
	_flush()


## Marks the cells the creeps walk on, for the worn trail on the grass.
func set_paths(paths: Array) -> void:
	_cells.fill(Color(0, 0, 0, 1))
	for cell: Vector2i in game.grid.rocks:
		_cells.set_pixelv(cell, Color(0, 1, 0, 1))
	for path: Array[Vector2i] in paths:
		for cell in path:
			var c := _cells.get_pixelv(cell)
			c.r = 1.0
			_cells.set_pixelv(cell, c)
	_cells_tex.update(_cells)


## A portal on a cell: a stone arch at the cell's outer edge with a glowing
## veil and a keystone rune, a swirl on the ground, a soft light and (for the
## goal) a beam of light. `direction` turns the swirl.
func add_portal(cell: Vector2i, color: Color, direction: float, beam: bool) -> void:
	var center := Vector3(cell.x + 0.5, 0.0, cell.y + 0.5)
	var out := _portal_side(cell)
	var arch := Node3D.new()
	arch.position = center + Vector3(out.x, 0.0, out.y) * 0.36
	arch.rotation.y = atan2(out.x, out.y)
	add_child(arch)
	for side: float in [-1.0, 1.0]:
		var foot := MeshInstance3D.new()
		foot.mesh = TerrainMeshes.prism(0.17, 0.15, 0.14, 4, PI / 4.0)
		foot.position = Vector3(side * 0.44, 0.0, 0.0)
		var pillar := MeshInstance3D.new()
		pillar.mesh = TerrainMeshes.prism(0.1, 0.085, 1.0, 4, PI / 4.0)
		pillar.position = Vector3(side * 0.44, 0.12, 0.0)
		for n: MeshInstance3D in [foot, pillar]:
			n.material_override = _rock_mat
			arch.add_child(n)
	var stone := BoxMesh.new()
	stone.size = Vector3(0.2, 0.15, 0.2)
	for k in 7:
		var a := PI * k / 6.0
		var block := MeshInstance3D.new()
		block.mesh = stone
		block.material_override = _rock_mat
		block.position = Vector3(cos(a) * 0.44, 1.12 + sin(a) * 0.36, 0.0)
		block.rotation.z = a - PI / 2.0
		arch.add_child(block)
	var rune := MeshInstance3D.new()
	var gem := BoxMesh.new()
	gem.size = Vector3(0.1, 0.1, 0.22)
	rune.mesh = gem
	rune.material_override = BoardView.mat(color.lightened(0.3), true)
	rune.position = Vector3(0.0, 1.48, 0.0)
	rune.rotation.z = PI / 4.0
	arch.add_child(rune)
	var veil := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.78, 1.3)
	veil.mesh = quad
	veil.material_override = _portal_mat(color, direction)
	veil.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	veil.position.y = 0.76
	arch.add_child(veil)
	var disk := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(1.3, 1.3)
	disk.mesh = plane
	disk.material_override = _portal_mat(color, direction)
	disk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	disk.position = center + Vector3(0.0, 0.02, 0.0)
	add_child(disk)
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 1.6
	light.omni_range = 2.6
	light.position = center + Vector3(0.0, 0.7, 0.0)
	add_child(light)
	if beam:
		var b := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.4
		cyl.bottom_radius = 0.45
		cyl.height = 3.0
		cyl.cap_top = false
		cyl.cap_bottom = false
		b.mesh = cyl
		var bm := _shader("beam")
		bm.set_shader_parameter("color", color)
		b.material_override = bm
		b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		b.position = center + Vector3(0.0, 1.5, 0.0)
		add_child(b)


func _portal_mat(color: Color, direction: float) -> ShaderMaterial:
	var m := _shader("portal")
	m.set_shader_parameter("color", color)
	m.set_shader_parameter("direction", direction)
	return m


## Which way is out of the map from a portal cell (towards the nearest edge).
func _portal_side(cell: Vector2i) -> Vector2:
	var c := Vector2(cell) + Vector2(0.5, 0.5)
	var gaps := [c.x, _size.x - c.x, c.y, _size.y - c.y]
	var sides := [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]
	var best := 0
	for i in 4:
		if gaps[i] < gaps[best]:
			best = i
	return sides[best]


## Height of the land outside the plateau (or -PLATEAU under it).
func height_at(p: Vector2) -> float:
	var d := _outside(p)
	var hills := _noise.get_noise_2dv(p) * 0.5 + 0.5
	var h := -PLATEAU + hills * hills * 4.2 * smoothstep(2.5, 15.0, d)
	h += _detail.get_noise_2d(p.x * 3.0, p.y * 3.0) * 0.1 * smoothstep(0.6, 3.0, d)
	var carve := 1.0 - smoothstep(1.0, 2.9, absf(p.y - river_z(p.x)))
	return lerpf(h, WATER - 0.45, carve)


## Middle of the river (world z) at world x: it winds behind the map.
func river_z(x: float) -> float:
	return -RIVER_OFF + sin(x * 0.19) * 1.2 + sin(x * 0.07 + 1.3) * 1.8


## Distance from p to the plateau (0 on it).
func _outside(p: Vector2) -> float:
	var half := _size / 2.0 + Vector2(LIP, LIP)
	var q := (p - _size / 2.0).abs() - half
	return Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length()


## Look hint from the map (data/maps/), e.g. "trees" or "style".
func _decor(key: String, default: Variant) -> Variant:
	return game.map.get("decor", {}).get(key, default)


func _build_field() -> void:
	_cells = Image.create(game.grid.size.x, game.grid.size.y, false, Image.FORMAT_RGBA8)
	_cells_tex = ImageTexture.create_from_image(_cells)
	ground = _shader("ground")
	ground.set_shader_parameter("noise", _noise_tex)
	ground.set_shader_parameter("cells", _cells_tex)
	ground.set_shader_parameter("field_size", _size)
	ground.set_shader_parameter("lip", LIP)
	var field := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = _size + Vector2(LIP, LIP) * 2.0
	field.mesh = plane
	field.material_override = ground
	field.position = Vector3(_size.x / 2.0, 0.0, _size.y / 2.0)
	add_child(field)
	set_paths([])


## Rough rocky cliff all around the plateau: columns of jittered vertices
## going down and slightly out from the edge, flat shaded.
func _build_cliff() -> void:
	var lo := Vector2(-LIP, -LIP)
	var hi := _size + Vector2(LIP, LIP)
	var corners: Array[Vector2] = [lo, Vector2(hi.x, lo.y), hi, Vector2(lo.x, hi.y)]
	var outs: Array[Vector2] = []
	for e in 4:
		outs.append((corners[(e + 1) % 4] - corners[e]).normalized().orthogonal())
	var ring: Array[Vector2] = []
	var ring_out: Array[Vector2] = []
	for e in 4:
		var a := corners[e]
		var b := corners[(e + 1) % 4]
		var steps := maxi(int(a.distance_to(b) / 0.32), 1)
		for s in steps:
			ring.append(a.lerp(b, float(s) / steps))
			ring_out.append((outs[e] + outs[e - 1]).normalized() if s == 0 else outs[e])
	# Row heights and how far each row sticks out.
	var rows: Array[Vector2] = [
		Vector2(0.0, 0.0),
		Vector2(-0.06, 0.06),
		Vector2(-0.24, 0.1),
		Vector2(-0.46, 0.17),
		Vector2(-0.66, 0.24),
		Vector2(-PLATEAU - 0.4, 0.4),
	]
	var cols: Array = []
	for i in ring.size():
		var col: Array[Vector3] = []
		for j in rows.size():
			var out := rows[j].y
			var y := rows[j].x
			if j >= 2 and j < rows.size() - 1:
				out += _detail.get_noise_2d(i * 2.3, j * 7.1) * 0.12
				y += _detail.get_noise_2d(i * 3.1 + 50.0, j * 5.3) * 0.06
			elif j == 1:
				out += _detail.get_noise_2d(i * 2.9, 3.0) * 0.03
			var p := ring[i] + ring_out[i] * out
			col.append(Vector3(p.x, y, p.y))
		cols.append(col)
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	for i in ring.size():
		var a: Array[Vector3] = cols[i]
		var b: Array[Vector3] = cols[(i + 1) % ring.size()]
		var out3 := Vector3(ring_out[i].x, 0.0, ring_out[i].y)
		for j in rows.size() - 1:
			_tri(verts, normals, a[j], b[j], a[j + 1], out3)
			_tri(verts, normals, b[j], b[j + 1], a[j + 1], out3)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var cliff := MeshInstance3D.new()
	cliff.mesh = mesh
	cliff.material_override = _rock_mat
	add_child(cliff)


## Adds a flat-shaded triangle facing `out` (Godot's front faces are clockwise).
static func _tri(
	verts: PackedVector3Array,
	normals: PackedVector3Array,
	a: Vector3,
	b: Vector3,
	c: Vector3,
	out: Vector3
) -> void:
	var n := (b - a).cross(c - a)
	if n.dot(out) > 0.0:
		var t := b
		b = c
		c = t
		n = -n
	verts.append_array([a, b, c])
	var face := -n.normalized()
	normals.append_array([face, face, face])


## Rolling land around the plateau (one mesh with vertex colours) and the river.
func _build_land() -> void:
	var origin := -Vector2(REACH, REACH)
	var nx := int((_size.x + REACH * 2.0) / STEP) + 1
	var nz := int((_size.y + REACH * 2.0) / STEP) + 1
	var heights := PackedFloat32Array()
	heights.resize(nx * nz)
	for j in nz:
		for i in nx:
			heights[j * nx + i] = height_at(origin + Vector2(i, j) * STEP)
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	for j in nz:
		for i in nx:
			var p := origin + Vector2(i, j) * STEP
			var h := heights[j * nx + i]
			var hl := heights[j * nx + maxi(i - 1, 0)]
			var hr := heights[j * nx + mini(i + 1, nx - 1)]
			var hd := heights[maxi(j - 1, 0) * nx + i]
			var hu := heights[mini(j + 1, nz - 1) * nx + i]
			verts.append(Vector3(p.x, h, p.y))
			normals.append(Vector3(hl - hr, 2.0 * STEP, hd - hu).normalized())
			colors.append(_land_color(p, h))
	var idx := PackedInt32Array()
	for j in nz - 1:
		for i in nx - 1:
			var a := j * nx + i
			idx.append_array([a, a + 1, a + nx, a + 1, a + nx + 1, a + nx])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var land := MeshInstance3D.new()
	land.mesh = mesh
	var m := _shader("outer")
	m.set_shader_parameter("noise", _noise_tex)
	land.material_override = m
	add_child(land)
	var water := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(_size.x + REACH * 2.0, 10.0)
	water.mesh = plane
	var wm := _shader("water")
	wm.set_shader_parameter("noise", _noise_tex)
	water.material_override = wm
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	water.position = Vector3(_size.x / 2.0, WATER, -RIVER_OFF)
	add_child(water)


## Grass shades, sandy banks and a darker, foggier look far from the map.
func _land_color(p: Vector2, h: float) -> Color:
	var n := _detail.get_noise_2dv(p * 0.6) * 0.5 + 0.5
	var c := LAND_DARK.lerp(LAND_LIGHT, smoothstep(0.25, 0.75, n))
	c = c.lerp(BANK, 1.0 - smoothstep(WATER + 0.05, WATER + 0.35, h))
	var d := _outside(p)
	c *= lerpf(0.7, 1.0, smoothstep(0.0, 1.6, d))  # shade at the foot of the cliff
	c = c.lerp(FOG_TINT, smoothstep(9.0, REACH - 4.0, d) * 0.75)
	return c


## Rock cells: tall peaks (style "mountain") or a boulder pile ("boulders"),
## varied per cell (seeded by the cell, so the map always looks the same).
func _rock_cells() -> void:
	var style := str(_decor("style", "boulders"))
	for cell: Vector2i in game.grid.rocks:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(cell) + 17
		var at := Vector3(cell.x + 0.5, 0.0, cell.y + 0.5)
		if style == "mountain":
			var file: String = MOUNTAINS[rng.randi() % MOUNTAINS.size()]
			_rock(
				file,
				at,
				rng.randf_range(0.55, 0.68),
				rng,
				Vector3(1.0, rng.randf_range(0.9, 1.25), 1.0)
			)
		else:
			if rng.randf() < 0.5:
				_rock("rock_single_C", at, rng.randf_range(3.4, 3.8), rng)
			else:
				_rock("rock_single_E", at, rng.randf_range(2.6, 2.8), rng)
		for i in rng.randi_range(2, 3):
			var off := Vector3(rng.randf_range(-0.42, 0.42), 0.0, rng.randf_range(-0.42, 0.42))
			var pebble: String = PEBBLES[rng.randi() % PEBBLES.size()]
			_rock(pebble, at + off, rng.randf_range(1.1, 1.7), rng)
		for i in rng.randi_range(1, 3):
			var off := Vector2(rng.randf_range(-0.48, 0.48), rng.randf_range(-0.48, 0.48))
			_plant(Vector3(at.x + off.x, 0.0, at.z + off.y), rng, 0.15)


## Rocks along the foot of the cliff, and boulders out in the land
## (decor "boulders").
func _cliff_rocks() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var perimeter := (_size.x + _size.y + LIP * 4.0) * 2.0
	for i in int(perimeter / 0.55):
		var p := _on_ring(rng.randf())
		var out := _ring_normal(p)
		var at := p + out * rng.randf_range(0.35, 0.75)
		var file: String = BOULDERS[rng.randi() % BOULDERS.size()]
		if rng.randf() < 0.45:
			file = PEBBLES[rng.randi() % PEBBLES.size()]
		_rock(file, Vector3(at.x, height_at(at) - 0.04, at.y), rng.randf_range(1.6, 3.4), rng)
	var placed := 0
	var tries := 0
	var want := int(_decor("boulders", 0)) + 10
	while placed < want and tries < want * 30:
		tries += 1
		var p := Vector2(
			rng.randf_range(-12.0, _size.x + 12.0), rng.randf_range(-10.0, _size.y + 10.0)
		)
		var d := _outside(p)
		var h := height_at(p)
		if d < 1.2 or h < WATER + 0.1:
			continue
		var file: String = BOULDERS[rng.randi() % BOULDERS.size()]
		_rock(file, Vector3(p.x, h - 0.05, p.y), rng.randf_range(2.2, 4.0), rng)
		placed += 1


## Point on the plateau edge, t in 0..1 around it.
func _on_ring(t: float) -> Vector2:
	var w := _size.x + LIP * 2.0
	var h := _size.y + LIP * 2.0
	var s := t * (w + h) * 2.0
	var lo := -Vector2(LIP, LIP)
	if s < w:
		return lo + Vector2(s, 0.0)
	if s < w + h:
		return lo + Vector2(w, s - w)
	if s < w * 2.0 + h:
		return lo + Vector2(w - (s - w - h), h)
	return lo + Vector2(0.0, h - (s - w * 2.0 - h))


func _ring_normal(p: Vector2) -> Vector2:
	var q := p - _size / 2.0
	var half := _size / 2.0 + Vector2(LIP, LIP)
	if absf(absf(q.x) - half.x) < absf(absf(q.y) - half.y):
		return Vector2(signf(q.x), 0.0)
	return Vector2(0.0, signf(q.y))


## Forests around the map: clumps from a noise field, small trees near the
## cliff and big clusters further out, in mixed leaf colours.
func _trees() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var forest := FastNoiseLite.new()
	forest.seed = 3
	forest.frequency = 0.08
	var target := int(_decor("trees", 140)) * 3
	var placed := 0
	var tries := 0
	var reach := REACH - 6.0
	while placed < target and tries < target * 12:
		tries += 1
		var p := Vector2(
			rng.randf_range(-reach, _size.x + reach), rng.randf_range(-reach * 0.8, _size.y + reach)
		)
		var d := _outside(p)
		var h := height_at(p)
		if d < 1.0 or h < WATER + 0.22:
			continue
		var f := forest.get_noise_2dv(p) * 0.5 + 0.5
		var density := smoothstep(0.38, 0.62, f) * 0.85 + 0.06 + smoothstep(14.0, 24.0, d) * 0.3
		density *= smoothstep(0.8, 2.2, d) * 0.6 + 0.4
		if rng.randf() > density:
			continue
		var big := d > 3.0 and rng.randf() < f
		var files: Array = BIG_TREES if big else SMALL_TREES
		var file: String = files[rng.randi() % files.size()]
		var s := rng.randf_range(1.15, 1.7) if big else rng.randf_range(1.0, 1.55)
		var leaf: Color = LEAVES[rng.randi() % (LEAVES.size() if rng.randf() < 0.25 else 5)]
		leaf = leaf * rng.randf_range(0.88, 1.1)
		var xf := Transform3D(
			Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s),
			Vector3(p.x, h - 0.05, p.y)
		)
		_add(file, "tree", xf, leaf, d < 9.0)
		placed += 1


## Grass tufts, flowers and pebbles on the grass lip and the land near the
## cliff (never on the buildable cells), and water lilies on the river.
func _plants() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var perimeter := (_size.x + _size.y) * 2.0
	for i in int(perimeter * 2.2):
		var p := _on_ring(rng.randf())
		p -= _ring_normal(p) * rng.randf_range(0.05, LIP - 0.04)
		_plant(Vector3(p.x, 0.0, p.y), rng, 0.25)
	# Water lilies along the river banks.
	for i in 70:
		var x := rng.randf_range(-REACH + 4.0, _size.x + REACH - 4.0)
		var side := 1.0 if rng.randf() < 0.5 else -1.0
		var p := Vector2(x, river_z(x) + side * rng.randf_range(0.5, 1.5))
		if height_at(p) > WATER - 0.08:
			continue
		var lily := "waterlily_A" if rng.randf() < 0.5 else "waterlily_B"
		var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(
			Vector3.ONE * rng.randf_range(2.0, 3.2)
		)
		_add(
			lily,
			"tree",
			Transform3D(b, Vector3(p.x, WATER + 0.005, p.y)),
			Color(0.5, 0.78, 0.32),
			false
		)
	for i in int(perimeter * 9.0):
		var p := Vector2(
			rng.randf_range(-10.0, _size.x + 10.0), rng.randf_range(-9.0, _size.y + 9.0)
		)
		var d := _outside(p)
		var h := height_at(p)
		if d < 0.45 or d > 9.0 or h < WATER + 0.12:
			continue
		if rng.randf() < 0.1:
			var pebble: String = PEBBLES[rng.randi() % PEBBLES.size()]
			_rock(pebble, Vector3(p.x, h, p.y), rng.randf_range(1.0, 2.0), rng)
		else:
			_plant(Vector3(p.x, h, p.y), rng, 0.3)


## A grass tuft, or with chance `flowers` a little flower clump.
func _plant(at: Vector3, rng: RandomNumberGenerator, flowers: float) -> void:
	var flower := rng.randf() < flowers
	var tint: Color = (
		FLOWERS[rng.randi() % FLOWERS.size()] if flower else GRASS[rng.randi() % GRASS.size()]
	)
	var s := rng.randf_range(0.8, 1.35)
	var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), at)
	_add("flower" if flower else "tuft", "plant", xf, tint, false)


func _rock(
	file: String, at: Vector3, s: float, rng: RandomNumberGenerator, stretch := Vector3.ONE
) -> void:
	var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(stretch * s)
	_add(file, "rock", Transform3D(b, at), STONES[rng.randi() % STONES.size()], true)


func _add(model: String, material: String, xf: Transform3D, tint: Color, shadow: bool) -> void:
	var key := "%s|%s|%s" % [model, material, shadow]
	if not _batches.has(key):
		_batches[key] = [[], []]
	_batches[key][0].append(xf)
	_batches[key][1].append(Color(tint, 1.0))


## One MultiMeshInstance3D per model, material and shadow setting.
func _flush() -> void:
	for key: String in _batches:
		var parts := key.split("|")
		var xfs: Array = _batches[key][0]
		var tints: Array = _batches[key][1]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = _model_mesh(parts[0])
		mm.instance_count = xfs.size()
		for i in xfs.size():
			mm.set_instance_transform(i, xfs[i])
			mm.set_instance_custom_data(i, tints[i])
		var node := MultiMeshInstance3D.new()
		node.multimesh = mm
		node.material_override = {"rock": _rock_mat, "tree": _tree_mat, "plant": _plant_mat}[parts[1]]
		if parts[2] != "true":
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node)
	_batches.clear()


## The mesh of a KayKit model (its first mesh), or a procedural plant.
static func _model_mesh(model: String) -> Mesh:
	if _mesh_cache.has(model):
		return _mesh_cache[model]
	var mesh: Mesh
	if model == "tuft":
		mesh = TerrainMeshes.tuft(false)
	elif model == "flower":
		mesh = TerrainMeshes.tuft(true)
	else:
		var scene := (load(MEDIEVAL + model + ".gltf") as PackedScene).instantiate()
		var mi := scene.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
		mesh = mi.mesh
		scene.free()
	_mesh_cache[model] = mesh
	return mesh


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


func _shader(shader_name: String) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(SHADERS + shader_name + ".gdshader")
	return m
