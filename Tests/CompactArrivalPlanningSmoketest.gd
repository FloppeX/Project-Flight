extends SceneTree

const Arrival = preload("res://AI/CompactRecoveryArrival.gd")
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var legs: Array = [{"position": Vector3(0, 0, 450), "speed_mps": 60.0},
		{"position": Vector3(0, 0, 1800), "speed_mps": 60.0}]
	var aligned: Dictionary = Arrival.assess(legs, Vector3.ZERO, Vector3(0, 0, 60), 14, 18, 450, 1.25)
	var reversed: Dictionary = Arrival.assess(legs, Vector3.ZERO, Vector3(0, 0, -60), 14, 18, 450, 1.25)
	_check(aligned.valid and reversed.valid, "flat joins rejected")
	_check(reversed.estimated_time_s > aligned.estimated_time_s + 20, "heading reversal has no time cost")
	var high: Array = legs.duplicate(true)
	high[0].position.y = 570
	var climb: Dictionary = Arrival.assess(high, Vector3.ZERO, Vector3(0, 0, 60), 14, 18, 450, 1.25)
	_check(not climb.valid and climb.reason == "climb_unreachable", "570 m climb over 450 m accepted")
	high[0].position = Vector3(0, 570, 0)
	_check(not Arrival.assess(high, Vector3.ZERO, Vector3(0, 0, 60), 14, 18, 450, 1.25).valid, "climb in place accepted")
	high[0].position = Vector3(0, -300, 450)
	_check(Arrival.assess(high, Vector3.ZERO, Vector3(0, 0, 60), 14, 18, 450, 1.25).reason == "descent_unreachable", "impossible descent accepted")
	var fast: Dictionary = Arrival.assess(legs, Vector3.ZERO, Vector3(0, 0, 100), 14, 18, 450, 1.25)
	_check(not fast.valid and fast.reason == "insufficient_deceleration_distance", "insufficient braking room accepted")
	var fast_climb_legs: Array = [{"position": Vector3(0, 100, 450), "speed_mps": 60.0},
		{"position": Vector3(0, 100, 3500), "speed_mps": 60.0}]
	_check(Arrival.assess(fast_climb_legs, Vector3.ZERO, Vector3(0, 0, 100), 14, 18, 450, 1.25).reason == "climb_unreachable", "fast entry borrowed target-speed climb time")
	var pilot: Node = load("res://Tests/Fixtures/CompactArrivalSelectionPilot.gd").new()
	_check(pilot._try_install_compact_recovery_route({}), "valid alternatives not selected")
	_check(pilot.built == 6 and pilot.installed.size() == 1, "alternatives installed while evaluating")
	_check(pilot.installed[0].metadata.side == -1.0, "nearest side selected instead of quicker side")
	pilot.installed.clear()
	pilot.equal_cost = true
	pilot._try_install_compact_recovery_route({})
	_check(pilot.installed[0].metadata.side == 1.0, "ties do not retain preferred side")
	pilot.installed.clear()
	pilot.reject_all = true
	_check(not pilot._try_install_compact_recovery_route({}) and pilot.installed.is_empty(), "rejected candidates replaced route")
	pilot.free()
	print("COMPACT_ARRIVAL_PLANNING ", "PASS" if failures.is_empty() else "FAIL", " ", failures)
	quit(0 if failures.is_empty() else 1)

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)
