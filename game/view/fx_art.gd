class_name FxArt
extends RefCounted
## Procedural art for the combat effects, made once and shared: the sprite
## atlas (4x4 cells, alpha = shape, red = white-hot core) and small meshes for
## projectiles (arrow, boulder, ice shard, wind blade). No files needed.

## Atlas cells.
const GLOW := 0
const FLARE := 1
const STAR := 2
const RING := 3
const SPARK := 4
const SMOKE := 5
const SCORCH := 6
const LEAF := 7
const FLAKE := 8
const SHARD := 9
const FLAME := 10
const SWIRL := 11
const SHOCK := 12
const CELLS := 4
const CELL_PX := 64

static var _atlas: ImageTexture
static var _meshes: Dictionary = {}


## The sprite atlas (built on first use, about 50k pixels).
static func atlas() -> ImageTexture:
	if _atlas == null:
		var size := CELLS * CELL_PX
		var data := PackedByteArray()
		data.resize(size * size * 4)
		data.fill(0)
		for cell in 13:
			_paint(data, size, cell)
		var img := Image.create_from_data(size, size, false, Image.FORMAT_RGBA8, data)
		img.generate_mipmaps()
		_atlas = ImageTexture.create_from_image(img)
	return _atlas


static func _paint(data: PackedByteArray, size: int, cell: int) -> void:
	var ox := (cell % CELLS) * CELL_PX
	var oy := (cell / CELLS) * CELL_PX
	var half := CELL_PX * 0.5
	for y in CELL_PX:
		for x in CELL_PX:
			# -1..1 with a pixel of margin so mipmaps do not bleed.
			var p := Vector2((x + 0.5 - half) / (half - 1.5), (y + 0.5 - half) / (half - 1.5))
			var v := _shape(cell, p)
			var o := ((oy + y) * size + ox + x) * 4
			data[o] = int(clampf(v.x, 0.0, 1.0) * 255.0)
			data[o + 1] = 255
			data[o + 2] = 255
			data[o + 3] = int(clampf(v.y, 0.0, 1.0) * 255.0)


## (core, alpha) of a cell at p in -1..1.
static func _shape(cell: int, p: Vector2) -> Vector2:
	var r := p.length()
	var edge := 1.0 - smoothstep(0.85, 1.0, r)
	var ang := atan2(p.y, p.x)
	match cell:
		GLOW:
			return Vector2(exp(-r * r * 14.0), exp(-r * r * 4.0) * edge)
		FLARE:
			var rays := exp(-absf(p.y) * 30.0) * (1.0 - absf(p.x))
			rays = maxf(rays, exp(-absf(p.x) * 30.0) * (1.0 - absf(p.y)))
			var diag := exp(-absf(absf(p.x) - absf(p.y)) * 40.0) * maxf(1.0 - r * 1.6, 0.0)
			var a := maxf(maxf(rays, diag * 0.5), exp(-r * r * 9.0))
			return Vector2(exp(-r * r * 30.0) + rays * 0.6, a * edge)
		STAR:
			var k := cos(5.0 * (ang + PI / 2.0)) * 0.5 + 0.5
			var rad := lerpf(0.45, 0.95, pow(k, 3.0))
			var a := 1.0 - smoothstep(rad - 0.12, rad, r)
			return Vector2(1.0 - smoothstep(0.0, 0.4, r), a)
		RING:
			var a := exp(-pow((r - 0.8) / 0.1, 2.0))
			return Vector2(a * 0.5, a)
		SPARK:
			return Vector2(1.0 - smoothstep(0.0, 0.3, r), 1.0 - smoothstep(0.2, 0.6, r))
		SMOKE:
			var n := _wobble(ang, r, 3.0)
			var a := (1.0 - smoothstep(0.35 + 0.2 * n, 0.95, r)) * (0.75 + 0.25 * n)
			return Vector2(1.0 - r, a)
		SCORCH:
			var n := _wobble(ang, r, 5.0)
			return Vector2(0.0, (1.0 - smoothstep(0.3 + 0.25 * n, 0.95, r)) * (0.8 + 0.2 * n))
		LEAF:
			var w := 0.42 * (1.0 - p.y * p.y)  # leaf along y
			var a := 1.0 - smoothstep(w - 0.08, w, absf(p.x))
			a *= 1.0 - smoothstep(0.9, 1.0, absf(p.y))
			var rib := exp(-absf(p.x) * 30.0)
			return Vector2(1.0 - rib * 0.6, a)
		FLAKE:
			var arms := 0.0
			for i in 3:
				var dir := Vector2.from_angle(i * PI / 3.0)
				var along := absf(p.dot(dir))
				var across := absf(p.dot(dir.orthogonal()))
				arms = maxf(arms, exp(-across * 22.0) * (1.0 - smoothstep(0.75, 0.95, along)))
			return Vector2(exp(-r * r * 20.0), maxf(arms, exp(-r * r * 30.0)))
		SHARD:
			var d := absf(p.x) / 0.32 + absf(p.y)
			return Vector2(1.0 - smoothstep(0.0, 0.6, d), 1.0 - smoothstep(0.8, 1.0, d))
		FLAME:
			# Teardrop pointing up (-y in the image is the top).
			var q := Vector2(p.x, p.y - 0.25)
			var w := 0.55 * clampf((q.y + 1.2) / 1.2, 0.0, 1.0)
			if q.y > 0.0:
				w = 0.55 * sqrt(maxf(1.0 - pow(q.y / 0.7, 2.0), 0.0))
			var a := 1.0 - smoothstep(w - 0.2, w, absf(q.x))
			return Vector2(exp(-(q.x * q.x * 8.0 + pow(q.y - 0.2, 2.0) * 4.0)), a * edge)
		SWIRL:
			var arms := 0.5 + 0.5 * sin(ang * 3.0 + r * 9.0)
			var a := pow(arms, 3.0) * smoothstep(0.1, 0.4, r) * (1.0 - smoothstep(0.7, 1.0, r))
			return Vector2(a * 0.3, a)
		SHOCK:
			var a := smoothstep(0.35, 0.9, r) * (1.0 - smoothstep(0.9, 1.0, r))
			return Vector2(pow(a, 4.0), a * a)
	return Vector2.ZERO


