class_name Round
extends Node3D
## One round on a map: runs the core Game with a fixed time step and wires the
## 3D view, the camera and the HUD to it. Set map_id and options (for
## Game.create_map, e.g. {"difficulty": "hard"}) before adding it to the tree
## (default: the default map on Normal, so the scene also runs on its own).
## Touch: tap a cell to preview, tap again (or "Bygg") to build the kind chosen
## in the menu, tap a tower to upgrade or sell; drag to pan, pinch to zoom.
## The pause button (or Esc, or the app going to the background) pauses the
## tree; the pause menu and settings keep working. The result of a finished
## round is kept in the progress file (Progress).

signal retry_requested  # "Prøv igjen" / "Start på nytt": the same map again
signal maps_requested  # "Velg kart" / "Avslutt til kart": back to the map select

const TAP_SLOP := 14.0  # pixels a finger may move and still count as a tap
const NO_CELL := Vector2i(-1, -1)

var map_id := Maps.DEFAULT
var options: Dictionary = {}  # passed on to Game.create_map, unknown keys too
var progress_path := Progress.PATH  # where results are kept ("" to keep none)
var paused := false
var game: Game
var board: BoardView
var camera: CameraRig
var hud: Hud
var audio: GameAudio
var speed := 1.0
var selected := NO_CELL
var build_kind := "arrow"  # tower kind chosen in the build menu

var _touches: Dictionary = {}  # index -> position
var _tap_start := Vector2.ZERO
var _tap_valid := false
var _record_wave := 0  # endless: the best wave before this round (0: no notice)


func _ready() -> void:
	game = Game.create_map(map_id, int(Time.get_unix_time_from_system()), options)
	speed = float(UserSettings.open().speed)
	add_environment(self)

	board = BoardView.new()
	add_child(board)
	board.setup(game)

	camera = CameraRig.new()
	add_child(camera)
	var size := Vector2(game.grid.size)
	camera.setup(Rect2(Vector2.ZERO, size), CameraRig.fit_distance(size))
	camera.make_current()

	hud = Hud.new()
	add_child(hud)
	hud.setup(game, board, camera)
	hud.start_wave_pressed.connect(func() -> void: game.start_wave())
	hud.build_pressed.connect(func() -> void: _build_selected())
	hud.sell_pressed.connect(_sell_selected)
	hud.upgrade_pressed.connect(func(option: String) -> void: game.upgrade(selected, option))
	hud.kind_selected.connect(func(kind: String) -> void: build_kind = kind)
	hud.targeting_pressed.connect(_toggle_targeting)
	hud.speed_pressed.connect(_toggle_speed)
	hud.retry_pressed.connect(_retry)
	hud.maps_pressed.connect(_choose_map)
	hud.pause_pressed.connect(set_paused.bind(true))
	hud.resume_pressed.connect(set_paused.bind(false))
	hud.set_speed_text("%dx" % int(speed))
	game.game_over.connect(_on_game_over)
	Haptics.load_setting(UserSettings.open())
	Haptics.watch(game)
	_watch_record()

	if audio == null:  # on its own; in the app the menus' GameAudio carries on
		audio = GameAudio.new()
		add_child(audio)
	audio.setup(game)
	hud.set_muted(audio.muted)
	hud.mute_pressed.connect(audio.toggle_muted)
	audio.muted_changed.connect(hud.set_muted)
	game.creep_leaked.connect(func(c: Creep) -> void: camera.shake(_shake_for(c, true)))
	game.creep_killed.connect(func(c: Creep) -> void: camera.shake(_shake_for(c, false)))


func _exit_tree() -> void:
	if paused:
		get_tree().paused = false


## Pauses the round: the simulation, the 3D view and the HUD stop (the tree is
## paused), the pause menu opens and the music ducks.
func set_paused(on: bool) -> void:
	if on == paused or (on and game.is_over()):
		return
	paused = on
	get_tree().paused = on
	_touches.clear()
	_tap_valid = false
	hud.show_paused(on)
	audio.set_ducked(on)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED and game and not game.is_over():
		set_paused(true)  # the app went to the background (mobile)


