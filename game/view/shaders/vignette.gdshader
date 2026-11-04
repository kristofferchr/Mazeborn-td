// Red glow along the screen edges (a creep leaked); strength 0 hides it.
shader_type canvas_item;

uniform float strength = 0.0;
uniform vec4 tint : source_color = vec4(0.95, 0.12, 0.1, 1.0);

void fragment() {
	vec2 d = abs(UV - 0.5) * 2.0;
	float edge = max(smoothstep(0.82, 1.0, d.x), smoothstep(0.7, 1.0, d.y));
	float corner = smoothstep(1.0, 1.5, length(d));
	COLOR = vec4(tint.rgb, tint.a * strength * clamp(edge * 0.8 + corner, 0.0, 1.0));
}
