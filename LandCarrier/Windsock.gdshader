shader_type spatial;
render_mode cull_disabled;

uniform mat4 rest_transform;
uniform mat3 rest_normal;
uniform float sock_length = 4.0;
uniform float fixed_cuff_fraction = 0.12;
uniform float droop = 1.0;
uniform float flutter = 0.0;
uniform float phase = 0.0;
uniform vec4 cloth_color : source_color = vec4(1.0);
uniform float cloth_roughness = 0.5;

void vertex() {
	vec3 p = (rest_transform * vec4(VERTEX, 1.0)).xyz;
	vec3 n = normalize(rest_normal * NORMAL);
	float s = clamp(p.x, 0.0, sock_length);
	// Keep the mast-side cuff rigid, then use one continuous centreline for all
	// four meshes so their joins remain together as the free fabric droops.
	float cuff_length = sock_length * clamp(fixed_cuff_fraction, 0.0, 0.3);
	float free_length = max(sock_length - cuff_length, 0.001);
	float free_s = max(s - cuff_length, 0.0);
	float free_t = free_s / free_length;
	float curvature = droop * 1.55 / free_length;
	float angle = curvature * free_s;
	vec2 centre = vec2(s, 0.0);
	if (free_s > 0.0 && curvature > 0.00001) {
		vec2 arc = vec2(sin(angle), cos(angle) - 1.0) / curvature;
		centre = vec2(cuff_length, 0.0) + arc;
	}
	float wave = flutter * free_t * free_t * sin(phase * 7.0 - free_t * 9.0);
	VERTEX = vec3(centre.x + p.y * sin(angle), centre.y + p.y * cos(angle), p.z + wave);
	NORMAL = normalize(vec3(n.x * cos(angle) + n.y * sin(angle), -n.x * sin(angle) + n.y * cos(angle), n.z));
}

void fragment() {
	ALBEDO = cloth_color.rgb;
	ROUGHNESS = cloth_roughness;
}
