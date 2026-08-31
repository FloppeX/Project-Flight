extends SceneTree

## Guards the authored fixed-wing identities around Aircraft_5, the reference
## airframe. This is a configuration and control-envelope smoke test; final
## handling feel still requires rendered player flights.

const EPSILON := 0.001
const PROFILES := {
	1: {"mass": 720.0, "pitch": 6.6, "roll": 14.0, "yaw": 2.2, "damping": 14.5, "stability": 1.9, "stall": 39.0, "autorudder": 0.28, "induced_drag": 0.21, "simplified_pitch": 7.5, "control_full": 1.30, "control_taper": 1.03, "stiffen": 115.0, "vne": 160.0, "stiffen_full": 200.0, "pitch_rate": 4.5, "roll_rate": 6.8, "yaw_rate": 3.8, "aoa_start": 21.0, "aoa_full": 40.0, "aoa_loss": 0.58, "lift_limit": 4.2, "nose_drop": 9.0, "wing_drop": 4.0, "autorotation": 4.2, "departure_build": 2.6, "departure_recovery": 2.3, "directional": 1.8},
	2: {"mass": 1200.0, "pitch": 5.0, "roll": 8.5, "yaw": 1.8, "damping": 19.0, "stability": 3.6, "stall": 50.0, "autorudder": 0.35, "induced_drag": 0.24, "simplified_pitch": 6.0, "control_full": 1.42, "control_taper": 1.08, "stiffen": 145.0, "vne": 195.0, "stiffen_full": 240.0, "pitch_rate": 3.2, "roll_rate": 4.2, "yaw_rate": 3.0, "aoa_start": 22.0, "aoa_full": 43.0, "aoa_loss": 0.55, "lift_limit": 3.6, "nose_drop": 9.0, "wing_drop": 3.2, "autorotation": 3.5, "departure_build": 2.2, "departure_recovery": 1.6, "directional": 3.8},
	3: {"mass": 700.0, "pitch": 6.8, "roll": 16.0, "yaw": 2.3, "damping": 13.5, "stability": 1.45, "stall": 36.0, "autorudder": 0.32, "induced_drag": 0.22, "simplified_pitch": 7.0, "control_full": 1.25, "control_taper": 1.00, "stiffen": 100.0, "vne": 145.0, "stiffen_full": 180.0, "pitch_rate": 5.0, "roll_rate": 7.5, "yaw_rate": 4.2, "aoa_start": 19.0, "aoa_full": 35.0, "aoa_loss": 0.62, "lift_limit": 4.3, "nose_drop": 10.5, "wing_drop": 5.3, "autorotation": 5.8, "departure_build": 3.3, "departure_recovery": 2.4, "directional": 1.5},
	4: {"mass": 1350.0, "pitch": 4.6, "roll": 6.6, "yaw": 2.2, "damping": 22.0, "stability": 4.2, "stall": 47.0, "autorudder": 0.42, "induced_drag": 0.28, "simplified_pitch": 7.0, "control_full": 1.42, "control_taper": 1.10, "stiffen": 90.0, "vne": 130.0, "stiffen_full": 165.0, "pitch_rate": 2.6, "roll_rate": 3.4, "yaw_rate": 2.5, "aoa_start": 23.0, "aoa_full": 45.0, "aoa_loss": 0.60, "lift_limit": 3.2, "nose_drop": 11.0, "wing_drop": 3.0, "autorotation": 3.2, "departure_build": 2.0, "departure_recovery": 1.5, "directional": 4.2},
	5: {"mass": 900.0, "pitch": 6.25, "roll": 13.0, "yaw": 2.0, "damping": 16.0, "stability": 2.8, "stall": 42.0, "autorudder": 0.25, "induced_drag": 0.20, "simplified_pitch": 7.5, "control_full": 1.35, "control_taper": 1.05, "stiffen": 135.0, "vne": 180.0, "stiffen_full": 225.0, "pitch_rate": 4.0, "roll_rate": 6.0, "yaw_rate": 3.5, "aoa_start": 20.0, "aoa_full": 38.0, "aoa_loss": 0.65, "lift_limit": 4.5, "nose_drop": 10.0, "wing_drop": 4.5, "autorotation": 5.0, "departure_build": 3.0, "departure_recovery": 2.0, "directional": 2.4},
	6: {"mass": 1100.0, "pitch": 5.5, "roll": 7.5, "yaw": 3.2, "damping": 22.0, "stability": 4.0, "stall": 32.0, "autorudder": 0.40, "induced_drag": 0.25, "simplified_pitch": 7.2, "control_full": 1.20, "control_taper": 0.98, "stiffen": 75.0, "vne": 115.0, "stiffen_full": 145.0, "pitch_rate": 3.0, "roll_rate": 3.8, "yaw_rate": 3.0, "aoa_start": 24.0, "aoa_full": 46.0, "aoa_loss": 0.50, "lift_limit": 3.4, "nose_drop": 9.0, "wing_drop": 2.5, "autorotation": 3.0, "departure_build": 1.8, "departure_recovery": 2.1, "directional": 4.0},
	7: {"mass": 1025.0, "pitch": 5.5, "roll": 11.5, "yaw": 1.6, "damping": 18.0, "stability": 2.2, "stall": 50.0, "autorudder": 0.20, "induced_drag": 0.24, "simplified_pitch": 8.8, "control_full": 1.50, "control_taper": 1.12, "stiffen": 150.0, "vne": 205.0, "stiffen_full": 250.0, "pitch_rate": 4.3, "roll_rate": 5.5, "yaw_rate": 3.0, "aoa_start": 18.5, "aoa_full": 33.0, "aoa_loss": 0.68, "lift_limit": 4.0, "nose_drop": 12.0, "wing_drop": 5.0, "autorotation": 5.5, "departure_build": 3.4, "departure_recovery": 1.8, "directional": 3.0},
	8: {"mass": 1025.0, "pitch": 6.8, "roll": 9.5, "yaw": 1.4, "damping": 18.0, "stability": 3.2, "stall": 40.0, "autorudder": 0.18, "induced_drag": 0.16, "simplified_pitch": 8.8, "control_full": 1.30, "control_taper": 1.02, "stiffen": 140.0, "vne": 195.0, "stiffen_full": 240.0, "pitch_rate": 4.8, "roll_rate": 4.5, "yaw_rate": 2.7, "aoa_start": 22.0, "aoa_full": 42.0, "aoa_loss": 0.52, "lift_limit": 4.6, "nose_drop": 8.0, "wing_drop": 2.8, "autorotation": 4.5, "departure_build": 2.2, "departure_recovery": 2.4, "directional": 2.0},
	14: {"mass": 480.0, "pitch": 7.0, "roll": 18.0, "yaw": 2.8, "damping": 10.5, "stability": 0.65, "stall": 37.0, "autorudder": 0.18, "induced_drag": 0.25, "simplified_pitch": 7.5, "control_full": 1.42, "control_taper": 1.10, "stiffen": 110.0, "vne": 165.0, "stiffen_full": 205.0, "pitch_rate": 6.0, "roll_rate": 9.0, "yaw_rate": 5.5, "aoa_start": 16.0, "aoa_full": 29.0, "aoa_loss": 0.78, "lift_limit": 4.8, "nose_drop": 13.0, "wing_drop": 7.5, "autorotation": 8.0, "departure_build": 4.3, "departure_recovery": 1.7, "directional": 4.0},
}

