class_name CameraRig
extends Camera3D
## WC3-style camera: fixed heading, tilted ~55°, panned by dragging and zoomed by
## pinching. The focus point stays within the map bounds.

const PITCH_DEG := 55.0

var focus := Vector3.ZERO
var distance := 16.0
var min_distance := 7.0
var max_distance := 24.0
var bounds := Rect2()  # allowed focus area on the ground (x, z)


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


func _apply() -> void:
	if bounds.size != Vector2.ZERO:
		focus.x = clampf(focus.x, bounds.position.x, bounds.end.x)
		focus.z = clampf(focus.z, bounds.position.y, bounds.end.y)
	var pitch := deg_to_rad(PITCH_DEG)
	position = focus + Vector3(0.0, sin(pitch), cos(pitch)) * distance
	rotation = Vector3(-pitch, 0.0, 0.0)
