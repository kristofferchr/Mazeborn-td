extends RefCounted
## Tests for view/audio.gd: every tower kind, element and event has a sound file.

const ROUND := preload("res://round.tscn")
const MAIN := preload("res://main.tscn")

var t: Object  # test runner (check/eq)


func _elements(config: Dictionary) -> Array[String]:
	var out: Array[String] = [""]
	for kind: String in config.towers.towers:
		for node: Dictionary in config.towers.towers[kind].nodes.values():
			var element := str(node.get("element", ""))
			if element not in out:
				out.append(element)
	return out


func test_every_tower_kind_and_element_has_fire_and_impact_sounds() -> void:
	var config := Game.default_config()
	var elements := _elements(config)
	t.check(elements.size() >= 5, "elements found: %s" % [elements])
	for kind: String in config.towers.towers:
		t.check(GameAudio.FIRE_SOUNDS.has(kind), "no fire sound for kind %s" % kind)
		t.check(GameAudio.IMPACT_SOUNDS.has(kind), "no impact sound for kind %s" % kind)
		for element in elements:
			for sound: String in [
				GameAudio.fire_sound(kind, element), GameAudio.impact_sound(kind, element)
			]:
				var path := GameAudio.sound_path(sound)
				t.check(ResourceLoader.exists(path), "%s/%s: missing %s" % [kind, element, path])
	for element in elements:
		if element != "":
			t.check(GameAudio.ELEMENT_FIRE.has(element), "no fire sound for %s" % element)
			t.check(GameAudio.ELEMENT_IMPACT.has(element), "no impact sound for %s" % element)


func test_elements_sound_different_from_each_other() -> void:
	var seen: Array[String] = []
	for element: String in ["", "fire", "ice", "lightning", "nature"]:
		var sound := GameAudio.fire_sound("elemental", element)
		t.check(sound not in seen, "%s shares %s" % [element, sound])
		seen.append(sound)


func test_every_sound_loads_as_an_audio_stream() -> void:
	var sounds := GameAudio.all_sounds()
	for event: String in [
		"build",
		"upgrade",
		"sell",
		"death",
		"leak",
		"wave_start",
		"wave_cleared",
		"coin",
		"victory",
		"defeat",
		"click",
		"chain"
	]:
		t.check(GameAudio.EVENTS.has(event), "no sound for event %s" % event)
	for sound in sounds:
		var stream := load(GameAudio.sound_path(sound)) as AudioStream
		t.check(stream != null, "%s does not load" % sound)
		if stream:
			var seconds := stream.get_length()
			var limit := 60.0 if sound.begins_with("music") else 5.0
			t.check(seconds > 0.02 and seconds < limit, "%s: %.2f s" % [sound, seconds])
		t.check(GameAudio.MIX.has(sound) or sound.begins_with("music"), "%s: no mix entry" % sound)


func test_music_layers_have_the_same_length() -> void:
	var calm := load(GameAudio.sound_path(GameAudio.MUSIC.calm)) as AudioStream
	var battle := load(GameAudio.sound_path(GameAudio.MUSIC.battle)) as AudioStream
	t.check(absf(calm.get_length() - battle.get_length()) < 0.05, "layers drift apart")


func test_menu_music_loads_and_loops() -> void:
	var stream := load(GameAudio.sound_path(GameAudio.MUSIC.menu)) as AudioStreamOggVorbis
	t.check(stream != null, "music_menu.ogg loads")
	if stream:
		t.check(stream.get_length() > 10.0 and stream.get_length() < 60.0, "a short loop")
	t.check(GameAudio.MUSIC.menu in GameAudio.all_sounds(), "listed with the other sounds")
	var size := FileAccess.get_file_as_bytes(GameAudio.sound_path(GameAudio.MUSIC.menu)).size()
	t.check(size < 150 * 1024, "small: %d bytes" % size)


func _music_players(audio: GameAudio) -> int:
	var n := 0
	for c in audio.get_children():
		if c is AudioStreamPlayer and (c as AudioStreamPlayer).bus == GameAudio.MUSIC_BUS:
			n += 1
	return n


func test_menu_and_round_music_crossfade() -> void:
	var root := (t as SceneTree).root
	var audio := GameAudio.new()
	root.add_child(audio)
	audio.play_menu()
	t.eq(audio.scene, "menu", "menu music")
	t.eq(audio.music_target("menu"), GameAudio.MENU_DB, "menu track up")
	t.eq(audio.music_target("calm"), GameAudio.SILENT_DB, "round music down")
	var game := Game.create_map("engen", 1)
	var before := game.tower_built.get_connections().size()
	audio.setup(game)
	t.eq(audio.scene, "round", "round music")
	t.eq(audio.music_target("menu"), GameAudio.SILENT_DB, "menu track fades out")
	t.eq(audio.music_target("calm"), GameAudio.MUSIC_DB, "calm layer fades in")
	t.eq(audio.music_target("battle"), GameAudio.SILENT_DB, "no drums before a wave")
	t.eq(_music_players(audio), 3, "no extra music players")
	audio.play_menu()
	t.eq(audio.scene, "menu", "back to the menu")
	t.eq(game.tower_built.get_connections().size(), before, "let go of the round's game")
	t.eq(audio.music_target("calm"), GameAudio.SILENT_DB, "round music fades out")
	t.eq(_music_players(audio), 3, "still three")
	root.remove_child(audio)
	audio.free()


func test_a_round_uses_the_app_audio() -> void:
	var tree := t as SceneTree
	var audio := GameAudio.new()
	tree.root.add_child(audio)
	audio.play_menu()
	var round := ROUND.instantiate() as Round
	round.audio = audio
	round.progress_path = ""
	tree.root.add_child(round)
	t.eq(tree.get_nodes_in_group(GameAudio.GROUP).size(), 1, "one GameAudio: no second music")
	t.eq(audio.scene, "round", "it plays the round")
	round.hud.mute_pressed.emit()
	t.check(audio.muted, "the mute button reaches it")
	audio.set_muted(false)
	tree.root.remove_child(round)
	round.free()
	audio.play_menu()
	t.eq(audio.scene, "menu", "menu music after the round")
	tree.root.remove_child(audio)
	audio.free()
	var alone := ROUND.instantiate() as Round
	alone.progress_path = ""
	tree.root.add_child(alone)
	t.check(alone.audio != null and alone.audio.get_parent() == alone, "on its own it has its own")
	t.eq(alone.audio.scene, "round", "and plays")
	tree.root.remove_child(alone)
	alone.free()


func test_the_app_plays_menu_music() -> void:
	var tree := t as SceneTree
	var main: Node = MAIN.instantiate()
	tree.root.add_child(main)
	var audio: GameAudio = main.get("audio")
	t.check(audio != null, "the app has a GameAudio")
	t.eq(audio.scene, "menu", "title screen music")
	main.call("show_menu")
	t.eq(audio.scene, "menu", "map select keeps it")
	t.eq(tree.get_nodes_in_group(GameAudio.GROUP).size(), 1, "one")
	tree.root.remove_child(main)
	main.free()
