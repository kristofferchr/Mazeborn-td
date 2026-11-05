class_name Overlay
extends ColorRect
## A modal layer: a dark shade over the whole screen that swallows every tap,
## with a glass card in the middle. Content goes into `box`. Keeps working
## while the tree is paused. Used by the pause menu and the settings.

var card: PanelContainer
var box: VBoxContainer


func _init(min_width := 560.0) -> void:
	color = Color(0.02, 0.03, 0.05, 0.72)
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	card = PanelContainer.new()
	var style := UiStyle.panel(Color(0.09, 0.11, 0.15, 0.96), 28)
	style.content_margin_left = 48
	style.content_margin_right = 48
	style.content_margin_top = 32
	style.content_margin_bottom = 36
	card.add_theme_stylebox_override("panel", style)
	card.custom_minimum_size = Vector2(min_width, 0)
	center.add_child(card)
	box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	card.add_child(box)


## A big centered title for the card.
func add_title(text: String, size := 54) -> Label:
	var l := UiStyle.label(text, size, UiStyle.TEXT, true)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(l)
	return l


## A full-width button in the card.
func add_button(text: String, kind: String, on_pressed: Callable, height := 84.0) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, height)
	b.add_theme_font_size_override("font_size", 30)
	UiStyle.style_button(b, kind)
	b.pressed.connect(on_pressed)
	box.add_child(b)
	return b


func open() -> void:
	visible = true
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.15)


func close() -> void:
	visible = false
