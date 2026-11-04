class_name Hud
extends CanvasLayer
## Heads-up display: resources, wave controls, the next-wave card, the build
## menu and tower panel, health bars, floating gold, the mute button and the
## end screen. Damage numbers, wave banners and the leak glow: HudFx.
## Reads the game state; user actions are sent out as signals. Look: UiStyle.

signal start_wave_pressed
signal build_pressed
signal kind_selected(kind: String)
signal upgrade_pressed(option: String)
signal sell_pressed
signal targeting_pressed
signal speed_pressed
signal mute_pressed
signal retry_pressed
signal maps_pressed

const MARGIN := 20.0
const TAG_COLORS := {
	"Rask": Color(0.2, 0.55, 0.85),
	"Pansret": Color(0.45, 0.47, 0.53),
	"Flygende": Color(0.55, 0.3, 0.8),
	"Helbreder": Color(0.22, 0.62, 0.32),
	"Skjold": Color(0.3, 0.4, 0.92),
	"Deler seg": Color(0.5, 0.62, 0.15),
	"Immun": Color(0.85, 0.5, 0.12),
	"Usynlig": Color(0.15, 0.55, 0.55),
	"Boss": Color(0.8, 0.22, 0.22),
}
const CREEP_DOTS := {
	"normal": Color(0.85, 0.4, 0.35),
	"fast": Color(0.95, 0.75, 0.25),
	"armored": Color(0.6, 0.63, 0.7),
	"flying": Color(0.65, 0.45, 0.95),
	"healer": Color(0.4, 0.9, 0.5),
	"shielded": Color(0.45, 0.6, 1.0),
	"splitter": Color(0.65, 0.85, 0.3),
	"spawnling": Color(0.65, 0.85, 0.3),
	"immune": Color(1.0, 0.6, 0.2),
	"invisible": Color(0.4, 0.8, 0.8),
	"miniboss": Color(0.9, 0.35, 0.3),
	"boss": Color(0.9, 0.2, 0.25),
}
const SHIELD_BAR := Color(0.4, 0.65, 1.0)
const INVULNERABLE_BAR := Color(1.0, 0.88, 0.45)
const THUMB := 112  # tower thumbnail size in pixels

var game: Game
var board: BoardView
var camera: Camera3D

var _root: Control
var _top: PanelContainer
var _gold: Label
var _lives: Label
var _wave: Label
var _speed: Button
var _mute: Button
var _mute_icon: UiIcon
var _start: Button
var _next: PanelContainer
var _next_title: Label
var _next_rows: VBoxContainer
var _next_tags: HBoxContainer
var _next_shown := -2  # wave shown in the next-wave card
var _panel: PanelContainer
var _info_title: Label
var _info_stats: Label
var _build_row: HBoxContainer
var _kind_cards: Dictionary = {}  # kind -> Button
var _kind_prices: Dictionary = {}  # kind -> Label
var _build_button: Button
var _tower_row: HBoxContainer
var _tower_thumb: TextureRect
var _pips: HBoxContainer
var _upgrades: HBoxContainer  # one card per upgrade option
var _upgrades_key := ""  # tower and node the cards were made for
var _targeting: Button
var _sell: Button
var _end: Control
var _end_title: Label
var _end_text: Label
var _end_stats: Label
var _bars: Control
var _floaters: Control
var _fx: HudFx
var _thumbs: Dictionary = {}  # "kind:level:element" -> ViewportTexture
var _thumb_life: Dictionary = {}  # SubViewport -> frames left to render
var _ui: Array[Control] = []  # controls that swallow taps