var _failures: Array[String] = []
var _metrics: Dictionary = {}
var _signature_owners: Dictionary = {}


func _initialize() -> void:
	for aircraft_index in PROFILES:
		_check_aircraft(int(aircraft_index), PROFILES[aircraft_index])
	_check_role_relationships()

	if _failures.is_empty():
		var ceilings: Array[String] = []
		for aircraft_index in PROFILES:
			ceilings.append("A%d=%.0f" % [aircraft_index, float(_metrics[aircraft_index].ceiling)])
		print("[FixedWingFleetHandlingSmoketest] PASS %s m/s" % " ".join(ceilings))
		quit(0)
		return
	for failure in _failures:
		push_error("[FixedWingFleetHandlingSmoketest] %s" % failure)
	quit(1)


func _check_aircraft(aircraft_index: int, expected: Dictionary) -> void:
	var scene_path := "res://Aircraft/Aircraft_%d.tscn" % aircraft_index
	var packed := load(scene_path) as PackedScene
	if packed == null:
		_fail("Aircraft_%d scene did not load" % aircraft_index)
		return
	var aircraft := packed.instantiate() as RigidBody3D
	if aircraft == null:
		_fail("Aircraft_%d did not instantiate as RigidBody3D" % aircraft_index)
		return
	var aero := aircraft.get_node_or_null("SimpleAero")
	var engine := aircraft.get_node_or_null("Engine")
	var pilot := aircraft.get_node_or_null("AIPilot")
	if aero == null or engine == null or pilot == null:
		_fail("Aircraft_%d did not contain SimpleAero, Engine, and AIPilot" % aircraft_index)
		aircraft.free()
		return

	_expect_close(aircraft.mass, float(expected.mass), "Aircraft_%d mass" % aircraft_index)
	for property_pair in [
		["pitch_power", "pitch"],
		["roll_power", "roll"],
		["yaw_power", "yaw"],
		["angular_damping_strength", "damping"],
		["stability_strength", "stability"],
		["stall_speed", "stall"],
		["auto_rudder_strength", "autorudder"],
		["induced_drag_strength", "induced_drag"],
		["simplified_pitch_power_override", "simplified_pitch"],
		["control_authority_full_stall_margin", "control_full"],
		["control_authority_taper_stall_margin", "control_taper"],
		["control_stiffening_start_speed_mps", "stiffen"],
		["never_exceed_speed_mps", "vne"],
		["control_stiffening_full_speed_mps", "stiffen_full"],
		["pitch_surface_rate_per_s", "pitch_rate"],
		["roll_surface_rate_per_s", "roll_rate"],
		["yaw_surface_rate_per_s", "yaw_rate"],
		["aoa_stall_start_deg", "aoa_start"],
		["aoa_stall_full_deg", "aoa_full"],
		["aoa_stall_lift_loss", "aoa_loss"],
		["max_lift_ratio", "lift_limit"],
		["stall_nose_drop_torque", "nose_drop"],
		["stall_wing_drop_torque", "wing_drop"],
		["stall_autorotation_yaw_torque", "autorotation"],
		["stall_departure_build_rate_per_s", "departure_build"],
		["stall_departure_recovery_rate_per_s", "departure_recovery"],
		["directional_stability_strength", "directional"],
	]:
		_expect_close(
			float(aero.get(property_pair[0])),
			float(expected[property_pair[1]]),
			"Aircraft_%d %s" % [aircraft_index, property_pair[0]]
		)

	var thrust := float(engine.get("PowerFactor"))
	var drag_coefficient := float(aero.get("forward_drag_strength")) \
		* float(aero.get("forward_drag_scale")) \
		* float(aero.get("drag_base_multiplier"))
	var ceiling_mps := sqrt(thrust / maxf(drag_coefficient, 0.001))
	_expect(
		ceiling_mps >= float(expected.stall) * 1.75,
		"Aircraft_%d clean ceiling %.1f m/s left too little headroom above %.1f m/s stall" % [
			aircraft_index, ceiling_mps, float(expected.stall),
		]
	)

	aero.set("pitch_input", 0.25)
	aero.set("roll_input", 0.25)
	aero.set("yaw_input", 0.0)
	aero.call(
		"_update_control_envelope",
		0.5,
		82.0,
		82.0,
		float(expected.stall),
		0.0,
		Vector3(0.0, 0.0, 82.0)
	)
	_expect(float(aero.get("actual_pitch_control")) > 0.20, "Aircraft_%d elevator did not respond" % aircraft_index)
	_expect(float(aero.get("actual_roll_control")) > 0.20, "Aircraft_%d aileron did not respond" % aircraft_index)
	_expect(float(aero.get("actual_yaw_control")) > 0.0, "Aircraft_%d autorudder did not respond" % aircraft_index)

	_metrics[aircraft_index] = {
		"ceiling": ceiling_mps,
		"pitch_response": float(expected.pitch) / float(expected.damping),
		"roll_response": float(expected.roll) / float(expected.damping),
		"yaw_response": float(expected.yaw) / float(expected.damping),
		"stability": float(expected.stability),
		"stall": float(expected.stall),
		"vne": float(expected.vne),
		"stiffen": float(expected.stiffen),
		"pitch_rate": float(expected.pitch_rate),
		"roll_rate": float(expected.roll_rate),
		"yaw_rate": float(expected.yaw_rate),
		"aoa_start": float(expected.aoa_start),
		"aoa_full": float(expected.aoa_full),
		"lift_limit": float(expected.lift_limit),
		"induced_drag": float(expected.induced_drag),
		"mass": float(expected.mass),
		"stall_wing_drop": float(expected.wing_drop),
		"stall_autorotation": float(expected.autorotation),
		"departure_build_rate": float(expected.departure_build),
		"departure_recovery_rate": float(expected.departure_recovery),
		"directional_stability": float(expected.directional),
	}
	var signature := "%.2f|%.2f|%.2f|%.2f|%.2f|%.2f|%.2f|%.2f|%.2f|%.2f|%.2f" % [
		float(expected.pitch),
		float(expected.roll),
		float(expected.yaw),
		float(expected.damping),
		float(expected.stability),
		float(expected.stall),
		ceiling_mps,
		float(expected.vne),
		float(expected.aoa_start),
		float(expected.aoa_full),
		float(expected.departure_build),
	]
	_expect(
		not _signature_owners.has(signature),
		"Aircraft_%d duplicated Aircraft_%s's complete handling signature" % [
			aircraft_index, str(_signature_owners.get(signature, "?")),
		]
	)
	_signature_owners[signature] = aircraft_index
	aircraft.free()


