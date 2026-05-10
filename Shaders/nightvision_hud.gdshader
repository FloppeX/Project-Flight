shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;

uniform float gain      : hint_range(1.0, 10.0) = 4.0;
uniform float noise_amt : hint_range(0.0, 0.3)  = 0.07;

void fragment() {
	vec2 screen_uv = FRAGCOORD.xy / VIEWPORT_SIZE.xy;
	vec3 scene = texture(screen_texture, screen_uv).rgb;

	float lum = dot(scene, vec3(0.299, 0.587, 0.114));
	lum = 1.0 - exp(-lum * gain);

	// Scanlines every other pixel row
	float sl = step(0.5, fract(FRAGCOORD.y * 0.5));
	lum *= mix(1.0, 0.72, sl);

	// Animated grain
	float grain = fract(sin(dot(screen_uv + vec2(TIME * 0.013, TIME * 0.007),
			vec2(127.1, 311.7))) * 43758.5453);
	lum += (grain * 2.0 - 1.0) * noise_amt;
	lum = max(lum, 0.0);

	// Green phosphor
	ALBEDO = vec3(lum * 0.10, lum * 1.00, lum * 0.18);
	ALPHA = 1.0;
}
