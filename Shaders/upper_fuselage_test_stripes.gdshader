shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4 base_color : source_color = vec4(0.28, 0.33, 0.38, 1.0);
uniform vec4 pattern_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 tertiary_pattern_color : source_color = vec4(0.35, 0.42, 0.22, 1.0);
uniform int pattern_mode = 1;
uniform float pattern_frequency_per_meter = 1.1;
uniform float pattern_width_fraction = 0.18;
uniform float roughness = 0.65;
uniform float metallic = 0.0;
uniform bool side_projection_enabled = false;

varying vec3 local_position;
varying vec3 local_normal;

void vertex() {
	// Calculate the world-space scale of the local axes to make patterns scale-independent
	float scale_x = length(MODEL_MATRIX[0].xyz);
	float scale_y = length(MODEL_MATRIX[1].xyz);
	float scale_z = length(MODEL_MATRIX[2].xyz);
	local_position = VERTEX * vec3(scale_x, scale_y, scale_z);
	local_normal = NORMAL;
}

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float band(float value, float width) {
	return 1.0 - step(width, fract(value));
}

vec4 apply_pattern(vec3 p, vec3 n) {
	float h = p.z;
	float v = p.y;
	if (side_projection_enabled) {
		vec3 an = abs(n);
		if (an.y > an.x && an.y > an.z) {
			h = p.x;
			v = p.z;
		} else if (an.x > an.z) {
			h = p.z;
			v = p.y;
		} else {
			h = p.x;
			v = p.y;
		}
	}
	vec2 side_uv = vec2(h, v);
	float freq = max(pattern_frequency_per_meter, 0.05);
	float width = clamp(pattern_width_fraction, 0.01, 0.95);
	float length_scale = 0.12 * freq / 1.1;

	if (pattern_mode == 1) {
		float mask = band(h * freq, width);
		return mix(base_color, pattern_color, mask);
	}
	if (pattern_mode == 2) {
		float wobble = sin(v * 5.0) * 0.22 + sin(v * 11.0 + h) * 0.08;
		float mask = band((h + wobble) * freq * 1.25, 0.34);
		return mix(base_color, pattern_color, mask);
	}
	if (pattern_mode == 3) {
		float wobble = sin(v * 6.0 + h * 1.4) * 0.24 + sin(v * 15.0) * 0.05;
		float mask = band((h + wobble) * freq * 1.45, 0.24);
		return mix(base_color, pattern_color, mask);
	}
	if (pattern_mode == 4) {
		float n1 = value_noise(side_uv * freq * 1.6);
		float n2 = value_noise(side_uv * freq * 3.1 + vec2(7.3, 2.1));
		vec4 camo = base_color;
		if (n1 > 0.58) {
			camo = tertiary_pattern_color;
		}
		if (n2 > 0.64) {
			camo = pattern_color;
		}
		if (n1 < 0.25) {
			camo = pattern_color;
		}
		return camo;
	}
	if (pattern_mode == 5) {
		float mask = band(v * freq * 1.6, width * 0.75);
		return mix(base_color, pattern_color, mask);
	}
	if (pattern_mode == 6) {
		vec2 cell = side_uv * freq * 1.4;
		vec2 centered = fract(cell) - vec2(0.5);
		float dot_mask = 1.0 - step(width * 0.75, length(centered));
		return mix(base_color, pattern_color, dot_mask);
	}
	if (pattern_mode == 7) {
		float zig = abs(fract(h * freq * 0.8) * 2.0 - 1.0);
		float bolt_y = (zig - 0.5) * 0.55 + sin(h * freq * 5.0) * 0.06;
		float repeat_y = fract((v - bolt_y) * freq * 0.75);
		float mask = 1.0 - step(width * 0.55, min(repeat_y, 1.0 - repeat_y));
		return mix(base_color, pattern_color, mask);
	}
	if (pattern_mode == 8) {
		float vertical = band(h * freq, width * 0.65);
		float horizontal = band(v * freq * 1.35, width * 0.55);
		vec4 plaid = mix(base_color, pattern_color, max(vertical, horizontal));
		return mix(plaid, tertiary_pattern_color, vertical * horizontal * 0.55);
	}
	if (pattern_mode == 9) {
		vec2 checker = floor(side_uv * freq * 1.2);
		float mask = mod(checker.x + checker.y, 2.0);
		return mix(base_color, pattern_color, mask);
	}
	if (pattern_mode == 10) {
		vec2 cell = side_uv * freq * 1.5;
		vec2 centered = fract(cell) - vec2(0.5);
		// 5-pointed star SDF
		float a = atan(centered.y, centered.x) + 1.570796;
		float r = length(centered);
		float star_val = cos(a * 5.0);
		float d = r - width * 0.4 * (0.7 + 0.3 * star_val);
		float mask = 1.0 - step(0.0, d);
		return mix(base_color, pattern_color, mask);
	}
	if (pattern_mode == 11) {
		vec2 grid = floor(side_uv * freq * 3.0);
		float n = hash21(grid);
		float n2 = hash21(grid + vec2(15.4, 23.7));
		vec4 digital = base_color;
		if (n > 0.65) {
			digital = tertiary_pattern_color;
		} else if (n2 > 0.65) {
			digital = pattern_color;
		} else if (n > 0.35) {
			digital = pattern_color;
		}
		return digital;
	}
	if (pattern_mode == 12) {
		float zig = abs(v) * 0.8;
		float mask = band((h + zig) * freq, width);
		return mix(base_color, pattern_color, mask);
	}
	if (pattern_mode == 13) {
		float wobble = sin(v * 8.0) * 0.15;
		float mask = band((h + wobble) * freq, width);
		return mix(base_color, pattern_color, mask);
	}
	if (pattern_mode == 14) {
		float wave = sin(h * 5.0 - v * 5.0) * 0.15;
		float mask = band((h + v + wave) * freq * 0.707, width);
		return mix(base_color, pattern_color, mask);
	}
	if (pattern_mode == 15) {
		vec2 cell = side_uv * freq * 1.5;
		vec2 centered = fract(cell) - vec2(0.5);
		float dist = abs(centered.x) + abs(centered.y);
		float mask = 1.0 - step(width * 0.7, dist);
		return mix(base_color, pattern_color, mask);
	}
	if (pattern_mode == 16) {
		vec2 cell = side_uv * freq * 1.8;
		vec2 centered = fract(cell);
		float mask = step(centered.x + centered.y, 1.0);
		vec2 grid = floor(cell);
		float alt = mod(grid.x + grid.y, 2.0);
		if (alt > 0.5) {
			mask = 1.0 - mask;
		}
		return mix(base_color, pattern_color, mask);
	}
	if (pattern_mode == 17) {
		vec2 shard_uv = side_uv * freq * 1.45;
		vec2 grid = floor(shard_uv);
		vec2 f = fract(shard_uv);
		float n = hash21(grid);
		float diagonal = step(0.0, (f.x - f.y) + (n - 0.5) * 0.85);
		float n2 = hash21(grid + diagonal + vec2(9.1, 3.7));
		vec4 shard = base_color;
		if (n2 > 0.66) {
			shard = pattern_color;
		} else if (n2 > 0.38) {
			shard = tertiary_pattern_color;
		}
		return shard;
	}
	if (pattern_mode == 18) {
		vec2 splinter_uv = side_uv * freq * 1.15;
		float a = floor((splinter_uv.x + splinter_uv.y * 0.55) * 1.4);
		float b = floor((splinter_uv.x * -0.65 + splinter_uv.y) * 1.7);
		float n = hash21(vec2(a, b));
		if (n > 0.68) {
			return pattern_color;
		}
		if (n > 0.42) {
			return tertiary_pattern_color;
		}
		return base_color;
	}
	if (pattern_mode == 19) {
		vec2 facet_uv = side_uv * freq * 1.25;
		vec2 grid = floor(facet_uv);
		vec2 f = fract(facet_uv);
		float left_triangle = step(f.y, f.x);
		float right_triangle = step(1.0 - f.y, f.x);
		float n = hash21(grid + vec2(left_triangle, right_triangle) * 4.0);
		if (n > 0.72) {
			return pattern_color;
		}
		if (n > 0.45) {
			return tertiary_pattern_color;
		}
		return base_color;
	}
	if (pattern_mode == 20) {
		float t = clamp(h * length_scale + 0.5, 0.0, 1.0);
		return mix(base_color, pattern_color, 1.0 - step(0.25, t));
	}
	if (pattern_mode == 21) {
		float t = clamp(h * length_scale + 0.5, 0.0, 1.0);
		float middle = step(0.25, t) * (1.0 - step(0.75, t));
		return mix(pattern_color, base_color, middle);
	}
	if (pattern_mode == 22) {
		float t = clamp(h * length_scale + 0.5, 0.0, 1.0);
		return mix(base_color, pattern_color, step(0.75, t));
	}
	if (pattern_mode == 23) {
		float t = clamp(h * length_scale + 0.5, 0.0, 1.0);
		if (t < 0.25) {
			return pattern_color;
		}
		if (t < 0.75) {
			return base_color;
		}
		return tertiary_pattern_color;
	}
	if (pattern_mode == 24) {
		float t = clamp(h * length_scale + sin(v * 1.7) * 0.035 + 0.5, 0.0, 1.0);
		if (t < 0.22) {
			return pattern_color;
		}
		if (t < 0.68) {
			return base_color;
		}
		return tertiary_pattern_color;
	}

	return base_color;
}

void fragment() {
	vec4 mixed_color = apply_pattern(local_position, normalize(local_normal));
	ALBEDO = mixed_color.rgb;
	ROUGHNESS = roughness;
	METALLIC = metallic;
}
