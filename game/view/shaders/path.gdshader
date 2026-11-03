// Creep path: a soft glowing trail with chevrons flowing towards the goal.
// UV.x is the distance along the path in cells, UV.y goes across (0..1).
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 color : source_color = vec4(1.0, 0.86, 0.45, 1.0);
uniform float speed = 0.9;
uniform float spacing = 1.0;

void fragment() {
	float across = abs(UV.y - 0.5) * 2.0;  // 0 in the middle, 1 at the edges
	float band = 1.0 - smoothstep(0.55, 1.0, across);
	float p = fract(UV.x / spacing - TIME * speed);
	// Chevron: a V pointing along the path.
	float v = abs(p + across * 0.28 - 0.5);
	float chevron = 1.0 - smoothstep(0.06, 0.12, v);
	float alpha = band * 0.16 + chevron * band * 0.55;
	ALBEDO = color.rgb;
	ALPHA = alpha * color.a;
}
