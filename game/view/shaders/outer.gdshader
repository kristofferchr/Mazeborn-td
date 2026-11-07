// Land around the plateau: colours come from the vertices (grass shades,
// banks and the darker distance, in sRGB), with a fine noise grain on top.
shader_type spatial;

uniform sampler2D noise : filter_linear_mipmap, repeat_enable;

varying vec2 world_xz;

void vertex() {
	world_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
	float fine = texture(noise, world_xz * 0.3).r;
	float speck = texture(noise, world_xz * 1.7).r;
	ALBEDO = pow(COLOR.rgb, vec3(2.2)) * (0.88 + fine * 0.18 + (speck - 0.5) * 0.08);
	ROUGHNESS = 1.0;
}
