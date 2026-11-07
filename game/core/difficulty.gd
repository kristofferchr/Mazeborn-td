class_name Difficulty
extends RefCounted
## Difficulty levels as data (data/difficulty.json): Lett, Normal, Vanskelig and
## Ekstrem. Each level scales the round's config on top of the map's rules:
## hp_scale (creep health, multiplies the map's hp_scale), start_gold_scale,
## lives_scale, bounty_scale (gold per kill) and interest_scale. A missing
## factor is 1.0, so Normal plays exactly like the plain config.
##
## A map may override a level's factors in its JSON with "difficulty":
## {"hard": {"hp_scale": 1.2}} sets the factor itself (instead of the level's)
## for that map; factors it leaves out come from the level. Inside it, a mode
## ("classic" or "endless") may override again: {"hard": {"bounty_scale": 0.8,
## "endless": {"bounty_scale": 0.9}}} pays 0.9 in endless and 0.8 in classic.

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


## A factor of a level (1.0 when the level does not set it). With a map, the
## map's override for that level (and for the mode inside it) wins (see the
## class doc).
static func factor(id: String, key: String, map := {}, mode := "classic") -> float:
	var own := _dict(_dict(map.get("difficulty")).get(id))
	var for_mode := _dict(own.get(mode))
	if for_mode.has(key):
		return float(for_mode[key])
	if own.has(key) and not own[key] is Dictionary:
		return float(own[key])
	return float(level(id).get(key, 1.0))


static func _dict(v: Variant) -> Dictionary:
	return v if v is Dictionary else {}


## Scales a round's config (shared config with the map's rules merged in) for
## a level on a map (its overrides for the level and mode, if any), in place.
## Unknown ids leave the config as it is.
static func apply(config: Dictionary, id: String, map := {}, mode := "classic") -> void:
	for key: String in SCALES:
		var target: String = SCALES[key]
		var f := factor(id, key, map, mode)
		var base := float(config.get(target, 1.0 if target.ends_with("_scale") else 0.0))
		if target in WHOLE:
			config[target] = maxi(roundi(base * f), 1)
		else:
			config[target] = base * f
