extends Node
## The app: the title screen, then the map select (with the difficulty), then
## a round on the chosen map (round.tscn). A first-time player's first "Spill"
## goes straight to the guided round on Engen instead (Onboarding), which can
## be played again from the settings ("Vis veiledning"). The title screen sits over a slowly
## circling 3D map (MenuBackdrop), which is paused and hidden behind the map
## select and freed during a round. Menus run at MENU_FPS. "Prøv igjen" starts
## the same map and options again; "Velg kart" and "Avslutt til kart" go back
## to the map select. The last map, difficulty and mode are kept in the
## settings (UserSettings). One GameAudio lives here for the whole app: menu
## music and button clicks in the menus, handed to each round (which
## crossfades to its own music).

const ROUND := preload("res://round.tscn")
const MENU_FPS := 30

var backdrop: MenuBackdrop
var title: TitleScreen
var menu: MapSelect
var current_round: Round
var audio: GameAudio


func _ready() -> void:
	audio = GameAudio.new()
	add_child(audio)
	show_title()


func _exit_tree() -> void:
	Engine.max_fps = 0


func show_title() -> void:
	_clear()
	Engine.max_fps = MENU_FPS
	if not is_instance_valid(backdrop):
		backdrop = MenuBackdrop.new()
		backdrop.map_id = UserSettings.open().map_id
		add_child(backdrop)
		move_child(backdrop, 0)
	backdrop.set_active(true)
	title = TitleScreen.new()
	title.play_pressed.connect(_on_play, CONNECT_DEFERRED)
	title.tutorial_pressed.connect(play_tutorial, CONNECT_DEFERRED)
	add_child(title)
	audio.play_menu()


func show_menu() -> void:
	_clear()
	Engine.max_fps = MENU_FPS
	if is_instance_valid(backdrop):
		backdrop.set_active(false)  # the map select covers it
	var settings := UserSettings.open()
	menu = MapSelect.new()
	menu.selected = settings.map_id
	menu.difficulty = settings.difficulty
	menu.endless = settings.mode == Progress.ENDLESS
	menu.play_pressed.connect(play, CONNECT_DEFERRED)
	menu.back_pressed.connect(show_title, CONNECT_DEFERRED)
	add_child(menu)
	audio.play_menu()


## "Spill": the map select, or the guided round for a first-time player.
func _on_play() -> void:
	if Onboarding.should_offer(UserSettings.open().tutorial_done, Progress.open()):
		play_tutorial()
	else:
		show_menu()


## The guided first round (Onboarding) on its map, from the start (also when
## it was done before: "Vis veiledning").
func play_tutorial() -> void:
	var settings := UserSettings.open()
	settings.tutorial_done = false
	settings.save()
	play(Onboarding.MAP, Onboarding.options())


## Starts a round. options go to Game.create_map as they are (difficulty and
## any keys other menus add). The guided round leaves the menu choices alone,
## and "Prøv igjen" plays it again only while it is not done.
func play(map_id: String, options: Dictionary = {}) -> void:
	var settings := UserSettings.open()
	if Onboarding.is_tutorial(options) and settings.tutorial_done:
		options = options.duplicate()
		options.erase("tutorial")
	if not Onboarding.is_tutorial(options):
		settings.map_id = map_id
		settings.difficulty = str(options.get("difficulty", settings.difficulty))
		settings.mode = Progress.mode_of(options)
		settings.save()
	_clear()
	_free(backdrop)
	backdrop = null
	Engine.max_fps = 0
	current_round = ROUND.instantiate() as Round
	current_round.map_id = map_id
	current_round.options = options.duplicate(true)
	current_round.audio = audio
	current_round.retry_requested.connect(play.bind(map_id, options), CONNECT_DEFERRED)
	current_round.maps_requested.connect(show_menu, CONNECT_DEFERRED)
	add_child(current_round)


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
