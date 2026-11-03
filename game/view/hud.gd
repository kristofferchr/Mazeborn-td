class_name Hud
extends CanvasLayer
## Heads-up display: gold, lives, wave, start/speed buttons, the selection panel,
## health bars over creeps and the end-of-round screen. Reads the game state;
## user actions are sent out as signals.

signal start_wave_pressed
signal build_pressed
signal kind_selected(kind: String)
signal upgrade_pressed
signal sell_pressed
signal targeting_pressed
signal speed_pressed
signal retry_pressed

const MARGIN := 20.0
const TAG_COLORS := {
	"Rask": Color(0.2, 0.55, 0.85),
	"Pansret": Color(0.45, 0.45, 0.5),
	"Flygende": Color(0.55, 0.3, 0.8),
	"Boss": Color(0.75, 0.2, 0.2),
}

var game: Game
var board: BoardView
var camera: Camera3D

var _root: Control
var _gold: Label
var _lives: Label
var _wave: Label
var _start: Button
var _next: PanelContainer
var _next_title: Label
var _next_body: Label
var _next_tags: HBoxContainer
var _next_shown := -1  # wave index shown in the next-wave card
var _speed: Button
var _panel: PanelContainer
var _info: Label
var _build_row: HBoxContainer
var _kind_buttons: Dictionary = {}  # kind -> Button
var _build_button: Button
var _tower_row: HBoxContainer
var _upgrade: Button
var _targeting: Button
var _sell: Button
var _end: Control
var _end_title: Label
var _end_text: Label
var _bars: Control
var _ui: Array[Control] = []  # controls that swallow taps


func setup(p_game: Game, p_board: BoardView, p_camera: Camera3D) -> void:
	game = p_game
	board = p_board
	camera = p_camera
	_build()
	game.game_over.connect(_on_game_over)
	get_viewport().size_changed.connect(_layout)
	_layout()


## True if a screen position is on a HUD control (so the tap is not for the map).
func is_over_ui(pos: Vector2) -> bool:
	if _end.visible:
		return true
	for c in _ui:
		if c.is_visible_in_tree() and c.get_global_rect().grow(6.0).has_point(pos):
			return true
	return false


## Updates the selection panel: the build menu on a free cell, or the selected
## tower's info with upgrade, targeting and sell.
func show_selection(cell: Vector2i, has_selection: bool, build_kind: String) -> void:
	_panel.visible = has_selection
	if not has_selection:
		return
	var tower := game.tower_at(cell)
	_build_row.visible = tower == null
	_layout.call_deferred()
	_tower_row.visible = tower != null
	if tower == null:
		var s := game.tower_level_stats(build_kind)
		_info.text = (
			"%s · %d gull\n%s"
			% [game.tower_name(build_kind), game.build_cost(build_kind), _describe(build_kind, s)]
		)
		for kind: String in _kind_buttons:
			var b: Button = _kind_buttons[kind]
			b.button_pressed = kind == build_kind
			b.modulate = Color.WHITE if game.can_afford(kind) else Color(1, 1, 1, 0.45)
		_build_button.disabled = not game.can_build(cell, build_kind)
	else:
		_info.text = (
			"%s · nivå %d/%d\n%s"
			% [
				tower.display_name(),
				tower.level + 1,
				tower.max_level() + 1,
				_describe(tower.kind, tower.stats()),
			]
		)
		if tower.can_upgrade():
			_upgrade.text = "Oppgrader %d" % tower.upgrade_cost()
			_upgrade.disabled = not game.can_upgrade(cell)
		else:
			_upgrade.text = "Maks nivå"
			_upgrade.disabled = true
		_sell.text = "Selg +%d" % game.refund_for(tower)
		_sell.disabled = game.is_over()
		_targeting.text = (
			"Mål: først" if tower.targeting == Tower.Targeting.FIRST else "Mål: nærmest"
		)


## One line of stats and effects for a tower kind at some level.
func _describe(kind: String, s: Dictionary) -> String:
	var parts: Array[String] = [
		"Skade %d–%d" % [int(s.damage_min), int(s.damage_max)],
		"%.1f/s" % (1.0 / float(s.cooldown)),
		"rekkevidde %.1f" % float(s.range),
	]
	if s.has("splash_radius"):
		parts.append("splash %.1f" % float(s.splash_radius))
	if s.has("slow"):
		parts.append("sakker ned %d %%" % roundi(float(s.slow) * 100.0))
	if s.has("poison_dps"):
		parts.append("gift %d/s ×%d" % [int(s.poison_dps), int(s.get("poison_stacks", 1))])
	var targets: Array = game.tower_defs[kind].get("targets", ["ground"])
	if "air" in targets and "ground" in targets:
		parts.append("bakke og luft")
	elif "air" in targets:
		parts.append("bare luft")
	return " · ".join(parts)


func set_speed_text(text: String) -> void:
	_speed.text = text


