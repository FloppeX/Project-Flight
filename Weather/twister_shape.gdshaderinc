// Keep these functions aligned with Twister.gd wind sampling.
vec3 axis_offset(float h, float t) {
	return vec3(sin(h * 3.0 + t * 0.13) * 95.0 * h, 0.0, cos(h * 4.0 - t * 0.11) * 65.0 * h);
}
float funnel_radius(float h) { return 48.0 + 210.0 * h * h + 70.0 * exp(-h * 32.0); }