func setup(p_game: Game, p_board: BoardView, p_camera: Camera3D) -> void:
	game = p_game
	board = p_board
	camera = p_camera
	_build()
	game.game_over.connect(_on_game_over)
	game.creep_killed.connect(_on_creep_killed)
	game.gold_bonus.connect(_on_gold_bonus)
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
func show_selection(
	cell: Vector2i, has_selection: bool, build_kind: String, buildable: bool
) -> void:
	_panel.visible = has_selection
	if not has_selection:
		return
	var tower := game.tower_at(cell)
	_build_row.visible = tower == null
	_tower_row.visible = tower != null
	_pips.visible = tower != null
	if tower == null:
		_info_title.text = game.tower_name(build_kind)
		_info_stats.text = _describe(build_kind, game.tower_base_stats(build_kind))
		for kind: String in _kind_cards:
			var card: Button = _kind_cards[kind]
			card.button_pressed = kind == build_kind
			var afford := game.can_afford(kind)
			card.modulate = Color.WHITE if afford else Color(1, 1, 1, 0.5)
			var price: Label = _kind_prices[kind]
			price.add_theme_color_override("font_color", UiStyle.GOLD if afford else UiStyle.DANGER)
		_build_button.disabled = not buildable
	else:
		_info_title.text = tower.display_name()
		_info_stats.text = _describe(tower.kind, tower.stats())
		_tower_thumb.texture = _thumb(tower.kind, tower.level, tower.element())
		for i in _pips.get_child_count():
			var pip := _pips.get_child(i) as Panel
			pip.visible = i <= tower.max_level()
			(pip.get_theme_stylebox("panel") as StyleBoxFlat).bg_color = (
				UiStyle.ACCENT if i <= tower.level else Color(1, 1, 1, 0.15)
			)
		_update_upgrades(cell, tower)
		_sell.text = "Selg  +%d" % game.refund_for(tower)
		_sell.disabled = game.is_over()
		_targeting.text = "Først" if tower.targeting == Tower.Targeting.FIRST else "Nærmest"
	_layout.call_deferred()


func set_speed_text(text: String) -> void:
	_speed.text = text


## Shows the sound on/off icon on the mute button.
func set_muted(muted: bool) -> void:
	_mute_icon.kind = "sound_off" if muted else "sound"
	_mute_icon.color = UiStyle.MUTED if muted else UiStyle.TEXT
	_mute_icon.queue_redraw()


func _process(_delta: float) -> void:
	if game == null:
		return
	_gold.text = str(game.gold)
	_lives.text = str(game.lives)
	_wave.text = "%d/%d" % [game.wave, game.waves.size()]
	_start.disabled = not game.can_start_wave()
	if game.can_send_early():
		_start.text = "Send neste  +%d" % game.early_bonus
	elif game.phase == Game.Phase.WAVE:
		_start.text = "Bølge pågår"
	else:
		_start.text = "Start bølge"
	_update_next_wave()
	_bars.queue_redraw()
	# Thumbnails render for a few frames, then their viewports stop updating.
	for view: SubViewport in _thumb_life.keys():
		_thumb_life[view] -= 1
		if _thumb_life[view] <= 0:
			view.render_target_update_mode = SubViewport.UPDATE_DISABLED
			_thumb_life.erase(view)


## Cards for the upgrades of the selected tower: rebuilt when the tower or its
## node changes, enabled while the player can pay.
func _update_upgrades(cell: Vector2i, tower: Tower) -> void:
	var key := "%s:%s" % [cell, tower.node_id]
	if key != _upgrades_key:
		_upgrades_key = key
		for child in _upgrades.get_children():
			_upgrades.remove_child(child)
			child.queue_free()
		var options := tower.upgrade_options()
		for option in options:
			_upgrades.add_child(_upgrade_card(tower, option))
		if options.is_empty():
			var done := UiStyle.label("Maks nivå", 22, UiStyle.MUTED, true)
			done.custom_minimum_size = Vector2(150, 0)
			done.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			done.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			done.size_flags_vertical = Control.SIZE_EXPAND_FILL
			_upgrades.add_child(done)
	for card in _upgrades.get_children():
		if card is Button:
			var option: String = card.get_meta("option")
			var ok := game.can_upgrade(cell, option)
			card.disabled = not ok
			card.modulate = Color.WHITE if ok else Color(1, 1, 1, 0.55)


