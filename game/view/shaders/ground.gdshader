// Playfield on top of the plateau: grass in a few noise-blended shades with
// small dirt patches, a worn dirt trail along the creep path, scree under the
// rock cells, a fine cell grid that shows more while building, and a softer
// grass lip between the outer cells and the cliff edge.
// `cells` has one texel per cell: r = on the creep path, g = rock cell.
shader_type spatial;

uniform sampler2D noise : filter_linear_mipmap, repeat_enable;
uniform sampler2D cells : filter_linear, repeat_disable;
uniform vec2 field_size = vec2(18.0, 12.0);
uniform float lip = 0.35;
uniform vec3 grass_dark : source_color = vec3(0.27, 0.4, 0.2);
uniform vec3 grass_mid : source_color = vec3(0.33, 0.45, 0.23);
uniform vec3 grass_light : source_color = vec3(0.43, 0.52, 0.27);
uniform vec3 dirt : source_color = vec3(0.50, 0.40, 0.27);
uniform vec3 worn : source_color = vec3(0.56, 0.48, 0.33);
uniform vec3 scree : source_color = vec3(0.52, 0.47, 0.39);
uniform vec3 grid_color : source_color = vec3(0.95, 1.0, 0.85);
uniform float grid_alpha = 0.05;

varying vec2 world_xz;

void vertex() {
	world_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
	vec2 p = world_xz;
	float big = texture(noise, p * 0.035).r;
	float mid = texture(noise, p * 0.11 + vec2(0.37, 0.11)).r;
	float fine = texture(noise, p * 0.9).r;
	float speck = texture(noise, p * 3.1).r;
	vec3 col = mix(grass_dark, grass_mid, smoothstep(0.22, 0.6, big));
	col = mix(col, grass_light, smoothstep(0.55, 0.85, mid) * 0.5);
	col *= 0.9 + fine * 0.14 + (speck - 0.5) * 0.08;
	// Small bare patches here and there.
	float bare = smoothstep(0.78, 0.86, mid * 0.7 + fine * 0.45);
	col = mix(col, dirt * (0.9 + fine * 0.2), bare * 0.35);
	// Worn trail along the path and scree under the rocks, with ragged edges.
	vec4 c = texture(cells, p / field_size);
	float edge_noise = (fine - 0.5) * 0.35 + (speck - 0.5) * 0.2;
	float trail = smoothstep(0.42, 0.75, c.r + edge_noise);
	col = mix(col, worn * (0.88 + fine * 0.22), trail * 0.75);
	float rubble = smoothstep(0.3, 0.6, c.g + edge_noise);
	col = mix(col, scree * (0.85 + speck * 0.3), rubble * 0.85);
	// Faint checker so cells read even when the grid is hidden.
	vec2 cell = floor(p);
	float checker = mod(cell.x + cell.y, 2.0);
	vec2 inside = step(vec2(0.0), p) * step(p, field_size);
	float in_field = inside.x * inside.y;
	col *= 1.0 + (checker - 0.5) * 0.035 * in_field;
	// Cell grid: thin lines, only on the playfield.
	vec2 f = abs(fract(p) - 0.5);
	float line = smoothstep(0.47, 0.497, max(f.x, f.y));
	col = mix(col, grid_color, line * grid_alpha * in_field);
	// Shade the lip and towards the cliff edge.
	vec2 d = min(p + lip, field_size + lip - p);
	float rim = smoothstep(0.0, lip + 0.9, min(d.x, d.y));
	col *= mix(0.72, 1.0, rim);
	ALBEDO = col;
	ROUGHNESS = 0.95;
}
