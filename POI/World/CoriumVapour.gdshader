shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform float elapsed = 0.0;
uniform float activity : hint_range(0.0, 1.0) = 1.0;

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
}

void fragment() {
	vec2 p = UV - vec2(0.5);
	p.x += sin(UV.y * 9.0 + elapsed * 0.8) * 0.08;
	float edge = max(0.0, 1.0 - length(p * vec2(2.4, 1.9)));
	float strand = 0.55 + 0.45 * sin(UV.y * 13.0 + UV.x * 7.0 - elapsed * 0.8);
	ALBEDO = mix(vec3(0.49, 0.28, 0.66), vec3(0.75, 0.59, 0.33), UV.y);
	ALPHA = edge * edge * strand * activity * 0.30;
}