func _upgrade_card(tower: Tower, option: String) -> Button:
	var node := tower.node(option)
	var card := Button.new()
	card.focus_mode = Control.FOCUS_NONE
	card.custom_minimum_size = Vector2(132, 164)
	card.set_meta("option", option)
	var normal := UiStyle.button_box("secondary", "normal")
	var element := str(node.get("element", ""))
	if element != "":
		normal.border_color = Color(BoardView.ELEMENT_COLORS[element], 0.8)
		normal.set_border_width_all(2)
	card.add_theme_stylebox_override("normal", normal)
	card.add_theme_stylebox_override("disabled", normal)
	card.pressed.connect(func() -> void: upgrade_pressed.emit(option))
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.add_theme_constant_override("separation", 0)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(box)
	var thumb := TextureRect.new()
	thumb.texture = _thumb(tower.kind, tower.level + 1, element)
	thumb.custom_minimum_size = Vector2(0, 54)
	thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(thumb)
	var title := str(node.get("name", option))
	if element == "" and title == tower.display_name():
		title = "Nivå %d" % (tower.level + 2)
	var name_label := UiStyle.label(title, 20, UiStyle.TEXT, true)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(name_label)
	var desc := UiStyle.label(str(node.get("desc", "")), 14, UiStyle.MUTED)
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(120, 0)
	box.add_child(desc)
	var price_row := HBoxContainer.new()
	price_row.alignment = BoxContainer.ALIGNMENT_CENTER
	price_row.add_theme_constant_override("separation", 4)
	price_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	price_row.add_child(UiIcon.make("coin", UiStyle.GOLD, 16))
	price_row.add_child(UiStyle.label(str(int(node.cost)), 18, UiStyle.GOLD, true))
	box.add_child(price_row)
	return card


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
		var what := "brann" if str(s.get("element", "")) == "fire" else "gift"
		parts.append("%s %d/s ×%d" % [what, int(s.poison_dps), int(s.get("poison_stacks", 1))])
	if s.has("stun"):
		parts.append("stun %.1fs" % float(s.stun))
	if s.has("knockback"):
		parts.append("skyver tilbake")
	if s.has("air_multiplier"):
		parts.append("×%.1f mot luft" % float(s.air_multiplier))
	if s.has("chain"):
		parts.append("hopper %d" % int(s.chain))
	if s.has("multishot"):
		parts.append("%d mål" % int(s.multishot))
	if s.get("armor_pierce", false):
		parts.append("gjennom rustning")
	if s.get("reveal", false):
		parts.append("avslører usynlige")
	var targets: Array = game.tower_defs[kind].get("targets", ["ground"])
	if "air" in targets and "ground" in targets:
		parts.append("bakke og luft")
	elif "air" in targets:
		parts.append("bare luft")
	return "  ·  ".join(parts)


## Card above the start button: what the next wave holds.
func _update_next_wave() -> void:
	var shown := game.wave if not game.is_over() else -1
	if shown == _next_shown:
		return
	_next_shown = shown
	var w := game.next_wave()
	_next.visible = not w.is_empty() and not game.is_over()
	if not _next.visible:
		return
	_next_title.text = "NESTE  ·  BØLGE %d" % (game.wave + 1)
	for child in _next_rows.get_children() + _next_tags.get_children():
		child.get_parent().remove_child(child)
		child.queue_free()
	for g in Game.wave_groups(w):
		_next_rows.add_child(_next_row(g))
	var tags := game.wave_tags(w)
	_next_tags.visible = not tags.is_empty()
	for tag in tags:
		_next_tags.add_child(UiStyle.chip(tag, TAG_COLORS.get(tag, Color(0.4, 0.4, 0.45))))
	_layout.call_deferred()


