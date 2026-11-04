class_name UiStyle
extends RefCounted
## Shared look of the HUD: colours, fonts and style boxes. Dark glass panels
## with a thin light edge and soft shadow, a warm gold accent for the main
## action, and bold numbers.

const PANEL := Color(0.07, 0.09, 0.12, 0.82)
const PANEL_EDGE := Color(1, 1, 1, 0.09)
const CARD := Color(0.13, 0.16, 0.21, 0.95)
const CARD_HOVER := Color(0.17, 0.2, 0.26, 0.95)
const TEXT := Color(0.95, 0.96, 0.98)
const MUTED := Color(0.62, 0.67, 0.75)
const ACCENT := Color(1.0, 0.76, 0.27)
const ACCENT_DARK := Color(0.85, 0.57, 0.12)
const ON_ACCENT := Color(0.16, 0.1, 0.02)
const GOLD := Color(1.0, 0.8, 0.3)
const LIFE := Color(1.0, 0.38, 0.42)
const DANGER := Color(0.95, 0.36, 0.33)
const GOOD := Color(0.42, 0.9, 0.5)
const RADIUS := 18

static var _bold: FontVariation


## Bold variant of the default font, for numbers and titles.
static func bold() -> Font:
	if _bold == null:
		_bold = FontVariation.new()
		_bold.base_font = ThemeDB.fallback_font
		_bold.variation_embolden = 0.7
	return _bold


static func theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 26
	t.set_color("font_color", "Label", TEXT)
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		t.set_stylebox(state, "Button", button_box("secondary", state))
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", TEXT)
	t.set_color("font_pressed_color", "Button", TEXT)
	t.set_color("font_disabled_color", "Button", Color(TEXT, 0.35))
	t.set_font("font", "Button", bold())
	return t


static func panel(color := PANEL, radius := RADIUS) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(radius)
	s.set_border_width_all(1)
	s.border_color = PANEL_EDGE
	s.shadow_color = Color(0, 0, 0, 0.35)
	s.shadow_size = 10
	s.shadow_offset = Vector2(0, 4)
	s.content_margin_left = 18
	s.content_margin_right = 18
	s.content_margin_top = 12
	s.content_margin_bottom = 12
	s.anti_aliasing = true
	return s


## Button look: "primary" (gold), "secondary" (dark card) or "danger" (red edge).
static func button_box(kind: String, state: String) -> StyleBoxFlat:
	var s := panel(CARD, 16)
	s.shadow_size = 6
	match kind:
		"primary":
			s.bg_color = ACCENT
			s.border_color = Color(1, 0.92, 0.7, 0.8)
			s.border_width_bottom = 4
			s.border_color = ACCENT_DARK
		"danger":
			s.bg_color = Color(0.22, 0.1, 0.11, 0.95)
			s.border_color = Color(DANGER, 0.7)
			s.set_border_width_all(2)
	match state:
		"hover":
			s.bg_color = s.bg_color.lightened(0.08)
		"pressed":
			s.bg_color = s.bg_color.darkened(0.12)
			s.shadow_size = 2
			s.shadow_offset = Vector2(0, 1)
		"disabled":
			s.bg_color = Color(0.16, 0.18, 0.22, 0.75)
			s.border_color = PANEL_EDGE
			s.set_border_width_all(1)
			s.shadow_size = 0
		"focus":
			s.draw_center = false
			s.set_border_width_all(0)
			s.shadow_size = 0
	return s


static func style_button(b: Button, kind: String) -> void:
	for state in ["normal", "hover", "pressed", "disabled", "focus", "hover_pressed"]:
		b.add_theme_stylebox_override(
			state, button_box(kind, "pressed" if state == "hover_pressed" else state)
		)
	if kind == "primary":
		for c in ["font_color", "font_hover_color", "font_pressed_color"]:
			b.add_theme_color_override(c, ON_ACCENT)


## Small rounded label with a coloured background ("Rask", "Boss" ...).
static func chip(text: String, color: Color, size := 18) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_font_override("font", bold())
	var s := StyleBoxFlat.new()
	s.bg_color = Color(color, 0.85)
	s.set_corner_radius_all(99)
	s.content_margin_left = 12
	s.content_margin_right = 12
	s.content_margin_top = 2
	s.content_margin_bottom = 3
	l.add_theme_stylebox_override("normal", s)
	return l


## Safe-area insets (notch, home indicator) of a viewport in canvas units:
## {left, top, right, bottom}.
static func safe_insets(viewport: Viewport) -> Dictionary:
	var vp := viewport.get_visible_rect().size
	var win := Vector2(DisplayServer.window_get_size())
	var safe := Rect2(DisplayServer.get_display_safe_area())
	var out := {"left": 0.0, "top": 0.0, "right": 0.0, "bottom": 0.0}
	if win.x <= 0 or win.y <= 0 or safe.size.x <= 0 or safe.size.y <= 0:
		return out
	var k := vp / win
	out.left = maxf(safe.position.x, 0.0) * k.x
	out.top = maxf(safe.position.y, 0.0) * k.y
	out.right = maxf(win.x - safe.end.x, 0.0) * k.x
	out.bottom = maxf(win.y - safe.end.y, 0.0) * k.y
	return out


static func label(text: String, size := 26, color := TEXT, is_bold := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if is_bold:
		l.add_theme_font_override("font", bold())
	return l
