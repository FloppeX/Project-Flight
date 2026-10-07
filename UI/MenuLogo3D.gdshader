shader_type spatial;
render_mode unshaded, cull_back;

// Linear colours and ramp thresholds exported from the authored Blender material.
uniform vec4 tone_0 = vec4(0.22, 0.10, 0.001, 1.0);
uniform vec4 tone_1 = vec4(0.48, 0.23, 0.002, 1.0);
uniform vec4 tone_2 = vec4(1.0, 0.48, 0.004, 1.0);
uniform vec4 tone_3 = vec4(1.0, 0.63, 0.005, 1.0);
uniform vec3 thresholds = vec3(0.30, 0.56, 0.81);
varying vec3 face_normal;

void vertex() {
    face_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

void fragment() {
    // Blender's (-X, -Y, +Z) studio direction, converted to Godot coordinates.
    float facing = dot(normalize(face_normal), vec3(-0.32, 0.70, 0.64));
    vec3 color = tone_0.rgb;
    if (facing >= thresholds.x) { color = tone_1.rgb; }
    if (facing >= thresholds.y) { color = tone_2.rgb; }
    if (facing >= thresholds.z) { color = tone_3.rgb; }
    ALBEDO = color;
}

