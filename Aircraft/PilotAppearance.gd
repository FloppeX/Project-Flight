extends RefCounted

## Identity-owned visual data shared by cockpit, ejection, downed-pilot, and
## passenger presentations. Animated bodies may be pooled; this palette is not.

const META_KEY: StringName = &"pilot_livery_colors"
const IDENTITY_FIELD: String = "pilot_livery_colors"

const HELMET_COLORS: Array[Color] = [
	Color(0.03, 0.03, 0.03),
	Color(0.96, 0.93, 0.82),
	Color(0.93, 0.62, 0.74),
	Color(0.78, 0.16, 0.16),
	Color(0.86, 0.42, 0.14),
	Color(0.90, 0.66, 0.18),
	Color(0.36, 0.38, 0.17),
	Color(0.16, 0.47, 0.20),
	Color(0.12, 0.46, 0.45),
	Color(0.17, 0.62, 0.67),
	Color(0.46, 0.68, 0.86),
	Color(0.20, 0.33, 0.73),
	Color(0.48, 0.32, 0.64),
	Color(0.73, 0.60, 0.44),
	Color(0.36, 0.40, 0.44),
]
const SUIT_COLORS: Array[Color] = [
	Color(0.36, 0.40, 0.44),
	Color(0.73, 0.60, 0.44),
	Color(0.16, 0.47, 0.20),
	Color(0.09, 0.13, 0.30),
]
const SUIT_DARK_COLORS: Array[Color] = [
	Color(0.17, 0.18, 0.20),
	Color(0.37, 0.24, 0.15),
	Color(0.09, 0.13, 0.30),
]


static func make_random_palette(rng: RandomNumberGenerator) -> Dictionary:
	var helmet_1 := HELMET_COLORS[rng.randi_range(0, HELMET_COLORS.size() - 1)]
	var helmet_2 := HELMET_COLORS[rng.randi_range(0, HELMET_COLORS.size() - 1)]
	if HELMET_COLORS.size() > 1:
		while helmet_2 == helmet_1:
			helmet_2 = HELMET_COLORS[rng.randi_range(0, HELMET_COLORS.size() - 1)]
	return {
		"main_color": SUIT_COLORS[rng.randi_range(0, SUIT_COLORS.size() - 1)],
		"main_color_dark": SUIT_DARK_COLORS[
			rng.randi_range(0, SUIT_DARK_COLORS.size() - 1)
		],
		"helmet_color_1": helmet_1,
		"helmet_color_2": helmet_2,
	}


static func is_valid_palette(value: Variant) -> bool:
	if not (value is Dictionary):
		return false
	var palette := value as Dictionary
	return palette.get("main_color", null) is Color \
			and palette.get("main_color_dark", null) is Color \
			and palette.get("helmet_color_1", null) is Color \
			and palette.get("helmet_color_2", null) is Color


static func ensure_identity_palette(
		identity: Dictionary,
		rng: RandomNumberGenerator
) -> Dictionary:
	var existing: Variant = identity.get(IDENTITY_FIELD, null)
	if is_valid_palette(existing):
		return (existing as Dictionary).duplicate(true)
	var created := make_random_palette(rng)
	identity[IDENTITY_FIELD] = created.duplicate(true)
	return created


static func copy_palette_metadata(source: Object, target: Object) -> bool:
	if source == null or target == null \
			or not is_instance_valid(source) or not is_instance_valid(target):
		return false
	if not source.has_meta(META_KEY):
		return false
	var palette: Variant = source.get_meta(META_KEY)
	if not is_valid_palette(palette):
		return false
	target.set_meta(META_KEY, (palette as Dictionary).duplicate(true))
	return true
