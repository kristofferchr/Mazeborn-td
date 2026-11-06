class_name CoachMarks
extends Control
## The guided first round on screen (Onboarding): a card at the left with the
## step ("1 av 5"), a title, a short text and "Hopp over", and gold marks that
## point at what to tap: a bouncing arrow and glowing cells on the map, or a
## ring around a HUD button. The round goes on as usual; only taps on the card
## are kept from the map (Hud.add_layer). When the steps are done, or skipped,
## a notice says so and "done" is kept in the settings (UserSettings).
## Look: UiStyle.

const CARD_WIDTH := 470.0
const BOB := 10.0  # pixels the arrow bobs
const NO_CELL := Vector2i(-1, -1)

var onboarding: Onboarding
var round: Round
var settings_path := UserSettings.PATH

var _card: PanelContainer
var _count: Label
var _dots: HBoxContainer
var _title: Label
var _body: Label
var _extra: Label
var _skip: Button
var _time := 0.0
var _cells: Array[Vector2i] = []  # cells to glow
var _arrow_cell := NO_CELL  # cell the arrow points down at
var _ring := Rect2()  # HUD control to ring (empty: none)
var _ring_arrow := Vector2.ZERO  # direction of the arrow at the ring (zero: none)
var _suggested := NO_CELL  # where the first tower could go (kept until the maze changes)
var _wall: Array[Vector2i] = []  # where the wall could go
var _stale := true  # the suggestions need working out again


## Starts the guided round in `p_round` (after its HUD is set up).
func setup(p_round: Round) -> void:
	round = p_round
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	onboarding = Onboarding.new()
	onboarding.attach(round.game)
	onboarding.finished.connect(_on_finished)
	onboarding.step_changed.connect(func(_s: Onboarding.Step) -> void: _stale = true)
	round.game.path_changed.connect(func() -> void: _stale = true)
	round.game.game_over.connect(func(_won: bool) -> void: hide())
	round.hud.add_layer(self, [_card] as Array[Control])
	_refresh()


func _build() -> void:
	_card = PanelContainer.new()
	var style := UiStyle.panel(Color(0.07, 0.09, 0.12, 0.92), 22)
	style.border_color = Color(UiStyle.ACCENT, 0.75)
	style.set_border_width_all(2)
	style.content_margin_left = 24
	style.content_margin_right = 24
	style.content_margin_top = 16
	style.content_margin_bottom = 18
	_card.add_theme_stylebox_override("panel", style)
	_card.mouse_filter = Control.MOUSE_FILTER_STOP
	_card.custom_minimum_size = Vector2(CARD_WIDTH, 0)
	add_child(_card)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	_card.add_child(col)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	col.add_child(head)
	_count = UiStyle.label("", 16, UiStyle.ACCENT, true)
	_count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_count)
	_dots = HBoxContainer.new()
	_dots.add_theme_constant_override("separation", 6)
	_dots.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_dots.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for i in Onboarding.STEPS:
		var dot := Panel.new()
		dot.custom_minimum_size = Vector2(22, 7)
		var s := StyleBoxFlat.new()
		s.set_corner_radius_all(4)
		dot.add_theme_stylebox_override("panel", s)
		_dots.add_child(dot)
	head.add_child(_dots)
	_skip = Button.new()
	_skip.text = "Hopp over"
	_skip.focus_mode = Control.FOCUS_NONE
	_skip.custom_minimum_size = Vector2(0, 48)
	_skip.add_theme_font_size_override("font_size", 19)
	UiStyle.style_button(_skip, "secondary")
	_skip.pressed.connect(func() -> void: onboarding.skip())
	head.add_child(_skip)
	_title = UiStyle.label("", 27, UiStyle.TEXT, true)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_title)
	_body = UiStyle.label("", 19, UiStyle.MUTED)
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_body)
	_extra = UiStyle.chip("", UiStyle.GOOD.darkened(0.45), 19)
	_extra.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.add_child(_extra)


