// Camera-facing strips (FxRibbons): projectile trails and lightning bolts.
// UV.y runs across the strip and UV.x is how much white-hot centre line it
// gets (bolts); the vertex colour carries colour and fade.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform float intensity = 1.2;

void fragment() {
	float d = abs(UV.y * 2.0 - 1.0);
	float edge = 1.0 - d;
	float hot = UV.x * (1.0 - smoothstep(0.0, 0.45, d));
	ALBEDO = mix(COLOR.rgb, vec3(1.0), hot) * intensity;
	ALPHA = COLOR.a * edge * edge;
}
