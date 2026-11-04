extends Node
## Screenshot scene for the juice: the demo maze mid-wave with the game running,
## so the wave banner, damage numbers and hit particles show. With `leak` set,
## a creep leaks just before the shot (red edge glow and camera shake); with
## `close`, the camera zooms in on the creeps to show the particles.
## Usage: scripts/screenshot.sh out.png res://tools/juice.tscn 30 2532x1170
##        scripts/screenshot.sh out.png res://tools/juice_leak.tscn 8 2532x1170
##        scripts/screenshot.sh out.png res://tools/juice_close.tscn 8 2532x1170

@export var leak := false
@export var close := false

var _main: Node
var _frames := 0


func _ready() -> void:
	var demo: Node = load("res://tools/demo.tscn").instantiate()
	add_child(demo)
	_main = demo.get_child(0)
	_main.speed = 1.0
	_main.selected = Vector2i(-1, -1)
	if close:
		var cam: CameraRig = _main.camera
		cam.focus = Vector3(4.0, 0.0, 6.0)
		cam.distance = cam.min_distance + 1.0
		cam.pan_screen(Vector2.ZERO, Vector2.ZERO)


## The leak happens a few frames in, just before an 8-frame screenshot.
func _process(_delta: float) -> void:
	_frames += 1
	if leak and _frames == 6:
		var game: Game = _main.game
		var creep: Creep = game.creeps[0]
		creep.next_index = creep.path.size()
		game.step()
