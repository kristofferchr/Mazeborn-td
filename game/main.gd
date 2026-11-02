extends Node3D
## Spike scene: WC3-style camera over a grid, a few placeholder towers and a creep walking a path.

const GRID := 12
var _creep: MeshInstance3D
var _t := 0.0


func _ready() -> void:
	var cam := Camera3D.new()
	cam.fov = 50.0
	cam.position = Vector3(GRID / 2.0, 11.0, GRID + 3.0)
	cam.rotation_degrees = Vector3(-55.0, 0.0, 0.0)
	add_child(cam)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, 30.0, 0.0)
	sun.shadow_enabled = true
	add_child(sun)

	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.35, 0.55, 0.85)
	env.environment.ambient_light_color = Color(0.6, 0.6, 0.7)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	add_child(env)

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(GRID, GRID)
	ground.mesh = plane
	ground.position = Vector3(GRID / 2.0, 0.0, GRID / 2.0)
	ground.material_override = _mat(Color(0.3, 0.55, 0.25))
	add_child(ground)

	for p: Vector2i in [Vector2i(3, 4), Vector2i(5, 7), Vector2i(8, 3), Vector2i(9, 8)]:
		var tower := MeshInstance3D.new()
		var box := CylinderMesh.new()
		box.top_radius = 0.3
		box.bottom_radius = 0.45
		box.height = 1.6
		tower.mesh = box
		tower.position = Vector3(p.x + 0.5, 0.8, p.y + 0.5)
		tower.material_override = _mat(Color(0.6, 0.55, 0.5))
		add_child(tower)

	_creep = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.3
	sphere.height = 0.6
	_creep.mesh = sphere
	_creep.material_override = _mat(Color(0.8, 0.2, 0.2))
	add_child(_creep)

	var label := Label.new()
	label.text = "Mazeborn TD - spike (Godot %s)" % Engine.get_version_info().string
	label.position = Vector2(24, 24)
	label.add_theme_font_size_override("font_size", 32)
	add_child(label)


func _process(delta: float) -> void:
	_t += delta
	_creep.position = Vector3(1.0 + fposmod(_t * 2.0, GRID - 2.0), 0.3, GRID / 2.0)


func _mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	return m
