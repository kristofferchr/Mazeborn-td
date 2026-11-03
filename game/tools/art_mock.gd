extends Node
## Art mockup: the demo scene with placeholder creeps, towers and trees swapped
## for candidate models (fetch them with scripts/fetch-art-candidates.sh).
## Env MOCK=kaykit|quaternius picks the set, MOCK_DIST zooms in near the spawn.
## Usage: MOCK=kaykit scripts/screenshot.sh out.png res://tools/art_mock.tscn 40 2532x1170

const SETS := {
	"kaykit":
	{
		"creeps":
		[
			"kaykit/Skeleton_Minion.glb",
			"kaykit/Skeleton_Warrior.glb",
			"kaykit/Skeleton_Rogue.glb",
		],
		"creep_h": 1.0,
		"tower": "kk_hex/building_tower_A_blue.gltf",
		"trees":
		["kk_hex/tree_single_A.gltf", "kk_hex/tree_single_B.gltf", "kk_hex/trees_A_medium.gltf"],
	},
	"quaternius":
	{
		"creeps": ["q_easy/Spider.fbx", "q_easy/Rat.fbx", "q_monsters/Slime.fbx"],
		"creep_h": 0.7,
		"tower": "kk_hex/building_tower_B_blue.gltf",
		"trees":
		["q_nature/CommonTree_2.gltf", "q_nature/Pine_2.gltf", "q_nature/CommonTree_4.gltf"],
	},
}

var _pending: Array = []  # [node, height, width] waiting to be scaled once posed


func _ready() -> void:
	var demo: Node = load("res://tools/demo.tscn").instantiate()
	add_child(demo)
	await get_tree().process_frame
	var set_name := OS.get_environment("MOCK") if OS.has_environment("MOCK") else "kaykit"
	var cfg: Dictionary = SETS[set_name]
	var board := _find_board(demo)
	if OS.has_environment("MOCK_DIST"):
		var cam := demo.find_children("*", "CameraRig", true, false)[0] as CameraRig
		cam.distance = float(OS.get_environment("MOCK_DIST"))
		cam.focus = Vector3(4.5, 0.0, 7.5)
		cam._apply()
	var i := 0
	for id: int in board._creeps:
		var node: Node3D = board._creeps[id]
		for c in node.get_children():
			(c as Node3D).visible = false
		var m := _model(cfg.creeps[i % cfg.creeps.size()], cfg.creep_h)
		node.add_child(m)
		_play_walk(m, i * 0.21)
		i += 1
	for cell: Vector2i in board._towers:
		var node: Node3D = board._towers[cell]
		for c in node.get_children():
			(c as Node3D).visible = false
		node.add_child(_model(cfg.tower, 1.8, 0.95))
	# Trees: the decoration nodes are plain Node3D children holding two meshes.
	var t := 0
	for c in board.get_children():
		if c is Node3D and c.get_child_count() == 2 and c.get_child(0) is MeshInstance3D:
			var mi := c.get_child(0) as MeshInstance3D
			if mi.mesh is CylinderMesh and (mi.mesh as CylinderMesh).top_radius == 0.0:
				var h := (mi.mesh as CylinderMesh).height * 1.3
				for k in c.get_children():
					(k as Node3D).visible = false
				var tree := _model(cfg.trees[t % cfg.trees.size()], h)
				tree.rotation.y = t * 1.7
				c.add_child(tree)
				t += 1


func _find_board(n: Node) -> BoardView:
	if n is BoardView:
		return n
	for c in n.get_children():
		var b := _find_board(c)
		if b:
			return b
	return null


## Instantiates a model; it is scaled to `height` (or to fit `width`) once posed.
func _model(rel: String, height: float, width := 0.0) -> Node3D:
	var node := (load("res://art_candidates/" + rel) as PackedScene).instantiate() as Node3D
	var holder := Node3D.new()
	holder.add_child(node)
	_pending.append([node, height, width])
	if _pending.size() == 1:
		_fit_later.call_deferred()
	return holder


func _fit_later() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	for p: Array in _pending:
		var node: Node3D = p[0]
		var aabb := _posed_aabb(node)
		var inv := node.global_transform.affine_inverse()
		aabb = inv * aabb
		var s := float(p[1]) / maxf(aabb.size.y, 0.001)
		if float(p[2]) > 0.0:
			s = minf(s, float(p[2]) / maxf(maxf(aabb.size.x, aabb.size.z), 0.001))
		node.scale = Vector3.ONE * s
		node.position = -Vector3(aabb.get_center().x, aabb.position.y, aabb.get_center().z) * s
	_pending.clear()


func _play_walk(n: Node, offset: float) -> void:
	for a: AnimationPlayer in n.find_children("*", "AnimationPlayer", true, false):
		for want in ["walking_a", "walk", "run"]:
			for name in a.get_animation_list():
				if name.to_lower().contains(want):
					a.get_animation(name).loop_mode = Animation.LOOP_LINEAR
					a.play(name)
					a.advance(offset)
					return


func _posed_aabb(n: Node) -> AABB:
	var out := AABB()
	var first := true
	for m: MeshInstance3D in n.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = m.mesh
		if m.skin != null:
			var baked := m.bake_mesh_from_current_skeleton_pose()
			if baked:
				mesh = baked
		if mesh == null:
			continue
		var b := m.global_transform * mesh.get_aabb()
		out = b if first else out.merge(b)
		first = false
	return out
