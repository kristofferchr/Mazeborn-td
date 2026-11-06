class_name WaveOverview
extends PanelContainer
## Overview of the waves left, opened from the next-wave card in the Hud: a
## header (tap it to close) over a scrolling list with a card per wave
## (number, enemy count, groups with health, tags). Boss waves get a red card
## and the next wave a gold edge. In endless it lists the next ENDLESS_AHEAD.
## Reads the game state. Look: UiStyle, colours: Hud.

signal close_pressed

const ENDLESS_AHEAD := 12
const BOSS_CARD := Color(0.26, 0.09, 0.1, 0.96)

var game: Game

var _title: Label
var _scroll: ScrollContainer
var _list: VBoxContainer
var _shown := -2  # wave the list was made for


## Chip for a wave tag in its colour.
static func tag_chip(tag: String, size := 18) -> Label:
	return UiStyle.chip(tag, Hud.TAG_COLORS.get(tag, Color(0.4, 0.4, 0.45)), size)


## One group of a wave: a dot in the creep colour, "10 × rask" and its health.
static func group_row(p_game: Game, g: Dictionary, size := 24) -> HBoxContainer:
	var kind := str(g.get("creep", "normal"))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	var dot := UiIcon.make("dot", Hud.CREEP_DOTS.get(kind, UiStyle.MUTED), size * 0.58)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(dot)
	var count := int(g.count)
	var creep_name := str(p_game.creep_defs.get(kind, {}).get("name", kind)).to_lower()
	if kind == "normal":
		creep_name = "fiende" if count == 1 else "fiender"
	row.add_child(UiStyle.label("%d × %s" % [count, creep_name], size, UiStyle.TEXT, true))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.custom_minimum_size = Vector2(16, 0)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(spacer)
	row.add_child(UiStyle.label("%d HP" % roundi(p_game.creep_hp(g)), size - 2, UiStyle.MUTED))
	return row


func setup(p_game: Game) -> void:
	game = p_game
	var style := UiStyle.panel(Color(0.07, 0.09, 0.12, 0.93))
	style.content_margin_left = 14
	style.content_margin_right = 14
	add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	add_child(box)
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_STOP
	head.custom_minimum_size = Vector2(0, 44)
	head.gui_input.connect(_on_head_input)
	box.add_child(head)
	_title = UiStyle.label("", 17, UiStyle.MUTED, true)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(_title)
	var close := UiStyle.label("Lukk  ▾", 17, UiStyle.ACCENT, true)
	close.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(close)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 8)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.mouse_filter = Control.MOUSE_FILTER_PASS
	_scroll.add_child(_list)


## Wave numbers listed: every scripted wave left, in endless the next
## ENDLESS_AHEAD.
func listed_waves() -> Array[int]:
	var out: Array[int] = []
	var last := game.wave + ENDLESS_AHEAD if game.endless else game.waves.size()
	for n in range(game.wave + 1, last + 1):
		if game.has_wave(n):
			out.append(n)
	return out


## Rebuilds the list when a new wave has started (or `force`).
func refresh(force := false) -> void:
	if _shown == game.wave and not force:
		return
	_shown = game.wave
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	var numbers := listed_waves()
	if game.endless:
		_title.text = "KOMMENDE BØLGER  ·  ENDELØS"
	else:
		_title.text = "BØLGER IGJEN  ·  %d" % numbers.size()
	for n in numbers:
		_list.add_child(_wave_card(n, game.wave_data(n)))
	_scroll.scroll_vertical = 0


func _wave_card(number: int, w: Dictionary) -> PanelContainer:
	var tags := game.wave_tags(w)
	var boss := "Boss" in tags
	var next := number == game.wave + 1
	var style := UiStyle.panel(UiStyle.CARD, 14)
	style.shadow_size = 0
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 10
	style.content_margin_bottom = 12
	if boss:
		style.bg_color = BOSS_CARD
		style.border_color = Color(Hud.TAG_COLORS.Boss, 0.95)
		style.set_border_width_all(2)
	elif next:
		style.border_color = Color(UiStyle.ACCENT, 0.8)
		style.set_border_width_all(2)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", style)
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.mouse_filter = Control.MOUSE_FILTER_PASS
	card.add_child(box)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	head.mouse_filter = Control.MOUSE_FILTER_PASS
	box.add_child(head)
	var title_color: Color = Hud.TAG_COLORS.Boss.lightened(0.45) if boss else UiStyle.TEXT
	head.add_child(UiStyle.label("Bølge %d" % number, 24, title_color, true))
	if next:
		var chip := UiStyle.chip("Neste", UiStyle.ACCENT_DARK, 15)
		chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		head.add_child(chip)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(spacer)
	var count := game.wave_count(w)
	var total := UiStyle.label(
		"%d %s" % [count, "fiende" if count == 1 else "fiender"], 19, UiStyle.MUTED
	)
	total.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(total)
	for g in Game.wave_groups(w):
		box.add_child(group_row(game, g, 20))
	if not tags.is_empty():
		var chips := HFlowContainer.new()
		chips.add_theme_constant_override("h_separation", 6)
		chips.add_theme_constant_override("v_separation", 4)
		chips.mouse_filter = Control.MOUSE_FILTER_PASS
		for tag in tags:
			chips.add_child(tag_chip(tag, 15))
		box.add_child(chips)
	return card


func _on_head_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		close_pressed.emit()
