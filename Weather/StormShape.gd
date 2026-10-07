extends RefCounted
## Bounded outlines shared by storm coverage, map polygons and rendered surfaces.

const MAX_EDGE := 1.4

static func random_outline(rng: RandomNumberGenerator) -> Vector4:
	return Vector4(rng.randi_range(2, 5), rng.randf_range(0.08, 0.24),
		rng.randf_range(-PI, PI), rng.randf_range(0.04, 0.12))

static func edge(angle: float, shape: Vector4) -> float:
	return 1.0 + shape.y * sin(angle * shape.x + shape.z) \
		+ shape.w * cos(angle * 2.0 - shape.z * 0.7)

static func dust_top(x: float, z: float, elapsed: float, dimensions: Vector3, shape: Vector4) -> float:
	var phase := shape.z
	var broad := sin(atan2(z / dimensions.z, x / dimensions.x) * 2.0 + phase)
	return clampf(0.86 + 0.09 * sin(x / 280.0 + elapsed * 0.045 + phase)
		+ 0.045 * sin(z / 350.0 - x / 1050.0 + elapsed * 0.03 - phase)
		+ 0.035 * sin(x / 93.0 + z / 137.0 + elapsed * 0.08)
		+ 0.1 * broad * shape.y / 0.24, 0.6, 1.18)

static func encode_outline(shape: Vector4) -> Array:
	# Plain numbers also work in legacy JSON checkpoints without Vector4 support.
	return [shape.x, shape.y, shape.z, shape.w]

static func decode_outline(value: Variant, fallback: Vector4) -> Vector4:
	if not value is Array or value.size() != 4:
		return fallback
	return Vector4(clampf(float(value[0]), 2.0, 6.0), clampf(float(value[1]), 0.0, 0.24),
		float(value[2]), clampf(float(value[3]), 0.0, 0.12))
