// Keep these bounded outline and crest functions in sync with StormShape.gd.
float storm_edge(float angle, vec4 shape) {
	return 1.0 + shape.y * sin(angle * shape.x + shape.z)
		+ shape.w * cos(angle * 2.0 - shape.z * 0.7);
}

float electrical_envelope(vec2 delta, vec2 radii, float yaw, vec4 outline) {
	float c = cos(yaw);
	float s = sin(yaw);
	vec2 q = vec2(c * delta.x - s * delta.y, s * delta.x + c * delta.y) / max(radii, vec2(1.0));
	return length(q) / storm_edge(atan(q.y, q.x), outline);
}

float dust_top(vec3 p, vec3 dimensions, float elapsed, vec4 shape) {
	float phase = shape.z;
	float broad = sin(atan(p.z / dimensions.z, p.x / dimensions.x) * 2.0 + phase);
	return clamp(0.86 + 0.09 * sin(p.x / 280.0 + elapsed * 0.045 + phase)
		+ 0.045 * sin(p.z / 350.0 - p.x / 1050.0 + elapsed * 0.03 - phase)
		+ 0.035 * sin(p.x / 93.0 + p.z / 137.0 + elapsed * 0.08)
		+ 0.1 * broad * shape.y / 0.24, 0.6, 1.18);
}
