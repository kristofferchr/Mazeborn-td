class_name UiIcon
extends Control
## Small vector icons drawn in code (no image files): dot, coin, heart, flag,
## speed, sound and sound_off.

var kind := "coin"
var color := Color.WHITE


static func make(p_kind: String, p_color: Color, size := 30.0) -> UiIcon:
	var icon := UiIcon.new()
	icon.kind = p_kind
	icon.color = p_color
	icon.custom_minimum_size = Vector2(size, size)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return icon


func _draw() -> void:
	var s := minf(size.x, size.y)
	var c := size / 2.0
	match kind:
		"dot":
			draw_circle(c, s * 0.45, color)
		"coin":
			draw_circle(c, s * 0.46, color.darkened(0.3))
			draw_circle(c - Vector2(0, s * 0.04), s * 0.42, color)
			draw_circle(c - Vector2(0, s * 0.04), s * 0.26, color.lightened(0.25))
			draw_circle(c - Vector2(0, s * 0.04), s * 0.18, color)
		"heart":
			var r := s * 0.24
			draw_circle(c + Vector2(-r * 0.95, -r * 0.45), r, color)
			draw_circle(c + Vector2(r * 0.95, -r * 0.45), r, color)
			draw_colored_polygon(
				PackedVector2Array(
					[
						c + Vector2(-r * 1.9, -r * 0.2),
						c + Vector2(r * 1.9, -r * 0.2),
						c + Vector2(0, r * 2.0),
					]
				),
				color
			)
		"flag":
			var x := c.x - s * 0.28
			draw_rect(Rect2(x, c.y - s * 0.42, s * 0.08, s * 0.86), color.darkened(0.2))
			draw_colored_polygon(
				PackedVector2Array(
					[
						Vector2(x + s * 0.08, c.y - s * 0.42),
						Vector2(x + s * 0.68, c.y - s * 0.22),
						Vector2(x + s * 0.08, c.y - s * 0.02),
					]
				),
				color
			)
		"speed":
			for i in 2:
				var x0 := c.x - s * 0.36 + i * s * 0.34
				draw_colored_polygon(
					PackedVector2Array(
						[
							Vector2(x0, c.y - s * 0.3),
							Vector2(x0 + s * 0.36, c.y),
							Vector2(x0, c.y + s * 0.3),
						]
					),
					color
				)
		"sound", "sound_off":
			_draw_speaker(c, s)


## A speaker with sound waves, or crossed out with an x.
func _draw_speaker(c: Vector2, s: float) -> void:
	var x := c.x - s * 0.34
	draw_rect(Rect2(x, c.y - s * 0.12, s * 0.16, s * 0.24), color)
	draw_colored_polygon(
		PackedVector2Array(
			[
				Vector2(x + s * 0.12, c.y - s * 0.12),
				Vector2(x + s * 0.36, c.y - s * 0.32),
				Vector2(x + s * 0.36, c.y + s * 0.32),
				Vector2(x + s * 0.12, c.y + s * 0.12),
			]
		),
		color
	)
	var w := maxf(s * 0.07, 1.5)
	var o := Vector2(x + s * 0.42, c.y)
	if kind == "sound":
		for r: float in [s * 0.14, s * 0.27]:
			draw_arc(o, r, -PI * 0.3, PI * 0.3, 12, color, w, true)
	else:
		var a := Vector2(o.x + s * 0.06, c.y - s * 0.14)
		var d := s * 0.26
		draw_line(a, a + Vector2(d, d), color, w, true)
		draw_line(a + Vector2(0, d), a + Vector2(d, 0), color, w, true)
