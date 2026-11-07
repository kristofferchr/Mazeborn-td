// Glowing effect sprites (flashes, embers, sparks, rings), added to the
// scene. The atlas alpha is the shape and red its white-hot core.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, skip_vertex_transform;

#include "fx_sprite.gdshaderinc"

uniform float intensity = 1.15;

void fragment() {
	vec4 t = texture(atlas, UV);
	ALBEDO = mix(COLOR.rgb, vec3(1.0), t.r * 0.6) * intensity;
	ALPHA = t.a * COLOR.a;
}
