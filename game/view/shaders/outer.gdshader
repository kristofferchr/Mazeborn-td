// Land around the playfield: darker grass with large soft patches.
shader_type spatial;

uniform sampler2D noise : filter_linear_mipmap, repeat_enable;
uniform vec3 color_a : source_color = vec3(0.13, 0.22, 0.12);
uniform vec3 color_b : source_color = vec3(0.19, 0.30, 0.15);

varying vec2 world_xz;

void vertex() {
	world_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
	float n = texture(noise, world_xz * 0.03).r;
	float fine = texture(noise, world_xz * 0.25).r;
	ALBEDO = mix(color_a, color_b, smoothstep(0.3, 0.7, n)) * (0.92 + fine * 0.16);
	ROUGHNESS = 1.0;
}
