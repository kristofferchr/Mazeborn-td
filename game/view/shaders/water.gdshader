// River water: deep teal with two drifting noise layers, soft light bands and
// a glossy surface that catches the sun.
shader_type spatial;

uniform sampler2D noise : filter_linear_mipmap, repeat_enable;
uniform vec3 deep : source_color = vec3(0.07, 0.2, 0.25);
uniform vec3 shallow : source_color = vec3(0.13, 0.33, 0.36);
uniform vec3 shine : source_color = vec3(0.75, 0.9, 0.9);

void fragment() {
	vec3 w = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float a = texture(noise, w.xz * 0.035 + vec2(TIME * 0.012, TIME * 0.006)).r;
	float b = texture(noise, w.xz * 0.08 - vec2(TIME * 0.01, -TIME * 0.016)).r;
	float bands = smoothstep(0.46, 0.5, fract((a + b) * 4.0)) * smoothstep(0.56, 0.5, fract((a + b) * 4.0));
	vec3 col = mix(deep, shallow, smoothstep(0.3, 0.8, a * 0.6 + b * 0.6));
	col = mix(col, shine, bands * 0.06);
	ALBEDO = col;
	ROUGHNESS = 0.12;
	SPECULAR = 0.7;
}