## Keeps the result in the progress file and shows the stars and any record.
func _on_game_over(_won: bool) -> void:
	_select(NO_CELL)
	var result := Progress.result_of(game)
	var record := false
	if progress_path != "":
		var progress := Progress.open(progress_path)
		var previous := progress.best(map_id, game.difficulty, str(result.mode))
		record = Progress.is_new_record(previous, result)
		if progress.record(map_id, game.difficulty, result):
			progress.save()
	hud.show_result(int(result.stars), record)


## Endless: a "Rekord!" notice the first time the round passes the best wave
## reached before.
func _watch_record() -> void:
	if progress_path == "" or Progress.mode_of(game.options) != Progress.ENDLESS:
		return
	var best := Progress.open(progress_path).best(map_id, game.difficulty, Progress.ENDLESS)
	_record_wave = int(best.get("wave", 0))
	if _record_wave > 0:
		game.wave_cleared.connect(_on_wave_cleared_record)


func _on_wave_cleared_record(_number: int) -> void:
	if Progress.passes_record(_record_wave, game.score()):
		hud.toast("Rekord!", "Forbi forrige beste: bølge %d" % _record_wave)
		_record_wave = 0


## Restarts the map: the app (main.gd) makes a new round; on its own the scene
## reloads.
func _retry() -> void:
	set_paused(false)
	if retry_requested.get_connections().is_empty():
		get_tree().reload_current_scene()
	else:
		retry_requested.emit()


func _choose_map() -> void:
	set_paused(false)
	if maps_requested.get_connections().is_empty():
		get_tree().change_scene_to_file("res://main.tscn")
	else:
		maps_requested.emit()


func _process(delta: float) -> void:
	game.simulate(minf(delta, 0.25) * speed)
	# Refresh the preview: gold, creeps and the maze change while it is shown.
	# can_build runs a path search per spawn, so it is done once per frame here.
	var has := selected != NO_CELL
	var buildable := (
		has and game.tower_at(selected) == null and game.can_build(selected, build_kind)
	)
	board.show_selection(selected, has, build_kind, buildable)
	hud.show_selection(selected, has, build_kind, buildable)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not game.is_over():
		get_viewport().set_input_as_handled()
		set_paused(true)
		return
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
		if hud.is_over_ui(mb.position):
			return  # e.g. the wheel at the end of the wave overview
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


## Camera shake for a creep that leaked or died: every leak, and a boss death.
func _shake_for(creep: Creep, leaked: bool) -> float:
	if creep.kind == "boss":
		return 0.6
	return 0.3 if leaked else 0.0


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


## Warm late-afternoon sun with soft shadows, cool sky fill light, filmic tone
## mapping and a little glow, added to `parent`. `cheap` leaves out the shadows
## and the glow (behind the menus).
static func add_environment(parent: Node, cheap := false) -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, 40.0, 0.0)
	sun.light_color = Color(1.0, 0.94, 0.84)
	sun.light_energy = 1.25
	sun.shadow_enabled = not cheap
	sun.shadow_blur = 1.5
	sun.directional_shadow_max_distance = 45.0
	parent.add_child(sun)

	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.13, 0.22, 0.14)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.62, 0.7, 0.85)
	e.ambient_light_energy = 0.75
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_exposure = 1.05
	e.tonemap_white = 6.0
	e.glow_enabled = not cheap
	e.glow_intensity = 0.6
	e.glow_bloom = 0.05
	e.glow_hdr_threshold = 0.9
	e.adjustment_enabled = true
	e.adjustment_saturation = 1.0
	e.adjustment_contrast = 1.05
	var env := WorldEnvironment.new()
	env.environment = e
	parent.add_child(env)
