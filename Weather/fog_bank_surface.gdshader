shader_type spatial;
render_mode unshaded, cull_back, depth_draw_never;
#include "res://Weather/fog_bank_shape.gdshaderinc"
uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;
uniform vec3 radii = vec3(460.0, 160.0, 280.0);
uniform float elapsed = 0.0;
uniform float strength = 1.0;
uniform float shell = 1.0;
uniform float shell_opacity = 0.8;
uniform float exterior_visibility = 1.0;
uniform vec4 tint : source_color = vec4(0.74, 0.59, 0.43, 1.0);
varying vec3 world_position;
varying vec3 smooth_world_normal;
void vertex() {
	vec3 direction = normalize(VERTEX);
	VERTEX = direction * radii * bank_radius(direction, elapsed) * shell;
	smooth_world_normal = normalize(mat3(MODEL_MATRIX) * (direction / radii));
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	vec3 face = normalize(cross(dFdx(world_position), dFdy(world_position)));
	float light = abs(dot(face, normalize(vec3(0.35, 0.85, 0.4))));
	// Three restrained tones keep broad faces legible without rock-like shadows.
	float shade = 0.82 + floor(light * 2.999) * 0.14;
	vec3 view_direction = normalize(CAMERA_POSITION_WORLD - world_position);
	float facing = abs(dot(normalize(smooth_world_normal), view_direction));
	float rim = mix(0.18, 1.0, smoothstep(0.0, 0.6, facing));
	float depth = textureLod(depth_texture, SCREEN_UV, 0.0).r;
	vec4 scene_view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	scene_view.xyz /= scene_view.w;
	float intersection = smoothstep(0.0, 24.0, -scene_view.z + VERTEX.z);
	float nearby = smoothstep(12.0, 70.0, distance(world_position, CAMERA_POSITION_WORLD));
	ALBEDO = tint.rgb * shade;
	ALPHA = strength * shell_opacity * rim * intersection * nearby * exterior_visibility;
}
