extends Node

const SLIP_BALL_MODULE_SCRIPT := preload("res://HUD/Instruments/SlipBallModule.gd")
const CONTROL_STEERING_SCRIPT := preload("res://addons/simplified_flightsim/aircraft_modules/Controls/ControlSteering.gd")

var _failures: PackedStringArray = []


func _ready() -> void:
	var aircraft := RigidBody3D.new()
	aircraft.name = "TestAircraft"
	add_child(aircraft)

	var controls := CONTROL_STEERING_SCRIPT.new() as AircraftModule_ControlSteering
	controls.name = "ControlSteering"
	controls.telemetry_rudder_assist_component = -0.684
	aircraft.add_child(controls)

	var slip_ball := SLIP_BALL_MODULE_SCRIPT.new() as SlipBallModule
	slip_ball.configure({"id": "slip_ball", "title": "BALL"})
	slip_ball.set_context(null, aircraft)
	slip_ball.size = Vector2(270.0, 78.0)
	add_child(slip_ball)
	await get_tree().process_frame

	slip_ball.update_from_aircraft(1.0 / 60.0)
	var readout := slip_ball.get_node_or_null("ModuleRoot/Body/AutorudderReadout") as Label
	_expect(readout != null, "autorudder readout was not created beneath the slip ball")
	if readout != null:
		_expect(readout.text == "Autorudder: 68%", "readout did not show the automatic contribution as a percentage")

	controls.telemetry_rudder_assist_component = 1.4
	slip_ball.update_from_aircraft(1.0 / 60.0)
	if readout != null:
		_expect(readout.text == "Autorudder: 100%", "readout did not clamp the percentage to 100")

	controls.ControlActive = false
	slip_ball.update_from_aircraft(1.0 / 60.0)
	if readout != null:
		_expect(readout.text == "Autorudder: 0%", "inactive controls did not clear the autorudder readout")

	if _failures.is_empty():
		print("SLIP_BALL_AUTORUDDER_READOUT_SMOKETEST_OK")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error("[SlipBallAutorudderReadoutSmoketest] %s" % failure)
	get_tree().quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
