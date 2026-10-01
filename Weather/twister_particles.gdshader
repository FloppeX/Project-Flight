shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
#include "res://Weather/twister_shape.gdshaderinc"
uniform float elapsed = 0.0;
uniform float height_m = 1100.0;
uniform float strength = 0.0;
uniform bool debris = false;
uniform vec4 dust_color : source_color = vec4(0.80, 0.68, 0.46, 1.0);
varying float opacity;
varying float shade;
varying vec3 world_pos;
void vertex() {
	float h = fract(INSTANCE_CUSTOM.x + elapsed * (debris ? 0.009 : 0.018));
	float a = INSTANCE_CUSTOM.y * 6.2831853 + elapsed * (0.8 + INSTANCE_CUSTOM.z * 0.4) / (1.0 + h * 2.0);
	float radius = funnel_radius(h) * (debris ? 0.8 + INSTANCE_CUSTOM.z * 0.65 : 1.05 + INSTANCE_CUSTOM.z * 0.55);
	float size = debris ? 0.6 + INSTANCE_CUSTOM.w * 1.5 : 9.0 + h * 23.0 + INSTANCE_CUSTOM.w * 13.0;
	VERTEX *= size;
	VERTEX += vec3(cos(a) * radius, h * height_m, sin(a) * radius) + axis_offset(h, elapsed);
	opacity = smoothstep(0.0, 0.04, h) * (1.0 - smoothstep(debris ? 0.35 : 0.7, debris ? 0.65 : 1.0, h));
	shade = 0.7 + INSTANCE_CUSTOM.w * 0.5;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	// Flat triangle shading makes the low-poly puffs read as facets rather than haze.
	vec3 face_normal = normalize(cross(dFdx(world_pos), dFdy(world_pos)));
	float facet = 0.82 + 0.18 * abs(dot(face_normal, normalize(vec3(0.4, 0.8, 0.3))));
	ALBEDO = dust_color.rgb * shade * (debris ? 0.45 : facet);
	ALPHA = strength * opacity * (debris ? 1.0 : 0.58) * smoothstep(5.0, 15.0, distance(world_pos, CAMERA_POSITION_WORLD));
}
