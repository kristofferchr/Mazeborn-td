class_name Maps
extends RefCounted
## Maps as data: one JSON file per map in data/maps/.
##
## Fields: id, name, description (Norwegian, for the map select), order (place
## in the list), size [w, h], spawns [[x, y], ...], goal [x, y], blocked (rocks:
## cells [x, y] or rectangles [x, y, w, h]), and optionally decor (look hints
## for the view: style "mountain" or "boulders", trees, boulders) and rules
## (overrides of data/waves.json such as start_gold or lives).

const DIR := "res://data/maps/"
const DEFAULT := "engen"


## Ids of all maps, in their order.
static func ids() -> Array[String]:
	var maps: Array[Dictionary] = []
	for file in ResourceLoader.list_directory(DIR):
		if file.ends_with(".json"):
			maps.append(load_map(file.get_basename()))
	maps.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return int(a.get("order", 99)) < int(b.get("order", 99))
	)
	var out: Array[String] = []
	for m in maps:
		out.append(str(m.id))
	return out


static func exists(id: String) -> bool:
	return ResourceLoader.exists(DIR + id + ".json")


static func load_map(id: String) -> Dictionary:
	var json := load(DIR + id + ".json") as JSON
	var map: Dictionary = (json.data as Dictionary).duplicate(true)
	map.id = id
	return map


static func size_of(map: Dictionary) -> Vector2i:
	return cell(map.size)


static func spawns_of(map: Dictionary) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for c: Array in map.spawns:
		out.append(cell(c))
	return out


static func goal_of(map: Dictionary) -> Vector2i:
	return cell(map.goal)


## Rock cells: every [x, y] and every cell of each [x, y, w, h] rectangle.
static func blocked_of(map: Dictionary) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for b: Array in map.get("blocked", []):
		var w := int(b[2]) if b.size() >= 4 else 1
		var h := int(b[3]) if b.size() >= 4 else 1
		for x in range(int(b[0]), int(b[0]) + w):
			for y in range(int(b[1]), int(b[1]) + h):
				var c := Vector2i(x, y)
				if c not in out:
					out.append(c)
	return out


static func grid(map: Dictionary) -> Grid:
	return Grid.create(size_of(map), spawns_of(map), goal_of(map), blocked_of(map))


static func cell(a: Array) -> Vector2i:
	return Vector2i(int(a[0]), int(a[1]))
