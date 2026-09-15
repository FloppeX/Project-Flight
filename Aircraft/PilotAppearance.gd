extends RefCounted

## Identity-owned visual data shared by cockpit, ejection, downed-pilot, and
## passenger presentations. Animated bodies may be pooled; this palette is not.

const META_KEY: StringName = &"pilot_livery_colors"
const IDENTITY_FIELD: String = "pilot_livery_colors"
const HELMET_RANDOMIZATION_VERSION := 1
# Append only: these indices also identify modes in the helmet paint shader.
const HELMET_PATTERNS: Array[String] = [
	"plain", "racing_stripes", "stars", "camo",
	"lightning_bolts", "shooting_stars", "flames", "checkerboard", "chevrons",
]

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
	var palette := {
		"main_color": SUIT_COLORS[rng.randi_range(0, SUIT_COLORS.size() - 1)],
		"main_color_dark": SUIT_DARK_COLORS[
			rng.randi_range(0, SUIT_DARK_COLORS.size() - 1)
		],
	}
	randomize_helmet(palette, rng)
	return palette


## Randomize only personal helmet paint; leave suit colors and identity intact.
static func randomize_helmet(palette: Dictionary, rng: RandomNumberGenerator) -> void:
	var first := HELMET_COLORS[rng.randi_range(0, HELMET_COLORS.size() - 1)]
	var secondary_options: Array[Color] = []
	for color in HELMET_COLORS:
		if _color_distance_squared(first, color) >= 0.08:
			secondary_options.append(color)
	var second := secondary_options[rng.randi_range(0, secondary_options.size() - 1)]
	var ink_options: Array[Color] = []
	for color in HELMET_COLORS:
		if _color_distance_squared(first, color) >= 0.25 \
				and _color_distance_squared(second, color) >= 0.25:
			ink_options.append(color)
	palette["helmet_color_1"] = first
	palette["helmet_color_2"] = second
	# Every generated pilot gets a visible design; plain remains a manual option.
	palette["helmet_pattern"] = HELMET_PATTERNS[rng.randi_range(1, HELMET_PATTERNS.size() - 1)]
	palette["helmet_marking_color"] = ink_options[rng.randi_range(0, ink_options.size() - 1)] \
			if not ink_options.is_empty() else contrasting_marking_color(first, second)
	palette["helmet_randomization_version"] = HELMET_RANDOMIZATION_VERSION


static func _color_distance_squared(first: Color, second: Color) -> float:
	return Vector3(first.r, first.g, first.b).distance_squared_to(Vector3(second.r, second.g, second.b))


static func helmet_pattern(palette: Dictionary) -> String:
	var pattern := str(palette.get("helmet_pattern", "plain"))
	return pattern if pattern in HELMET_PATTERNS else "plain"


static func contrasting_marking_color(first: Color, second: Color) -> Color:
	var average := first.lerp(second, 0.5)
	var brightness := average.r * 0.2126 + average.g * 0.7152 + average.b * 0.0722
	return Color(0.96, 0.93, 0.82) if brightness < 0.48 else Color(0.035, 0.04, 0.05)


static func helmet_marking_color(palette: Dictionary) -> Color:
	var supplied: Variant = palette.get("helmet_marking_color")
	if supplied is Color:
		return supplied as Color
	return contrasting_marking_color(palette.get("helmet_color_1", Color.GRAY),
			palette.get("helmet_color_2", Color.GRAY))


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
		var palette := (existing as Dictionary).duplicate(true)
		if int(palette.get("helmet_randomization_version", 0)) < HELMET_RANDOMIZATION_VERSION:
			# A deterministic, per-identity upgrade makes Continue/Trailer resets
			# stable even before the upgraded campaign has been saved again. Do not
			# consume the roster RNG or change subsequent pilot assignment draws.
			var upgrade_rng := RandomNumberGenerator.new()
			var seed_text := "%s|%s|%s|%s|helmet-v1" % [identity.get("id", ""),
				identity.get("name", ""), (palette["helmet_color_1"] as Color).to_html(),
				(palette["helmet_color_2"] as Color).to_html()]
			upgrade_rng.seed = seed_text.hash()
			randomize_helmet(palette, upgrade_rng)
			identity[IDENTITY_FIELD] = palette.duplicate(true)
		return palette
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
