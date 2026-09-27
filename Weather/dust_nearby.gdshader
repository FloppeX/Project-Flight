shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;

uniform vec4 dust_color : source_color = vec4(0.78, 0.46, 0.26, 1.0);
uniform float opacity = 0.24;
uniform bool cockpit_view = false;
uniform vec3 flow_direction = vec3(1.0, 0.0, 0.0);
uniform float grain_stretch = 1.0;
varying float camera_distance;

void vertex() {
	vec3 local_flow = normalize(transpose(mat3(MODEL_MATRIX)) * flow_direction);
	VERTEX += local_flow * dot(VERTEX, local_flow) * (grain_stretch - 1.0);
	camera_distance = length((MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz - CAMERA_POSITION_WORLD);
}

void fragment() {
	// Depth testing lets the cockpit frame occlude dust. Fade out before any
	// puff can reach the cabin; all visible movement stays beyond the glass.
	float clearance = cockpit_view ? smoothstep(8.0, 12.0, camera_distance) : smoothstep(1.0, 3.0, camera_distance);
	ALBEDO = dust_color.rgb;
	ALPHA = opacity * COLOR.a * clearance;
}