func _next_row(g: Dictionary) -> HBoxContainer:
	var kind := str(g.get("creep", "normal"))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var dot := UiIcon.make("dot", CREEP_DOTS.get(kind, UiStyle.MUTED), 14)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(dot)
	var count := int(g.count)
	var creep_name := str(game.creep_defs.get(kind, {}).get("name", kind)).to_lower()
	if kind == "normal":
		creep_name = "fiende" if count == 1 else "fiender"
	row.add_child(UiStyle.label("%d × %s" % [count, creep_name], 24, UiStyle.TEXT, true))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.custom_minimum_size = Vector2(16, 0)
	row.add_child(spacer)
	row.add_child(UiStyle.label("%d HP" % roundi(game.creep_hp(g)), 22, UiStyle.MUTED))
	return row


# --- Building the UI ------------------------------------------------------------


func _build() -> void:
	_root = Control.new()
	_root.theme = UiStyle.theme()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_bars = _overlay()
	_bars.draw.connect(_draw_bars)
	_fx = HudFx.new()
	_root.add_child(_fx)
	_fx.setup(game, board, camera)
	_floaters = _overlay()

	# Resources: one pill with gold, lives and wave.
	_top = PanelContainer.new()
	var top_style := UiStyle.panel(UiStyle.PANEL, 99)
	top_style.content_margin_left = 22
	top_style.content_margin_right = 26
	top_style.content_margin_top = 8
	top_style.content_margin_bottom = 8
	_top.add_theme_stylebox_override("panel", top_style)
	var stats := HBoxContainer.new()
	stats.add_theme_constant_override("separation", 14)
	_top.add_child(stats)
	_gold = _stat(stats, "coin", UiStyle.GOLD)
	_divider(stats)
	_lives = _stat(stats, "heart", UiStyle.LIFE)
	_divider(stats)
	_wave = _stat(stats, "flag", Color(0.6, 0.8, 1.0))
	_root.add_child(_top)

	_speed = _button("1x", "secondary", func() -> void: speed_pressed.emit())
	_speed.custom_minimum_size = Vector2(92, 72)
	_root.add_child(_speed)

	_mute = _button("", "secondary", func() -> void: mute_pressed.emit())
	_mute.custom_minimum_size = Vector2(72, 72)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mute.add_child(center)
	_mute_icon = UiIcon.make("sound", UiStyle.TEXT, 36)
	center.add_child(_mute_icon)
	_root.add_child(_mute)

	_start = _button("Start bølge", "primary", func() -> void: start_wave_pressed.emit())
	_start.custom_minimum_size = Vector2(300, 92)
	_start.add_theme_font_size_override("font_size", 32)
	_root.add_child(_start)

	_build_next_card()
	_build_panel()
	_build_end_screen()
	_ui = [_top, _speed, _mute, _start, _panel]


func _build_next_card() -> void:
	_next = PanelContainer.new()
	_next.add_theme_stylebox_override("panel", UiStyle.panel())
	_next.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_next.add_child(box)
	_next_title = UiStyle.label("", 17, UiStyle.MUTED, true)
	box.add_child(_next_title)
	_next_rows = VBoxContainer.new()
	_next_rows.add_theme_constant_override("separation", 2)
	box.add_child(_next_rows)
	_next_tags = HBoxContainer.new()
	_next_tags.add_theme_constant_override("separation", 8)
	box.add_child(_next_tags)
	_root.add_child(_next)


