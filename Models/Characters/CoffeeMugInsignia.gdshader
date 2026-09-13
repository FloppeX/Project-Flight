shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2D insignia_texture : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec4 ceramic_color : source_color = vec4(0.92, 0.92, 0.9, 1.0);
uniform vec2 uv_scale = vec2(1.0);

void fragment() {
	vec2 logo_uv = (UV - vec2(0.5)) * uv_scale + vec2(0.5);
	vec4 logo = texture(insignia_texture, logo_uv);
	float inside = step(0.0, logo_uv.x) * step(logo_uv.x, 1.0)
		* step(0.0, logo_uv.y) * step(logo_uv.y, 1.0);
	ALBEDO = mix(ceramic_color.rgb, logo.rgb, logo.a * inside);
	ROUGHNESS = 0.27;
}
