extends Node
## Screenshot scene: every creep model walking right on the real board, in two
## rows, plus one killed creep playing its death animation. Towers of every kind
## and level stand along the bottom edge.
## Usage: scripts/screenshot.sh out.png res://tools/creeps.tscn 30 2532x1170
## Env CREEPS_DIST sets the camera distance (game default 19), CREEPS_X/CREEPS_Z
## the focus, CREEPS_YAW the facing of the creeps (default: walking right).

const FLYING := ["bat", "dragon", "wasp"]


func _ready() -> void:
	var main: Node = load("res://main.tscn").instantiate()
	add_child(main)
	main.speed = 0.0
	var game: Game = main.game
	var board: BoardView = main.board
	game.wave = 1
	var ids: Array = CreepArt.MODELS.keys()
	for i in ids.size():
		var id: String = ids[i]
		var kind := "boss" if id == "skeleton_warrior" else ("flying" if id in FLYING else "normal")
		game.waves[0] = {"groups": [{"creep": kind, "model": id}]} as Dictionary
		var cell := Vector2i(1 + (i % 6) * 3, 2 + (i / 6) * 4)
		var creep := Creep.new(i, 100.0, 1.7, 1, cell, kind)
		creep.flying = kind == "flying"
		game.creeps.append(creep)
		board._on_creep_spawned(creep)
		(board._creeps[i] as Node3D).rotation.y = (
			float(OS.get_environment("CREEPS_YAW"))
			if OS.has_environment("CREEPS_YAW")
			else PI / 2.0
		)
	# One more rat, killed just now.
	game.waves[0] = {"groups": [{"creep": "normal", "model": "rat"}]}
	var dead := Creep.new(99, 100.0, 1.7, 1, Vector2i(8, 9))
	board._on_creep_spawned(dead)
	board._on_creep_removed(dead, true)
	# Towers: every kind at level 0, 1 and 2 along the bottom edge.
	var x := 1
	for kind: String in game.tower_order:
		for level in 3:
			var tower := Tower.new(Vector2i(x, 11), kind, game.tower_defs[kind])
			tower.level = level
			board._on_tower_built(tower)
			x += 1
	if OS.has_environment("CREEPS_DIST"):
		main.camera.distance = float(OS.get_environment("CREEPS_DIST"))
		main.camera.focus = Vector3(
			float(OS.get_environment("CREEPS_X")) if OS.has_environment("CREEPS_X") else 9.0,
			0.0,
			float(OS.get_environment("CREEPS_Z")) if OS.has_environment("CREEPS_Z") else 6.5
		)
		main.camera._apply()
