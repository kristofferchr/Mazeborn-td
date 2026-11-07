// Stone for the cliffs, rock cells and boulders: banded grey-brown stone with
// moss on the faces that point up and darker bottoms. Works in world space,
// so every rock shares one material. A MultiMesh can tint each instance
// through its custom data (alpha > 0).
shader_type spatial;

uniform sampler2D noise : filter_linear_mipmap, repeat_enable;
uniform vec3 stone_light : source_color = vec3(0.52, 0.48, 0.43);
uniform vec3 stone_dark : source_color = vec3(0.30, 0.28, 0.26);
uniform vec3 moss : source_color = vec3(0.31, 0.42, 0.2);
uniform float moss_from = 0.9;  // world normal y where moss starts
uniform float floor_y = -1.1;  // world height that is shaded darkest

varying vec3 tint;

void vertex() {
	tint = INSTANCE_CUSTOM.a > 0.0 ? INSTANCE_CUSTOM.rgb : vec3(1.0);
}

void fragment() {
	vec3 w = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 wn = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float n = texture(noise, w.xz * 0.21 + vec2(w.y * 0.17, 0.0)).r;
	float fine = texture(noise, w.xz * 1.3 + w.yy * 0.9).r;
	float strata = 0.5 + 0.5 * sin(w.y * 13.0 + n * 7.0);
	vec3 col = mix(stone_dark, stone_light, clamp(n * 0.55 + strata * 0.5 - 0.05, 0.0, 1.0));
	col *= tint * (0.9 + fine * 0.2);
	float up = smoothstep(moss_from, moss_from + 0.06, wn.y);
	up *= 1.0 - smoothstep(0.45, 0.85, w.y) * 0.8;  // bare peaks above the playfield
	col = mix(col, moss * (0.85 + n * 0.3), up * 0.85);
	col *= mix(0.55, 1.0, clamp((w.y - floor_y) / 1.3, 0.0, 1.0));
	ALBEDO = col;
	ROUGHNESS = 0.92;
}
