// Range indicator on a unit plane: faint fill, bright rim and a slow pulse.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, shadows_disabled;

uniform vec4 color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float rim_width = 0.035;

void fragment() {
	float r = length(UV - 0.5) * 2.0;
	if (r > 1.0) {
		discard;
	}
	float rim = smoothstep(1.0 - rim_width * 2.0, 1.0 - rim_width, r) * (1.0 - smoothstep(0.99, 1.0, r));
	float pulse = 0.5 + 0.5 * sin(TIME * 2.5);
	float fill = 0.07 + 0.04 * pulse * smoothstep(0.4, 1.0, r);
	ALBEDO = color.rgb;
	ALPHA = (fill + rim * 0.85) * color.a;
}
