class_name MenuBackdrop
extends Node3D
## Behind the menus: a map with a finished maze and creeps walking through it,
## seen by a camera that slowly circles it. The game runs with endless lives
## and loops over the first waves. No sound and no input. Same lighting as a
## round (Round.add_environment), without shadows and glow. The app pauses and
## hides it behind the map select (set_active).

const ORBIT_SPEED := 0.045  # radians per second
const LOOP_WAVES := 6  # waves shown before starting over
const KINDS := ["arrow", "arrow", "earth", "arrow", "elemental", "arrow", "wind", "elemental"]
const ELEMENTS := ["fire", "ice", "lightning", "nature"]

var map_id := Maps.DEFAULT
var game: Game
var board: BoardView
var camera: Camera3D
var angle := 0.6
var h_shift := 0.28  # share of the orbit radius the view is moved left


func _ready() -> void:
	game = Game.create_map(map_id, 7)
	game.lives = 1 << 30
	game.gold = 1 << 20
	Round.add_environment(self, true)  # no shadows or glow: cheap behind a menu
	board = BoardView.new()
	add_child(board)
	board.setup(game)
	var plan := MazePlan.serpentine(game.grid)
	for i in plan.size():
		game.build(plan[i], KINDS[i % KINDS.size()] if i >= 4 else "arrow")
	var k := 0
	for cell: Vector2i in game.towers.keys():
		var tower: Tower = game.towers[cell]
		if tower.kind == "elemental":
			game.upgrade(cell, ELEMENTS[k % ELEMENTS.size()])
		elif k % 3 == 1:
			game.upgrade(cell)
		k += 1
	camera = Camera3D.new()
	camera.fov = 40.0
	camera.far = 200.0
	add_child(camera)
	camera.make_current()
	_place_camera()


## Runs and shows the backdrop, or pauses and hides it (when a menu covers it).
func set_active(on: bool) -> void:
	visible = on
	process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED
	if on and camera:
		camera.make_current()


func _process(delta: float) -> void:
	if game.phase == Game.Phase.BUILD:
		if game.wave >= LOOP_WAVES:
			game.wave = 0
		game.start_wave()
	game.simulate(minf(delta, 0.25))
	angle += delta * ORBIT_SPEED
	_place_camera()


func _place_camera() -> void:
	var size := Vector2(game.grid.size)
	var center := Vector3(size.x / 2.0, 0.0, size.y / 2.0)
	var radius := maxf(size.x, size.y) * 0.85
	var eye := center + Vector3(cos(angle) * radius, radius * 0.6, sin(angle) * radius)
	camera.look_at_from_position(eye, center)
	camera.h_offset = -radius * h_shift  # the map sits to the right of the menu
