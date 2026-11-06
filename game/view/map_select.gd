class_name MapSelect
extends Control
## Map select before a round: a difficulty selector, a card per map (schematic,
## name, chips, description and the best result on the chosen difficulty and
## mode, with stars), "Tilbake", a mode selector (Klassisk / Endeløs) and a
## "Spill" button for the chosen map. Look: UiStyle.
## Drawn opaque (or with a translucent shade over a 3D scene, see opaque).

## options for Game.create_map: {"difficulty": id, "mode": "classic"|"endless"}.
signal play_pressed(map_id: String, options: Dictionary)
signal back_pressed

const MARGIN := 40.0
const GAP := 22
## The Klassisk/Endeløs selector (false hides it and forces "classic").
const SHOW_MODE := true

var selected := Maps.DEFAULT
var difficulty := Difficulty.DEFAULT
var endless := false  # play the endless mode
var progress: Progress
var opaque := true  # false: a translucent shade, so a 3D scene behind shows through

var _cards: Dictionary = {}  # map id -> Button
var _grid: GridContainer
var _play: Button
var _back_button: Button
var _title: Label
var _subtitle: Label
var _levels: Segmented
var _level_text: Label
var _modes: Segmented
var _grid_top := 0.0  # top of the cards, set by _place
var _back: Texture2D


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UiStyle.theme()
	if progress == null:
		progress = Progress.open()
	if not Difficulty.exists(difficulty):
		difficulty = Difficulty.DEFAULT
	_build()
	get_viewport().size_changed.connect(_layout)
	_select(selected if _cards.has(selected) else Maps.DEFAULT)
	_set_difficulty(difficulty)
	_layout()


## Options for the chosen difficulty and mode, as sent with play_pressed.
func options() -> Dictionary:
	return {"difficulty": difficulty, "mode": _mode()}


func _mode() -> String:
	return Progress.ENDLESS if endless and SHOW_MODE else Progress.CLASSIC


func _build() -> void:
	_back = _backdrop()
	_title = UiStyle.label("Velg kart", 54, UiStyle.TEXT, true)
	add_child(_title)
	_subtitle = UiStyle.label("Mazeborn TD  ·  bygg mazen, hold fienden ute", 22, UiStyle.MUTED)
	add_child(_subtitle)

	var names: Array[String] = []
	for id in Difficulty.ids():
		names.append(Difficulty.display_name(id))
	_levels = Segmented.make(names, Difficulty.ids().find(difficulty), 24, 68)
	_levels.changed.connect(func(i: int) -> void: _set_difficulty(Difficulty.ids()[i]))
	add_child(_levels)
	_level_text = UiStyle.label("", 20, UiStyle.MUTED)
	_level_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_level_text)
	var modes: Array[String] = ["Klassisk", "∞  Endeløs"]
	_modes = Segmented.make(modes, 1 if endless else 0, 26, 96)
	_modes.changed.connect(
		func(i: int) -> void:
			endless = i == 1
			_show_results()
	)
	_modes.visible = SHOW_MODE
	add_child(_modes)

	_grid = GridContainer.new()
	_grid.add_theme_constant_override("h_separation", GAP)
	_grid.add_theme_constant_override("v_separation", GAP)
	add_child(_grid)
	for id in Maps.ids():
		var card := _card(Maps.load_map(id))
		_grid.add_child(card)
		_cards[id] = card

	_back_button = Button.new()
	_back_button.text = "Tilbake"
	_back_button.focus_mode = Control.FOCUS_NONE
	_back_button.custom_minimum_size = Vector2(220, 96)
	_back_button.add_theme_font_size_override("font_size", 30)
	UiStyle.style_button(_back_button, "secondary")
	_back_button.pressed.connect(func() -> void: back_pressed.emit())
	add_child(_back_button)

	_play = Button.new()
	_play.text = "Spill"
	_play.focus_mode = Control.FOCUS_NONE
	_play.custom_minimum_size = Vector2(320, 96)
	_play.add_theme_font_size_override("font_size", 38)
	UiStyle.style_button(_play, "primary")
	_play.pressed.connect(func() -> void: play_pressed.emit(selected, options()))
	add_child(_play)