## Smooth 0..1 wobble around a circle for ragged edges.
static func _wobble(ang: float, r: float, seed_f: float) -> float:
	var n := sin(ang * 3.0 + seed_f) * 0.5 + sin(ang * 7.0 - seed_f * 2.0) * 0.3
	n += sin(ang * 13.0 + r * 4.0) * 0.2
	return n * 0.5 + 0.5


## Material for one of the sprite batches ("fx_add" or "fx_mix").
static func sprite_material(shader_name: String) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://view/shaders/%s.gdshader" % shader_name)
	m.set_shader_parameter("atlas", atlas())
	m.set_shader_parameter("cells", float(CELLS))
	return m


## Shared projectile mesh by name: "arrow", "boulder", "meteor", "shard",
## "blade". Each has its material on the surface; it points along -Z.
static func mesh(mesh_name: String) -> ArrayMesh:
	if not _meshes.has(mesh_name):
		match mesh_name:
			"arrow":
				_meshes[mesh_name] = _arrow()
			"boulder":
				_meshes[mesh_name] = _boulder(false)
			"meteor":
				_meshes[mesh_name] = _boulder(true)
			"shard":
				_meshes[mesh_name] = _shard()
			_:
				_meshes[mesh_name] = _blade()
	return _meshes[mesh_name]


static func _vertex_material(unshaded := false, additive := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.85
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.no_depth_test = false
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	return m


## Collects primitive parts with a transform and a colour into one surface.
class Builder:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()

	func add(prim: PrimitiveMesh, xf: Transform3D, color: Color) -> void:
		var arrays := prim.get_mesh_arrays()
		var base := verts.size()
		var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var n: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		for i in v.size():
			verts.append(xf * v[i])
			normals.append((xf.basis * n[i]).normalized())
			colors.append(color)
		for i: int in arrays[Mesh.ARRAY_INDEX]:
			indices.append(base + i)

	## A flat-shaded triangle, turned to face away from the origin (the
	## shapes here are round around it).
	func tri(
		a: Vector3, b: Vector3, c: Vector3, color: Color, color_c := Color(0, 0, 0, 0)
	) -> void:
		var n := (c - a).cross(b - a).normalized()  # Godot's front faces wind clockwise
		if n.dot(a + b + c) < 0.0:
			var swap := b
			b = c
			c = swap
			n = -n
		var base := verts.size()
		for p: Vector3 in [a, b, c]:
			verts.append(p)
			normals.append(n)
		colors.append(color)
		colors.append(color)
		colors.append(color_c if color_c.a > 0.0 else color)
		indices.append_array([base, base + 1, base + 2])

	func build(material: Material) -> ArrayMesh:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_COLOR] = colors
		arrays[Mesh.ARRAY_INDEX] = indices
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		m.surface_set_material(0, material)
		return m


