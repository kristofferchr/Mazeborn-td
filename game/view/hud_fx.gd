class_name HudFx
extends Control
## HUD juice on top of the map: floating damage numbers, a red pulse along the
## screen edges when a creep leaks, and banners when a wave starts or is
## cleared. Reads the game state and its signals; part of the Hud.

const NUMBER_INTERVAL := 0.35  # seconds of damage on one creep summed into one number
const MAX_NUMBERS := 28  # labels in the pool; the oldest is reused when all are busy
const BANNER_HOLD := 2.2  # seconds a banner stays before it slides out
const SHADER := "res://view/shaders/vignette.gdshader"

var game: Game
var board: BoardView
var camera: Camera3D
var banner_top := 100.0  # y where banners slide in to (set by the Hud layout)

var _hp: Dictionary = {}  # creep id -> hp seen last frame
var _pending: Dictionary = {}  # creep id -> damage not shown yet
var _wait: Dictionary = {}  # creep id -> seconds until the next number may show
var _numbers: Array[Label] = []
var _next_number := 0
var _vignette: ColorRect
var _vignette_tween: Tween
var _banner: PanelContainer
var _banner_title: Label
var _banner_sub: Label
var _banner_tween: Tween
var _bonus := 0  # wave bonus and interest paid for the wave being cleared


## Font size of a damage number: small, bigger for hits that take a large
## share of the creep's health or are large on their own.
static func number_size(damage: float, max_hp: float) -> int:
	var share := damage / maxf(max_hp, 1.0)
	if damage >= 250.0 or share >= 0.5:
		return 36
	if damage >= 90.0 or share >= 0.25:
		return 28
	return 21


## Banner title for a wave: "Bølge 5 — Flygende".
static func wave_title(number: int, tags: Array[String]) -> String:
	if tags.is_empty():
		return "Bølge %d" % number
	return "Bølge %d — %s" % [number, ", ".join(tags)]


func setup(p_game: Game, p_board: BoardView, p_camera: Camera3D) -> void:
	game = p_game
	board = p_board
	camera = p_camera
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_vignette()
	_build_banner()
	game.creep_killed.connect(_on_creep_killed)
	game.creep_leaked.connect(_on_creep_leaked)
	game.wave_started.connect(_on_wave_started)
	game.wave_cleared.connect(_on_wave_cleared)
	game.gold_bonus.connect(_on_gold_bonus)


func _process(delta: float) -> void:
	if game == null:
		return
	for creep in game.creeps:
		var last: float = _hp.get(creep.id, creep.max_hp)
		if creep.hp < last:
			_pending[creep.id] = float(_pending.get(creep.id, 0.0)) + last - creep.hp
		_hp[creep.id] = creep.hp
		var wait := float(_wait.get(creep.id, 0.0)) - delta
		_wait[creep.id] = wait
		if wait <= 0.0 and float(_pending.get(creep.id, 0.0)) >= 1.0:
			_show_number(creep, _pending[creep.id])
			_pending[creep.id] = 0.0
			_wait[creep.id] = NUMBER_INTERVAL


func _forget(creep: Creep) -> void:
	_hp.erase(creep.id)
	_pending.erase(creep.id)
	_wait.erase(creep.id)


func _on_creep_killed(creep: Creep) -> void:
	var last: float = _hp.get(creep.id, creep.max_hp)
	var damage := float(_pending.get(creep.id, 0.0)) + maxf(last - creep.hp, 0.0)
	_forget(creep)
	if damage >= 1.0:
		_show_number(creep, damage)


func _on_creep_leaked(creep: Creep) -> void:
	_forget(creep)
	pulse_vignette(0.9 if creep.kind == "boss" else 0.7)


# --- Damage numbers -------------------------------------------------------------


func _show_number(creep: Creep, damage: float) -> void:
	var world := board.creep_world_pos(creep) + Vector3(0, board.creep_top(creep) + 0.55, 0)
	if camera.is_position_behind(world):
		return
	var at := camera.unproject_position(world) + Vector2(randf_range(-26, 26), randf_range(-8, 4))
	var size := number_size(damage, creep.max_hp)
	var label := _number_label()
	label.text = str(roundi(damage))
	label.add_theme_font_size_override("font_size", size)
	var big := size > 21
	label.add_theme_color_override("font_color", Color(1, 0.93, 0.75) if big else Color.WHITE)
	label.reset_size()
	label.pivot_offset = label.size / 2.0
	label.position = at - label.size / 2.0
	label.modulate = Color.WHITE
	label.scale = Vector2.ONE * (1.5 if big else 1.2)
	label.visible = true
	if label.has_meta("tween"):
		(label.get_meta("tween") as Tween).kill()
	var tw := label.create_tween()
	label.set_meta("tween", tw)
	tw.set_parallel()
	tw.tween_property(label, "scale", Vector2.ONE, 0.15).set_ease(Tween.EASE_OUT)
	var rise := 52.0 if big else 38.0
	tw.tween_property(label, "position:y", label.position.y - rise, 0.75).set_ease(Tween.EASE_OUT)
	tw.tween_property(label, "modulate:a", 0.0, 0.3).set_delay(0.45)
	tw.chain().tween_callback(label.hide)


