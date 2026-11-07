class_name Toast
extends RefCounted
## Short messages ("Kopiert") at the bottom centre of the screen that fade out.
## One at a time: a new one replaces the one still showing.

const HOLD := 1.6  # seconds fully visible
const FADE := 0.4
const NODE_NAME := "Toast"


## Shows text over `parent` (a full-screen control), `bottom` pixels above the
## bottom edge. Returns the label (it frees itself).
static func pop(parent: Control, text: String, bottom := 60.0) -> Label:
	var old := parent.get_node_or_null(NODE_NAME)
	if old:
		parent.remove_child(old)
		old.queue_free()
	var l := UiStyle.chip(text, UiStyle.ACCENT_DARK, 30)
	l.name = NODE_NAME
	l.add_theme_color_override("font_color", UiStyle.ON_ACCENT)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	l.reset_size()
	var area := parent.get_viewport_rect().size
	l.position = Vector2((area.x - l.size.x) / 2.0, area.y - bottom - l.size.y)
	var tw := l.create_tween()
	tw.tween_interval(HOLD)
	tw.tween_property(l, "modulate:a", 0.0, FADE)
	tw.tween_callback(l.queue_free)
	return l
