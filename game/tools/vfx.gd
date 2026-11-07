extends Node
## Screenshot scene for the combat effects: a maze of chosen towers on the
## default map, wave VFX_WAVE (default 6) played with a fixed step for
## VFX_FRAMES frames (default 30), then everything frozen (game and effects)
## as soon as three shots or bolts are in the air,
## with the camera close on the first walls so shots in flight can be seen.
## VFX_SET picks the towers: "mix" (default, one of each look), "chain"
## (Kjedelyn only), "arrow",
## "earth", "wind", or an element ("fire", "ice", "lightning", "nature") for
## Elemental towers of that element and its two upgrades.
## VFX_FOCUS "x,z" and VFX_DIST move the camera; VFX_STATS prints the draw
## calls with and without the effects.
## Usage: VFX_SET=fire VFX_FRAMES=40 \
##   scripts/screenshot.sh out.png res://tools/vfx.tscn 50 2532x1170

const SETS := {
	"mix":
	[
		["arrow", 2],
		["elemental", "fire"],
		["earth", 2],
		["elemental", "lightning", "chainlightning"],
		["wind", 2],
		["elemental", "ice", "blizzard"],
		["elemental", "nature", "roots"],
		["elemental", "fire", "meteor"],
		["elemental", "lightning", "storm"],
		["elemental", "ice", "frostlance"],
		["elemental", "nature"],
		["elemental"],
	],
	"chain": [["elemental", "lightning", "chainlightning"]],
	"arrow": [["arrow", 0], ["arrow", 1], ["arrow", 2]],
	"earth": [["earth", 0], ["earth", 1], ["earth", 2]],
	"wind": [["wind", 0], ["wind", 1], ["wind", 2]],
}

var _main: Node
var _game: Game
var _frames := 0
var _stop := 30
var _stat_frames := 0


func _ready() -> void:
	_main = load("res://round.tscn").instantiate()
	_main.progress_path = ""
	add_child(_main)
	_main.speed = 0.0  # stepped here
	_game = _main.game
	_game.rng.seed = 5
	var set_name := OS.get_environment("VFX_SET")
	var towers: Array = SETS.get(set_name, [])
	if towers.is_empty() and set_name != "":
		towers = [["elemental", set_name], ["elemental", set_name, ""], ["elemental", set_name]]
	if towers.is_empty():
		towers = SETS.mix
	var k := 0
	for cell in MazePlan.serpentine(_game.grid):
		_game.gold = 100000
		var spec: Array = towers[k % towers.size()]
		if _game.build(cell, str(spec[0])) == null:
			continue
		_upgrade(cell, spec, k)
		k += 1
	var wave := OS.get_environment("VFX_WAVE")
	_game.wave = (int(wave) if wave != "" else 6) - 1
	_game.lives = 999
	_game.start_wave()
	var frames := OS.get_environment("VFX_FRAMES")
	_stop = int(frames) if frames != "" else 30
	var cam: CameraRig = _main.camera
	var focus := OS.get_environment("VFX_FOCUS").split(",")
	cam.focus = Vector3(4.5, 0.0, 6.0)
	if focus.size() == 2:
		cam.focus = Vector3(float(focus[0]), 0.0, float(focus[1]))
	var dist := OS.get_environment("VFX_DIST")
	if dist != "":
		cam.min_distance = minf(cam.min_distance, float(dist))
	cam.distance = float(dist) if dist != "" else cam.min_distance + 1.5
	cam.pan_screen(Vector2.ZERO, Vector2.ZERO)


## Upgrades along spec: ["kind", levels] or ["elemental", element, node...];
## an empty node name picks one of the element's two upgrades by k.
func _upgrade(cell: Vector2i, spec: Array, k: int) -> void:
	if spec[0] != "elemental":
		for i in int(spec[1]):
			_game.upgrade(cell)
		return
	for i in range(1, spec.size()):
		var option := str(spec[i])
		if option == "":
			var tower: Tower = _game.towers[cell]
			var nexts: Array = tower.stats().get("next", [])
			if nexts.is_empty():
				return
			option = nexts[k % nexts.size()]
		_game.upgrade(cell, option)


func _process(delta: float) -> void:
	var fx: CombatFx = _main.board.combat
	_frames += 1
	# Freeze once past VFX_FRAMES with a few shots or bolts in the air.
	var frozen := fx.time_scale == 0.0
	if (
		_frames > _stop
		and (frozen or _game.projectiles.size() >= 3 or fx.active().y >= 3 or _frames > _stop + 60)
	):
		fx.time_scale = 0.0  # frozen for the screenshot
		if OS.get_environment("VFX_STATS") != "":
			_stats(fx)
		return
	_game.simulate(Game.DT)
	fx.time_scale = Game.DT / maxf(delta, 0.0001)


## VFX_STATS: prints the draw calls with the effects shown and, a few frames
## later, hidden, so their share of the frame can be read off.
func _stats(fx: CombatFx) -> void:
	_stat_frames += 1
	var calls := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	if _stat_frames == 4:
		print("vfx stats: %d draw calls with effects, %s shots/bolts" % [calls, fx.active()])
		fx.visible = false
	elif _stat_frames == 8:
		print("vfx stats: %d draw calls without effects" % calls)
		fx.visible = true