func _build_panel() -> void:
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", UiStyle.panel())
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	_panel.add_child(col)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	col.add_child(head)
	_info_title = UiStyle.label("", 26, UiStyle.TEXT, true)
	head.add_child(_info_title)
	_pips = HBoxContainer.new()
	_pips.add_theme_constant_override("separation", 6)
	_pips.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for i in 3:
		var pip := Panel.new()
		pip.custom_minimum_size = Vector2(22, 8)
		var s := StyleBoxFlat.new()
		s.set_corner_radius_all(4)
		pip.add_theme_stylebox_override("panel", s)
		_pips.add_child(pip)
	head.add_child(_pips)
	_info_stats = UiStyle.label("", 19, UiStyle.MUTED)
	col.add_child(_info_stats)

	# Build menu: a card per tower kind and the build button.
	_build_row = HBoxContainer.new()
	_build_row.add_theme_constant_override("separation", 10)
	col.add_child(_build_row)
	for kind in game.tower_order:
		_build_row.add_child(_kind_card(kind))
	_build_button = _button("Bygg", "primary", func() -> void: build_pressed.emit())
	_build_button.custom_minimum_size = Vector2(150, 0)
	_build_button.add_theme_font_size_override("font_size", 30)
	_build_row.add_child(_build_button)

	# Selected tower: thumbnail, upgrade, targeting and sell.
	_tower_row = HBoxContainer.new()
	_tower_row.add_theme_constant_override("separation", 12)
	col.add_child(_tower_row)
	_tower_thumb = TextureRect.new()
	_tower_thumb.custom_minimum_size = Vector2(84, 84)
	_tower_thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_tower_thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_tower_row.add_child(_tower_thumb)
	_upgrades = HBoxContainer.new()
	_upgrades.add_theme_constant_override("separation", 10)
	_tower_row.add_child(_upgrades)
	_targeting = _button("Først", "secondary", func() -> void: targeting_pressed.emit())
	_targeting.custom_minimum_size = Vector2(130, 84)
	_tower_row.add_child(_targeting)
	_sell = _button("Selg", "danger", func() -> void: sell_pressed.emit())
	_sell.custom_minimum_size = Vector2(140, 84)
	_tower_row.add_child(_sell)
	_panel.visible = false
	_root.add_child(_panel)


func _kind_card(kind: String) -> Button:
	var card := Button.new()
	card.toggle_mode = true
	card.focus_mode = Control.FOCUS_NONE
	card.custom_minimum_size = Vector2(118, 150)
	var selected := UiStyle.button_box("secondary", "hover")
	selected.bg_color = BoardView.tower_color(kind).darkened(0.6)
	selected.set_border_width_all(3)
	selected.border_color = UiStyle.ACCENT
	card.add_theme_stylebox_override("normal", UiStyle.button_box("secondary", "normal"))
	card.add_theme_stylebox_override("hover", UiStyle.button_box("secondary", "hover"))
	card.add_theme_stylebox_override("pressed", selected)
	card.add_theme_stylebox_override("hover_pressed", selected)
	card.add_theme_stylebox_override("focus", UiStyle.button_box("secondary", "focus"))
	card.pressed.connect(func() -> void: kind_selected.emit(kind))
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.add_theme_constant_override("separation", 0)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(box)
	var thumb := TextureRect.new()
	thumb.texture = _thumb(kind, 0, "")
	thumb.custom_minimum_size = Vector2(0, 82)
	thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(thumb)
	var title := game.tower_name(kind).trim_suffix("tårn")
	var name_label := UiStyle.label(title, 21, UiStyle.TEXT, true)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(name_label)
	var price_row := HBoxContainer.new()
	price_row.alignment = BoxContainer.ALIGNMENT_CENTER
	price_row.add_theme_constant_override("separation", 4)
	price_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	price_row.add_child(UiIcon.make("coin", UiStyle.GOLD, 18))
	var price := UiStyle.label(str(game.build_cost(kind)), 20, UiStyle.GOLD, true)
	price_row.add_child(price)
	box.add_child(price_row)
	_kind_cards[kind] = card
	_kind_prices[kind] = price
	return card


