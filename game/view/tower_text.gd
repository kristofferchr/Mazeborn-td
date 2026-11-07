class_name TowerText
extends RefCounted
## Text about towers for the HUD: one line of stats and effects.


## One line of stats and effects for a tower kind at some level.
static func describe(game: Game, kind: String, s: Dictionary) -> String:
	var parts: Array[String] = [
		"Skade %d–%d" % [int(s.damage_min), int(s.damage_max)],
		"%.1f/s" % (1.0 / float(s.cooldown)),
		"rekkevidde %.1f" % float(s.range),
	]
	if s.has("splash_radius"):
		parts.append("splash %.1f" % float(s.splash_radius))
	if s.has("slow"):
		parts.append("sakker ned %d %%" % roundi(float(s.slow) * 100.0))
	if s.has("poison_dps"):
		var what := "brann" if str(s.get("element", "")) == "fire" else "gift"
		parts.append("%s %d/s ×%d" % [what, int(s.poison_dps), int(s.get("poison_stacks", 1))])
	if s.has("stun"):
		parts.append("stun %.1fs" % float(s.stun))
	if s.has("knockback"):
		parts.append("skyver tilbake")
	if s.has("air_multiplier"):
		parts.append("×%.1f mot luft" % float(s.air_multiplier))
	if s.has("chain"):
		parts.append("hopper %d" % int(s.chain))
	if s.has("multishot"):
		parts.append("%d mål" % int(s.multishot))
	if s.get("armor_pierce", false):
		parts.append("gjennom rustning")
	if s.get("reveal", false):
		parts.append("avslører usynlige")
	var targets: Array = game.tower_defs[kind].get("targets", ["ground"])
	if "air" in targets and "ground" in targets:
		parts.append("bakke og luft")
	elif "air" in targets:
		parts.append("bare luft")
	return "  ·  ".join(parts)
