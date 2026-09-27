shader_type fog;
uniform vec3 box_size;
uniform vec3 dimensions;
uniform float elapsed = 0.0;
uniform float strength = 0.0;
uniform float extinction = 0.008693;
uniform vec4 dust_color : source_color = vec4(0.78, 0.46, 0.26, 1.0);
uniform vec3 interior_clear_center = vec3(0.0);
uniform float interior_clear_radius = 0.0;

void fog() {
	vec3 p = (UVW - 0.5) * box_size + vec3(0.0, dimensions.y * 0.5, 0.0);
	float x = p.x / dimensions.x;
	float z = p.z / dimensions.z;
	float lobe = 1.0 + 0.035 * sin(atan(z, x) * 5.0);
	float radial = length(vec2(x, z)) / lobe;
	float top = 0.86 + 0.09 * sin(p.x / 280.0 + elapsed * 0.045) + 0.045 * sin(p.z / 350.0 - p.x / 1050.0 + elapsed * 0.03) + 0.035 * sin(p.x / 93.0 + p.z / 137.0 + elapsed * 0.08);
	float y = max(p.y, 0.0) / (dimensions.y * top);
	float envelope = sqrt(radial * radial + pow(y, 8.0));
	float body = (1.0 - smoothstep(0.90, 1.015, envelope)) * smoothstep(-110.0, 0.0, p.y);
	if (interior_clear_radius > 0.0) {
		body *= smoothstep(interior_clear_radius, interior_clear_radius + 2.0, distance(p, interior_clear_center));
	}
	float billow = 0.78 + 0.22 * sin(p.x / 90.0 + elapsed * 0.14) * sin(p.z / 75.0 - elapsed * 0.3) * sin(p.y / 65.0);
	DENSITY = extinction * strength * body * billow;
	ALBEDO = mix(dust_color.rgb, vec3(0.94, 0.84, 0.70), 0.45);
}
