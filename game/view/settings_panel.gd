class_name SettingsPanel
extends Overlay
## Settings over the title screen or the pause menu: music and sound-effect
## volume (heard at once) and the default game speed for new rounds. Saved in
## user://settings.cfg (UserSettings) when a slider is let go, when closed and
## when the app goes away with the panel open.

signal closed

var settings: UserSettings
var _music: HSlider
var _sfx: HSlider
var _music_value: Label
var _sfx_value: Label
var _speed: Segmented


func _init() -> void:
	super(640.0)
	visible = false
	settings = UserSettings.open()
	add_title("Innstillinger", 48)
	box.add_child(_gap(4))
	_music = _slider_row("Musikk", settings.music_volume)
	_music_value = _music.get_meta("value")
	_sfx = _slider_row("Lydeffekter", settings.sfx_volume)
	_sfx_value = _sfx.get_meta("value")
	_music.value_changed.connect(_on_volume)
	_sfx.value_changed.connect(_on_volume)
	for s: HSlider in [_music, _sfx]:
		s.drag_ended.connect(func(_changed: bool) -> void: settings.save())
	box.add_child(_gap(4))
	var speed_row := HBoxContainer.new()
	speed_row.add_theme_constant_override("separation", 20)
	var speed_text := VBoxContainer.new()
	speed_text.add_theme_constant_override("separation", 0)
	speed_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	speed_text.add_child(UiStyle.label("Standard spillfart", 26, UiStyle.TEXT, true))
	speed_text.add_child(UiStyle.label("Gjelder fra neste runde", 18, UiStyle.MUTED))
	speed_row.add_child(speed_text)
	var labels: Array[String] = []
	for s in UserSettings.SPEEDS:
		labels.append("%dx" % s)
	_speed = Segmented.make(labels, maxi(UserSettings.SPEEDS.find(settings.speed), 0), 24, 64)
	_speed.custom_minimum_size = Vector2(200, 0)
	_speed.changed.connect(
		func(i: int) -> void:
			settings.speed = UserSettings.SPEEDS[i]
			settings.save()
	)
	speed_row.add_child(_speed)
	box.add_child(speed_row)
	box.add_child(_gap(10))
	add_button("Ferdig", "primary", close)


## Shows the panel with the saved settings.
func open() -> void:
	settings = UserSettings.open()
	_music.set_value_no_signal(settings.music_volume)
	_sfx.set_value_no_signal(settings.sfx_volume)
	_speed.select(maxi(UserSettings.SPEEDS.find(settings.speed), 0))
	_show_values()
	super()


func close() -> void:
	settings.save()
	super()
	closed.emit()


## Keeps the volumes when the app goes away with the panel open.
func _notification(what: int) -> void:
	var leaving := what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST
	if leaving and visible and settings:
		settings.save()


func _on_volume(_value: float) -> void:
	settings.music_volume = _music.value
	settings.sfx_volume = _sfx.value
	GameAudio.set_volumes(settings.music_volume, settings.sfx_volume)
	_show_values()


func _show_values() -> void:
	_music_value.text = "%d %%" % roundi(_music.value * 100.0)
	_sfx_value.text = "%d %%" % roundi(_sfx.value * 100.0)


func _slider_row(title: String, value: float) -> HSlider:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	var head := HBoxContainer.new()
	var name_label := UiStyle.label(title, 26, UiStyle.TEXT, true)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(name_label)
	var value_label := UiStyle.label("", 24, UiStyle.MUTED, true)
	head.add_child(value_label)
	col.add_child(head)
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.05
	s.value = value
	s.focus_mode = Control.FOCUS_NONE
	s.custom_minimum_size = Vector2(0, 48)
	UiStyle.style_slider(s)
	s.set_meta("value", value_label)
	col.add_child(s)
	box.add_child(col)
	return s


func _gap(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c
