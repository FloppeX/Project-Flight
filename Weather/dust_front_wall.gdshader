shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;

uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;
uniform vec3 dimensions;
uniform float elapsed = 0.0;
uniform float strength = 0.0;
uniform float shell = 1.0;
uniform float shell_opacity = 0.78;
uniform vec4 dust_color : source_color = vec4(0.78, 0.46, 0.26, 1.0);
varying vec3 world_position;
varying vec3 local_position;
varying vec3 local_camera;

void vertex() {
	VERTEX.xz *= shell;
	float top = 0.86 + 0.09 * sin(VERTEX.x / 280.0 + elapsed * 0.045)
		+ 0.045 * sin(VERTEX.z / 350.0 - VERTEX.x / 1050.0 + elapsed * 0.03)
		+ 0.035 * sin(VERTEX.x / 93.0 + VERTEX.z / 137.0 + elapsed * 0.08);
	VERTEX.y *= top * shell;
	local_position = VERTEX;
	local_camera = (inverse(MODEL_MATRIX) * vec4(CAMERA_POSITION_WORLD, 1.0)).xyz;
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float radial = length(local_camera.xz / dimensions.xz);
	float height = max(local_camera.y, 0.0) / (dimensions.y * 0.88);
	float camera_boundary = sqrt(radial * radial + pow(height, 8.0));
	// The local fog takes over near the shell, including cockpit and bridge views.
	float exterior = smoothstep(0.96, 1.16, camera_boundary);
	vec3 face = normalize(cross(dFdx(world_position), dFdy(world_position)));
	float light = abs(dot(face, normalize(vec3(0.35, 0.85, 0.4))));
	float shade = 0.60 + floor(light * 2.999) * 0.15;
	float facing = abs(dot(face, normalize(CAMERA_POSITION_WORLD - world_position)));
	float rim = mix(0.72, 1.0, smoothstep(0.0, 0.58, facing));
	float broad_breakup = 0.82 + 0.18 * sin(local_position.x * 0.0009 + elapsed * 0.012)
		* sin(local_position.z * 0.0012 - elapsed * 0.018);
	float nearby = smoothstep(20.0, 100.0, distance(world_position, CAMERA_POSITION_WORLD));
	float bottom_fade = smoothstep(-20.0, 110.0, local_position.y);
	float depth = textureLod(depth_texture, SCREEN_UV, 0.0).r;
	vec4 scene_view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	scene_view.xyz /= scene_view.w;
	float intersection = smoothstep(0.0, 100.0, -scene_view.z + VERTEX.z);
	ALBEDO = dust_color.rgb * shade;
	ALPHA = strength * shell_opacity * exterior * rim * broad_breakup * nearby * bottom_fade * intersection;
}
