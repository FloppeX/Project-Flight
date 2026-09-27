shader_type fog;

uniform float bottom_world = -500.0;
uniform float top_world = 2080.0;
uniform float lower_world = 1200.0;
uniform float upper_world = 2000.0;
uniform float base_density = 0.00024;
uniform float bank_density = 0.006;
uniform vec4 tint : source_color = vec4(0.8, 0.6, 0.46, 1.0);
uniform vec3 volume_size = vec3(80000.0, 4500.0, 80000.0);
uniform vec3 clear_center = vec3(0.0);
uniform vec3 volume_center_world = vec3(0.0);
uniform vec3 storm_center_world = vec3(0.0);
uniform float storm_radius_m = 0.0;

void fog() {
	float y = mix(bottom_world, top_world, UVW.y);
	float band = smoothstep(lower_world - 25.0, lower_world + 110.0, y)
		* (1.0 - smoothstep(upper_world - 110.0, upper_world + 35.0, y));
	vec3 p = (UVW - 0.5) * volume_size;
	float clearance = smoothstep(4.0, 8.0, distance(p, clear_center));
	vec2 storm_delta = (p + volume_center_world).xz - storm_center_world.xz;
	float storm_angle = atan(storm_delta.y, storm_delta.x);
	float storm_edge = 1.0 + 0.12 * sin(storm_angle * 5.0 + 0.8) + 0.07 * cos(storm_angle * 9.0);
	float storm_mask = 0.0;
	if (storm_radius_m > 0.0) {
		storm_mask = 1.0 - smoothstep(storm_radius_m * storm_edge * 0.58,
			storm_radius_m * storm_edge, length(storm_delta));
	}
	DENSITY = base_density + (bank_density + storm_mask * 0.0015) * band * clearance;
	vec3 normal_dust = mix(tint.rgb, vec3(0.94, 0.88, 0.78), band * 0.85);
	ALBEDO = mix(normal_dust, vec3(0.25, 0.28, 0.35), storm_mask * band * 0.85);
}
