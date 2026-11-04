class_name MapPreview
extends Control
## Small schematic of a map drawn in 2D: the cells, rocks, the creep paths on
## the open map, the spawns and the goal. Keeps the map's aspect ratio.

const FIELD := Color(0.24, 0.4, 0.22)
const FIELD_LINE := Color(1, 1, 1, 0.05)
const ROCK := Color(0.58, 0.55, 0.5)
const ROCK_EDGE := Color(0.36, 0.34, 0.31)
const PATH := Color(1.0, 0.86, 0.45, 0.55)
const SPAWN := Color(0.85, 0.3, 1.0)
const GOAL := Color(0.35, 0.7, 1.0)

var grid: Grid


static func make(p_grid: Grid, min_size: Vector2) -> MapPreview:
	var p := MapPreview.new()
	p.grid = p_grid
	p.custom_minimum_size = min_size
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


func _draw() -> void:
	if grid == null:
		return
	var cells := Vector2(grid.size)
	var k := minf(size.x / cells.x, size.y / cells.y)
	var origin := (size - cells * k) / 2.0
	var field := StyleBoxFlat.new()
	field.bg_color = FIELD
	field.set_corner_radius_all(int(k * 0.6))
	field.anti_aliasing = true
	draw_style_box(field, Rect2(origin - Vector2(2, 2), cells * k + Vector2(4, 4)))
	for x in range(1, grid.size.x):
		draw_line(origin + Vector2(x * k, 0), origin + Vector2(x * k, cells.y * k), FIELD_LINE)
	for y in range(1, grid.size.y):
		draw_line(origin + Vector2(0, y * k), origin + Vector2(cells.x * k, y * k), FIELD_LINE)
	for cell: Vector2i in grid.rocks:
		var r := Rect2(origin + Vector2(cell) * k, Vector2(k, k))
		draw_rect(r, ROCK_EDGE)
		draw_rect(r.grow(-maxf(k * 0.12, 1.0)), ROCK)
	for i in grid.spawns.size():
		var pts := PackedVector2Array()
		for c in grid.path(i):
			pts.append(origin + Grid.center(c) * k)
		if pts.size() >= 2:
			draw_polyline(pts, PATH, maxf(k * 0.22, 2.0), true)
	for s in grid.spawns:
		_marker(origin + Grid.center(s) * k, k, SPAWN)
	_marker(origin + Grid.center(grid.goal) * k, k, GOAL)


func _marker(at: Vector2, k: float, color: Color) -> void:
	draw_circle(at, k * 0.85, Color(color, 0.3))
	draw_circle(at, k * 0.5, color)
	draw_circle(at, k * 0.22, color.lightened(0.6))
