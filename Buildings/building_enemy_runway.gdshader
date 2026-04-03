shader_type spatial;

uniform vec4 base_color : source_color = vec4(0.19, 0.19, 0.20, 1.0);
uniform vec4 stripe_color : source_color = vec4(0.95, 0.95, 0.95, 1.0);
uniform float runway_half_width = 10.0;
uniform float runway_half_length = 200.0;
uniform float edge_inset = 1.1;
uniform float edge_width = 0.45;
uniform float center_width = 0.55;
uniform float dash_length = 2.0;
uniform float gap_length = 2.0;
uniform float roughness_value = 0.92;
uniform float specular_value = 0.05;

varying vec3 local_pos;
varying vec3 local_normal;

void vertex() {
	local_pos = VERTEX;
	local_normal = NORMAL;
}

void fragment() {
	vec3 albedo = base_color.rgb;

	if (normalize(local_normal).y > 0.9) {
		float abs_x = abs(local_pos.x);
		float abs_z = abs(local_pos.z);
		bool inside_top = abs_x <= runway_half_width && abs_z <= runway_half_length;
		if (inside_top) {
			float edge_center = runway_half_width - edge_inset - edge_width * 0.5;
			float edge_delta = abs(abs_x - edge_center);
			float edge_half_width = edge_width * 0.5;
			float edge_aa = max(fwidth(edge_delta), 0.02);
			float edge_mask = 1.0 - smoothstep(edge_half_width, edge_half_width + edge_aa, edge_delta);

			float dash_cycle = max(dash_length + gap_length, 0.001);
			float dash_phase = mod(local_pos.z + runway_half_length, dash_cycle);
			float center_delta = abs(local_pos.x);
			float center_half_width = center_width * 0.5;
			float center_aa = max(fwidth(center_delta), 0.02);
			float center_width_mask = 1.0 - smoothstep(center_half_width, center_half_width + center_aa, center_delta);
			float dash_aa = max(fwidth(dash_phase), 0.02);
			float dash_mask = 1.0 - smoothstep(dash_length, dash_length + dash_aa, dash_phase);
			float center_mask = center_width_mask * dash_mask;
			float stripe_mask = max(edge_mask, center_mask);

			albedo = mix(albedo, stripe_color.rgb, clamp(stripe_mask, 0.0, 1.0));
		}
	}

	ALBEDO = albedo;
	ROUGHNESS = roughness_value;
	SPECULAR = specular_value;
}
