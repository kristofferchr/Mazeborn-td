extends Node3D
## Art comparison: candidate models lined up on a field at the game's camera
## angle, scaled to a target height. Fetch the models first with
## scripts/fetch-art-candidates.sh (they go to the git-ignored res://art_candidates/).
## Usage: scripts/screenshot.sh out.png res://tools/art_lineup.tscn 30 2532x1170
## Env LINEUP_DIST sets the camera distance (game default 19), LINEUP_Z the focus row.

const ROWS := [
	{
		"z": 1.0,
		"items":
		[
			["kaykit/Skeleton_Minion.glb", 0.9],
			["kaykit/Skeleton_Warrior.glb", 0.9],
			["kaykit/Skeleton_Rogue.glb", 0.9],
			["kaykit/Skeleton_Mage.glb", 0.9],
			["kaykit/Barbarian.glb", 0.9],
			["kaykit/Knight.glb", 0.9],
			["kaykit/Mage.glb", 0.9],
			["kaykit/Rogue_Hooded.glb", 0.9],
		]
	},
	{
		"z": 3.6,
		"items":
		[
			["q_monsters/Skeleton.fbx", 0.9],
			["q_monsters/Slime.fbx", 0.6],
			["q_monsters/Bat.fbx", 0.6],
			["q_monsters/Dragon.fbx", 1.1],
			["q_easy/Spider.fbx", 0.7],
			["q_easy/Rat.fbx", 0.6],
			["q_easy/Frog.fbx", 0.6],
			["q_easy/Wasp.fbx", 0.6],
			["q_easy/Snake.fbx", 0.5],
		]
	},
	{
		"z": 6.6,
		"items":
		[
			["kk_hex/building_tower_A_blue.gltf", 1.7],
			["kk_hex/building_tower_B_blue.gltf", 1.7],
			["kk_hex/building_tower_catapult_blue.gltf", 1.7],
			["kk_hex/tree_single_A.gltf", 1.6],
			["kk_hex/trees_A_medium.gltf", 1.6],
		]
	},
	{
		"z": 9.4,
		"items":
		[
			["q_nature/CommonTree_2.gltf", 1.8],
			["q_nature/Pine_2.gltf", 1.9],
			["q_nature/TwistedTree_1.gltf", 1.8],
			["q_nature/DeadTree_2.gltf", 1.6],
			["q_nature/Bush_Common_Flowers.gltf", 0.7],
			["q_nature/Rock_Medium_1.gltf", 0.6],
			["q_nature/Flower_3_Group.gltf", 0.35],
		]
	},
]
const WIDTH := 18.0


func _ready() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.24, 0.38, 0.18)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.65, 0.65, 0.75)
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, 30.0, 0.0)
	sun.shadow_enabled = true
	add_child(sun)
	var field := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(WIDTH + 2.0, 12.0)
	field.mesh = plane
	field.material_override = BoardView.mat(Color(0.35, 0.54, 0.25))
	field.position = Vector3(WIDTH / 2.0, 0.0, 5.5)
	add_child(field)
	for row: Dictionary in ROWS:
		var items: Array = row.items
		for i in items.size():
			var x := (i + 0.5) * WIDTH / items.size()
			_place(items[i][0], Vector3(x, 0.0, row.z), items[i][1])
	var cam := CameraRig.new()
	add_child(cam)
	var dist: float = (
		float(OS.get_environment("LINEUP_DIST")) if OS.has_environment("LINEUP_DIST") else 19.0
	)
	cam.setup(Rect2(0, 0, WIDTH, 11.0), dist)
	cam.focus = Vector3(
		WIDTH / 2.0,
		0.0,
		float(OS.get_environment("LINEUP_Z")) if OS.has_environment("LINEUP_Z") else 5.8
	)
	cam.distance = dist
	cam._apply()
	cam.make_current()


func _place(rel: String, pos: Vector3, height: float) -> void:
	var path := "res://art_candidates/" + rel
	var res := load(path) as PackedScene
	var label := Label3D.new()
	label.text = rel.get_file().get_basename()
	label.font_size = 48
	label.pixel_size = 0.0045
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = pos + Vector3(0.0, 0.02, 0.85)
	label.outline_size = 12
	label.modulate = Color(1, 1, 0.8)
	add_child(label)
	if res == null:
		label.text += " (feil)"
		return
	var node := res.instantiate() as Node3D
	add_child(node)
	var anim := _find_anim(node)
	if anim:
		var names := anim.get_animation_list()
		var pick := ""
		for want in ["walking_a", "walk", "run", "fly", "idle"]:
			for n in names:
				if pick == "" and n.to_lower().contains(want):
					pick = n
		if pick != "":
			anim.get_animation(pick).loop_mode = Animation.LOOP_LINEAR
			anim.play(pick)
			anim.advance(0.37)
	print("%s anims=%s" % [rel, anim.get_animation_list() if anim else []])
	await get_tree().process_frame
	await get_tree().process_frame
	var aabb := _aabb(node)
	var s := height / maxf(aabb.size.y, 0.001)
	node.scale = Vector3.ONE * s
	node.position = pos - Vector3(aabb.get_center().x, aabb.position.y, aabb.get_center().z) * s
	var tris := _tris(node)
	print("STAT %s tris=%d h=%.2f" % [rel, tris, aabb.size.y])


func _find_anim(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var a := _find_anim(c)
		if a:
			return a
	return null


## World-space bounds of all meshes (skinned meshes in their current pose).
func _aabb(n: Node) -> AABB:
	var out := AABB()
	var first := true
	for m: MeshInstance3D in n.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = m.mesh
		if m.skin != null or m.skeleton != NodePath(""):
			var baked := m.bake_mesh_from_current_skeleton_pose()
			if baked:
				mesh = baked
		if mesh == null:
			continue
		var b := m.global_transform * mesh.get_aabb()
		out = b if first else out.merge(b)
		first = false
	return out


func _tris(n: Node) -> int:
	var total := 0
	for m: MeshInstance3D in n.find_children("*", "MeshInstance3D", true, false):
		if m.mesh == null:
			continue
		for si in m.mesh.get_surface_count():
			var arr := m.mesh.surface_get_arrays(si)
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			total += (
				idx.size() / 3
				if idx.size() > 0
				else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
			)
	return total
