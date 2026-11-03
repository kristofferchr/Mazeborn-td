extends Node3D
## Game scene: runs the core Game with a fixed time step and wires the 3D view,
## the camera and the HUD to it. Touch: tap a cell to preview, tap again (or
## "Bygg") to build the kind chosen in the menu, tap a tower to upgrade or sell;
## drag to pan, pinch to zoom.

const TAP_SLOP := 14.0  # pixels a finger may move and still count as a tap
const NO_CELL := Vector2i(-1, -1)

var game: Game
var board: BoardView
var camera: CameraRig
var hud: Hud
var speed := 1.0
var selected := NO_CELL
var build_kind := "stone"  # tower kind chosen in the build menu

var _touches: Dictionary = {}  # index -> position
var _tap_start := Vector2.ZERO
var _tap_valid := false


func _ready() -> void:
	game = Game.create_default(int(Time.get_unix_time_from_system()))
	_build_environment()

	board = BoardView.new()
	add_child(board)
	board.setup(game)

	camera = CameraRig.new()
	add_child(camera)
	var size := Vector2(game.grid.size)
	camera.setup(Rect2(Vector2.ZERO, size), 19.0)
	camera.make_current()

	hud = Hud.new()
	add_child(hud)
	hud.setup(game, board, camera)
	hud.start_wave_pressed.connect(func() -> void: game.start_wave())
	hud.build_pressed.connect(func() -> void: _build_selected())
	hud.sell_pressed.connect(_sell_selected)
	hud.upgrade_pressed.connect(func() -> void: game.upgrade(selected))
	hud.kind_selected.connect(func(kind: String) -> void: build_kind = kind)
	hud.targeting_pressed.connect(_toggle_targeting)
	hud.speed_pressed.connect(_toggle_speed)
	hud.retry_pressed.connect(func() -> void: get_tree().reload_current_scene())
	game.game_over.connect(func(_won: bool) -> void: _select(NO_CELL))


func _process(delta: float) -> void:
	game.simulate(minf(delta, 0.25) * speed)
	# Refresh the preview: gold, creeps and the maze change while it is shown.
	board.show_selection(selected, selected != NO_CELL, build_kind)
	hud.show_selection(selected, selected != NO_CELL, build_kind)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var e := event as InputEventScreenTouch
		if e.pressed:
			if hud.is_over_ui(e.position):
				return  # a button press, not a gesture on the map
			_touches[e.index] = e.position
			_tap_valid = _touches.size() == 1 and not hud.is_over_ui(e.position)
			_tap_start = e.position
		else:
			_touches.erase(e.index)
			if _tap_valid and _touches.is_empty():
				_on_tap(e.position)
			_tap_valid = false
	elif event is InputEventScreenDrag:
		var e := event as InputEventScreenDrag
		if not _touches.has(e.index):
			return
		var old: Vector2 = _touches[e.index]
		_touches[e.index] = e.position
		if _touches.size() == 1:
			if _tap_valid and e.position.distance_to(_tap_start) < TAP_SLOP:
				return
			if _tap_valid:
				old = _tap_start
				_tap_valid = false
			camera.pan_screen(old, e.position)
		elif _touches.size() == 2:
			_pinch(e.index, old)
	elif event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			camera.zoom(1.1, mb.position)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera.zoom(1.0 / 1.1, mb.position)
	elif event is InputEventMagnifyGesture:
		var mg := event as InputEventMagnifyGesture
		camera.zoom(mg.factor, mg.position)


func _pinch(moved: int, old: Vector2) -> void:
	var other: Vector2
	for i: int in _touches:
		if i != moved:
			other = _touches[i]
	var now: Vector2 = _touches[moved]
	var d_old := old.distance_to(other)
	var d_new := now.distance_to(other)
	if d_old > 1.0 and d_new > 1.0:
		camera.zoom(d_new / d_old, (now + other) / 2.0)
	camera.pan_screen((old + other) / 2.0, (now + other) / 2.0)


func _on_tap(pos: Vector2) -> void:
	if game.is_over():
		return
	var p := camera.ground_point(pos)
	var cell := Vector2i(floori(p.x), floori(p.z))
	if not game.grid.in_bounds(cell):
		_select(NO_CELL)
	elif cell == selected and game.tower_at(cell) == null:
		_build_selected()
	else:
		_select(cell)


func _select(cell: Vector2i) -> void:
	selected = cell


func _build_selected() -> void:
	if selected != NO_CELL and game.build(selected, build_kind) != null:
		_select(NO_CELL)


func _sell_selected() -> void:
	if selected != NO_CELL and game.sell(selected) > 0:
		_select(NO_CELL)


func _toggle_targeting() -> void:
	var tower := game.tower_at(selected)
	if tower:
		tower.targeting = (
			Tower.Targeting.CLOSEST
			if tower.targeting == Tower.Targeting.FIRST
			else Tower.Targeting.FIRST
		)


func _toggle_speed() -> void:
	speed = 2.0 if speed == 1.0 else 1.0
	hud.set_speed_text("%dx" % int(speed))


func _build_environment() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55.0, 35.0, 0.0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 60.0
	add_child(sun)

	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.18, 0.28, 0.2)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.65, 0.65, 0.75)
	env.environment.ambient_light_energy = 0.7
	add_child(env)