func _card(m: Dictionary) -> Button:
	var id := str(m.id)
	var card := Button.new()
	card.toggle_mode = true
	card.focus_mode = Control.FOCUS_NONE
	var normal := UiStyle.button_box("secondary", "normal")
	normal.set_corner_radius_all(22)
	var hover := UiStyle.button_box("secondary", "hover")
	hover.set_corner_radius_all(22)
	var chosen := UiStyle.button_box("secondary", "hover")
	chosen.set_corner_radius_all(22)
	chosen.set_border_width_all(3)
	chosen.border_color = UiStyle.ACCENT
	chosen.bg_color = Color(0.17, 0.19, 0.22, 0.97)
	card.add_theme_stylebox_override("normal", normal)
	card.add_theme_stylebox_override("hover", hover)
	card.add_theme_stylebox_override("pressed", chosen)
	card.add_theme_stylebox_override("hover_pressed", chosen)
	card.add_theme_stylebox_override("focus", UiStyle.button_box("secondary", "focus"))
	card.pressed.connect(_select.bind(id))

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 18
	box.offset_right = -18
	box.offset_top = 18
	box.offset_bottom = -16
	box.add_theme_constant_override("separation", 10)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(box)

	var grid := Maps.grid(m)
	var preview := MapPreview.make(grid, Vector2(0, 150))
	preview.name = "Preview"
	box.add_child(preview)
	box.add_child(UiStyle.label(str(m.name), 30, UiStyle.TEXT, true))
	var chips := HFlowContainer.new()
	chips.add_theme_constant_override("h_separation", 8)
	chips.add_theme_constant_override("v_separation", 6)
	chips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chips.add_child(UiStyle.chip("%d × %d" % [grid.size.x, grid.size.y], Color(0.3, 0.34, 0.4), 16))
	var n := grid.spawns.size()
	var portals := "1 portal" if n == 1 else "%d portaler" % n
	chips.add_child(UiStyle.chip(portals, Color(0.5, 0.25, 0.65), 16))
	if float(m.get("rules", {}).get("hp_scale", 1.0)) > 1.0:
		chips.add_child(UiStyle.chip("Seigere fiender", Color(0.65, 0.25, 0.25), 16))
	box.add_child(chips)
	var text := UiStyle.label(str(m.get("description", "")), 19, UiStyle.MUTED)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(text)
	# The best result on the chosen difficulty: stars and a line of text.
	var result := HBoxContainer.new()
	result.add_theme_constant_override("separation", 12)
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var stars := UiStyle.stars(0, 28)
	stars.name = "Stars"
	stars.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	result.add_child(stars)
	var best := UiStyle.label("", 18, UiStyle.MUTED, true)
	best.name = "Best"
	best.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	best.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	best.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result.add_child(best)
	box.add_child(result)
	return card


## Short text for the best result on a map: "Seier · 14 liv", "Bølge 9 av 12" ...
static func best_text(best: Dictionary) -> String:
	if best.is_empty():
		return "Ikke spilt ennå"
	if bool(best.won):
		return "Seier · %d liv" % int(best.lives)
	if int(best.get("waves", 0)) <= 0:
		return "Rekord: bølge %d" % int(best.wave)  # endless
	return "Bølge %d av %d" % [int(best.wave), int(best.waves)]


func _select(id: String) -> void:
	selected = id
	for key: String in _cards:
		(_cards[key] as Button).set_pressed_no_signal(key == id)
	if _play:
		_play.text = "Spill  %s" % Maps.load_map(id).name


func _set_difficulty(id: String) -> void:
	difficulty = id
	_levels.select(Difficulty.ids().find(id))
	_level_text.text = str(Difficulty.level(id).get("description", ""))
	_show_results()


## Stars (classic) and the best result on every card for the chosen difficulty
## and mode.
func _show_results() -> void:
	for map_id: String in _cards:
		var card := _cards[map_id] as Button
		var best := progress.best(map_id, difficulty, _mode())
		var stars := card.find_child("Stars", true, false) as HBoxContainer
		UiStyle.set_stars(stars, progress.stars(map_id, difficulty))
		stars.visible = _mode() == Progress.CLASSIC
		var label := card.find_child("Best", true, false) as Label
		label.text = best_text(best)
		var good := (
			bool(best.get("won", false)) or (_mode() == Progress.ENDLESS and not best.is_empty())
		)
		label.add_theme_color_override("font_color", UiStyle.GOLD if good else UiStyle.MUTED)
	_place()


