class_name FxSprites
extends MultiMeshInstance3D
## A fixed-size batch of effect sprites drawn in one draw call: camera-facing
## (or flat on the ground) quads cut from the FxArt atlas, see
## shaders/fx_sprite.gdshaderinc. Two kinds share the batch:
## - particles from spawn(): simulated here (velocity, gravity, drag, spin),
##   growing from size0 to size1 and fading out over their life;
## - one-frame sprites from draw(), for things that follow something
##   (a projectile's glow, stars around a stunned creep).
## Nothing is allocated after setup(); when the batch is full new sprites are
## dropped, so the cost has a ceiling.
## Call step(delta) once per frame, then draw(), then commit().

const STRIDE := 20  # floats per instance: 12 transform, 4 colour, 4 custom

var capacity := 0
var count := 0  # live particles
var _drawn := 0  # sprites written this frame (particles first)
var _buf := PackedFloat32Array()
var _pos := PackedVector3Array()
var _vel := PackedVector3Array()
var _color := PackedColorArray()
# Per particle: age, life, size0, size1, gravity, drag, rotation, spin.
var _f := PackedFloat32Array()
var _cell := PackedInt32Array()  # atlas cell, + 100 when flat on the ground


func setup(p_capacity: int, material: Material) -> void:
	capacity = p_capacity
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	mm.mesh = quad
	mm.instance_count = capacity
	mm.visible_instance_count = 0
	mm.custom_aabb = AABB(Vector3(-200, -50, -200), Vector3(400, 100, 400))
	multimesh = mm
	material_override = material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_buf.resize(capacity * STRIDE)
	_buf.fill(0.0)
	_pos.resize(capacity)
	_vel.resize(capacity)
	_color.resize(capacity)
	_f.resize(capacity * 8)
	_cell.resize(capacity)


func free_slots() -> int:
	return capacity - count


## Starts a particle; false if the batch is full. `motion` is gravity (y
## acceleration), drag (per second) and spin (radians per second); spinning
## particles start at a random angle.
func spawn(
	at: Vector3,
	vel: Vector3,
	life: float,
	size0: float,
	size1: float,
	color: Color,
	cell: int,
	motion := Vector3.ZERO,
) -> bool:
	var rot := randf() * TAU if motion.z != 0.0 else 0.0
	return _add(at, vel, life, Vector2(size0, size1), color, cell, motion, rot)


## Starts a particle lying flat on the ground (rings, scorch marks) at a
## fixed angle.
func flat(
	at: Vector3, life: float, size0: float, size1: float, color: Color, cell: int, rot := 0.0
) -> bool:
	return _add(at, Vector3.ZERO, life, Vector2(size0, size1), color, cell + 100, Vector3.ZERO, rot)


func _add(
	at: Vector3,
	vel: Vector3,
	life: float,
	sizes: Vector2,
	color: Color,
	cell: int,
	motion: Vector3,
	rot: float,
) -> bool:
	if count >= capacity or life <= 0.0:
		return false
	var i := count
	count += 1
	_pos[i] = at
	_vel[i] = vel
	_color[i] = color
	_cell[i] = cell
	var j := i * 8
	_f[j] = 0.0
	_f[j + 1] = life
	_f[j + 2] = sizes.x
	_f[j + 3] = sizes.y
	_f[j + 4] = motion.x
	_f[j + 5] = motion.y
	_f[j + 6] = rot
	_f[j + 7] = motion.z
	return true


## Ages and moves the particles, drops dead ones and writes the rest into the
## batch. Starts a new frame for draw().
func step(delta: float) -> void:
	var i := 0
	_drawn = 0
	while i < count:
		var j := i * 8
		var age := _f[j] + delta
		var life := _f[j + 1]
		if age >= life:
			_remove(i)
			continue
		_f[j] = age
		var v := _vel[i]
		v.y += _f[j + 4] * delta
		v *= maxf(1.0 - _f[j + 5] * delta, 0.0)
		_vel[i] = v
		_pos[i] += v * delta
		_f[j + 6] += _f[j + 7] * delta
		var k := age / life
		var c := _color[i]
		c.a *= (1.0 - k) * minf(k * 12.0 + 0.35, 1.0)
		var cell := _cell[i]
		_write(_pos[i], lerpf(_f[j + 2], _f[j + 3], k), c, cell % 100, _f[j + 6], cell >= 100, 1.0)
		i += 1


## Adds a sprite for this frame only.
func draw(
	at: Vector3, size: float, color: Color, cell: int, rot := 0.0, flat := false, stretch := 1.0
) -> void:
	if _drawn < capacity:
		_write(at, size, color, cell, rot, flat, stretch)


## Sends this frame's sprites to the renderer.
func commit() -> void:
	RenderingServer.multimesh_set_buffer(multimesh.get_rid(), _buf)
	multimesh.visible_instance_count = _drawn


func drawn() -> int:
	return _drawn


func _write(
	at: Vector3, size: float, c: Color, cell: int, rot: float, flat: bool, stretch: float
) -> void:
	var o := _drawn * STRIDE
	_drawn += 1
	_buf[o] = size
	_buf[o + 3] = at.x
	_buf[o + 5] = size
	_buf[o + 7] = at.y
	_buf[o + 10] = size
	_buf[o + 11] = at.z
	_buf[o + 12] = c.r
	_buf[o + 13] = c.g
	_buf[o + 14] = c.b
	_buf[o + 15] = c.a
	_buf[o + 16] = cell
	_buf[o + 17] = rot
	_buf[o + 18] = 1.0 if flat else 0.0
	_buf[o + 19] = stretch


## Swap-remove: the last particle takes slot i.
func _remove(i: int) -> void:
	count -= 1
	if i == count:
		return
	_pos[i] = _pos[count]
	_vel[i] = _vel[count]
	_color[i] = _color[count]
	_cell[i] = _cell[count]
	for k in 8:
		_f[i * 8 + k] = _f[count * 8 + k]
