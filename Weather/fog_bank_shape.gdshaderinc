// Broad billows shared by the silhouette and interior density.
float bank_radius(vec3 direction, float elapsed) {
	return 0.94
		+ 0.12 * sin(direction.x * 5.0 + elapsed * 0.045) * sin(direction.z * 4.0 - elapsed * 0.035)
		+ 0.07 * cos(direction.x * 8.0 - direction.z * 6.0 + direction.y * 3.0 + elapsed * 0.025)
		+ 0.09 * sin(direction.z * 7.0 + direction.y * 4.0 - elapsed * 0.03);
}
float bank_envelope(vec3 p, vec3 radii, float elapsed) {
	vec3 q = p / radii;
	float r = length(q);
	return r / bank_radius(q / max(r, 0.0001), elapsed);
}