## Cards in one row on wide screens and in two on narrower ones, sized to fit
## inside the safe area.
func _layout() -> void:
	var area := _area()
	var cols := 4 if area.size.x >= 1100 and area.size.x / area.size.y >= 1.5 else 2
	_grid.columns = cols
	var rows := ceili(_cards.size() / float(cols))
	var w := clampf((area.size.x - GAP * (cols - 1)) / cols, 240.0, 560.0)
	var h := clampf((area.size.y - 250.0 - GAP * (rows - 1)) / rows, 220.0, 440.0)
	for card: Button in _cards.values():
		card.custom_minimum_size = Vector2(w, h)
		var preview := card.find_child("Preview", true, false) as Control
		preview.custom_minimum_size.y = clampf(h * 0.36, 90.0, 170.0)
	_place()
	_fit_cards.call_deferred()


## Makes every card tall enough for its wrapped text (known after layout). If
## the cards would then reach the buttons, the schematics get smaller.
func _fit_cards() -> void:
	var need := _card_need()
	var rows := ceili(_cards.size() / float(_grid.columns))
	var room := (_area().end.y - _play.size.y - 26.0 - _grid_top - GAP * (rows - 1)) / rows
	if need > room:
		for card: Button in _cards.values():
			var preview := card.find_child("Preview", true, false) as Control
			preview.custom_minimum_size.y = maxf(
				preview.custom_minimum_size.y - (need - room), 56.0
			)
		need = _card_need()
	for card: Button in _cards.values():
		card.custom_minimum_size.y = clampf(card.custom_minimum_size.y, need, maxf(room, need))
	_place()


func _card_need() -> float:
	var need := 0.0
	for card: Button in _cards.values():
		var box := card.get_child(0) as Control
		need = maxf(need, box.get_combined_minimum_size().y + 34.0)
	return need


func _place() -> void:
	if _grid == null:
		return
	var area := _area()
	_grid.reset_size()
	_title.position = area.position
	_subtitle.position = area.position + Vector2(2, 68)
	_levels.reset_size()
	_levels.position = Vector2(area.end.x - _levels.size.x, area.position.y + 4.0)
	_level_text.reset_size()
	_level_text.position = Vector2(
		area.end.x - _level_text.size.x - 8.0, _levels.position.y + _levels.size.y + 8.0
	)
	# On narrow screens the selector goes under the title.
	var title_end := area.position.x + maxf(_title.size.x, _subtitle.size.x) + 32.0
	var grid_top := area.position.y + 126.0
	if _levels.position.x < title_end:
		_levels.position = Vector2(area.position.x, area.position.y + 112.0)
		_level_text.position = Vector2(
			_levels.position.x + _levels.size.x + 18.0,
			_levels.position.y + (_levels.size.y - _level_text.size.y) / 2.0
		)
		grid_top = _levels.position.y + _levels.size.y + 24.0
	_grid_top = grid_top
	_grid.position = Vector2(area.get_center().x - _grid.size.x / 2.0, grid_top)
	_play.size = _play.custom_minimum_size
	_play.reset_size()
	var buttons_y := minf(grid_top + _grid.size.y + 26.0, area.end.y - _play.size.y)
	_play.position = Vector2(area.end.x - _play.size.x, buttons_y)
	_back_button.reset_size()
	_back_button.position = Vector2(area.position.x, buttons_y)
	_modes.reset_size()
	_modes.position = Vector2(_play.position.x - 22.0 - _modes.size.x, buttons_y)
	queue_redraw()


## The screen minus the safe-area insets (notch, home indicator) and a margin.
func _area() -> Rect2:
	var vp := get_viewport_rect().size
	var inset := UiStyle.safe_insets(get_viewport())
	var left: float = MARGIN + inset.left
	var top: float = MARGIN * 0.8 + inset.top
	var right: float = vp.x - MARGIN - inset.right
	var bottom: float = vp.y - MARGIN - inset.bottom
	return Rect2(left, top, right - left, bottom - top)


func _draw() -> void:
	var vp := get_viewport_rect().size
	var a := 1.0 if opaque else 0.82
	if opaque:
		draw_rect(Rect2(Vector2.ZERO, vp), Color(0.03, 0.05, 0.07))
	draw_texture_rect(_back, Rect2(Vector2.ZERO, vp), false, Color(1, 1, 1, a))


## Dark backdrop with a soft green glow in the middle.
func _backdrop() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(0.1, 0.2, 0.14))
	g.set_color(1, Color(0.03, 0.05, 0.07))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.45)
	tex.fill_to = Vector2(1.1, 1.1)
	tex.width = 256
	tex.height = 256
	return tex
