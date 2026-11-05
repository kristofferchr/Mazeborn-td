class_name Difficulty
extends RefCounted
## Difficulty levels as data (data/difficulty.json): Lett, Normal, Vanskelig and
## Ekstrem. Each level scales the round's config on top of the map's rules:
## hp_scale (creep health, multiplies the map's hp_scale), start_gold_scale,
## lives_scale, bounty_scale (gold per kill) and interest_scale. A missing
## factor is 1.0, so Normal plays exactly like the plain config.

const FILE := "res://data/difficulty.json"
const DEFAULT := "normal"
## Factor in a level -> the config key it scales.
const SCALES := {
	"hp_scale": "hp_scale",
	"start_gold_scale": "start_gold",
	"lives_scale": "lives",
	"bounty_scale": "bounty_scale",
	"interest_scale": "interest_rate",
}
## Config keys that stay whole numbers after scaling (at least 1).
const WHOLE := ["start_gold", "lives"]

static var _data: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		_data = Game.load_json(FILE)
	return _data


## Level ids from easiest to hardest.
static func ids() -> Array[String]:
	var out: Array[String] = []
	for id: Variant in data().order:
		out.append(str(id))
	return out


static func exists(id: String) -> bool:
	return data().levels.has(id)


## The level with this id ({} for an unknown id).
static func level(id: String) -> Dictionary:
	return data().levels.get(id, {})


## Display name ("Lett", "Normal" ...); the id itself if unknown.
static func display_name(id: String) -> String:
	return str(level(id).get("name", id))


## A factor of a level (1.0 when the level does not set it).
static func factor(id: String, key: String) -> float:
	return float(level(id).get(key, 1.0))


## Scales a round's config (shared config with the map's rules merged in) for
## a level, in place. Unknown ids leave the config as it is.
static func apply(config: Dictionary, id: String) -> void:
	for key: String in SCALES:
		var target: String = SCALES[key]
		var f := factor(id, key)
		var base := float(config.get(target, 1.0 if target.ends_with("_scale") else 0.0))
		if target in WHOLE:
			config[target] = maxi(roundi(base * f), 1)
		else:
			config[target] = base * f