func _build_end_screen() -> void:
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.03, 0.05, 0.7)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_end = shade
	_end.visible = false
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_end.add_child(center)
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
	_end_title = UiStyle.label("", 76, UiStyle.ACCENT, true)
	_end_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_end_title)
	_end_text = UiStyle.label("", 26, UiStyle.TEXT)
	_end_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_end_text)
	_end_stats = UiStyle.label("", 22, UiStyle.MUTED)
	_end_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_end_stats)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 10)
	box.add_child(gap)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 16)
	box.add_child(buttons)
	var maps := _button("Velg kart", "secondary", func() -> void: maps_pressed.emit())
	maps.custom_minimum_size = Vector2(240, 96)
	maps.add_theme_font_size_override("font_size", 30)
	buttons.add_child(maps)
	var retry := _button("Prøv igjen", "primary", func() -> void: retry_pressed.emit())
	retry.custom_minimum_size = Vector2(300, 96)
	retry.add_theme_font_size_override("font_size", 34)
	buttons.add_child(retry)
	_root.add_child(_end)


func _overlay() -> Control:
	var c := Control.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(c)
	return c


func _stat(parent: Control, icon: String, color: Color) -> Label:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var i := UiIcon.make(icon, color, 30)
	i.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(i)
	var label := UiStyle.label("", 32, UiStyle.TEXT, true)
	row.add_child(label)
	parent.add_child(row)
	return label


func _divider(parent: Control) -> void:
	var d := ColorRect.new()
	d.color = Color(1, 1, 1, 0.12)
	d.custom_minimum_size = Vector2(2, 30)
	d.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	parent.add_child(d)


func _button(text: String, kind: String, on_pressed: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 26)
	UiStyle.style_button(b, kind)
	b.pressed.connect(on_pressed)
	return b


## A small transparent picture of a tower kind at a level and element, rendered
## on demand for the menus and cached.
func _thumb(kind: String, level: int, element: String) -> Texture2D:
	var key := "%s:%d:%s" % [kind, level, element]
	if _thumbs.has(key):
		return _thumbs[key]
	var view := SubViewport.new()
	view.size = Vector2i(THUMB, THUMB)
	view.transparent_bg = true
	view.own_world_3d = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var model := board.tower_preview(kind, level, element)
	view.add_child(model)
	var top: float = model.get_meta("top", 1.5)
	var look := Vector3(0, top * 0.45, 0)
	var cam := Camera3D.new()
	cam.fov = 30.0
	view.add_child(cam)
	cam.look_at_from_position(look + Vector3(1.6, 1.3, 2.6).normalized() * (top * 2.6 + 1.0), look)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 35, 0)
	view.add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.75, 0.78, 0.9)
	view.add_child(env)
	add_child(view)
	_thumb_life[view] = 8
	_thumbs[key] = view.get_texture()
	return _thumbs[key]


# --- Layout and drawing --------------------------------------------------------


func _layout() -> void:
	var vp := get_viewport().get_visible_rect().size
	var inset := UiStyle.safe_insets(get_viewport())
	var left: float = MARGIN + inset.left
	var right: float = vp.x - MARGIN - inset.right
	var top: float = MARGIN + inset.top
	var bottom: float = vp.y - MARGIN - inset.bottom
	_top.reset_size()
	_top.position = Vector2(left, top)
	_speed.size = _speed.custom_minimum_size
	_speed.position = Vector2(right - _speed.size.x, top)
	_mute.size = _mute.custom_minimum_size
	_mute.position = Vector2(_speed.position.x - 12.0 - _mute.size.x, top)
	_fx.banner_top = top + maxf(_top.size.y, _speed.size.y) + 18.0
	_start.size = _start.custom_minimum_size
	_start.position = Vector2(right - _start.size.x, bottom - _start.size.y)
	_next.reset_size()
	_next.size.x = maxf(_next.size.x, _start.size.x)
	_next.position = Vector2(right - _next.size.x, _start.position.y - 14.0 - _next.size.y)
	_panel.reset_size()
	_panel.position = Vector2(left, bottom - _panel.size.y)


