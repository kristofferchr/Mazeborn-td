class_name Toast
extends Control
## Short notices that drop in at the top centre, stay a moment and fade out
## ("Rekord!", "Veiledningen er ferdig"). One shows at a time; later ones wait
## in a queue. A glass pill with a coloured edge, an optional icon (UiIcon
## kind), a bold title and an optional muted line. Never takes taps. Put it
## full-rect over the screen and set `top` to where notices should sit.
## Look: UiStyle.

const HOLD := 2.4  # seconds a notice stays
const IN_SECONDS := 0.35
const OUT_SECONDS := 0.3
const MAX_QUEUE := 4

var top := 140.0  # y of the notice's top edge
var queue: Array[Dictionary] = []  # notices waiting: {title, sub, icon, color}
var current: Dictionary = {}  # the notice on screen, {} when none

var _pill: PanelContainer
var _icon: UiIcon
var _title: Label
var _sub: Label
var _tween: Tween


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	_pill = PanelContainer.new()
	_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pill.visible = false
	add_child(_pill)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pill.add_child(row)
	_icon = UiIcon.make("star", UiStyle.GOLD, 40)
	_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_icon)
	var lines := VBoxContainer.new()
	lines.add_theme_constant_override("separation", -2)
	lines.alignment = BoxContainer.ALIGNMENT_CENTER
	lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(lines)
	_title = UiStyle.label("", 32, UiStyle.TEXT, true)
	lines.add_child(_title)
	_sub = UiStyle.label("", 20, UiStyle.MUTED)
	lines.add_child(_sub)


## Shows a notice now, or after the ones already waiting. `icon` is a UiIcon
## kind ("" for none). Returns false when the queue is full (it is dropped).
func show_toast(title: String, sub := "", icon := "star", color := UiStyle.ACCENT) -> bool:
	var notice := {"title": title, "sub": sub, "icon": icon, "color": color}
	if not current.is_empty() or not queue.is_empty():
		if queue.size() >= MAX_QUEUE:
			return false
		queue.append(notice)
		return true
	_show(notice)
	return true


## True while a notice is on screen or waiting.
func is_busy() -> bool:
	return not current.is_empty() or not queue.is_empty()


func _show(notice: Dictionary) -> void:
	current = notice
	var color: Color = notice.color
	var style := UiStyle.panel(Color(0.07, 0.09, 0.12, 0.92), 99)
	style.border_color = Color(color, 0.9)
	style.set_border_width_all(2)
	style.content_margin_left = 30
	style.content_margin_right = 38
	style.content_margin_top = 10
	style.content_margin_bottom = 12
	_pill.add_theme_stylebox_override("panel", style)
	_icon.visible = str(notice.icon) != ""
	_icon.kind = str(notice.icon)
	_icon.color = color
	_icon.queue_redraw()
	_title.text = str(notice.title)
	_title.add_theme_color_override("font_color", color.lightened(0.3))
	_sub.text = str(notice.sub)
	_sub.visible = _sub.text != ""
	_pill.reset_size()
	_pill.pivot_offset = _pill.size / 2.0
	_pill.position = Vector2((size.x - _pill.size.x) / 2.0, top - 24.0)
	_pill.modulate.a = 0.0
	_pill.scale = Vector2.ONE * 0.92
	_pill.visible = true
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.set_parallel()
	(
		_tween
		. tween_property(_pill, "position:y", top, IN_SECONDS)
		. set_trans(Tween.TRANS_BACK)
		. set_ease(Tween.EASE_OUT)
	)
	_tween.tween_property(_pill, "modulate:a", 1.0, IN_SECONDS * 0.6)
	_tween.tween_property(_pill, "scale", Vector2.ONE, IN_SECONDS).set_ease(Tween.EASE_OUT)
	_tween.chain().tween_interval(HOLD)
	_tween.chain().tween_property(_pill, "modulate:a", 0.0, OUT_SECONDS)
	_tween.tween_property(_pill, "position:y", top - 16.0, OUT_SECONDS)
	_tween.chain().tween_callback(_next)


## Takes the next notice from the queue (or hides the pill).
func _next() -> void:
	current = {}
	_pill.visible = false
	if not queue.is_empty():
		_show(queue.pop_front())
