class_name TerrainMeshes
extends RefCounted
## Small procedural meshes for the terrain and the towers: grass tufts and
## flowers, crystals and stone prisms. On the plants UV.x = 1 marks the parts
## the foliage shader tints per instance (UV.x = 0 is a green stem).


## A tuft of grass blades (tinted), or with `flower` a few stems (green) with
## small heads (tinted). About 0.2 high.
static func tuft(flower: bool) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3 if flower else 1
	var blades := 4 if flower else 7
	for i in blades:
		var a := TAU * i / blades + rng.randf_range(-0.3, 0.3)
		var lean := Vector3(cos(a), 0.0, sin(a))
		var side := Vector3(-lean.z, 0.0, lean.x)
		var base := lean * rng.randf_range(0.0, 0.05)
		var tall := rng.randf_range(0.13, 0.22) if not flower else rng.randf_range(0.14, 0.2)
		var tip := base + lean * tall * 0.45 + Vector3(0.0, tall, 0.0)
		var w := 0.025 if not flower else 0.008
		_double_tri(st, base - side * w, base + side * w, tip, 0.0 if flower else 1.0)
		if flower:
			_head(st, tip, 0.035)
	st.generate_normals()
	return st.commit()


## Both faces of a triangle, so thin blades show from every side.
static func _double_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, mask: float) -> void:
	for v: Vector3 in [a, b, c, a, c, b]:
		st.set_uv(Vector2(mask, 0.0))
		st.add_vertex(v)


## Little diamond flower head at p.
static func _head(st: SurfaceTool, p: Vector3, r: float) -> void:
	var top := p + Vector3(0, r, 0)
	var bottom := p - Vector3(0, r * 0.5, 0)
	var ring: Array[Vector3] = []
	for k in 4:
		var a := TAU * k / 4.0
		ring.append(p + Vector3(cos(a), 0.0, sin(a)) * r)
	for k in 4:
		var a := ring[k]
		var b := ring[(k + 1) % 4]
		for v: Vector3 in [top, a, b, bottom, b, a]:
			st.set_uv(Vector2(1.0, 0.0))
			st.add_vertex(v)


## Pointed crystal along +y: a hexagonal bipyramid with a long top, flat shaded.
## `height` from bottom tip to top tip, centred on the widest point at y = 0.
static func crystal(radius: float, height: float, sides := 6) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	var top := Vector3(0, height * 0.65, 0)
	var bottom := Vector3(0, -height * 0.35, 0)
	for k in sides:
		var a0 := TAU * k / sides
		var a1 := TAU * (k + 1) / sides
		var p0 := Vector3(cos(a0), 0.0, sin(a0)) * radius
		var p1 := Vector3(cos(a1), 0.0, sin(a1)) * radius
		for v: Vector3 in [top, p0, p1, bottom, p1, p0]:
			st.add_vertex(v)
	st.generate_normals()
	return st.commit()


## An n-sided tapered prism (plinths, pillars), flat shaded, from y = 0 up.
static func prism(
	bottom_r: float, top_r: float, height: float, sides := 8, turn := 0.0
) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	var up := Vector3(0, height, 0)
	for k in sides:
		var a0 := TAU * k / sides + turn
		var a1 := TAU * (k + 1) / sides + turn
		var d0 := Vector3(cos(a0), 0.0, sin(a0))
		var d1 := Vector3(cos(a1), 0.0, sin(a1))
		var b0 := d0 * bottom_r
		var b1 := d1 * bottom_r
		var t0 := d0 * top_r + up
		var t1 := d1 * top_r + up
		for v: Vector3 in [b0, b1, t1, b0, t1, t0, up, t0, t1]:
			st.add_vertex(v)
	st.generate_normals()
	return st.commit()
