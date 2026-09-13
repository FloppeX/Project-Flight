extends RefCounted

## Competence only. Temperament must not alter these perception capabilities.
static func for_skill(value: int) -> Dictionary:
	var tier := clampi(value, 0, 4)
	return {
		"tier": tier,
		"name": ["RECRUIT", "ROOKIE", "EXPERIENCED", "VETERAN", "ELITE"][tier],
		"recognition_s": [1.0, 0.75, 0.45, 0.25, 0.15][tier],
		"motion_response_hz": [1.2, 2.0, 4.0, 6.0, 9.0][tier],
		"turn_response_hz": [2.0, 3.0, 6.0, 9.0, 12.0][tier],
		"estimate_uncertainty_m": [18.0, 12.0, 7.0, 4.0, 2.0][tier],
		"shoulder_interval_s": [10.0, 8.0, 6.0, 4.5, 3.0][tier],
		"shoulder_duration_s": [0.6, 0.8, 1.0, 1.1, 1.2][tier],
	}
