class_name CameraRig
extends Camera3D
## WC3-style camera: fixed heading, tilted ~55°, panned by dragging and zoomed by
## pinching. The focus point stays within the map bounds. shake() jolts the view
## for a moment through the lens offsets, so pan and zoom are untouched.

const PITCH_DEG := 55.0
const SHAKE_DECAY := 2.2  # trauma lost per second
const SHAKE_MAX := 0.35  # largest offset in world units at full trauma and distance 16

var focus := Vector3.ZERO
var distance := 16.0
var min_distance := 7.0
var max_distance := 24.0
var bounds := Rect2()  # allowed focus area on the ground (x, z)
var trauma := 0.0  # shake strength 0..1, fades over time
var _shake_time := 0.0


func _ready() -> void:
	fov = 45.0
	near = 0.2
	far = 200.0
	_apply()


func setup(map_bounds: Rect2, start_distance: float) -> void:
	bounds = map_bounds
	# Slightly below the centre so the map sits above the bottom HUD.
	focus = Vector3(bounds.get_center().x, 0.0, bounds.get_center().y + 1.0)
	max_distance = start_distance * 1.25
	distance = start_distance
	_apply()


## Point on the ground plane (y = 0) under a screen position.
func ground_point(screen_pos: Vector2) -> Vector3:
	var origin := project_ray_origin(screen_pos)
	var dir := project_ray_normal(screen_pos)
	if absf(dir.y) < 0.0001:
		return focus
	return origin + dir * (-origin.y / dir.y)


## Moves the camera so the ground under `from` ends up under `to`.
func pan_screen(from: Vector2, to: Vector2) -> void:
	var delta := ground_point(from) - ground_point(to)
	focus += Vector3(delta.x, 0.0, delta.z)
	_apply()


## Zooms by factor (>1 zooms in) keeping the ground under `around` in place.
func zoom(factor: float, around: Vector2) -> void:
	var before := ground_point(around)
	distance = clampf(distance / factor, min_distance, max_distance)
	_apply()
	var after := ground_point(around)
	focus += Vector3(before.x - after.x, 0.0, before.z - after.z)
	_apply()


## Shakes the camera; strength 0..1 (a leak ~0.3, a boss ~0.6). Stronger
## shakes override weaker ones and they fade on their own.
func shake(strength: float) -> void:
	trauma = clampf(maxf(trauma, strength), 0.0, 1.0)


func _process(delta: float) -> void:
	if trauma <= 0.0:
		return
	trauma = maxf(trauma - SHAKE_DECAY * delta, 0.0)
	_shake_time += delta
	# Squared trauma feels better than linear; sums of sines look like noise.
	var amount := trauma * trauma * SHAKE_MAX * distance / 16.0
	var t := _shake_time * 30.0
	h_offset = amount * (sin(t * 1.0) + 0.5 * sin(t * 2.3 + 1.0)) / 1.5
	v_offset = amount * (sin(t * 1.3 + 2.0) + 0.5 * sin(t * 2.9)) / 1.5
	if trauma <= 0.0:
		h_offset = 0.0
		v_offset = 0.0


func _apply() -> void:
	if bounds.size != Vector2.ZERO:
		focus.x = clampf(focus.x, bounds.position.x, bounds.end.x)
		focus.z = clampf(focus.z, bounds.position.y, bounds.end.y)
	var pitch := deg_to_rad(PITCH_DEG)
	position = focus + Vector3(0.0, sin(pitch), cos(pitch)) * distance
	rotation = Vector3(-pitch, 0.0, 0.0)
