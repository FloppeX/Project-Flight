shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;

uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;
uniform vec4 tint : source_color = vec4(0.88, 0.76, 0.62, 0.65);
uniform float motion_amplitude_m = 30.0;
uniform float motion_speed = 0.055;
uniform float motion_frequency = 0.00125;
uniform float motion_phase = 0.0;
uniform vec3 storm_center_world = vec3(0.0);
uniform float storm_radius_m = 0.0;
varying vec3 world_position;
varying vec3 local_position;

void vertex() {
	float t = TIME * motion_speed + motion_phase;
	float wave_a = sin((VERTEX.x + VERTEX.z * 0.37) * motion_frequency + t);
	float wave_b = sin((VERTEX.z - VERTEX.x * 0.41) * motion_frequency * 1.73 - t * 1.41);
	float wave_c = sin((VERTEX.x * 0.31 - VERTEX.z * 0.29) * motion_frequency * 2.67 + t * 0.73);
	VERTEX.y += (wave_a * 0.52 + wave_b * 0.32 + wave_c * 0.16) * motion_amplitude_m;
	local_position = VERTEX;
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 face = normalize(cross(dFdx(world_position), dFdy(world_position)));
	vec3 view_direction = normalize(CAMERA_POSITION_WORLD - world_position);
	float facing = abs(dot(face, view_direction));
	float rim = mix(0.75, 1.0, smoothstep(0.0, 0.48, facing));
	float shade = 0.80 + floor(abs(dot(face, normalize(vec3(0.35, 0.85, 0.4)))) * 2.999) * 0.12;
	float breakup = 0.78 + 0.22 * sin(local_position.x * 0.00091 + TIME * 0.018) * sin(local_position.z * 0.00083 - TIME * 0.014);
	float nearby = smoothstep(15.0, 85.0, distance(world_position, CAMERA_POSITION_WORLD));
	float depth = textureLod(depth_texture, SCREEN_UV, 0.0).r;
	vec4 scene_view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	scene_view.xyz /= scene_view.w;
	float intersection = smoothstep(0.0, 90.0, -scene_view.z + VERTEX.z);
	vec2 storm_delta = world_position.xz - storm_center_world.xz;
	float storm_angle = atan(storm_delta.y, storm_delta.x);
	float storm_edge = 1.0 + 0.12 * sin(storm_angle * 5.0 + 0.8) + 0.07 * cos(storm_angle * 9.0);
	float storm_mask = 0.0;
	if (storm_radius_m > 0.0) {
		storm_mask = 1.0 - smoothstep(storm_radius_m * storm_edge * 0.62,
			storm_radius_m * storm_edge, length(storm_delta));
	}
	vec3 normal_dust = mix(tint.rgb, tint.rgb * COLOR.rgb, 0.30) * shade;
	vec3 charged_dust = vec3(0.19, 0.20, 0.27) * shade * COLOR.rgb;
	ALBEDO = mix(normal_dust, charged_dust, storm_mask * 0.94);
	ALPHA = min(tint.a * rim * breakup * nearby * intersection * (1.0 + storm_mask * 0.38), 1.0);
}
