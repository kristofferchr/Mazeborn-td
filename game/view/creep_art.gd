class_name CreepArt
extends RefCounted
## Creep models (see CREDITS.md). A wave group picks its model with the "model"
## key in data/waves.json, or gets the default model of its creep kind.
## Bounds were measured in a walk pose: `extent` is the largest side of the
## model's box and `center` the centre of its footprint and its lowest point, in
## model units. `size` is the wanted largest side in cells, and `yaw` turns
## models that face +X so that all of them face +Z.

const DIR := "res://assets/creeps/"
const DEFAULT := "rat"
## Model for a creep kind when the wave group does not name one.
const KIND_MODELS := {
	"normal": "rat",
	"fast": "spider",
	"armored": "skeleton_minion",
	"flying": "bat",
	"boss": "skeleton_warrior",
}
const MODELS := {
	"rat":
	{
		"file": "Rat.fbx",
		"walk": "Rat_Walk",
		"death": "Rat_Death",
		"extent": 6.92,
		"center": Vector3(-0.005, -0.004, -1.501),
		"size": 1.8,
	},
	"spider":
	{
		"file": "Spider.fbx",
		"walk": "Spider_Walk",
		"death": "Spider_Death",
		"extent": 5.91,
		"center": Vector3(0.038, -0.015, 0.124),
		"size": 1.6,
	},
	"slime":
	{
		"file": "Slime.fbx",
		"walk": "Slime_Walk",
		"death": "Slime_Death",
		"yaw": -PI / 2.0,
		"extent": 2.99,
		"center": Vector3(0.002, -0.016, -0.082),
		"size": 1.2,
	},
	"bat":
	{
		"file": "Bat.fbx",
		"walk": "Bat_Flying",
		"death": "Bat_Death",
		"extent": 4.55,
		"center": Vector3(-0.113, -0.011, 0.208),
		"size": 1.4,
	},
	"dragon":
	{
		"file": "Dragon.fbx",
		"walk": "Dragon_Flying",
		"death": "Dragon_Death",
		"extent": 4.14,
		"center": Vector3(-0.057, 0.060, -0.276),
		"size": 1.7,
	},
	"wasp":
	{
		"file": "Wasp.fbx",
		"walk": "Wasp_Flying",
		"death": "Wasp_Death",
		"yaw": -PI / 2.0,
		"extent": 3.43,
		"center": Vector3(0.890, 0.745, -0.022),
		"size": 1.4,
	},
	"velociraptor":
	{
		"file": "Velociraptor.fbx",
		"walk": "Velociraptor_Run",
		"death": "Velociraptor_Death",
		"extent": 13.72,
		"center": Vector3(-0.054, -0.053, -1.427),
		"size": 1.7,
	},
	"stegosaurus":
	{
		"file": "Stegosaurus.fbx",
		"walk": "Stegosaurus_Run",
		"death": "Stegosaurus_Death",
		"extent": 21.92,
		"center": Vector3(0.086, -0.113, -3.676),
		"size": 1.8,
	},
	"triceratops":
	{
		"file": "Triceratops.fbx",
		"walk": "Triceratops_Run",
		"death": "Triceratops_Death",
		"extent": 20.78,
		"center": Vector3(0.083, -0.134, -1.199),
		"size": 1.8,
	},
	"trex":
	{
		"file": "Trex.fbx",
		"walk": "TRex_Run",
		"death": "TRex_Death",
		"extent": 31.41,
		"center": Vector3(-0.277, 0.074, -0.990),
		"size": 2.0,
	},
	"skeleton_minion":
	{
		"file": "Skeleton_Minion.glb",
		"walk": "Walking_A",
		"death": "Death_A",
		"extent": 2.06,
		"center": Vector3(0.006, 0.108, 0.220),
		"size": 1.6,
	},
	"skeleton_warrior":
	{
		"file": "Skeleton_Warrior.glb",
		"walk": "Walking_A",
		"death": "Death_A",
		"extent": 2.64,
		"center": Vector3(-0.026, 0.104, 0.404),
		"size": 1.7,
	},
}

static var _scenes: Dictionary = {}  # id -> PackedScene


static func info(id: String) -> Dictionary:
	return MODELS.get(id, MODELS[DEFAULT])


## Model id for a creep kind: the "model" of the latest wave (up to `wave`, 1-based)
## that has a group of that kind, else the kind's default. Looking back covers
## creeps of a wave that still spawn after the next one was sent early.
static func model_for(kind: String, waves: Array[Dictionary], wave: int) -> String:
	for i in range(mini(wave, waves.size()) - 1, -1, -1):
		for g: Dictionary in Game.wave_groups(waves[i]):
			if str(g.get("creep", "normal")) == kind and g.has("model"):
				return str(g.model)
	return KIND_MODELS.get(kind, DEFAULT)


## Height above its feet (cells, before the creep scale) of the top of the model.
static func top(id: String) -> float:
	return float(info(id).size) * 0.75


## A node with the model centred on its footprint, feet at y = 0.
static func instantiate(id: String) -> Node3D:
	var m := info(id)
	if not _scenes.has(id):
		_scenes[id] = load(DIR + m.file)
	var model := (_scenes[id] as PackedScene).instantiate() as Node3D
	var s := float(m.size) / float(m.extent)
	model.scale = Vector3.ONE * s
	var yaw := float(m.get("yaw", 0.0))
	model.rotation.y = yaw
	var c: Vector3 = m.center
	model.position = (Basis(Vector3.UP, yaw) * -c) * s
	var holder := Node3D.new()
	holder.name = "Body"
	holder.add_child(model)
	return holder


## Finds the animation whose name contains `part` (FBX names carry an armature prefix).
static func find_animation(player: AnimationPlayer, part: String) -> String:
	for n in player.get_animation_list():
		if n.contains(part):
			return n
	return ""


static func player(body: Node) -> AnimationPlayer:
	return body.find_children("*", "AnimationPlayer", true, false).pop_front() as AnimationPlayer
