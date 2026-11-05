class_name Segmented
extends PanelContainer
## Segmented control: a dark pill with one option per segment; the chosen one
## is gold. Look: UiStyle.

signal changed(index: int)

var selected := 0
var buttons: Array[Button] = []


static func make(
	labels: Array[String], p_selected := 0, font_size := 24, height := 64
) -> Segmented:
	var s := Segmented.new()
	var style := UiStyle.panel(Color(0.05, 0.07, 0.1, 0.9), 99)
	style.set_content_margin_all(5)
	style.shadow_size = 6
	s.add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	s.add_child(row)
	var group := ButtonGroup.new()
	for i in labels.size():
		var b := Button.new()
		b.text = labels[i]
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, height - 10)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", font_size)
		b.add_theme_font_override("font", UiStyle.bold())
		var off := StyleBoxFlat.new()
		off.bg_color = Color(1, 1, 1, 0.0)
		off.set_corner_radius_all(99)
		off.content_margin_left = 22
		off.content_margin_right = 22
		var hover := off.duplicate() as StyleBoxFlat
		hover.bg_color = Color(1, 1, 1, 0.06)
		var on := off.duplicate() as StyleBoxFlat
		on.bg_color = UiStyle.ACCENT
		on.anti_aliasing = true
		b.add_theme_stylebox_override("normal", off)
		b.add_theme_stylebox_override("hover", hover)
		b.add_theme_stylebox_override("pressed", on)
		b.add_theme_stylebox_override("hover_pressed", on)
		b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		b.add_theme_color_override("font_color", UiStyle.MUTED)
		b.add_theme_color_override("font_hover_color", UiStyle.TEXT)
		b.add_theme_color_override("font_pressed_color", UiStyle.ON_ACCENT)
		b.add_theme_color_override("font_hover_pressed_color", UiStyle.ON_ACCENT)
		b.pressed.connect(s._on_pressed.bind(i))
		row.add_child(b)
		s.buttons.append(b)
	s.select(p_selected)
	return s


## Chooses a segment without sending changed.
func select(index: int) -> void:
	selected = clampi(index, 0, buttons.size() - 1)
	for i in buttons.size():
		buttons[i].set_pressed_no_signal(i == selected)


func _on_pressed(index: int) -> void:
	if index == selected:
		return
	select(index)
	changed.emit(index)
