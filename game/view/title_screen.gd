class_name TitleScreen
extends Control
## The start screen over the MenuBackdrop: the name, "Spill", "Innstillinger"
## (with "Vis veiledning") and the stars earned so far. Look: UiStyle.

signal play_pressed
signal tutorial_pressed  # "Vis veiledning" in the settings

const MARGIN := 64.0

var progress: Progress
var _column: VBoxContainer
var _settings: SettingsPanel
var _shade: GradientTexture2D
var _floor: GradientTexture2D


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UiStyle.theme()
	if progress == null:
		progress = Progress.open()
	_shade = _gradient(Color(0.02, 0.04, 0.06, 0.95), Color(0.02, 0.04, 0.06, 0.0), false)
	_shade.gradient.add_point(0.45, Color(0.02, 0.04, 0.06, 0.75))
	_floor = _gradient(Color(0.02, 0.04, 0.06, 0.0), Color(0.02, 0.04, 0.06, 0.75), true)
	_build()
	get_viewport().size_changed.connect(_layout)
	_layout()


func _build() -> void:
	_column = VBoxContainer.new()
	_column.add_theme_constant_override("separation", 0)
	add_child(_column)
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 22)
	var title := UiStyle.label("Mazeborn", 124, UiStyle.TEXT, true)
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.45))
	title.add_theme_constant_override("shadow_offset_y", 6)
	name_row.add_child(title)
	var td := UiStyle.label("TD", 124, UiStyle.ACCENT, true)
	td.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.45))
	td.add_theme_constant_override("shadow_offset_y", 6)
	name_row.add_child(td)
	_column.add_child(name_row)
	var tagline := UiStyle.label("Bygg mazen. Hold fienden ute.", 32, UiStyle.MUTED)
	_column.add_child(tagline)
	_column.add_child(_gap(54))

	var play := _button("Spill", "primary", func() -> void: play_pressed.emit())
	play.custom_minimum_size = Vector2(420, 108)
	play.add_theme_font_size_override("font_size", 44)
	_column.add_child(play)
	_column.add_child(_gap(18))
	var settings := _button("Innstillinger", "secondary", _open_settings)
	settings.custom_minimum_size = Vector2(420, 88)
	_column.add_child(settings)
	_column.add_child(_gap(36))

	var stars := HBoxContainer.new()
	stars.add_theme_constant_override("separation", 10)
	stars.add_child(UiIcon.make("star", UiStyle.GOLD, 30))
	var total := 0
	var maps := Maps.ids()
	for level in Difficulty.ids():
		total += progress.total_stars(level, maps)
	var most := maps.size() * Difficulty.ids().size() * Progress.MAX_STARS
	stars.add_child(UiStyle.label("%d av %d stjerner" % [total, most], 24, UiStyle.TEXT, true))
	_column.add_child(stars)

	_settings = SettingsPanel.new()
	_settings.show_tutorial_button(true)
	_settings.tutorial_pressed.connect(
		func() -> void:
			_settings.close()
			tutorial_pressed.emit()
	)
	add_child(_settings)


func _open_settings() -> void:
	_settings.open()


func _layout() -> void:
	var vp := get_viewport_rect().size
	var inset := UiStyle.safe_insets(get_viewport())
	# Smaller screens get a smaller title column.
	var k := clampf(minf(vp.x / 1700.0, vp.y / 900.0), 0.6, 1.4)
	_column.scale = Vector2(k, k)
	_column.reset_size()
	var left: float = MARGIN * k + inset.left
	_column.position = Vector2(left, (vp.y - _column.size.y * k) / 2.0)
	queue_redraw()


func _draw() -> void:
	var vp := get_viewport_rect().size
	draw_texture_rect(_shade, Rect2(Vector2.ZERO, Vector2(vp.x * 0.75, vp.y)), false)
	draw_texture_rect(_floor, Rect2(Vector2(0, vp.y * 0.55), Vector2(vp.x, vp.y * 0.45)), false)


func _button(text: String, kind: String, on_pressed: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 32)
	UiStyle.style_button(b, kind)
	b.pressed.connect(on_pressed)
	return b


func _gap(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


## A linear gradient from `a` to `b`, left to right (or top to bottom).
static func _gradient(a: Color, b: Color, vertical: bool) -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, a)
	g.set_color(1, b)
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill_from = Vector2.ZERO
	tex.fill_to = Vector2(0, 1) if vertical else Vector2(1, 0)
	tex.width = 64 if not vertical else 4
	tex.height = 64 if vertical else 4
	return tex