## The texts and marks for the step, given what is selected now.
func _refresh() -> void:
	var game := round.game
	var step := onboarding.step
	var cell := round.selected
	var tower := game.tower_at(cell) if cell != NO_CELL else null
	var free_cell := cell != NO_CELL and tower == null
	if _stale:  # path searches: only when the maze changed
		_stale = false
		_suggested = Onboarding.suggest_cell(game)
		_wall = Onboarding.suggest_wall(game, onboarding.first_tower, 3)
	_cells.clear()
	_arrow_cell = NO_CELL
	_ring = Rect2()
	_ring_arrow = Vector2.RIGHT
	_extra.visible = false
	var title := ""
	var body := ""
	match step:
		Onboarding.Step.BUILD:
			title = "Bygg et tårn"
			if free_cell:
				body = "Bra! Trykk på ruten en gang til, eller på «Bygg», for å bygge tårnet."
				_ring = round.hud.anchor_rect("build")
				_ring_arrow = Vector2.DOWN  # from above: the tower cards are to its left
			else:
				body = "Trykk på en rute for å se tårnet der før du bygger."
				_arrow_cell = _suggested
				_cells = [_suggested] as Array[Vector2i]
		Onboarding.Step.MAZE:
			title = "Mazing: fiendene må gå lenger"
			body = (
				"Bygg en vegg på tvers av stien (pilene på bakken). Fiendene må gå rundt, "
				+ "og tårnene får skyte lenger."
			)
			_cells = _wall.duplicate()
			if not _cells.is_empty():
				_arrow_cell = _cells[0]
			_extra.visible = true
			var gain := onboarding.gain()
			_extra.text = (
				"Stien: %d ruter → %d ruter%s"
				% [
					onboarding.start_length,
					onboarding.path_length,
					"  (+%d)" % gain if gain > 0 else "",
				]
			)
		Onboarding.Step.START:
			title = "Start bølgen"
			body = "Fiendene kommer fra portalen og følger stien mot målet. Trykk på «Start bølge»."
			_ring = round.hud.anchor_rect("start")
		Onboarding.Step.TOWER:
			title = "Oppgrader eller selg"
			if tower:
				body = "Velg en oppgradering (koster gull), eller «Selg» for å få igjen 75 %."
				_ring = round.hud.anchor_rect("panel")
				_ring_arrow = Vector2.ZERO
			else:
				body = "Trykk på et tårn. Da kan du oppgradere det eller selge det."
				_arrow_cell = _a_tower()
				_cells = [_arrow_cell] as Array[Vector2i]
		Onboarding.Step.COUNTDOWN:
			title = "Nedtelling og «Send nå»"
			if game.countdown_active():
				body = (
					"Neste bølge kommer av seg selv når ringen er tom. «Send nå» sender "
					+ "den med en gang og gir bonusgull."
				)
			else:
				body = (
					"Når bølgen er slått, teller knappen ned til neste. Vent, eller send "
					+ "den tidlig for bonusgull."
				)
			_ring = round.hud.anchor_rect("start")
	_title.text = title
	_body.text = body
	var number := mini(int(step) + 1, Onboarding.STEPS)
	_count.text = "%d AV %d" % [number, Onboarding.STEPS]
	for i in _dots.get_child_count():
		var s := (_dots.get_child(i) as Panel).get_theme_stylebox("panel") as StyleBoxFlat
		s.bg_color = UiStyle.ACCENT if i < number else Color(1, 1, 1, 0.15)


## The tower nearest the start of the path (the arrow points at it).
func _a_tower() -> Vector2i:
	var best := NO_CELL
	var best_d := INF
	for c: Vector2i in round.game.towers:
		var d := Vector2(c).distance_to(Vector2(round.game.grid.spawn))
		if d < best_d:
			best_d = d
			best = c
	return best


func _process(delta: float) -> void:
	if onboarding == null or not onboarding.is_active():
		return
	_time += delta
	_refresh()
	_layout()
	queue_redraw()


