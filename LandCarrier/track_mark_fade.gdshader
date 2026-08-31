shader_type spatial;
render_mode cull_disabled, blend_mix, depth_prepass_alpha;

uniform float track_time_s = 0.0;
uniform float fresh_brightness : hint_range(1.0, 1.5) = 1.06;
uniform float fresh_lift_fraction : hint_range(0.01, 1.0) = 0.33;

varying vec2 track_lifetime;

void vertex() {
	// Spawn time and lifetime are written once through MultiMesh custom data.
	track_lifetime = INSTANCE_CUSTOM.rg;
}

void fragment() {
	float lifetime_s = max(track_lifetime.y, 0.01);
	float normalized_age = clamp((track_time_s - track_lifetime.x) / lifetime_s, 0.0, 1.0);
	// Smoothstep avoids both the old 5 Hz stepping and a linear-looking dissolve.
	float opacity = 1.0 - smoothstep(0.0, 1.0, normalized_age);
	// Freshly disturbed ground is softer than a fully opaque dark decal. Blend
	// back to the sampled track color early, then preserve the established fade.
	float fresh_weight = 1.0 - smoothstep(0.0, max(fresh_lift_fraction, 0.01), normalized_age);
	ALBEDO = min(COLOR.rgb * mix(1.0, fresh_brightness, fresh_weight), vec3(1.0));
	ROUGHNESS = 1.0;
	SPECULAR = 0.05;
	ALPHA = COLOR.a * opacity;
}
