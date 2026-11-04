extends RefCounted
## Tests for view/audio.gd: every tower kind, element and event has a sound file.

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
