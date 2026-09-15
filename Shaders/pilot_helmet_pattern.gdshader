shader_type spatial;
render_mode cull_disabled;

uniform vec4 base_color : source_color = vec4(0.2, 0.3, 0.6, 1.0);
uniform vec4 marking_color : source_color = vec4(0.96, 0.93, 0.82, 1.0);
uniform int pattern_mode = 0;
uniform float roughness = 0.65;
uniform float metallic = 0.0;
varying vec3 helmet_position;

void vertex() {
	helmet_position = CUSTOM0.xyz;
}

float hash3(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

float noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i), hash3(i + vec3(1,0,0)), f.x),
		mix(hash3(i + vec3(0,1,0)), hash3(i + vec3(1,1,0)), f.x), f.y),
		mix(mix(hash3(i + vec3(0,0,1)), hash3(i + vec3(1,0,1)), f.x),
		mix(hash3(i + vec3(0,1,1)), hash3(i + vec3(1,1,1)), f.x), f.y), f.z);
}

// Exact straight-edged five-point star, with a derivative-sized antialias edge.
float star(vec2 p) {
	float angle = atan(p.x, p.y);
	float sector = (angle + 6.2831853) / 0.62831853;
	float index = floor(sector);
	float local_angle = fract(sector) * 0.62831853;
	float r1 = mix(1.0, 0.44, mod(index, 2.0));
	float r2 = mix(0.44, 1.0, mod(index, 2.0));
	float edge = r1 * r2 * sin(0.62831853) /
		(r2 * sin(0.62831853 - local_angle) + r1 * sin(local_angle));
	float distance_to_edge = length(p) - edge;
	float aa = max(fwidth(distance_to_edge), 0.006);
	return 1.0 - smoothstep(-aa, aa, distance_to_edge);
}

float painted_edge(float distance_to_edge) {
	float aa = max(fwidth(distance_to_edge), 0.005);
	return 1.0 - smoothstep(-aa, aa, distance_to_edge);
}

float lightning(vec2 p) {
	const vec2 corners[7] = vec2[7](
		vec2(-0.87, 0.38), vec2(0.02, 0.38), vec2(-0.22, 0.08),
		vec2(0.88, 0.13), vec2(0.02, -0.51), vec2(0.20, -0.12),
		vec2(-0.57, -0.10));
	float distance_to_edge = 10.0;
	bool inside = false;
	for (int i = 0; i < 7; i++) {
		vec2 a = corners[i];
		vec2 b = corners[(i + 1) % 7];
		vec2 edge = b - a;
		vec2 nearest = a + edge * clamp(dot(p - a, edge) / dot(edge, edge), 0.0, 1.0);
		distance_to_edge = min(distance_to_edge, length(p - nearest));
		if ((a.y > p.y) != (b.y > p.y)) {
			if (p.x < a.x + (p.y - a.y) * edge.x / edge.y) { inside = !inside; }
		}
	}
	return painted_edge(inside ? -distance_to_edge : distance_to_edge);
}

void fragment() {
	// The authored helmet shell is double-sided, including some stripe faces.
	if (!FRONT_FACING) { NORMAL = -NORMAL; }
	vec3 p = helmet_position;
	float mask = 0.0;
	vec3 ink = marking_color.rgb;
	if (pattern_mode == 1) {
		// Two diagonal racing bands cross the existing material boundary.
		float band = abs(abs(p.x + p.z * 0.38) - 0.34) - 0.10;
		float aa = max(fwidth(band), 0.004);
		mask = 1.0 - smoothstep(-aa, aa, band);
	} else if (pattern_mode == 2) {
		// Badges on both sides plus the crown, not separate per-material UVs.
		float side = star((p.zy - vec2(0.05, 0.20)) / vec2(0.57, 0.65));
		float top = star(p.xz / 0.62);
		mask = max(side * smoothstep(0.35, 0.65, abs(p.x)),
			top * smoothstep(0.55, 0.8, p.y));
	} else if (pattern_mode == 3) {
		float n = noise3(p * 5.0 + vec3(7.1, 3.8, 13.4)) * 0.76
			+ noise3(p * 10.0 + vec3(2.7, 8.1, 4.3)) * 0.24;
		float aa = max(fwidth(n), 0.005);
		mask = smoothstep(0.45 - aa, 0.45 + aa, n);
		ink = mix(marking_color.rgb, marking_color.rgb * 0.42,
			smoothstep(0.62 - aa, 0.62 + aa, n));
	} else if (pattern_mode == 4) {
		// Same forward-pointing emblem on both sides, never mirrored nose-to-tail.
		mask = lightning(p.zy - vec2(0.0, 0.13)) * smoothstep(0.35, 0.60, abs(p.x));
	} else if (pattern_mode == 5) {
		float badge = star((p.zy - vec2(0.38, 0.30)) / vec2(0.32, 0.37));
		float u = (p.z + 0.86) / 1.16;
		float trails = 0.0;
		for (int streak = -1; streak <= 1; streak++) {
			float center = -0.20 + 0.50 * u + float(streak) * 0.16 * (1.0 - 0.6 * u);
			float width = 0.013 + 0.022 * clamp(u, 0.0, 1.0);
			float d = max(abs(p.y - center) - width, max(-u, u - 1.0));
			trails = max(trails, painted_edge(d));
		}
		mask = max(badge, trails) * smoothstep(0.35, 0.60, abs(p.x));
	} else if (pattern_mode == 6) {
		// Static hot-rod paint: tongues rise from the rim, wrapping continuously.
		// Integer angular harmonics keep the rear seam closed; no TIME animation.
		float angle = atan(p.z, p.x);
		float curl = angle + 0.13 * sin(p.y * 5.0);
		float tongue = pow(0.5 + 0.5 * sin(curl * 7.0 + sin(curl * 3.0) * 0.9), 2.5);
		float tip = -0.22 + tongue * 0.94 + sin(curl * 11.0) * 0.08;
		mask = painted_edge(p.y - tip);
		float core = painted_edge(p.y - (tip - 0.23));
		ink = mix(marking_color.rgb * 0.48, marking_color.rgb, core);
	} else if (pattern_mode == 7) {
		// Checkered band around the lower shell, leaving the crown colors visible.
		float around = atan(p.z, p.x) * (8.0 / 3.14159265);
		float vertical = (p.y + 1.0) * 4.0;
		float wave = sin(around * 3.14159265) * sin(vertical * 3.14159265);
		float aa = max(fwidth(wave), 0.015);
		mask = smoothstep(-aa, aa, wave) * painted_edge(p.y - 0.15);
	} else if (pattern_mode == 8) {
		// Three forward-pointing V bands wrap over the crown and both sides.
		float v = p.z - abs(p.x) * 0.65;
		float bands = min(abs(v + 0.55), min(abs(v + 0.05), abs(v - 0.45)));
		mask = painted_edge(bands - 0.075);
	}
	ALBEDO = mix(base_color.rgb, ink, mask * marking_color.a);
	ROUGHNESS = roughness;
	METALLIC = metallic;
}
