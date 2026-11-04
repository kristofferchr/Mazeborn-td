class_name MapSelect
extends Control
## Map select before a round: a card per map (schematic, name, description and
## chips) and a "Spill" button for the chosen one. Look: UiStyle.

signal play_pressed(map_id: String)

const MARGIN := 40.0
const GAP := 22

var selected := Maps.DEFAULT

var _cards: Dictionary = {}  # map id -> Button
var _grid: GridContainer
var _play: Button
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
	_play.pressed.connect(func() -> void: play_pressed.emit(selected))
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


func _select(id: String) -> void:
	selected = id
	for key: String in _cards:
		(_cards[key] as Button).set_pressed_no_signal(key == id)
	if _play:
		_play.text = "Spill  %s" % Maps.load_map(id).name


## Cards in one row on wide screens and in two on narrower ones, sized to fit.
func _layout() -> void:
	var vp := get_viewport_rect().size
	var cols := 4 if vp.x >= 1200 and vp.x / vp.y >= 1.6 else 2
	_grid.columns = cols
	var rows := ceili(_cards.size() / float(cols))
	var w := clampf((vp.x - MARGIN * 2.0 - GAP * (cols - 1)) / cols, 240.0, 560.0)
	var h := clampf((vp.y - 300.0 - GAP * (rows - 1)) / rows, 220.0, 420.0)
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
	var vp := get_viewport_rect().size
	_grid.reset_size()
	var top := MARGIN * 0.8
	_title.position = Vector2(MARGIN, top)
	_subtitle.position = Vector2(MARGIN + 2, top + 68)
	var grid_top := top + 116.0
	_grid.position = Vector2((vp.x - _grid.size.x) / 2.0, grid_top)
	_play.size = _play.custom_minimum_size
	_play.reset_size()
	_play.position = Vector2(
		vp.x - MARGIN - _play.size.x, minf(grid_top + _grid.size.y + 26.0, vp.y - MARGIN - 96)
	)
	queue_redraw()


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
