class_name MapSelect
extends Control
## Map select before a round: a card per map (schematic, name, description and
## chips), an "Endeløs" toggle (the endless mode) and a "Spill" button for the
## chosen one. Look: UiStyle.

signal play_pressed(map_id: String, options: Dictionary)

const MARGIN := 40.0
const GAP := 22

var selected := Maps.DEFAULT
var endless := false  # play the endless mode

var _cards: Dictionary = {}  # map id -> Button
var _grid: GridContainer
var _play: Button
var _endless: Button
var _title: Label
var _subtitle: Label
var _back: Texture2D


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = UiStyle.theme()
	_build()
	get_viewport().size_changed.connect(_layout)
	_select(selected if _cards.has(selected) else Maps.DEFAULT)
	_layout()


func _build() -> void:
	_back = _backdrop()
	_title = UiStyle.label("Velg kart", 54, UiStyle.TEXT, true)
	add_child(_title)
	_subtitle = UiStyle.label("Mazeborn TD  ·  bygg mazen, hold fienden ute", 22, UiStyle.MUTED)
	add_child(_subtitle)

	_grid = GridContainer.new()
	_grid.add_theme_constant_override("h_separation", GAP)
	_grid.add_theme_constant_override("v_separation", GAP)
	add_child(_grid)
	for id in Maps.ids():
		var card := _card(Maps.load_map(id))
		_grid.add_child(card)
		_cards[id] = card

	_play = Button.new()
	_play.text = "Spill"
	_play.focus_mode = Control.FOCUS_NONE
	_play.custom_minimum_size = Vector2(320, 96)
	_play.add_theme_font_size_override("font_size", 38)
	UiStyle.style_button(_play, "primary")
	_play.pressed.connect(func() -> void: play_pressed.emit(selected, options()))
	add_child(_play)

	_endless = Button.new()
	_endless.toggle_mode = true
	_endless.focus_mode = Control.FOCUS_NONE
	_endless.custom_minimum_size = Vector2(0, 96)
	_endless.add_theme_font_size_override("font_size", 28)
	var off := UiStyle.button_box("secondary", "normal")
	off.set_corner_radius_all(99)
	off.content_margin_left = 30
	off.content_margin_right = 30
	var on := off.duplicate() as StyleBoxFlat
	on.bg_color = Color(0.36, 0.2, 0.5, 0.97)
	on.border_color = Color(0.75, 0.55, 1.0)
	on.set_border_width_all(3)
	for state: String in ["normal", "hover", "focus"]:
		_endless.add_theme_stylebox_override(state, off)
	for state: String in ["pressed", "hover_pressed"]:
		_endless.add_theme_stylebox_override(state, on)
	_endless.button_pressed = endless
	_endless.toggled.connect(_set_endless)
	add_child(_endless)
	_set_endless(endless)


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
	var title := UiStyle.label(str(m.name), 30, UiStyle.TEXT, true)
	box.add_child(title)
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
	return card


## Round options for Game: {"mode": "endless"} when the toggle is on.
func options() -> Dictionary:
	return {"mode": "endless"} if endless else {}


func _set_endless(on: bool) -> void:
	endless = on
	_endless.text = "∞  Endeløs: på" if on else "∞  Endeløs: av"
	_endless.reset_size()
	if _play:
		_place()


func _select(id: String) -> void:
	selected = id
	for key: String in _cards:
		(_cards[key] as Button).set_pressed_no_signal(key == id)
	if _play:
		_play.text = "Spill  %s" % Maps.load_map(id).name


## Cards in one row on wide screens and in two on narrower ones, sized to fit
## inside the safe area.
func _layout() -> void:
	var area := _area()
	var cols := 4 if area.size.x >= 1100 and area.size.x / area.size.y >= 1.5 else 2
	_grid.columns = cols
	var rows := ceili(_cards.size() / float(cols))
	var w := clampf((area.size.x - GAP * (cols - 1)) / cols, 240.0, 560.0)
	var h := clampf((area.size.y - 230.0 - GAP * (rows - 1)) / rows, 220.0, 420.0)
	for card: Button in _cards.values():
		card.custom_minimum_size = Vector2(w, h)
		var preview := card.find_child("Preview", true, false) as Control
		preview.custom_minimum_size.y = clampf(h * 0.38, 90.0, 170.0)
	_place()
	_fit_cards.call_deferred()


## Makes every card tall enough for its wrapped text (known after layout).
func _fit_cards() -> void:
	var need := 0.0
	for card: Button in _cards.values():
		var box := card.get_child(0) as Control
		need = maxf(need, box.get_combined_minimum_size().y + 34.0)
	for card: Button in _cards.values():
		card.custom_minimum_size.y = maxf(card.custom_minimum_size.y, need)
	_place()


func _place() -> void:
	var area := _area()
	_grid.reset_size()
	_title.position = area.position
	_subtitle.position = area.position + Vector2(2, 68)
	var grid_top := area.position.y + 116.0
	_grid.position = Vector2(area.get_center().x - _grid.size.x / 2.0, grid_top)
	_play.size = _play.custom_minimum_size
	_play.reset_size()
	_play.position = Vector2(
		area.end.x - _play.size.x, minf(grid_top + _grid.size.y + 26.0, area.end.y - _play.size.y)
	)
	_endless.size = Vector2.ZERO
	_endless.reset_size()
	_endless.position = Vector2(_play.position.x - 18.0 - _endless.size.x, _play.position.y)
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
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0.03, 0.05, 0.07))
	draw_texture_rect(_back, Rect2(Vector2.ZERO, vp), false)


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
