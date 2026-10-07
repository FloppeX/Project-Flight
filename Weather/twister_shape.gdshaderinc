// Keep these functions aligned with Twister.gd wind sampling.
uniform vec4 funnel_profile = vec4(48.0, 210.0, 70.0, 2.0);
uniform vec2 bend_scale = vec2(95.0, 65.0);
uniform float shape_phase = 0.0;
vec3 axis_offset(float h, float t) {
	return vec3(sin(h * 3.0 + t * 0.13 + shape_phase) * bend_scale.x * h,
		0.0, cos(h * 4.0 - t * 0.11 - shape_phase) * bend_scale.y * h);
}
float funnel_radius(float h) {
	return funnel_profile.x + funnel_profile.y * pow(h, funnel_profile.w) + funnel_profile.z * exp(-h * 32.0);
}
