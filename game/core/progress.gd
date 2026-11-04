class_name Progress
extends RefCounted
## The player's best result per map and difficulty, kept in user://progress.cfg
## (section = map id, key = difficulty id). A result is
## {"won": bool, "lives": int, "wave": int, "waves": int, "stars": int}.
##
## Stars: 1 for a win, 2 for a win with at least half the lives left (10 of 20
## on Normal), 3 for a win without a single leak. A loss gives none.
## The rules and the comparison are pure; only load() and save() touch a file.

const PATH := "user://progress.cfg"
const MAX_STARS := 3

var path: String
var _best: Dictionary = {}  # "map/difficulty" -> result


func _init(p_path := PATH) -> void:
	path = p_path


## Progress from the file (empty if there is none yet).
static func open(p_path := PATH) -> Progress:
	var p := Progress.new(p_path)
	p.load_file()
	return p


static func stars_for(won: bool, lives_left: int, start_lives: int) -> int:
	if not won:
		return 0
	if lives_left >= start_lives:
		return 3
	if lives_left * 2 >= start_lives:
		return 2
	return 1


## The result of a finished (or abandoned) round.
static func result_of(game: Game) -> Dictionary:
	var won := game.phase == Game.Phase.WON
	return {
		"won": won,
		"lives": game.lives,
		"wave": game.wave,
		"waves": game.waves.size(),
		"stars": stars_for(won, game.lives, game.start_lives),
	}


## True if result a beats result b: a win beats a loss, then more stars, then
## more lives left (wins) or more waves reached (losses). Anything beats {}.
static func is_better(a: Dictionary, b: Dictionary) -> bool:
	if a.is_empty():
		return false
	if b.is_empty():
		return true
	var a_won := bool(a.get("won", false))
	if a_won != bool(b.get("won", false)):
		return a_won
	if int(a.get("stars", 0)) != int(b.get("stars", 0)):
		return int(a.get("stars", 0)) > int(b.get("stars", 0))
	if a_won:
		return int(a.get("lives", 0)) > int(b.get("lives", 0))
	if int(a.get("wave", 0)) != int(b.get("wave", 0)):
		return int(a.get("wave", 0)) > int(b.get("wave", 0))
	return int(a.get("lives", 0)) > int(b.get("lives", 0))


## A result is shown as "Ny rekord!" when it beats an earlier one, or when it is
## the first win (a first loss is not a record).
static func is_new_record(previous: Dictionary, result: Dictionary) -> bool:
	if not is_better(result, previous):
		return false
	return not previous.is_empty() or bool(result.get("won", false))


## Best result on a map and difficulty, {} if never played.
func best(map_id: String, difficulty: String) -> Dictionary:
	return _best.get(_key(map_id, difficulty), {})


func stars(map_id: String, difficulty: String) -> int:
	return int(best(map_id, difficulty).get("stars", 0))


## Stars over every map on a difficulty.
func total_stars(difficulty: String, map_ids: Array[String]) -> int:
	var n := 0
	for id in map_ids:
		n += stars(id, difficulty)
	return n


## Keeps the result if it beats the best one. Returns true if it did. Does not
## save; call save() after.
func record(map_id: String, difficulty: String, result: Dictionary) -> bool:
	if not is_better(result, best(map_id, difficulty)):
		return false
	_best[_key(map_id, difficulty)] = result.duplicate()
	return true


func load_file() -> Error:
	_best.clear()
	var cfg := ConfigFile.new()
	var err := cfg.load(path)
	if err != OK:
		return err
	for map_id in cfg.get_sections():
		for difficulty in cfg.get_section_keys(map_id):
			var v: Variant = cfg.get_value(map_id, difficulty)
			if v is Dictionary:
				_best[_key(map_id, difficulty)] = _clean(v)
	return OK


func save() -> Error:
	var cfg := ConfigFile.new()
	for key: String in _best:
		var parts := key.split("/")
		cfg.set_value(parts[0], parts[1], _best[key])
	return cfg.save(path)


static func _key(map_id: String, difficulty: String) -> String:
	return "%s/%s" % [map_id, difficulty]


## A stored result with the expected types (the file may be edited by hand).
static func _clean(v: Dictionary) -> Dictionary:
	return {
		"won": bool(v.get("won", false)),
		"lives": int(v.get("lives", 0)),
		"wave": int(v.get("wave", 0)),
		"waves": int(v.get("waves", 0)),
		"stars": clampi(int(v.get("stars", 0)), 0, MAX_STARS),
	}