## Bottom left, clear of the spawns on the left edge; under the resources
## while the selection panel takes the bottom left.
func _layout() -> void:
	var inset := UiStyle.safe_insets(get_viewport())
	_card.reset_size()
	var x: float = Hud.MARGIN + inset.left
	if round.hud.anchor_rect("panel").has_area():
		_card.position = Vector2(x, Hud.MARGIN + inset.top + 92.0)
	else:
		var bottom: float = get_viewport_rect().size.y - Hud.MARGIN - inset.bottom
		_card.position = Vector2(x, bottom - _card.size.y)


func _draw() -> void:
	if onboarding == null or not onboarding.is_active():
		return
	var pulse := 0.5 + 0.5 * sin(_time * 4.0)
	var gold := UiStyle.ACCENT
	for c in _cells:
		if c == NO_CELL:
			continue
		var quad := _cell_quad(c)
		if quad.is_empty():
			continue
		draw_colored_polygon(quad, Color(gold, 0.18 + 0.2 * pulse))
		var outline := quad.duplicate()
		outline.append(quad[0])
		draw_polyline(outline, Color(gold, 0.6 + 0.4 * pulse), 3.0, true)
	if _arrow_cell != NO_CELL:
		var cam := round.camera
		var on_tower := round.game.tower_at(_arrow_cell) != null
		var top := BoardView.cell_pos(_arrow_cell, 1.9 if on_tower else 0.9)
		if not cam.is_position_behind(top):
			var tip := cam.unproject_position(top) - Vector2(0, 10.0 + BOB * pulse)
			_arrow(tip, Vector2.DOWN)
	if _ring.has_area():
		var r := _ring.grow(6.0 + 4.0 * pulse)
		var box := StyleBoxFlat.new()
		box.draw_center = false
		box.set_border_width_all(4)
		box.border_color = Color(gold, 0.55 + 0.45 * pulse)
		box.set_corner_radius_all(22)
		box.anti_aliasing = true
		draw_style_box(box, r)
		var gap := 12.0 + BOB * pulse
		if _ring_arrow == Vector2.RIGHT:
			_arrow(Vector2(r.position.x - gap, r.get_center().y), Vector2.RIGHT)
		elif _ring_arrow == Vector2.DOWN:
			_arrow(Vector2(r.get_center().x, r.position.y - gap), Vector2.DOWN)


## A gold arrow whose tip is at `tip`, pointing along `dir`.
func _arrow(tip: Vector2, dir: Vector2) -> void:
	var side := Vector2(-dir.y, dir.x)
	var head := 30.0
	var base := tip - dir * head
	var shaft := 34.0
	var shadow := Vector2(0, 3)
	for pass_i in 2:
		var off := shadow if pass_i == 0 else Vector2.ZERO
		var col := Color(0, 0, 0, 0.35) if pass_i == 0 else UiStyle.ACCENT
		draw_colored_polygon(
			PackedVector2Array([tip + off, base + side * 20.0 + off, base - side * 20.0 + off]), col
		)
		draw_line(base + off, base - dir * shaft + off, col, 13.0, true)


## The corners of a cell on the ground, on screen ([] when behind the camera).
func _cell_quad(cell: Vector2i) -> PackedVector2Array:
	var cam := round.camera
	var out := PackedVector2Array()
	for corner: Vector2 in [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]:
		var p := Vector3(cell.x + 0.06 + corner.x * 0.88, 0.06, cell.y + 0.06 + corner.y * 0.88)
		if cam.is_position_behind(p):
			return PackedVector2Array()
		out.append(cam.unproject_position(p))
	return out


func _on_finished(skipped: bool) -> void:
	var settings := UserSettings.open(settings_path)
	settings.tutorial_done = true
	settings.save()
	hide()
	if not skipped:
		round.hud.notify("Veiledningen er ferdig", "Lykke til! Resten av runden er din.", "star")
