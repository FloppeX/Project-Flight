extends Node

const AIRCRAFT_1_SCENE: PackedScene = preload("res://Aircraft/Aircraft_1.tscn")
const AIRCRAFT_5_SCENE: PackedScene = preload("res://Aircraft/Aircraft_5.tscn")

var _failures: PackedStringArray = []


func _ready() -> void:
	var aircraft_1 := AIRCRAFT_1_SCENE.instantiate() as RigidBody3D
	var aircraft_5 := AIRCRAFT_5_SCENE.instantiate() as RigidBody3D
	_expect(aircraft_1 != null and aircraft_5 != null, "comparison aircraft did not instantiate")
	if aircraft_1 == null or aircraft_5 == null:
		_finish(aircraft_1, aircraft_5)
		return

	var aero_1 := aircraft_1.get_node_or_null("SimpleAero") as SimpleAero
	var aero_5 := aircraft_5.get_node_or_null("SimpleAero") as SimpleAero
	var engine_1 := aircraft_1.get_node_or_null("Engine")
	var engine_5 := aircraft_5.get_node_or_null("Engine")
	_expect(aero_1 != null and aero_5 != null, "SimpleAero nodes were not found")
	_expect(engine_1 != null and engine_5 != null, "engine nodes were not found")

	_expect(is_equal_approx(aircraft_1.mass, 720.0), "Aircraft 1 mass is not 720")
	_expect(aircraft_1.mass < aircraft_5.mass, "Aircraft 1 is not lighter than Aircraft 5")
	if engine_1 != null and engine_5 != null:
		var thrust_1 := float(engine_1.get("PowerFactor"))
		var thrust_5 := float(engine_5.get("PowerFactor"))
		_expect(is_equal_approx(thrust_1, 4500.0), "Aircraft 1 engine thrust is not 4500")
		_expect(is_equal_approx(thrust_5, 6250.0), "Aircraft 5 engine thrust is not 6250")
		_expect(thrust_1 < thrust_5, "Aircraft 1 engine is not weaker than Aircraft 5")
		_expect(thrust_1 / aircraft_1.mass < thrust_5 / aircraft_5.mass, "Aircraft 1 thrust-to-mass ratio is not lower than Aircraft 5")
	if aero_1 != null and aero_5 != null:
		_expect(is_equal_approx(aero_1.stability_strength, 1.8), "Aircraft 1 stability strength is not 1.8")
		_expect(aero_1.stability_strength < aero_5.stability_strength, "Aircraft 1 stability strength is not lower")
		_expect(aero_1.roll_stability_factor < aero_5.roll_stability_factor, "Aircraft 1 roll stability is not lower")
		_expect(aero_1.pitch_stability_factor < aero_5.pitch_stability_factor, "Aircraft 1 pitch stability is not lower")
		_expect(aero_1.stability_torque_scale < aero_5.stability_torque_scale, "Aircraft 1 restoring torque is not lower")
		_expect(aero_1.roll_stability_rate_damping < aero_5.roll_stability_rate_damping, "Aircraft 1 roll-rate stability is not lower")
		_expect(aero_1.pitch_stability_rate_damping < aero_5.pitch_stability_rate_damping, "Aircraft 1 pitch-rate stability is not lower")

	_finish(aircraft_1, aircraft_5)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish(aircraft_1: Node, aircraft_5: Node) -> void:
	if aircraft_1 != null:
		aircraft_1.free()
	if aircraft_5 != null:
		aircraft_5.free()
	if _failures.is_empty():
		print("AIRCRAFT_1_STATS_SMOKETEST_OK")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error("[Aircraft1StatsSmoketest] %s" % failure)
	get_tree().quit(1)
