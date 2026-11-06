extends Node
## Screenshot scene for the menus. Env MENU picks the screen: title,
## title_settings, maps (with made-up progress), pause, settings, won, lost or
## endless_lost (end screens with a new record), or shared (the won one after
## "Del replay", with the toast). Progress goes to a temp file. For maps,
## MENU_LEVEL picks the difficulty and MENU_MODE=endless the endless mode.
## Usage: MENU=maps scripts/screenshot.sh out.png res://tools/menus.tscn 30 2532x1170

const PROGRESS := "user://menus_shot_progress.cfg"
const END_PROGRESS := "user://menus_shot_end.cfg"
const DEMO := "res://tools/demo.tscn"


func _ready() -> void:
	var which := OS.get_environment("MENU")
	if which == "":
		which = "title"
	var progress := _progress()
	match which:
		"title", "title_settings":
			add_child(MenuBackdrop.new())
			var title := TitleScreen.new()
			title.progress = progress
			add_child(title)
			if which == "title_settings":
				title._open_settings()
		"maps":
			var menu := MapSelect.new()
			menu.progress = progress
			menu.selected = "klofta"
			var level := OS.get_environment("MENU_LEVEL")
			menu.difficulty = level if level != "" else "normal"
			menu.endless = OS.get_environment("MENU_MODE") == "endless"
			add_child(menu)
		"pause", "settings":
			var demo: Node = load(DEMO).instantiate()
			add_child(demo)
			var round := demo.get_child(0) as Round
			for i in 15:  # let the HUD and the board catch up first
				await get_tree().process_frame
			round.set_paused(true)
			if which == "settings":
				round.hud._pause_menu.settings_pressed.emit()
		"won", "lost", "endless_lost", "shared":
			if which == "endless_lost":
				OS.set_environment("DEMO_STATE", "endless")
			var demo: Node = load(DEMO).instantiate()
			add_child(demo)
			var round := demo.get_child(0) as Round
			# A fresh file: the first win is a new record.
			round.progress_path = END_PROGRESS
			if FileAccess.file_exists(END_PROGRESS):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(END_PROGRESS))
			var game := round.game
			game.creeps.clear()
			if which == "won" or which == "shared":
				game.wave = game.waves.size()
				game.lives = 17
				game.phase = Game.Phase.WON
			else:
				game.lives = 0
				game.cleared = game.wave - 1  # endless: the score is the last cleared wave
				game.phase = Game.Phase.LOST
			game.game_over.emit(which != "lost" and which != "endless_lost")
			if which == "shared":
				for i in 24:  # late, so the toast still shows in frame 30
					await get_tree().process_frame
				round.hud.share_pressed.emit()


## Some made-up results: Engen won flawlessly, Kløfta won narrowly, a loss on
## Tvillingportene, Steinrøysa not played.
func _progress() -> Progress:
	var p := Progress.new(PROGRESS)
	p.record("engen", "normal", {"won": true, "lives": 20, "wave": 12, "waves": 12, "stars": 3})
	p.record("klofta", "normal", {"won": true, "lives": 4, "wave": 12, "waves": 12, "stars": 1})
	p.record(
		"tvillingportene", "normal", {"won": false, "lives": 0, "wave": 9, "waves": 12, "stars": 0}
	)
	p.record("engen", "hard", {"won": true, "lives": 12, "wave": 12, "waves": 12, "stars": 2})
	p.record("engen", "easy", {"won": true, "lives": 30, "wave": 12, "waves": 12, "stars": 3})
	for id: String in ["engen", "klofta"]:
		p.record(id, "normal", {"wave": 31 if id == "engen" else 18, "mode": "endless"})
	p.save()
	return p
