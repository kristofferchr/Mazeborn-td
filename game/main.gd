extends Node
## The app: the map select first, then a round on the chosen map (round.tscn).
## "Prøv igjen" starts the same map again and "Velg kart" goes back to the
## map select, with the last map and options chosen.

const ROUND := preload("res://round.tscn")

static var last_map := Maps.DEFAULT
static var last_options: Dictionary = {}

var menu: MapSelect
var current_round: Round


func _ready() -> void:
	show_menu()


func show_menu() -> void:
	_clear()
	menu = MapSelect.new()
	menu.selected = last_map
	menu.endless = str(last_options.get("mode", "")) == "endless"
	menu.play_pressed.connect(play, CONNECT_DEFERRED)
	add_child(menu)


func play(map_id: String, options := {}) -> void:
	last_map = map_id
	last_options = options
	_clear()
	current_round = ROUND.instantiate() as Round
	current_round.map_id = map_id
	current_round.options = options
	current_round.retry_requested.connect(play.bind(map_id, options), CONNECT_DEFERRED)
	current_round.maps_requested.connect(show_menu, CONNECT_DEFERRED)
	add_child(current_round)


func _clear() -> void:
	for n: Node in [menu, current_round]:
		if is_instance_valid(n):
			remove_child(n)
			n.queue_free()
	menu = null
	current_round = null
