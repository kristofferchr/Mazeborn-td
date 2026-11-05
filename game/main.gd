extends Node
## The app: the title screen, then the map select (with the difficulty), then
## a round on the chosen map (round.tscn). Both menus sit over a slowly
## circling 3D map (MenuBackdrop). "Prøv igjen" starts the same map and options
## again; "Velg kart" and "Avslutt til kart" go back to the map select. The
## last map, difficulty and mode are kept in the settings (UserSettings).

const ROUND := preload("res://round.tscn")

var backdrop: MenuBackdrop
var title: TitleScreen
var menu: MapSelect
var current_round: Round


func _ready() -> void:
	show_title()


func show_title() -> void:
	_clear()
	_ensure_backdrop()
	title = TitleScreen.new()
	title.play_pressed.connect(show_menu, CONNECT_DEFERRED)
	add_child(title)


func show_menu() -> void:
	_clear()
	_ensure_backdrop()
	var settings := UserSettings.open()
	menu = MapSelect.new()
	menu.selected = settings.map_id
	menu.difficulty = settings.difficulty
	menu.endless = settings.mode == Progress.ENDLESS
	menu.play_pressed.connect(play, CONNECT_DEFERRED)
	menu.back_pressed.connect(show_title, CONNECT_DEFERRED)
	add_child(menu)


## Starts a round. options go to Game.create_map as they are (difficulty and
## any keys other menus add).
func play(map_id: String, options: Dictionary = {}) -> void:
	var settings := UserSettings.open()
	settings.map_id = map_id
	settings.difficulty = str(options.get("difficulty", settings.difficulty))
	settings.mode = Progress.mode_of(options)
	settings.save()
	_clear()
	_free(backdrop)
	backdrop = null
	current_round = ROUND.instantiate() as Round
	current_round.map_id = map_id
	current_round.options = options.duplicate(true)
	current_round.retry_requested.connect(play.bind(map_id, options), CONNECT_DEFERRED)
	current_round.maps_requested.connect(show_menu, CONNECT_DEFERRED)
	add_child(current_round)


func _ensure_backdrop() -> void:
	if not is_instance_valid(backdrop):
		backdrop = MenuBackdrop.new()
		backdrop.map_id = UserSettings.open().map_id
		add_child(backdrop)
		move_child(backdrop, 0)


func _clear() -> void:
	for n: Node in [title, menu, current_round]:
		_free(n)
	title = null
	menu = null
	current_round = null


func _free(n: Node) -> void:
	if is_instance_valid(n):
		remove_child(n)
		n.queue_free()
