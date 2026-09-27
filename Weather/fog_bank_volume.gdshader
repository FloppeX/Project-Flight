shader_type fog;
#include "res://Weather/fog_bank_shape.gdshaderinc"
uniform vec3 radii = vec3(460.0, 160.0, 280.0);
uniform vec3 box_size;
uniform float elapsed = 0.0;
uniform float strength = 1.0;
uniform float extinction = 0.025;
uniform vec4 tint : source_color;
uniform vec3 clear_center = vec3(0.0);
void fog() {
	vec3 p = (UVW - 0.5) * box_size;
	float envelope = bank_envelope(p, radii, elapsed);
	float density = 1.0 - smoothstep(0.65, 1.12, envelope);
	float clearance = smoothstep(4.0, 7.0, distance(p, clear_center));
	DENSITY = extinction * strength * density * clearance;
	ALBEDO = tint.rgb;
}
