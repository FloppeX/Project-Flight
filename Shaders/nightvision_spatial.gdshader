shader_type spatial;
render_mode unshaded, transparent, cull_disabled, depth_draw_never;

void fragment() {
	// Diagnostic: solid bright green. If this shows green the shader is loading
	// and running. If still grey, the shader file isn't loading at all.
	ALBEDO = vec3(0.0, 1.0, 0.0);
	ALPHA = 1.0;
}