func _check_role_relationships() -> void:
	if _metrics.size() != PROFILES.size():
		return
	var baseline: Dictionary = _metrics[5]
	_expect(float(_metrics[2].roll_response) < float(baseline.roll_response), "Crusader was not less agile than Aircraft_5")
	_expect(float(_metrics[2].stability) > float(baseline.stability), "Crusader was not more stable than Aircraft_5")
	_expect(float(_metrics[3].roll_response) > float(baseline.roll_response), "Wasp was not the livelier light fighter")
	_expect(float(_metrics[4].pitch_response) < float(_metrics[2].pitch_response), "Vulture was not the slowest pitch responder")
	_expect(float(_metrics[6].stability) > float(baseline.stability), "Razorback was not more stable than Aircraft_5")
	_expect(float(_metrics[6].ceiling) < float(_metrics[4].ceiling), "Razorback was not the slowest low-level attacker")
	for aircraft_index in PROFILES:
		if int(aircraft_index) != 7:
			_expect(float(_metrics[7].ceiling) > float(_metrics[aircraft_index].ceiling), "Dagger was not the fastest airframe")
	_expect(float(_metrics[8].induced_drag) < float(baseline.induced_drag), "Ghost did not retain its efficient sustained-turn identity")
	_expect(float(_metrics[8].roll_response) < float(baseline.roll_response), "Ghost roll response was not smoother than Aircraft_5")
	_expect(float(_metrics[8].yaw_response) < float(baseline.yaw_response), "Ghost did not retain its deliberately weak yaw authority")
	_expect(float(_metrics[6].stall) < float(_metrics[3].stall), "Razorback was not the lowest-speed airframe")
	_expect(float(_metrics[6].aoa_start) > float(baseline.aoa_start), "Razorback stall did not begin more gently than the baseline")
	_expect(float(_metrics[6].stall_wing_drop) < float(baseline.stall_wing_drop), "Razorback stall did not retain the mildest wing drop")
	_expect(float(_metrics[7].vne) > float(baseline.vne), "Dagger did not retain the highest-speed control envelope")
	_expect(float(_metrics[7].aoa_full) < float(baseline.aoa_full), "Dagger high-AoA departure was not sharper than the baseline")
	_expect(float(_metrics[4].vne) < float(baseline.vne), "Vulture did not retain its lower structural-speed envelope")
	_expect(float(_metrics[4].roll_rate) < float(baseline.roll_rate), "Vulture surfaces were not slower than the baseline")
	for aircraft_index in PROFILES:
		if int(aircraft_index) != 14:
			_expect(float(_metrics[14].mass) < float(_metrics[aircraft_index].mass), "Aircraft_14 was not the lightest airframe")
			_expect(float(_metrics[14].roll_response) > float(_metrics[aircraft_index].roll_response), "Aircraft_14 was not the quickest roll responder")
			_expect(float(_metrics[14].stability) < float(_metrics[aircraft_index].stability), "Aircraft_14 was not the least self-stabilizing airframe")
	_expect(float(_metrics[14].ceiling) > float(baseline.ceiling), "Aircraft_14 was not relatively faster than Aircraft_5")
	_expect(float(_metrics[14].aoa_start) < float(baseline.aoa_start), "Aircraft_14 did not have the earliest stall onset")
	_expect(float(_metrics[14].aoa_full) < float(baseline.aoa_full), "Aircraft_14 did not have the narrowest high-AoA margin")
	_expect(float(_metrics[14].roll_rate) > float(baseline.roll_rate), "Aircraft_14 ailerons were not the quickest in the fleet")
	_expect(float(_metrics[14].stall_wing_drop) > float(baseline.stall_wing_drop), "Aircraft_14 did not retain its stronger stall wing drop")
	_expect(float(_metrics[14].stall_autorotation) > float(baseline.stall_autorotation), "Aircraft_14 did not retain its stronger stall autorotation")
	_expect(float(_metrics[14].departure_build_rate) > float(baseline.departure_build_rate), "Aircraft_14 departure did not build faster than Aircraft_5")
	_expect(float(_metrics[14].directional_stability) > float(baseline.directional_stability), "Aircraft_14 did not retain stronger weathervaning than Aircraft_5")
	for aircraft_index in PROFILES:
		_expect(float(_metrics[aircraft_index].directional_stability) > 0.0, "Aircraft_%s lacked authored passive directional stability" % aircraft_index)


func _expect_close(actual: float, expected: float, description: String) -> void:
	_expect(is_equal_approx(actual, expected) or absf(actual - expected) <= EPSILON, "%s expected %.3f, got %.3f" % [description, expected, actual])


func _expect(condition: bool, description: String) -> void:
	if not condition:
		_fail(description)


func _fail(description: String) -> void:
	_failures.append(description)