## Wooden shaft, iron head and two crossed fletchings; tip at -Z.
static func _arrow() -> ArrayMesh:
	var b := Builder.new()
	var shaft := BoxMesh.new()
	shaft.size = Vector3(0.026, 0.026, 0.4)
	b.add(shaft, Transform3D(), Color(0.62, 0.42, 0.22))
	var head := CylinderMesh.new()
	head.top_radius = 0.0
	head.bottom_radius = 0.05
	head.height = 0.12
	head.radial_segments = 4
	head.rings = 1
	var tip := Transform3D(Basis(Vector3.RIGHT, -PI / 2.0), Vector3(0, 0, -0.25))
	b.add(head, tip, Color(0.78, 0.8, 0.86))
	var fin := BoxMesh.new()
	fin.size = Vector3(0.006, 0.08, 0.12)
	for i in 2:
		var xf := Transform3D(Basis(Vector3.BACK, PI / 2.0 * i), Vector3(0, 0, 0.17))
		b.add(fin, xf, Color(0.95, 0.92, 0.85) if i == 0 else Color(0.85, 0.25, 0.2))
	for i in b.verts.size():
		b.verts[i] *= 1.4  # a little larger than life, so it reads from afar
	return b.build(_vertex_material())


## A lumpy low-poly rock (flat shaded); `burning` glows like a meteor.
static func _boulder(burning: bool) -> ArrayMesh:
	var sphere := SphereMesh.new()
	sphere.radius = 0.125
	sphere.height = 0.25
	sphere.radial_segments = 7
	sphere.rings = 4
	var arrays := sphere.get_mesh_arrays()
	var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for i in v.size():
		var q := v[i]
		var h := sin(q.x * 31.0 + q.y * 17.0) + sin(q.z * 23.0 - q.y * 11.0)
		v[i] = q * (1.0 + 0.16 * h)
	var b := Builder.new()
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var rocks := [Color(0.52, 0.47, 0.41), Color(0.45, 0.41, 0.36), Color(0.58, 0.53, 0.46)]
	for t in idx.size() / 3:
		var a := v[idx[t * 3]]
		var c := v[idx[t * 3 + 2]]
		var mid := v[idx[t * 3 + 1]]
		var col: Color = rocks[t % rocks.size()]
		if burning:
			col = Color(0.35, 0.16, 0.1).lerp(Color(1.0, 0.45, 0.1), float(t % 3) / 3.0)
		b.tri(a, mid, c, col)
	var m := _vertex_material()
	if burning:
		m.emission_enabled = true
		m.emission = Color(1.0, 0.35, 0.05)
		m.emission_energy_multiplier = 0.9
	return b.build(m)


## A six-sided ice crystal, long tip at -Z, pale with white tips.
static func _shard() -> ArrayMesh:
	var b := Builder.new()
	var front := Vector3(0, 0, -0.26)
	var back := Vector3(0, 0, 0.12)
	var ring: Array[Vector3] = []
	for i in 6:
		var a := TAU * i / 6.0
		ring.append(Vector3(cos(a) * 0.055, sin(a) * 0.055, -0.02))
	var body := Color(0.55, 0.85, 1.0)
	var light := Color(0.85, 0.97, 1.0)
	for i in 6:
		var p0 := ring[i]
		var p1 := ring[(i + 1) % 6]
		b.tri(p0, p1, front, light if i % 2 == 0 else body, Color(1, 1, 1))
		b.tri(p1, p0, back, body, Color(0.4, 0.7, 1.0))
	return b.build(_vertex_material(true))


## Two crossed crescents of wind, bulging forward (-Z), fading at the tips.
static func _blade() -> ArrayMesh:
	var b := Builder.new()
	var segs := 10
	for plane in 2:
		var basis := Basis(Vector3.BACK, PI / 2.0 * plane)
		for i in segs:
			var f0 := float(i) / segs
			var f1 := float(i + 1) / segs
			var p0o := basis * _crescent(f0, 0.22)
			var p1o := basis * _crescent(f1, 0.22)
			var p0i := basis * _crescent(f0, 0.22 - 0.07 * sin(PI * f0))
			var p1i := basis * _crescent(f1, 0.22 - 0.07 * sin(PI * f1))
			var c0 := Color(0.85, 0.97, 1.0, 0.15 + 0.6 * sin(PI * f0))
			var c1 := Color(0.85, 0.97, 1.0, 0.15 + 0.6 * sin(PI * f1))
			b.tri(p0o, p1o, p0i, c0, c0)
			b.colors[b.colors.size() - 2] = c1
			b.tri(p1o, p1i, p0i, c1, c0)
			b.colors[b.colors.size() - 2] = c1
	return b.build(_vertex_material(true, true))


static func _crescent(f: float, radius: float) -> Vector3:
	var a := lerpf(-1.25, 1.25, f)
	return Vector3(sin(a) * radius, 0.0, -cos(a) * radius + 0.12)
