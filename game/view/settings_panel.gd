class_name SettingsPanel
extends Overlay
## Settings over the title screen or the pause menu: music and sound-effect
## volume (heard at once: the effects slider clicks), the default game speed
## for new rounds, vibration (Haptics) and, over the title screen, "Vis
## veiledning" to play the guided first round again. Saved in
## user://settings.cfg (UserSettings) when a slider is let go, when closed and
## when the app goes away with the panel open.

signal closed
signal tutorial_pressed  # "Vis veiledning" (only shown with show_tutorial_button)

var settings: UserSettings
var _music: HSlider
var _sfx: HSlider
var _music_value: Label
var _sfx_value: Label
var _speed: Segmented
var _vibration: Segmented
var _tutorial: Button


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
	var labels: Array[String] = []
	for s in UserSettings.SPEEDS:
		labels.append("%dx" % s)
	var speed_at := maxi(UserSettings.SPEEDS.find(settings.speed), 0)
	_speed = _choice_row("Standard spillfart", "Gjelder fra neste runde", labels, speed_at)
	_speed.changed.connect(
		func(i: int) -> void:
			settings.speed = UserSettings.SPEEDS[i]
			settings.save()
	)
	var hint := "Små støt når du bygger og når fiender slipper gjennom"
	if not Haptics.supported:
		hint = "Ikke på denne enheten"
	var on_off: Array[String] = ["På", "Av"]
	_vibration = _choice_row("Vibrasjon", hint, on_off, 0 if settings.vibration else 1)
	_vibration.changed.connect(_on_vibration)
	box.add_child(_gap(10))
	_tutorial = add_button("Vis veiledning", "secondary", func() -> void: tutorial_pressed.emit())
	_tutorial.visible = false
	add_button("Ferdig", "primary", close)


## Shows the panel with the saved settings.
func open() -> void:
	settings = UserSettings.open()
	_music.set_value_no_signal(settings.music_volume)
	_sfx.set_value_no_signal(settings.sfx_volume)
	_speed.select(maxi(UserSettings.SPEEDS.find(settings.speed), 0))
	_vibration.select(0 if settings.vibration else 1)
	_show_values()
	super()


## Shows "Vis veiledning" (over the title screen, not in a round).
func show_tutorial_button(on: bool) -> void:
	_tutorial.visible = on


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


func _on_vibration(i: int) -> void:
	settings.vibration = i == 0
	settings.save()
	Haptics.load_setting(settings)
	Haptics.light()  # feel it


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


## A row with a title, a muted line under it and a segmented choice on the right.
func _choice_row(title: String, sub: String, labels: Array[String], at: int) -> Segmented:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", 0)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_child(UiStyle.label(title, 26, UiStyle.TEXT, true))
	var line := UiStyle.label(sub, 18, UiStyle.MUTED)
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_child(line)
	row.add_child(text)
	var choice := Segmented.make(labels, at, 24, 64)
	choice.custom_minimum_size = Vector2(200, 0)
	choice.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(choice)
	box.add_child(row)
	return choice


func _gap(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c
