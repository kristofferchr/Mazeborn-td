class_name FxRibbons
extends MeshInstance3D
## Camera-facing strips rebuilt every frame into one ArrayMesh surface (one
## draw call for all of them): projectile trails and lightning bolts. Each
## strip is a polyline that turns its flat side to the camera, with width and
## colour blended from its tail (first point) to its head (last point), and an
## optional white-hot centre line (`core`, 0..1, for bolts).
## The vertices go into preallocated packed arrays and reach the mesh with one
## add_surface_from_arrays per frame.
## Call begin() once per frame, strip() per line, then end().

const MAX_VERTS := 4000  # ceiling per frame (two per point); strips past it are dropped

var _mesh := ArrayMesh.new()
var _eye := Vector3(0, 30, 0)
var _verts := 0
var _indices := 0
var _pos := PackedVector3Array()
var _col := PackedColorArray()
var _uv := PackedVector2Array()
var _idx := PackedInt32Array()
var _arrays := []


func setup(material: Material) -> void:
	mesh = _mesh
	material_override = material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_pos.resize(MAX_VERTS)
	_col.resize(MAX_VERTS)
	_uv.resize(MAX_VERTS)
	_idx.resize(MAX_VERTS * 3)
	_arrays.resize(Mesh.ARRAY_MAX)


func begin() -> void:
	_verts = 0
	_indices = 0
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam:
		_eye = cam.global_position


func end() -> void:
	_mesh.clear_surfaces()
	if _indices == 0:
		return
	_arrays[Mesh.ARRAY_VERTEX] = _pos.slice(0, _verts)
	_arrays[Mesh.ARRAY_COLOR] = _col.slice(0, _verts)
	_arrays[Mesh.ARRAY_TEX_UV] = _uv.slice(0, _verts)
	_arrays[Mesh.ARRAY_INDEX] = _idx.slice(0, _indices)
	_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _arrays)


## Vertices written this frame.
func vertex_count() -> int:
	return _verts


func strip(
	points: PackedVector3Array,
	w_tail: float,
	w_head: float,
	c_tail: Color,
	c_head: Color,
	core := 0.0,
) -> void:
	var n := points.size()
	if n < 2 or _verts + n * 2 > MAX_VERTS:
		return
	var base := _verts
	for i in n:
		var f := float(i) / (n - 1)
		var tangent := points[mini(i + 1, n - 1)] - points[maxi(i - 1, 0)]
		var side := tangent.cross(_eye - points[i])
		var length := side.length()
		side = side / length if length > 0.00001 else Vector3.RIGHT
		side *= lerpf(w_tail, w_head, f) * 0.5
		var c := c_tail.lerp(c_head, f)
		var v := base + i * 2
		_pos[v] = points[i] - side
		_pos[v + 1] = points[i] + side
		_col[v] = c
		_col[v + 1] = c
		_uv[v] = Vector2(core, 0.0)
		_uv[v + 1] = Vector2(core, 1.0)
	for i in n - 1:
		var a := base + i * 2
		var k := _indices + i * 6
		_idx[k] = a
		_idx[k + 1] = a + 1
		_idx[k + 2] = a + 2
		_idx[k + 3] = a + 1
		_idx[k + 4] = a + 3
		_idx[k + 5] = a + 2
	_verts += n * 2
	_indices += (n - 1) * 6