func _number_label() -> Label:
	if _numbers.size() < MAX_NUMBERS:
		var l := UiStyle.label("", 21, Color.WHITE, true)
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
		l.add_theme_constant_override("outline_size", 6)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(l)
		_numbers.append(l)
		return l
	var reused := _numbers[_next_number]
	_next_number = (_next_number + 1) % _numbers.size()
	return reused


# --- Leak vignette --------------------------------------------------------------


func _build_vignette() -> void:
	_vignette = ColorRect.new()
	_vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	m.shader = load(SHADER)
	_vignette.material = m
	_vignette.visible = false
	add_child(_vignette)


## Flashes the red edge glow and lets it fade.
func pulse_vignette(strength: float) -> void:
	var m := _vignette.material as ShaderMaterial
	if _vignette_tween:
		_vignette_tween.kill()
	_vignette.visible = true
	_vignette_tween = create_tween()
	_vignette_tween.tween_method(_set_vignette, 0.0, strength, 0.07)
	_vignette_tween.tween_interval(0.12)
	_vignette_tween.tween_method(_set_vignette, strength, 0.0, 0.7).set_ease(Tween.EASE_IN)
	_vignette_tween.tween_callback(_vignette.hide)
	m.set_shader_parameter("strength", 0.0)


func _set_vignette(value: float) -> void:
	(_vignette.material as ShaderMaterial).set_shader_parameter("strength", value)


# --- Wave banners ---------------------------------------------------------------


func _build_banner() -> void:
	_banner = PanelContainer.new()
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	_banner.add_child(box)
	_banner_title = UiStyle.label("", 40, UiStyle.TEXT, true)
	_banner_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_banner_title)
	_banner_sub = UiStyle.label("", 21, UiStyle.MUTED)
	_banner_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_banner_sub)
	_banner.visible = false
	add_child(_banner)


## Slides a banner in at the top centre, holds it and slides it out.
func show_banner(title: String, sub: String, color: Color) -> void:
	var style := UiStyle.panel(Color(0.07, 0.09, 0.12, 0.9), 22)
	style.border_color = Color(color, 0.85)
	style.set_border_width_all(2)
	style.border_width_bottom = 4
	style.content_margin_left = 40
	style.content_margin_right = 40
	style.content_margin_top = 10
	style.content_margin_bottom = 12
	_banner.add_theme_stylebox_override("panel", style)
	_banner_title.text = title
	_banner_title.add_theme_color_override("font_color", color.lightened(0.25))
	_banner_sub.text = sub
	_banner_sub.visible = sub != ""
	_banner.reset_size()
	var x := (size.x - _banner.size.x) / 2.0
	var hidden_y := -_banner.size.y - 20.0
	_banner.position = Vector2(x, hidden_y)
	_banner.modulate.a = 0.0
	_banner.visible = true
	if _banner_tween:
		_banner_tween.kill()
	_banner_tween = create_tween()
	_banner_tween.set_parallel()
	(
		_banner_tween
		. tween_property(_banner, "position:y", banner_top, 0.45)
		. set_trans(Tween.TRANS_BACK)
		. set_ease(Tween.EASE_OUT)
	)
	_banner_tween.tween_property(_banner, "modulate:a", 1.0, 0.2)
	_banner_tween.chain().tween_interval(BANNER_HOLD)
	_banner_tween.chain().tween_property(_banner, "position:y", hidden_y, 0.35).set_ease(
		Tween.EASE_IN
	)
	_banner_tween.tween_property(_banner, "modulate:a", 0.0, 0.35)
	_banner_tween.chain().tween_callback(_banner.hide)


func _on_wave_started(number: int) -> void:
	_bonus = 0
	var w: Dictionary = game.waves[number - 1]
	var tags := game.wave_tags(w)
	var color := UiStyle.ACCENT
	if tags.size() > 0:
		color = Hud.TAG_COLORS.get(tags[0], color)
	if "Boss" in tags:
		color = Hud.TAG_COLORS.Boss
	var count := game.wave_count(w)
	var sub := "%d %s" % [count, "fiende" if count == 1 else "fiender"]
	if number == game.waves.size():
		sub += "  ·  siste bølge!"
	show_banner(wave_title(number, tags), sub, color)


func _on_gold_bonus(amount: int, reason: String) -> void:
	if reason == "wave" or reason == "interest":
		_bonus += amount


func _on_wave_cleared(number: int) -> void:
	if number >= game.waves.size() or game.is_over():
		return  # the end screen takes over
	var sub := "+%d gull i bonus" % _bonus if _bonus > 0 else ""
	show_banner("Bølge %d klart" % number, sub, UiStyle.GOOD)
