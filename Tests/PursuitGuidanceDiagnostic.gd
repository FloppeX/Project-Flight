extends SceneTree

## Read-only reproduction of reciprocal-target guidance. This reports behavior,
## not a passing assertion that the current behavior is correct.
const Follower = preload("res://AI/FlightPathFollower.gd")

func _init() -> void:
	for bearing_deg in [0.0, 30.0, 90.0, 150.0, 179.9, 180.0, -179.9]:
		var angle := deg_to_rad(bearing_deg)
		var desired := Vector3(sin(angle), 0, cos(angle)) * 100.0
		var result: Dictionary = Follower.solve_velocity_guidance(
			Vector3(0, 0, 100), Vector3.BACK, desired, 2.0,
			Vector3.ZERO, deg_to_rad(-60), 80.0, 4.5, 0.1, 1.0, 0.0)
		print("PURSUIT_GUIDANCE_DIAGNOSTIC ", JSON.stringify({
			"target_bearing_deg": bearing_deg,
			"bank_deg": rad_to_deg(float(result.bank_rad)),
			"right_acceleration_mps2": result.signed_right_accel_mps2,
			"load_g": result.target_load_g}))
	quit()
