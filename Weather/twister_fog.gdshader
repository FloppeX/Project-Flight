shader_type fog;
#include "res://Weather/twister_shape.gdshaderinc"
uniform vec3 box_size;
uniform float height_m = 1100.0;
uniform float elapsed = 0.0;
uniform float strength = 0.0;
uniform vec4 dust_color : source_color;
uniform vec3 clear_center = vec3(0.0);
uniform float clear_radius = 0.0;
void fog() {
	vec3 p = (UVW - 0.5) * box_size + vec3(0.0, height_m * 0.5 - 20.0, 0.0);
	float h = clamp(p.y / height_m, 0.0, 1.0);
	float radius = funnel_radius(h);
	float radial = length((p - axis_offset(h, elapsed)).xz);
	float core = 1.0 - smoothstep(radius * 0.5, radius * 1.4, radial);
	float fade = smoothstep(-30.0, 0.0, p.y) * (1.0 - smoothstep(0.6, 1.0, h));
	if (clear_radius > 0.0) { fade *= smoothstep(clear_radius, clear_radius + 3.0, distance(p, clear_center)); }
	DENSITY = 0.035 * strength * core * fade;
	ALBEDO = mix(dust_color.rgb, vec3(0.85, 0.75, 0.62), 0.4);
}
