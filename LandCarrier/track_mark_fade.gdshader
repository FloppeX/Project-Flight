shader_type spatial;
render_mode cull_disabled, blend_mix, depth_prepass_alpha;

uniform float track_time_s = 0.0;

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
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 1.0;
	SPECULAR = 0.05;
	ALPHA = COLOR.a * opacity;
}
