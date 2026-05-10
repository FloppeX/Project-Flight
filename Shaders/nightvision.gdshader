shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;

uniform float gain      : hint_range(1.0, 20.0) = 8.0;
uniform float gamma     : hint_range(0.2, 1.0)  = 0.45;
uniform float noise_amt : hint_range(0.0, 0.5)  = 0.16;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec3 scene = texture(screen_texture, SCREEN_UV).rgb;

	float lum = dot(scene, vec3(0.299, 0.587, 0.114));
	lum = 1.0 - exp(-lum * gain);
	lum = pow(lum, gamma);

	// Heavier scanlines
	float sl = step(0.5, fract((SCREEN_UV.y / SCREEN_PIXEL_SIZE.y) * 0.5));
	lum *= mix(1.0, 0.60, sl);

	// Fine grain (fast, frame-to-frame)
	float grain = hash(SCREEN_UV + vec2(TIME * 0.013, TIME * 0.007));
	lum += (grain * 2.0 - 1.0) * noise_amt;

	// Coarse grain — smooth value noise, slowly drifting (tube surface / phosphor wear)
	vec2 blob_uv = SCREEN_UV * 5.5 + vec2(TIME * 0.04, TIME * 0.03);
	vec2 blob_i  = floor(blob_uv);
	vec2 blob_f  = fract(blob_uv);
	blob_f = blob_f * blob_f * (3.0 - 2.0 * blob_f);  // smoothstep curves
	float n00 = hash(blob_i);
	float n10 = hash(blob_i + vec2(1.0, 0.0));
	float n01 = hash(blob_i + vec2(0.0, 1.0));
	float n11 = hash(blob_i + vec2(1.0, 1.0));
	float blob = mix(mix(n00, n10, blob_f.x), mix(n01, n11, blob_f.x), blob_f.y);
	lum += (blob * 2.0 - 1.0) * noise_amt * 0.5;

	// Vignette — optical tube falloff toward edges
	vec2 c = SCREEN_UV * 2.0 - 1.0;
	float vignette = 1.0 - dot(c * 0.55, c * 0.55);
	lum *= clamp(vignette, 0.0, 1.0);

	// Occasional horizontal scan artifact
	float t_slot = floor(TIME * 4.0);
	float artifact_on = step(0.88, hash(vec2(t_slot, 0.3)));
	float artifact_y  = hash(vec2(t_slot, 1.7));
	float band = step(0.994, 1.0 - abs(SCREEN_UV.y - artifact_y)) * artifact_on;
	lum += band * 0.35;

	lum = max(lum, 0.0);

	COLOR = vec4(lum * 0.10, lum * 1.00, lum * 0.18, 1.0);
}
