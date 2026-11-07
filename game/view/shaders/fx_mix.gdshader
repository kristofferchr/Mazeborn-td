// Opaque-ish effect sprites (dust, smoke, scorch marks, leaves), blended over
// the scene. The atlas alpha is the shape and red shades it a little.
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled, skip_vertex_transform;

#include "fx_sprite.gdshaderinc"

void fragment() {
	vec4 t = texture(atlas, UV);
	ALBEDO = COLOR.rgb * (0.75 + 0.25 * t.r);
	ALPHA = t.a * COLOR.a;
}
