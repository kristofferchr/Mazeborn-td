// Trees and small plants. Textured (the KayKit atlas): the green leaves are
// recoloured by the instance tint (MultiMesh custom data) and trunks keep
// their colour. Untextured (plants): the tint where UV.x is 1, else stem green.
// Lighter towards the top for a painted look.
shader_type spatial;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform bool textured = true;
uniform vec3 stem : source_color = vec3(0.3, 0.5, 0.2);
uniform float height = 1.2;  // model height that gets the full top light

varying vec3 tint;
varying float h;

void vertex() {
	tint = INSTANCE_CUSTOM.a > 0.0 ? pow(INSTANCE_CUSTOM.rgb, vec3(2.2)) : vec3(1.0);  // sRGB
	h = VERTEX.y;
}

void fragment() {
	vec3 c;
	if (textured) {
		c = texture(albedo_tex, UV).rgb;
		float leaf = clamp((c.g - max(c.r, c.b)) * 5.0, 0.0, 1.0);
		c = mix(c, tint * dot(c, vec3(0.3, 0.59, 0.11)) * 2.0, leaf);
	} else {
		c = mix(stem, tint, UV.x);
	}
	c *= mix(0.62, 1.12, clamp(h / height, 0.0, 1.0));
	ALBEDO = c;
	ROUGHNESS = 0.85;
}
