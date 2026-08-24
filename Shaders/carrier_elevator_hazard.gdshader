shader_type spatial;
render_mode unshaded, cull_disabled;

uniform vec4 warning_yellow : source_color = vec4(0.95, 0.72, 0.08, 1.0);
uniform vec4 warning_black : source_color = vec4(0.025, 0.03, 0.028, 1.0);
uniform float stripe_width_m : hint_range(0.05, 1.0, 0.01) = 0.28;
uniform vec2 marking_offset_xz = vec2(0.0);

varying vec2 marking_position_xz;


void vertex() {
	// Each edge is a separate box mesh. Adding its elevator-local offset keeps
	// the diagonal phase continuous instead of restarting at every corner.
	marking_position_xz = VERTEX.xz + marking_offset_xz;
}


void fragment() {
	float phase = (marking_position_xz.x + marking_position_xz.y) / max(stripe_width_m, 0.001);
	float stripe_wave = sin(phase * PI);
	float antialias_width = max(fwidth(stripe_wave), 0.001);
	float yellow_amount = smoothstep(-antialias_width, antialias_width, stripe_wave);
	vec4 warning_color = mix(warning_black, warning_yellow, yellow_amount);
	ALBEDO = warning_color.rgb;
	ALPHA = warning_color.a;
}
