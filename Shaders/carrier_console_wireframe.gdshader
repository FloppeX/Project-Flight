shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled;

uniform vec4 wire_color : source_color = vec4(0.463, 0.780, 0.780, 1.0);
uniform float emission_strength : hint_range(0.0, 4.0, 0.05) = 1.35;

void fragment() {
	ALBEDO = wire_color.rgb;
	EMISSION = wire_color.rgb * emission_strength;
}
