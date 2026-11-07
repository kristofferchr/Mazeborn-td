class_name Onboarding
extends RefCounted
## The guided first round as a state machine, pure logic over a Game. The
## steps, in order, each passed by the player's own action (Game signals):
##   BUILD      build a tower (tap a cell to preview, tap again or "Bygg")
##   MAZE       make the path at least MAZE_GAIN cells longer (or build
##              MAZE_TOWERS towers in the step, so nobody gets stuck)
##   START      start the wave
##   TOWER      upgrade or sell a tower
##   COUNTDOWN  the next wave starts (the countdown ran out, or "Send nå")
## A step the player has already done (a wave started or a tower upgraded or
## sold before its turn) is passed over. skip() ends it at once. The view
## (CoachMarks) shows the steps and keeps "done" in the settings.

signal step_changed(step: Step)
signal finished(skipped: bool)

enum Step { BUILD, MAZE, START, TOWER, COUNTDOWN, DONE }

const MAP := "engen"
const STEPS := 5  # steps shown to the player (DONE is not one)
const MAZE_GAIN := 2
const MAZE_TOWERS := 5
const NO_CELL := Vector2i(-1, -1)

var game: Game
var step := Step.BUILD
var skipped := false
var start_length := 0  # path cells when the maze step began
var path_length := 0
var maze_towers := 0  # towers built during the maze step
var first_tower := NO_CELL  # where the BUILD step's tower went
var waves_started := 0
var tower_changed := false  # a tower was upgraded or sold


## Offer the guided round on the first "Spill": not played or skipped yet, and
## no results kept (so players from before it came are not stopped).
static func should_offer(done: bool, progress: Progress) -> bool:
	return not done and progress.is_empty()


## Round options for the guided round (Game.create_map keeps "tutorial").
static func options() -> Dictionary:
	return {"difficulty": Difficulty.DEFAULT, "mode": Progress.CLASSIC, "tutorial": true}


static func is_tutorial(round_options: Dictionary) -> bool:
	return bool(round_options.get("tutorial", false))


## A free cell on the path about a third of the way in: a good first tower.
static func suggest_cell(g: Game) -> Vector2i:
	var path := g.grid.path(0)
	for i in range(path.size() / 3, path.size()):
		if g.grid.can_build(path[i], g.creep_cells()):
			return path[i]
	return NO_CELL


## Up to `count` cells that make a wall with a tower at `near`: the same column,
## up and down from it, nearest first, each still leaving a way through.
static func suggest_wall(g: Game, near: Vector2i, count := 4) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if near == NO_CELL:
		return out
	var sim := g.grid.duplicate_grid()
	for d in range(1, g.grid.size.y):
		for y: int in [near.y - d, near.y + d]:
			var cell := Vector2i(near.x, y)
			if out.size() < count and sim.can_build(cell):
				sim.build(cell)
				out.append(cell)
	return out


func attach(p_game: Game) -> void:
	game = p_game
	path_length = _length()
	start_length = path_length
	game.tower_built.connect(_on_built)
	game.path_changed.connect(_on_path)
	game.wave_started.connect(_on_wave_started)
	game.tower_upgraded.connect(_on_upgraded)
	game.tower_sold.connect(_on_sold)
	game.game_over.connect(_on_game_over)


## Lets go of the game (when the steps are done or the round is over). The
## connections are method callables, so they never keep this object or the
## game alive on their own.
func detach() -> void:
	if game == null:
		return
	for pair: Array in [
		[game.tower_built, _on_built],
		[game.path_changed, _on_path],
		[game.wave_started, _on_wave_started],
		[game.tower_upgraded, _on_upgraded],
		[game.tower_sold, _on_sold],
		[game.game_over, _on_game_over],
	]:
		var sig: Signal = pair[0]
		if sig.is_connected(pair[1]):
			sig.disconnect(pair[1])
	game = null


func is_active() -> bool:
	return step != Step.DONE


## Cells the maze step has added to the path so far.
func gain() -> int:
	return path_length - start_length


## Ends the guided round now ("Hopp over").
func skip() -> void:
	if is_active():
		skipped = true
		_go(Step.DONE)


func _length() -> int:
	return game.grid.path(0).size()


func _on_built(tower: Tower) -> void:
	if step == Step.BUILD:
		first_tower = tower.cell
		_go(Step.MAZE)
	elif step == Step.MAZE:
		maze_towers += 1
		_check_maze()


func _on_path() -> void:
	path_length = _length()
	_check_maze()


func _check_maze() -> void:
	if step == Step.MAZE and (gain() >= MAZE_GAIN or maze_towers >= MAZE_TOWERS):
		_go(Step.START)


func _on_wave_started(_number: int) -> void:
	waves_started += 1
	if step == Step.START or step == Step.COUNTDOWN:
		_go(step + 1)


func _on_upgraded(_tower: Tower) -> void:
	_on_tower_changed()


func _on_sold(_tower: Tower, _refund: int) -> void:
	_on_tower_changed()


func _on_game_over(_won: bool) -> void:
	detach()


func _on_tower_changed() -> void:
	tower_changed = true
	if step == Step.TOWER:
		_go(Step.COUNTDOWN)


func _go(to: int) -> void:
	step = to as Step
	if step == Step.MAZE:
		start_length = path_length
		maze_towers = 0
	elif step == Step.START and waves_started > 0:
		_go(Step.TOWER)
		return
	elif step == Step.TOWER and tower_changed:
		_go(Step.COUNTDOWN)
		return
	step_changed.emit(step)
	if step == Step.DONE:
		detach()
		finished.emit(skipped)
