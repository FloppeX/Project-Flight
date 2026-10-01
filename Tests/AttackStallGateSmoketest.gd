extends Node

class AeroFixture:
	extends Node
	var stall := 32.0
	func get_effective_stall_speed_mps() -> float:
		return stall

class PilotFixture:
	extends AIPilot
	var target: Node3D
	var speed := 46.0
	var intercept_calls := 0
	var recovery_calls := 0
	func _check_air_threat_proximity() -> bool:
		return false
	func _resolve_current_ground_attack_target() -> Node3D:
		return target
	func _get_air_relative_velocity() -> Vector3:
		return Vector3(0, 0, speed)
	func _get_surface_target_position(_node: Variant) -> Vector3:
		return target.position
	func _uses_direct_ground_attack_intercept() -> bool:
		return true
	func _navigate_to_waypoint(_delta: float) -> void:
		recovery_calls += 1
	func _state_direct_ground_attack_intercept(_delta: float, _target: Node3D, _pos: Vector3) -> void:
		intercept_calls += 1

func _ready() -> void:
	var craft := RigidBody3D.new()
	craft.freeze = true
	add_child(craft)
	var target := Node3D.new()
	add_child(target)
	var aero := AeroFixture.new()
	var pilot := PilotFixture.new()
	pilot.aircraft = craft
	pilot.target = target
	pilot.simple_aero = aero
	pilot.ground_attack_smart_retarget_enabled = false
	var failures: Array[String] = []
	pilot._state_attack_positioning(0.016)
	if pilot.intercept_calls != 1 or pilot.recovery_calls != 0:
		failures.append("Aircraft 6 at 46 m/s failed to proceed to interception")
	pilot.speed = 39.0
	pilot._state_attack_positioning(0.016)
	if pilot.intercept_calls != 1 or pilot.recovery_calls != 1:
		failures.append("Below the live stall margin, recovery was bypassed")
	aero.stall = 52.0
	pilot.speed = 55.0
	pilot._state_attack_positioning(0.016)
	if pilot.recovery_calls != 2:
		failures.append("Higher aircraft stall speed was ignored")
	pilot.simple_aero = null
	pilot.speed = 46.0
	pilot._state_attack_positioning(0.016)
	if pilot.recovery_calls != 3:
		failures.append("Missing flight model did not retain the fallback stall floor")
	pilot.free()
	aero.free()
	for failure in failures:
		push_error(failure)
	print("[AttackStallGateSmoketest] %s" % ("PASS" if failures.is_empty() else "FAIL"))
	get_tree().quit(0 if failures.is_empty() else 1)
