extends Node
## The app: the map select first, then a round on the chosen map (round.tscn).
## "Prøv igjen" starts the same map again and "Velg kart" goes back to the
## map select, with the last map chosen.

const ROUND := preload("res://round.tscn")

static var last_map := Maps.DEFAULT

var menu: MapSelect
var current_round: Node


func _ready() -> void:
	show_menu()


func show_menu() -> void:
	_clear()
	menu = MapSelect.new()
	menu.selected = last_map
	menu.play_pressed.connect(play, CONNECT_DEFERRED)
	add_child(menu)


func play(map_id: String) -> void:
	last_map = map_id
	_clear()
	current_round = ROUND.instantiate()
	current_round.map_id = map_id
	current_round.retry_requested.connect(play.bind(map_id), CONNECT_DEFERRED)
	current_round.maps_requested.connect(show_menu, CONNECT_DEFERRED)
	add_child(current_round)


func _clear() -> void:
	for n: Node in [menu, current_round]:
		if is_instance_valid(n):
			remove_child(n)
			n.queue_free()
	menu = null
	current_round = null
