shader_type spatial;
render_mode unshaded;

uniform vec3 grass_color : source_color = vec3(0.25, 0.75, 0.45);
uniform vec3 rock_color  : source_color = vec3(0.55, 0.55, 0.60);

uniform vec3  sun_dir   = normalize(vec3(0.35, 0.75, 0.55));
uniform float ambient   = 0.35;
uniform float slope_start = 0.65; // y≈0.65 begins rock
uniform float slope_end   = 0.35; // y≈0.35 full rock on steep faces

void fragment() {
    vec3 n = normalize(cross(dFdx(WORLD_POSITION), dFdy(WORLD_POSITION)));
    float ndl = max(dot(n, normalize(sun_dir)), 0.0);
    float light = max(ambient, ndl);

    // Use upward-facing component (n.y) to choose color
    float t = smoothstep(slope_end, slope_start, n.y);
    vec3 base = mix(rock_color, grass_color, t);

    ALBEDO = base * light;
}