func _process(_delta: float) -> void:
	if game == null:
		return
	_gold.text = "Gull %d" % game.gold
	_lives.text = "Liv %d" % game.lives
	_wave.text = "Bølge %d/%d" % [game.wave, game.waves.size()]
	_start.disabled = not game.can_start_wave()
	if game.can_send_early():
		_start.text = "Send neste +%d" % game.early_bonus
	elif game.phase == Game.Phase.WAVE:
		_start.text = "Bølge pågår"
	else:
		_start.text = "Start bølge"
	_update_next_wave()
	_bars.queue_redraw()


## Card above the start button: what the next wave holds (count, health, tags).
func _update_next_wave() -> void:
	var shown := game.wave if not game.is_over() else -1
	if shown == _next_shown:
		return
	_next_shown = shown
	var w := game.next_wave()
	_next.visible = not w.is_empty() and not game.is_over()
	if not _next.visible:
		return
	_next_title.text = "Neste: bølge %d" % (game.wave + 1)
	var lines: Array[String] = []
	for g in Game.wave_groups(w):
		var count := int(g.count)
		var kind := str(g.get("creep", "normal"))
		var creep_name := str(game.creep_defs.get(kind, {}).get("name", kind)).to_lower()
		if kind == "normal":
			creep_name = "fiende" if count == 1 else "fiender"
		lines.append("%d %s · %d HP" % [count, creep_name, int(g.hp)])
	_next_body.text = "\n".join(lines)
	for child in _next_tags.get_children():
		_next_tags.remove_child(child)
		child.queue_free()
	var tags := game.wave_tags(w)
	_next_tags.visible = not tags.is_empty()
	for tag in tags:
		var chip := Label.new()
		chip.text = tag
		chip.add_theme_font_size_override("font_size", 20)
		var style := _box(TAG_COLORS.get(tag, Color(0.4, 0.4, 0.45)))
		style.content_margin_top = 2
		style.content_margin_bottom = 2
		style.content_margin_left = 10
		style.content_margin_right = 10
		chip.add_theme_stylebox_override("normal", style)
		_next_tags.add_child(chip)
	_layout()


func _build() -> void:
	var theme := Theme.new()
	theme.default_font_size = 28
	_root = Control.new()
	_root.theme = theme
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_bars = Control.new()
	_bars.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bars.draw.connect(_draw_bars)
	_root.add_child(_bars)

	var top := HBoxContainer.new()
	top.name = "Top"
	top.add_theme_constant_override("separation", 12)
	_root.add_child(top)
	_gold = _stat(top, Color(1.0, 0.85, 0.3))
	_lives = _stat(top, Color(1.0, 0.5, 0.5))
	_wave = _stat(top, Color(0.85, 0.9, 1.0))

	_speed = _button("1x", func() -> void: speed_pressed.emit())
	_speed.custom_minimum_size = Vector2(96, 72)
	_root.add_child(_speed)

	_start = _button("Start bølge", func() -> void: start_wave_pressed.emit())
	_start.custom_minimum_size = Vector2(260, 96)
	_start.add_theme_font_size_override("font_size", 34)
	_root.add_child(_start)

	_next = PanelContainer.new()
	_next.add_theme_stylebox_override("panel", _box(Color(0.08, 0.08, 0.1, 0.75)))
	var next_box := VBoxContainer.new()
	next_box.add_theme_constant_override("separation", 4)
	_next.add_child(next_box)
	_next_title = Label.new()
	_next_title.add_theme_font_size_override("font_size", 20)
	_next_title.add_theme_color_override("font_color", Color(0.75, 0.78, 0.85))
	next_box.add_child(_next_title)
	_next_body = Label.new()
	_next_body.add_theme_font_size_override("font_size", 26)
	next_box.add_child(_next_body)
	_next_tags = HBoxContainer.new()
	_next_tags.add_theme_constant_override("separation", 8)
	next_box.add_child(_next_tags)
	_next.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_next)

	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", _box(Color(0.08, 0.08, 0.1, 0.82)))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	_panel.add_child(col)
	_info = Label.new()
	_info.add_theme_font_size_override("font_size", 22)
	col.add_child(_info)
	_build_row = HBoxContainer.new()
	_build_row.add_theme_constant_override("separation", 8)
	col.add_child(_build_row)
	for kind in game.tower_order:
		var b := _button(
			"%s\n%d" % [game.tower_name(kind).trim_suffix("tårn"), game.build_cost(kind)],
			func() -> void: kind_selected.emit(kind)
		)
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(112, 84)
		b.add_theme_font_size_override("font_size", 22)
		var normal := _box(BoardView.tower_color(kind).darkened(0.55))
		var pressed := _box(BoardView.tower_color(kind).darkened(0.1))
		pressed.set_border_width_all(3)
		pressed.border_color = Color(1.0, 0.9, 0.4)
		b.add_theme_stylebox_override("normal", normal)
		b.add_theme_stylebox_override("hover", normal)
		b.add_theme_stylebox_override("pressed", pressed)
		b.add_theme_stylebox_override("hover_pressed", pressed)
		_kind_buttons[kind] = b
		_build_row.add_child(b)
	_build_button = _button("Bygg", func() -> void: build_pressed.emit())
	_build_button.custom_minimum_size = Vector2(150, 84)
	_build_row.add_child(_build_button)
	_tower_row = HBoxContainer.new()
	_tower_row.add_theme_constant_override("separation", 12)
	col.add_child(_tower_row)
	_upgrade = _button("Oppgrader", func() -> void: upgrade_pressed.emit())
	_upgrade.custom_minimum_size = Vector2(220, 80)
	_tower_row.add_child(_upgrade)
	_targeting = _button("Mål: først", func() -> void: targeting_pressed.emit())
	_targeting.custom_minimum_size = Vector2(190, 80)
	_targeting.add_theme_font_size_override("font_size", 22)
	_tower_row.add_child(_targeting)
	_sell = _button("Selg", func() -> void: sell_pressed.emit())
	_sell.custom_minimum_size = Vector2(160, 80)
	_tower_row.add_child(_sell)
	_panel.visible = false
	_root.add_child(_panel)

	_end = ColorRect.new()
	(_end as ColorRect).color = Color(0, 0, 0, 0.6)
	_end.set_anchors_preset(Control.PRESET_FULL_RECT)
	_end.visible = false
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_end.add_child(center)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 20)
	center.add_child(box)
	_end_title = Label.new()
	_end_title.add_theme_font_size_override("font_size", 72)
	_end_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_end_title)
	_end_text = Label.new()
	_end_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_end_text)
	var retry := _button("Prøv igjen", func() -> void: retry_pressed.emit())
	retry.custom_minimum_size = Vector2(300, 96)
	retry.add_theme_font_size_override("font_size", 36)
	box.add_child(retry)
	_root.add_child(_end)

	_ui = [top, _speed, _start, _panel]


