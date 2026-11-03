// Playfield: grass with soft colour variation, a fine cell grid that shows
// more while building, and a darker rim towards the edge of the field.
shader_type spatial;

uniform sampler2D noise : filter_linear_mipmap, repeat_enable;
uniform vec2 field_size = vec2(18.0, 12.0);
uniform vec3 grass_a : source_color = vec3(0.30, 0.50, 0.25);
uniform vec3 grass_b : source_color = vec3(0.40, 0.58, 0.29);
uniform vec3 grid_color : source_color = vec3(0.92, 1.0, 0.85);
uniform float grid_alpha = 0.05;

varying vec2 world_xz;

void vertex() {
	world_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
	float n = texture(noise, world_xz * 0.045).r;
	float fine = texture(noise, world_xz * 0.35).r;
	vec3 col = mix(grass_a, grass_b, smoothstep(0.25, 0.75, n));
	col *= 0.94 + fine * 0.12;
	// Cell grid: thin lines with rounded corners.
	vec2 f = abs(fract(world_xz) - 0.5);
	float edge = max(f.x, f.y);
	float line = smoothstep(0.475, 0.497, edge);
	col = mix(col, grid_color, line * grid_alpha);
	// Darken towards the border of the field.
	vec2 d = min(world_xz, field_size - world_xz);
	float rim = smoothstep(0.0, 1.6, min(d.x, d.y));
	col *= mix(0.78, 1.0, rim);
	ALBEDO = col;
	ROUGHNESS = 0.95;
}
