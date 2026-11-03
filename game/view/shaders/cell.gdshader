// Highlight of the selected cell: rounded outline with a soft fill.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, shadows_disabled;

uniform vec4 color : source_color = vec4(0.3, 1.0, 0.5, 1.0);

void fragment() {
	vec2 q = abs(UV - 0.5) * 2.0;  // 0 in the centre, 1 at the edges
	float radius = 0.22;
	vec2 c = max(q - (1.0 - radius), 0.0);
	float d = length(c) + min(max(q.x, q.y) - (1.0 - radius), 0.0);  // rounded box distance
	float outline = smoothstep(0.80, 0.88, d + radius) * (1.0 - smoothstep(0.96, 1.0, d + radius));
	float fill = (1.0 - smoothstep(0.9, 1.0, d + radius)) * 0.22;
	float pulse = 0.85 + 0.15 * sin(TIME * 5.0);
	ALBEDO = color.rgb;
	ALPHA = (outline * 0.95 + fill) * pulse * color.a;
}
