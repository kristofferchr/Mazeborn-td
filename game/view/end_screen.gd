class_name EndScreen
extends ColorRect
## The end of a round over the map: the title (Seier!, Tapt, or the wave
## reached in endless), the stars and "Ny rekord!", a line on how it went, the
## map, level and result, and the buttons Velg kart, Del replay and Prøv igjen.
## Part of the Hud, which passes the button presses on.

signal maps_pressed
signal share_pressed
signal retry_pressed

var _stars: HBoxContainer
var _title: Label
var _record: Label
var _text: Label
var _stats: Label


func _init() -> void:
	color = Color(0.02, 0.03, 0.05, 0.7)
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var card := PanelContainer.new()
	var style := UiStyle.panel(Color(0.09, 0.11, 0.15, 0.96), 28)
	style.content_margin_left = 56
	style.content_margin_right = 56
	style.content_margin_top = 36
	style.content_margin_bottom = 40
	card.add_theme_stylebox_override("panel", style)
	center.add_child(card)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 14)
	card.add_child(box)
	_stars = UiStyle.stars(0, 64)
	_stars.alignment = BoxContainer.ALIGNMENT_CENTER
	_stars.visible = false
	box.add_child(_stars)
	_title = UiStyle.label("", 76, UiStyle.ACCENT, true)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_title)
	_record = UiStyle.chip("Ny rekord!", UiStyle.ACCENT_DARK, 24)
	_record.add_theme_color_override("font_color", UiStyle.ON_ACCENT)
	_record.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_record.visible = false
	box.add_child(_record)
	_text = UiStyle.label("", 26, UiStyle.TEXT)
	_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_text)
	_stats = UiStyle.label("", 22, UiStyle.MUTED)
	_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_stats)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 10)
	box.add_child(gap)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 16)
	box.add_child(buttons)
	buttons.add_child(_button("Velg kart", "secondary", maps_pressed.emit, 240.0, 30))
	buttons.add_child(_button("Del replay", "secondary", share_pressed.emit, 260.0, 30))
	buttons.add_child(_button("Prøv igjen", "primary", retry_pressed.emit, 300.0, 34))


## Shows the screen with the texts for how the round ended.
func show_for(game: Game, won: bool) -> void:
	visible = true
	var parts: Array[String] = [
		str(game.map.get("name", "Kart")),
		Difficulty.display_name(game.difficulty),
		"Endeløs" if game.endless else Hud.wave_text(game),
		"%d liv" % game.lives,
		"%d gull" % game.gold,
	]
	_stats.text = "   ·   ".join(parts)
	if game.endless:
		_title.text = "Bølge %d" % game.score()
		_title.add_theme_color_override("font_color", UiStyle.ACCENT)
		_text.text = (
			"Endeløs: mazen holdt til og med bølge %d." % game.score()
			if game.score() > 0
			else "Endeløs: fiendene slapp gjennom på første bølge."
		)
	elif won:
		_title.text = "Seier!"
		_title.add_theme_color_override("font_color", UiStyle.ACCENT)
		_text.text = "Mazen holdt gjennom alle bølgene."
	else:
		_title.text = "Tapt"
		_title.add_theme_color_override("font_color", UiStyle.DANGER)
		_text.text = "Fiendene slapp gjennom på bølge %d." % game.wave


## Stars (shown for a won round) and "Ny rekord!".
func show_result(stars: int, won: bool, new_record: bool) -> void:
	UiStyle.set_stars(_stars, stars)
	_stars.visible = won
	_record.visible = new_record
	if _stars.visible:
		for i in _stars.get_child_count():
			var star := _stars.get_child(i) as Control
			star.pivot_offset = star.custom_minimum_size / 2.0
			star.scale = Vector2.ZERO
			var tw := star.create_tween()
			tw.tween_interval(0.25 + 0.18 * i)
			(
				tw
				. tween_property(star, "scale", Vector2.ONE, 0.35)
				. set_trans(Tween.TRANS_BACK)
				. set_ease(Tween.EASE_OUT)
			)
	if new_record:
		var pulse := _record.create_tween().set_loops()
		pulse.tween_property(_record, "modulate:a", 0.7, 0.6)
		pulse.tween_property(_record, "modulate:a", 1.0, 0.6)


func _button(text: String, kind: String, on_pressed: Callable, width: float, font: int) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(width, 96)
	b.add_theme_font_size_override("font_size", font)
	UiStyle.style_button(b, kind)
	b.pressed.connect(on_pressed)
	return b