func _stat(parent: Control, color: Color) -> Label:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _box(Color(0.08, 0.08, 0.1, 0.75)))
	var label := Label.new()
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", 30)
	panel.add_child(label)
	parent.add_child(panel)
	return label


func _button(text: String, on_pressed: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(on_pressed)
	return b


func _box(color: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(10)
	s.content_margin_left = 16
	s.content_margin_right = 16
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	return s


## Safe-area insets (notch, home indicator) in canvas units.
func _safe_insets() -> Dictionary:
	var vp := get_viewport().get_visible_rect().size
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


func _layout() -> void:
	var vp := get_viewport().get_visible_rect().size
	var inset := _safe_insets()
	var left: float = MARGIN + inset.left
	var right: float = vp.x - MARGIN - inset.right
	var top: float = MARGIN + inset.top
	var bottom: float = vp.y - MARGIN - inset.bottom
	var top_bar := _root.get_node("Top") as Control
	top_bar.position = Vector2(left, top)
	_speed.size = _speed.custom_minimum_size
	_speed.position = Vector2(right - _speed.size.x, top)
	_start.size = _start.custom_minimum_size
	_start.position = Vector2(right - _start.size.x, bottom - _start.size.y)
	_next.reset_size()
	_next.size.x = maxf(_next.size.x, _start.size.x)
	_next.position = Vector2(right - _next.size.x, _start.position.y - 10.0 - _next.size.y)
	_panel.reset_size()
	_panel.position = Vector2(left, bottom - _panel.size.y)


func _draw_bars() -> void:
	if game == null or camera == null:
		return
	for creep in game.creeps:
		var world := board.creep_world_pos(creep)
		var scale := BoardView.creep_scale(creep)
		world.y += board.creep_top(creep) + 0.15
		if camera.is_position_behind(world):
			continue
		var p := camera.unproject_position(world)
		var w := 44.0 * clampf(scale, 1.0, 1.6)
		var rect := Rect2(p - Vector2(w / 2.0, 4.0), Vector2(w, 8.0))
		_bars.draw_rect(rect.grow(1.5), Color(0, 0, 0, 0.8))
		var f := clampf(creep.hp / creep.max_hp, 0.0, 1.0)
		var col := Color(0.9, 0.2, 0.15).lerp(Color(0.3, 0.95, 0.3), f)
		_bars.draw_rect(Rect2(rect.position, Vector2(w * f, rect.size.y)), col)


func _on_game_over(won: bool) -> void:
	_panel.visible = false
	_next.visible = false
	_end.visible = true
	if won:
		_end_title.text = "Seier!"
		_end_text.text = (
			"Du holdt stand gjennom alle %d bølgene med %d liv igjen."
			% [game.waves.size(), game.lives]
		)
	else:
		_end_title.text = "Tapt"
		_end_text.text = "Fiendene slapp gjennom på bølge %d." % game.wave
