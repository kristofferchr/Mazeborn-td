// Soft vertical light beam (on an open cylinder) above the goal.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 color : source_color = vec4(0.4, 0.7, 1.0, 1.0);

void fragment() {
	float fade = pow(UV.y, 1.6);  // bright at the bottom
	float flicker = 0.85 + 0.15 * sin(TIME * 3.0 + UV.x * 12.0);
	ALBEDO = color.rgb * fade * flicker * 0.55;
}
