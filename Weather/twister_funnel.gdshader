shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
#include "res://Weather/twister_shape.gdshaderinc"
uniform float elapsed = 0.0;
uniform float height_m = 1100.0;
uniform float strength = 0.0;
uniform float shell = 1.0;
uniform vec4 dust_color : source_color = vec4(0.65, 0.46, 0.3, 1.0);
varying float height_fraction;
varying float angle;
varying vec3 world_pos;
void vertex() {
	float h = UV.y;
	float a = UV.x * 6.2831853;
	float radius = funnel_radius(h) * shell * (1.0 + 0.085 * sin(a * 5.0 - h * 23.0 - elapsed * 1.1));
	VERTEX = vec3(cos(a) * radius, h * height_m, sin(a) * radius) + axis_offset(h, elapsed);
	height_fraction = h;
	angle = a;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	float h = height_fraction;
	float streak = sin(angle * 9.0 - h * 46.0 - elapsed * 2.0) * 0.5 + 0.5;
	float billow = sin(angle * 5.0 + h * 32.0 - elapsed * 1.3) * sin(angle * 13.0 - h * 59.0 - elapsed * 0.9) * 0.5 + 0.5;
	float fade = smoothstep(0.0, 0.018, h) * (1.0 - smoothstep(0.62, 1.0, h));
	ALBEDO = dust_color.rgb * mix(0.62, 1.25, billow * 0.6 + streak * 0.4);
	// Dense silhouette, with soft formation/dissipation and a frayed upper edge.
	ALPHA = strength * fade * (0.72 + billow * 0.16 + streak * 0.08) * smoothstep(6.0, 25.0, distance(world_pos, CAMERA_POSITION_WORLD));
}
