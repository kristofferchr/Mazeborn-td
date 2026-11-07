class_name FxRibbons
extends MeshInstance3D
## Camera-facing strips rebuilt every frame into one ImmediateMesh (one draw
## call for all of them): projectile trails and lightning bolts. Each strip is
## a polyline that turns its flat side to the camera, with width and colour
## blended from its tail (first point) to its head (last point), and an
## optional white-hot centre line (`core`, 0..1, for bolts).
## Call begin() once per frame, strip() per line, then end().

const MAX_VERTS := 12000  # ceiling per frame; strips past it are dropped

var _mesh := ImmediateMesh.new()
var _open := false
var _eye := Vector3(0, 30, 0)
var _verts := 0
var _sides := PackedVector3Array()


func setup(material: Material) -> void:
	mesh = _mesh
	material_override = material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func begin() -> void:
	_mesh.clear_surfaces()
	_open = false
	_verts = 0
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam:
		_eye = cam.global_position


func end() -> void:
	if _open:
		_mesh.surface_end()
	_open = false


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
	if n < 2 or _verts + (n - 1) * 6 > MAX_VERTS:
		return
	if not _open:
		_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		_open = true
	_sides.resize(n)
	for i in n:
		var tangent := points[mini(i + 1, n - 1)] - points[maxi(i - 1, 0)]
		var side := tangent.cross(_eye - points[i])
		var len := side.length()
		side = side / len if len > 0.00001 else Vector3.RIGHT
		_sides[i] = side * (lerpf(w_tail, w_head, float(i) / (n - 1)) * 0.5)
	for i in n - 1:
		var f0 := float(i) / (n - 1)
		var f1 := float(i + 1) / (n - 1)
		var c0 := c_tail.lerp(c_head, f0)
		var c1 := c_tail.lerp(c_head, f1)
		var a0 := points[i] - _sides[i]
		var b0 := points[i] + _sides[i]
		var a1 := points[i + 1] - _sides[i + 1]
		var b1 := points[i + 1] + _sides[i + 1]
		_vertex(a0, c0, core, 0.0)
		_vertex(b0, c0, core, 1.0)
		_vertex(a1, c1, core, 0.0)
		_vertex(b0, c0, core, 1.0)
		_vertex(b1, c1, core, 1.0)
		_vertex(a1, c1, core, 0.0)
	_verts += (n - 1) * 6


func _vertex(p: Vector3, c: Color, core: float, v: float) -> void:
	_mesh.surface_set_color(c)
	_mesh.surface_set_uv(Vector2(core, v))
	_mesh.surface_add_vertex(p)
