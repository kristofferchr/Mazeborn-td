// Towers: one merged mesh per tower. Vertex colour alpha picks the look:
// 0 = the KayKit atlas texture, 1 = the vertex colour, 0.5 = the vertex
// colour glowing. Moving parts (sails, wind ring, crystal) turn in the vertex
// shader around `spin_axis` (local space) and can bob, so no tweens are needed.
shader_type spatial;

uniform sampler2D atlas : source_color, filter_linear_mipmap;
uniform float spin = 0.0;  // radians per second
uniform vec3 spin_axis = vec3(0.0, 1.0, 0.0);
uniform float bob = 0.0;  // up and down, in model units
uniform float glow = 0.9;

vec3 turn(vec3 v, vec3 k, float a) {
	return v * cos(a) + cross(k, v) * sin(a) + k * dot(k, v) * (1.0 - cos(a));
}

void vertex() {
	if (spin != 0.0) {
		float a = TIME * spin;
		VERTEX = turn(VERTEX, spin_axis, a);
		NORMAL = turn(NORMAL, spin_axis, a);
	}
	VERTEX.y += sin(TIME * 2.6) * bob;
}

void fragment() {
	vec3 tinted = COLOR.rgb;
	float solid = step(0.25, COLOR.a);
	vec3 col = mix(texture(atlas, UV).rgb, tinted, solid);
	ALBEDO = col;
	ROUGHNESS = 0.85;
	EMISSION = tinted * solid * (1.0 - step(0.75, COLOR.a)) * glow;
}
