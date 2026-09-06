extends Node

const AIRCRAFT_SCENE: PackedScene = preload("res://Aircraft/Aircraft_5.tscn")

var _failures: Array[String] = []


func _ready() -> void:
	var aircraft := AIRCRAFT_SCENE.instantiate() as RigidBody3D
	_expect(aircraft != null, "Aircraft_5 did not instantiate")
	if aircraft != null:
		var authored_aero := aircraft.get_node_or_null("SimpleAero") as SimpleAero
		_expect(authored_aero != null, "Aircraft_5 SimpleAero was not found")
		if authored_aero != null:
			_expect(
				absf(authored_aero.auto_rudder_strength - 0.25) < 0.001,
				"Aircraft_5 roll-linked autorudder is not tuned to 0.25"
			)
			authored_aero.roll_input = 0.20
			authored_aero.yaw_input = 0.0
			authored_aero._update_control_envelope(
				0.20,
				82.0,
				82.0,
				authored_aero.stall_speed,
				0.0,
				Vector3(0.0, 0.0, 82.0)
			)
			_expect(
				absf(authored_aero.actual_yaw_control - authored_aero.actual_roll_control * 0.25) < 0.001,
				"Aircraft_5 small-roll autorudder did not follow physical aileron travel"
			)
		aircraft.free()

	var controls := AircraftModule_ControlSteering.new()
	_expect(controls.rudder_assist_max_input <= 0.35, "LIGHT fixed-wing rudder assist can command excessive normal-speed rudder")
	_expect(controls.rudder_assist_stiffened_max_input <= 0.18, "LIGHT fixed-wing rudder assist can command excessive Vne rudder")
	_expect(controls.rudder_assist_full_max_input >= 0.99, "FULL fixed-wing rudder assist cannot request full input")
	_expect(
		controls._get_advanced_fixed_wing_rudder_assist_limit(1.0, 0.0) >= 0.99 \
			and controls._get_advanced_fixed_wing_rudder_assist_limit(1.0, 1.0) >= 0.99,
		"FULL fixed-wing rudder authority is still reduced by the secondary speed schedule"
	)
	_expect(
		controls._get_advanced_fixed_wing_rudder_assist_limit(0.45, 0.0) <= 0.35 \
			and controls._get_advanced_fixed_wing_rudder_assist_limit(0.45, 1.0) <= 0.18,
		"LIGHT fixed-wing rudder authority no longer retains its bounded speed schedule"
	)
	controls._reset_rudder_assist_state()
	_expect(
		absf(controls._blend_fixed_wing_manual_rudder_priority(-0.50, 1.0, 1.0 / 60.0)) < 0.001,
		"half opposing player rudder does not cancel a full automatic command"
	)
	controls._reset_rudder_assist_state()
	_expect(
		absf(controls._blend_fixed_wing_manual_rudder_priority(0.50, 1.0, 1.0 / 60.0) - 1.0) < 0.001,
		"half matching player rudder and a full automatic command do not saturate at full output"
	)
	controls._reset_rudder_assist_state()
	_expect(
		absf(controls._blend_fixed_wing_manual_rudder_priority(-1.0, 1.0, 1.0 / 60.0) + 1.0) < 0.001,
		"full opposing player rudder does not take complete control"
	)
	var first_reengaged_output := controls._blend_fixed_wing_manual_rudder_priority(0.0, 1.0, 1.0 / 60.0)
	_expect(
		first_reengaged_output > 0.0 and first_reengaged_output < 0.20,
		"autorudder snaps back instead of re-engaging smoothly after player release"
	)
	_expect(
		absf(controls._blend_legacy_manual_rudder_override(-0.50, 1.0, 0.02, 0.16) + 0.50) < 0.001,
		"helicopter threshold takeover behavior changed with the fixed-wing mixer"
	)
	_expect(controls.rudder_assist_response_speed <= 4.0, "rudder assist still outruns the normal physical surface")
	_expect(controls.rudder_assist_stiffened_response_speed <= 1.2, "rudder assist still outruns the stiffened physical surface")

	_expect(
		controls.rudder_assist_lateral_g_weight >= 0.20 \
			and controls.rudder_assist_large_error_lateral_g_weight >= 0.30,
		"fixed-wing rudder assist does not retain progressive slip-ball sensitivity"
	)
	var ball_only_error := controls._combine_fixed_wing_slip_error(0.0, 1.0)
	var geometric_slip_error := controls._combine_fixed_wing_slip_error(0.08, 1.0)
	_expect(
		absf(ball_only_error + controls.rudder_assist_large_error_lateral_g_weight) < 0.01,
		"large slip-ball displacement does not use the stronger progressive weight"
	)
	_expect(
		absf(geometric_slip_error - (0.08 - controls.rudder_assist_large_error_lateral_g_weight)) < 0.01,
		"fixed-wing assist no longer blends geometric sideslip and slip-ball with their correct signs"
	)
	var near_center_ball_error := controls._combine_fixed_wing_slip_error(0.0, 0.10)
	_expect(
		absf(near_center_ball_error + 0.10 * controls.rudder_assist_lateral_g_weight) < 0.001,
		"near-center slip-ball sensitivity no longer retains the stable lower weight"
	)

	var aero := SimpleAero.new()
	controls.simple_aero = aero
	controls._simple_aero_has_control_envelope = true
	aero.set_flight_model_override_for_testing(1)
	var banked_aircraft := RigidBody3D.new()
	banked_aircraft.freeze = true
	add_child(banked_aircraft)
	banked_aircraft.global_transform = Transform3D(
		Basis(Vector3.FORWARD, deg_to_rad(20.0)),
		Vector3.ZERO
	)
	banked_aircraft.linear_velocity = banked_aircraft.global_transform.basis.z * 90.0
	controls.aircraft = banked_aircraft
	controls.rudder_assist_lateral_g_filter_speed = 60.0
	controls._reset_rudder_assist_state()
	controls._previous_velocity = banked_aircraft.linear_velocity
	controls._has_previous_velocity = true
	var banked_ball_error := controls._estimate_slip_ball_error(1.0 / 60.0, false)
	_expect(
		banked_ball_error >= 0.18,
		"a banked off-ball aircraft does not receive automatic rudder opposite its lateral force"
	)
	banked_aircraft.free()
	aero.current_high_speed_stiffening = 0.0
	_expect(controls._get_fixed_wing_rudder_stiffening() < 0.01, "normal flight incorrectly reports rudder stiffening")
	_expect(controls._get_fixed_wing_slip_ball_scale() > 0.99, "normal flight incorrectly suppresses slip-ball assistance")
	aero.current_high_speed_stiffening = 1.0
	_expect(controls._get_fixed_wing_rudder_stiffening() > 0.99, "Vne stiffening is not visible to the rudder assist")
	_expect(controls._get_fixed_wing_slip_ball_scale() < 0.01, "Vne does not fade delayed slip-ball force feedback")

	var slip_ball_weight := controls.rudder_assist_lateral_g_weight
	var large_ball_weight := controls.rudder_assist_large_error_lateral_g_weight
	controls.free()
	aero.free()
	if _failures.is_empty():
		print("[FixedWingYawAssistSmoketest] PASS aircraft5_auto=0.25 light=0.35->0.18 full=1.00 response=4.0->1.2 ball_weight=%.2f->%.2f banked_ball=%.2f" % [slip_ball_weight, large_ball_weight, banked_ball_error])
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error("[FixedWingYawAssistSmoketest] %s" % failure)
	get_tree().quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
