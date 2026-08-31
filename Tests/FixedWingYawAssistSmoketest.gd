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
	_expect(controls.rudder_assist_max_input <= 0.35, "fixed-wing rudder assist can still command excessive normal-speed rudder")
	_expect(controls.rudder_assist_stiffened_max_input <= 0.18, "fixed-wing rudder assist can still command excessive Vne rudder")
	_expect(controls.rudder_assist_response_speed <= 4.0, "rudder assist still outruns the normal physical surface")
	_expect(controls.rudder_assist_stiffened_response_speed <= 1.2, "rudder assist still outruns the stiffened physical surface")

	var alignment_only_error := controls._combine_fixed_wing_slip_error(0.0, 1.0)
	var geometric_slip_error := controls._combine_fixed_wing_slip_error(0.08, 1.0)
	_expect(absf(alignment_only_error) < 0.01, "SimpleAero alignment acceleration still drives the fixed-wing rudder loop")
	_expect(absf(geometric_slip_error - 0.08) < 0.01, "fixed-wing assist no longer follows geometric sideslip")

	var aero := SimpleAero.new()
	controls.simple_aero = aero
	controls._simple_aero_has_control_envelope = true
	aero.current_high_speed_stiffening = 0.0
	_expect(controls._get_fixed_wing_rudder_stiffening() < 0.01, "normal flight incorrectly reports rudder stiffening")
	aero.current_high_speed_stiffening = 1.0
	_expect(controls._get_fixed_wing_rudder_stiffening() > 0.99, "Vne stiffening is not visible to the rudder assist")

	controls.free()
	aero.free()
	if _failures.is_empty():
		print("[FixedWingYawAssistSmoketest] PASS aircraft5_auto=0.25 normal_max=0.35 vne_max=0.18 response=4.0->1.2 alignment_feedback=0")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error("[FixedWingYawAssistSmoketest] %s" % failure)
	get_tree().quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
