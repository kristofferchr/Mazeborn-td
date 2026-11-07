extends Node3D
## Tower lineup: every kind at every level (rows: arrow, earth, wind, fire
## elemental) and an elemental of each element, on the default map up close
## at the game's camera angle, with the round's lighting.
## Usage: scripts/screenshot.sh out.png res://tools/towers.tscn 30 2532x1170
## Env TOWERS_DIST sets the camera distance (default 8).

const ROWS := [["arrow", ""], ["earth", ""], ["wind", ""], ["elemental", "fire"]]
const ELEMENTS := ["fire", "ice", "lightning", "nature"]


func _ready() -> void:
	var game := Game.create_map(Maps.DEFAULT, 1)
	Round.add_environment(self)
	var board := BoardView.new()
	add_child(board)
	board.setup(game)
	for r in ROWS.size():
		for level in 3:
			var cell := Vector2i(4 + level * 2, 1 + r * 2)
			game.gold = 100000
			game.build(cell, ROWS[r][0])
			for i in level:
				game.upgrade(cell, ROWS[r][1] if i == 0 else "")
	for e in ELEMENTS.size():
		var cell := Vector2i(10, 1 + e * 2)
		game.gold = 100000
		game.build(cell, "elemental")
		game.upgrade(cell, ELEMENTS[e])
		game.upgrade(cell)
	var dist := 8.0
	if OS.has_environment("TOWERS_DIST"):
		dist = float(OS.get_environment("TOWERS_DIST"))
	var cam := CameraRig.new()
	add_child(cam)
	# An empty bounds rect: the focus sits at its centre (+2 rows), unclamped.
	cam.setup(Rect2(Vector2(7.5, 2.6), Vector2.ZERO), dist)
	cam.make_current()
