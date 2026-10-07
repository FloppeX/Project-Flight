shader_type spatial;
render_mode cull_disabled;

uniform float elapsed = 0.0;
uniform float activity : hint_range(0.0, 1.0) = 1.0;
uniform float surface_fraction : hint_range(0.0, 1.0) = 1.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0)), f.x), f.y);
}

void fragment() {
	vec2 p = UV * 9.0;
	vec2 drift = vec2(elapsed * 0.035, -elapsed * 0.018) * activity;
	float swirl = noise(p + drift) * 0.6 + noise(p * 2.5 - drift) * 0.28 + noise(p * 7.0) * 0.12;
	float veins = 1.0 - smoothstep(0.015, 0.11, abs(swirl - 0.52));
	float pulse = 0.82 + 0.18 * sin(elapsed * 0.78 + swirl * 6.0);
	vec3 dark_liquid = vec3(0.075, 0.034, 0.095);
	vec3 violet = vec3(0.23, 0.08, 0.34);
	vec3 amber = vec3(0.96, 0.47, 0.11);
	vec3 molten = mix(violet, amber, smoothstep(0.38, 0.58, swirl));
	ALBEDO = mix(dark_liquid, molten * 0.5, veins * (0.2 + activity * 0.55));
	EMISSION = molten * veins * pulse * (0.05 + activity * 1.65) * (0.4 + surface_fraction * 0.6);
	METALLIC = 0.32;
	ROUGHNESS = 0.22 + (1.0 - activity) * 0.5;
}
