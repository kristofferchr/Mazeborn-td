// Spawn and goal portal on a unit plane: a glowing swirl.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 color : source_color = vec4(0.8, 0.3, 1.0, 1.0);
uniform float direction = 1.0;

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float r = length(p);
	if (r > 1.0) {
		discard;
	}
	float a = atan(p.y, p.x);
	float swirl = 0.5 + 0.5 * sin(a * 3.0 + r * 9.0 - TIME * 3.0 * direction);
	float core = 1.0 - smoothstep(0.0, 0.55, r);
	float rim = smoothstep(0.7, 0.9, r) * (1.0 - smoothstep(0.9, 1.0, r));
	float glow = (swirl * 0.45 + 0.2) * (1.0 - r) + rim * 0.9 + core * 0.35;
	ALBEDO = color.rgb * glow * 1.6;
}
