extends Node
## Rough frame-cost check for the combat effects: the default map walled with
## towers of every kind and element (all upgraded), waves played back to back
## at 2x with a fixed step, and the average process time and node counts
## printed after FRAMES frames. Headless, so it measures the CPU side only.
## Usage: scripts/godot.sh --headless --path game res://tools/vfx_bench.tscn

const FRAMES := 900
const WARMUP := 120
const DELTA := 1.0 / 60.0
const SPEED := 2.0
const ELEMENTS := ["fire", "ice", "lightning", "nature"]
const FINALS := [
	"inferno", "meteor", "blizzard", "frostlance", "chainlightning", "storm", "venom", "roots"
]

var _main: Node
var _game: Game
var _frames := 0
var _time := 0.0
var _peak_nodes := 0
var _peak_fx := Vector3i.ZERO  # shots, sprites, strip vertices


func _ready() -> void:
	_main = load("res://round.tscn").instantiate()
	_main.progress_path = ""
	add_child(_main)
	_main.speed = 0.0  # stepped here with a fixed delta
	_game = _main.game
	_game.rng.seed = 3
	var kinds := ["arrow", "earth", "wind", "elemental"]
	var k := 0
	for cell in MazePlan.serpentine(_game.grid):
		_game.gold = 100000
		var kind: String = kinds[k % kinds.size()]
		if _game.build(cell, kind) == null:
			continue
		if kind == "elemental":
			_game.upgrade(cell, ELEMENTS[(k / 4) % ELEMENTS.size()])
			for i in [k % 2, 1 - k % 2]:
				var pick: String = FINALS[((k / 4) % ELEMENTS.size()) * 2 + i]
				if _game.upgrade(cell, pick):
					break
		else:
			_game.upgrade(cell)
			_game.upgrade(cell)
		k += 1
	print("bench: %d towers" % _game.towers.size())
	_game.wave = 7


func _process(_delta: float) -> void:
	_game.lives = 999
	if _game.phase != Game.Phase.WAVE:
		_game.start_wave()
	_game.simulate(DELTA * SPEED)
	_frames += 1
	if _frames > WARMUP:
		_time += Performance.get_monitor(Performance.TIME_PROCESS)
		var nodes := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
		_peak_nodes = maxi(_peak_nodes, nodes)
		var cfx: Variant = _main.board.get("combat")
		if cfx:
			var now := Vector3i(
				cfx.active().x, cfx.glow.drawn() + cfx.dust.drawn(), cfx.ribbons.vertex_count()
			)
			_peak_fx = Vector3i(
				maxi(_peak_fx.x, now.x), maxi(_peak_fx.y, now.y), maxi(_peak_fx.z, now.z)
			)
	if _frames == WARMUP + FRAMES:
		var line := "bench: %.3f ms process/frame, peak %d nodes, %d objects, wave %d"
		print(
			(
				line
				% [
					_time / FRAMES * 1000.0,
					_peak_nodes,
					int(Performance.get_monitor(Performance.OBJECT_COUNT)),
					_game.wave,
				]
			)
		)
		var fx: Variant = _main.board.get("combat")
		if fx:
			var fx_line := "bench fx: %s shots/bolts, %d models, %d/%d sprites, %d strip verts, peak %s"
			var sprites: Vector2i = Vector2i(fx.glow.drawn(), fx.dust.drawn())
			print(
				(
					fx_line
					% [
						fx.active(),
						fx.models_drawn(),
						sprites.x,
						sprites.y,
						fx.ribbons.vertex_count(),
						_peak_fx,
					]
				)
			)
		get_tree().quit()