func _draw_bars() -> void:
	if game == null or camera == null:
		return
	var back := StyleBoxFlat.new()
	back.bg_color = Color(0.05, 0.05, 0.07, 0.85)
	back.set_corner_radius_all(4)
	var fill := StyleBoxFlat.new()
	fill.set_corner_radius_all(3)
	for creep in game.creeps:
		var world := board.creep_world_pos(creep)
		world.y += board.creep_top(creep) + 0.15
		if camera.is_position_behind(world):
			continue
		var p := camera.unproject_position(world)
		var w := 90.0 if creep.boss else 46.0
		# Hidden invisible creeps get faint bars.
		var a := 0.4 if creep.invisible and not creep.revealed else 1.0
		back.bg_color.a = 0.85 * a
		var rect := Rect2(p - Vector2(w / 2.0, 4.0), Vector2(w, 8.0))
		_bars.draw_style_box(back, rect.grow(2.0))
		if creep.max_shield > 0.0 and creep.shield > 0.0:
			var shield_rect := Rect2(rect.position - Vector2(0, 9.0), Vector2(w, 5.0))
			_bars.draw_style_box(back, shield_rect.grow(2.0))
			fill.bg_color = Color(SHIELD_BAR, a)
			var sf := clampf(creep.shield / creep.max_shield, 0.0, 1.0)
			_bars.draw_style_box(
				fill, Rect2(shield_rect.position, Vector2(maxf(w * sf, 5.0), shield_rect.size.y))
			)
		var f := clampf(creep.hp / creep.max_hp, 0.0, 1.0)
		if f <= 0.0:
			continue
		var col := UiStyle.DANGER
		if creep.invulnerable_time > 0.0:
			col = INVULNERABLE_BAR
		elif f > 0.6:
			col = UiStyle.GOOD
		elif f > 0.3:
			col = UiStyle.ACCENT
		fill.bg_color = Color(col, a)
		_bars.draw_style_box(fill, Rect2(rect.position, Vector2(maxf(w * f, 6.0), rect.size.y)))


## "+3" in gold rising from a killed creep.
func _on_creep_killed(creep: Creep) -> void:
	var world := board.creep_world_pos(creep) + Vector3(0, board.creep_top(creep) + 0.3, 0)
	if camera.is_position_behind(world):
		return
	_float_text("+%d" % creep.bounty, camera.unproject_position(world), 26, true)


## Wave bonus, interest and early send pop up next to the resources.
func _on_gold_bonus(amount: int, reason: String) -> void:
	var what: String = {"wave": "bølgebonus", "interest": "rente", "early": "tidlig"}.get(
		reason, ""
	)
	var at := _top.position + Vector2(_top.size.x + 20.0, _top.size.y / 2.0)
	if reason == "interest":
		at.y += 34.0
	_float_text("+%d %s" % [amount, what], at, 24, false)


func _float_text(text: String, at: Vector2, size: int, centered: bool) -> void:
	var l := UiStyle.label(text, size, UiStyle.GOLD, true)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	l.add_theme_constant_override("outline_size", 6)
	_floaters.add_child(l)
	l.reset_size()
	l.position = at - (l.size / 2.0 if centered else Vector2(0, l.size.y / 2.0))
	var tw := l.create_tween()
	tw.set_parallel()
	tw.tween_property(l, "position:y", l.position.y - 46.0, 0.9).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 0.55).set_delay(0.35)
	tw.chain().tween_callback(l.queue_free)


func _on_game_over(won: bool) -> void:
	_panel.visible = false
	_next.visible = false
	_end.visible = true
	_end_stats.text = (
		"%s   ·   Bølge %d av %d   ·   %d liv   ·   %d gull"
		% [game.map.get("name", "Kart"), game.wave, game.waves.size(), game.lives, game.gold]
	)
	if won:
		_end_title.text = "Seier!"
		_end_title.add_theme_color_override("font_color", UiStyle.ACCENT)
		_end_text.text = "Mazen holdt gjennom alle bølgene."
	else:
		_end_title.text = "Tapt"
		_end_title.add_theme_color_override("font_color", UiStyle.DANGER)
		_end_text.text = "Fiendene slapp gjennom på bølge %d." % game.wave
