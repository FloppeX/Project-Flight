extends "res://Tests/GroundAttackDiagnostic.gd"

func _ready() -> void:
	get_node("/root/FloatingOrigin").set("enabled", false)
	super._ready()

func _write(status: String) -> void:
	if is_instance_valid(pilot):
		var controls := {}
		for key in ["roll_input", "pitch_input", "yaw_input", "_navigation_desired_bank_rad_debug",
			"_navigation_raw_roll_debug", "_route_forward_projection_active", "_route_forward_projection_dir",
			"_route_guidance_yaw_error_rad", "maneuver_waypoint", "nav_waypoint", "_attack_geometry_job",
			"current_waypoint_index", "_flight_plan_legs", "_attack_locked_setup_distance_m", "_route_follow_debug"]:
			controls[key] = str(pilot.get(key))
		print("GROUND_CONTROL t=%.1f %s" % [elapsed, JSON.stringify(controls)])
		result["controls"] = controls
	super._write(status)
