shader_type spatial;
render_mode unshaded, cull_back;

uniform vec3 sand_color : source_color = vec3(0.78, 0.68, 0.45);
uniform vec3 rock_color : source_color = vec3(0.55, 0.55, 0.55);
uniform float slope_start = 0.35; // begin blending around ~20 degrees
uniform float slope_end = 0.8;    // fully rock by ~53 degrees

void fragment() {
    // Derive geometric world-space normal from world-position derivatives (camera-invariant)
    vec3 dx = dFdx(WORLD_POSITION);
    vec3 dy = dFdy(WORLD_POSITION);
    vec3 world_normal = normalize(cross(dx, dy));
    float up_dot = abs(world_normal.y);
    float slope = 1.0 - up_dot;
    float t = smoothstep(slope_start, slope_end, slope);
    vec3 base_col = mix(sand_color, rock_color, clamp(t, 0.0, 1.0));
    ALBEDO = base_col;
}


