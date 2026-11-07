// Shared vertex stage for the effect sprites (FxSprites): one MultiMesh of
// unit quads. Each instance's basis scale is its size; INSTANCE_CUSTOM holds
// the atlas cell (x), the rotation in radians (y), 1 to lie flat on the
// ground instead of facing the camera (z) and a stretch along the rotated
// x axis (w, 1 = round).
uniform sampler2D atlas : filter_linear_mipmap, repeat_disable;
uniform float cells = 4.0;

void vertex() {
	float size = length(MODEL_MATRIX[0].xyz);
	float c = cos(INSTANCE_CUSTOM.y);
	float s = sin(INSTANCE_CUSTOM.y);
	vec2 q = VERTEX.xy * vec2(max(INSTANCE_CUSTOM.w, 0.05), 1.0);
	vec2 v = vec2(q.x * c - q.y * s, q.x * s + q.y * c) * size;
	vec3 right = INV_VIEW_MATRIX[0].xyz;
	vec3 up = INV_VIEW_MATRIX[1].xyz;
	if (INSTANCE_CUSTOM.z > 0.5) {
		right = vec3(1.0, 0.0, 0.0);
		up = vec3(0.0, 0.0, -1.0);
	}
	vec3 world = MODEL_MATRIX[3].xyz + right * v.x + up * v.y;
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	NORMAL = vec3(0.0, 0.0, 1.0);
	float cell = floor(INSTANCE_CUSTOM.x + 0.5);
	UV = (vec2(mod(cell, cells), floor(cell / cells)) + UV) / cells;
}
