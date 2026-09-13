shader_type spatial;
render_mode cull_disabled;
uniform vec4 plate_color : source_color = vec4(0.3, 0.33, 0.35, 1.0);
uniform float plate_metallic = 0.2;
uniform float plate_roughness = 0.8;
uniform vec4 plate_emission : source_color = vec4(0.0);
uniform float door_offset_x = 0.0;
uniform float aperture_half_width = 0.55;
varying float door_x;
void vertex() { door_x = VERTEX.x + door_offset_x; }
void fragment() {
    if (abs(door_x) > aperture_half_width) { discard; }
    ALBEDO = plate_color.rgb;
    METALLIC = plate_metallic;
    ROUGHNESS = plate_roughness;
    EMISSION = plate_emission.rgb;
}
