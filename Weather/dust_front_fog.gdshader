shader_type fog;
#include "res://Weather/storm_shape.gdshaderinc"
uniform vec3 box_size;
uniform vec3 dimensions;
uniform vec4 outline = vec4(5.0, 0.035, 0.0, 0.0);
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
	float lobe = storm_edge(atan(z, x), outline);
	float radial = length(vec2(x, z)) / lobe;
	float top = dust_top(p, dimensions, elapsed, outline);
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
