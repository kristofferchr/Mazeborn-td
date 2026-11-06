class_name PauseMenu
extends Overlay
## The pause menu over a round: Fortsett, Start på nytt, Innstillinger and
## Avslutt til kart, with the map and difficulty.

signal resume_pressed
signal restart_pressed
signal settings_pressed
signal quit_pressed

var _info: Label


func _init() -> void:
	super(520.0)
	visible = false
	add_title("Pause", 60)
	_info = UiStyle.label("", 22, UiStyle.MUTED)
	_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_info)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 6)
	box.add_child(gap)
	add_button("Fortsett", "primary", func() -> void: resume_pressed.emit(), 92.0)
	add_button("Start på nytt", "secondary", func() -> void: restart_pressed.emit())
	add_button("Innstillinger", "secondary", func() -> void: settings_pressed.emit())
	add_button("Avslutt til kart", "danger", func() -> void: quit_pressed.emit())


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		resume_pressed.emit()


## The line under the title: map, difficulty and wave.
func set_info(text: String) -> void:
	_info.text = text
