extends SceneTree

class FakeEngine extends Node:
	var is_engine_working := false
	var commanded_power := 0.0
	func engine_start() -> void:
		pass
	func engine_stop() -> void:
		is_engine_working = false
	func engine_set_power(value: float) -> void:
		commanded_power = value

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if not InputMap.has_action("throttle_abs"):
		InputMap.add_action("throttle_abs")
	for number in [9, 10, 11, 12, 13, 15]:
		var aircraft: Node = load("res://Aircraft/Aircraft_%d.tscn" % number).instantiate()
		var control: Node = aircraft.get_node("ControlEngine")
		assert(control.RequireThrottleReleaseAfterManualStart, "Missing helicopter manual-start setting")
		var engine := FakeEngine.new()
		control.engine_modules = [engine]
		Input.action_press("throttle_up")
		for frame in 600:
			control._physics_process(0.02)
		assert(is_equal_approx(engine.commanded_power, 0.02), "Held startup input accumulated throttle")
		engine.is_engine_working = true
		for frame in 100:
			control._physics_process(0.02)
		assert(is_equal_approx(engine.commanded_power, 0.02), "Engine completion forced throttle up")
		Input.action_release("throttle_up")
		control._physics_process(0.02)
		Input.action_press("throttle_up")
		control._physics_process(0.5)
		Input.action_release("throttle_up")
		var chosen: float = control.target_power
		for frame in 100:
			control._physics_process(0.02)
		assert(chosen > 0.02 and chosen < 1.0 and is_equal_approx(engine.commanded_power, chosen), "Chosen partial throttle did not hold")
		Input.action_press("throttle_up")
		control._physics_process(2.0)
		Input.action_release("throttle_up")
		assert(is_equal_approx(engine.commanded_power, 1.0), "Player cannot choose full throttle")
		control.set_target_power(0.83)
		assert(is_equal_approx(engine.commanded_power, 0.83), "AI throttle was restricted")
		control.set_target_power(0.0)
		Input.action_press("throttle_abs", 0.9)
		for frame in 100:
			control._physics_process(0.02)
		assert(is_equal_approx(engine.commanded_power, 0.02), "Absolute throttle accumulated during cold start")
		Input.action_release("throttle_abs")
		control._physics_process(0.02)
		Input.action_press("throttle_abs", 0.6)
		for frame in 100:
			control._physics_process(0.02)
		assert(absf(engine.commanded_power - 0.6) < 0.001, "Absolute throttle choice was not respected")
		Input.action_release("throttle_abs")
		engine.free()
		aircraft.free()
	for number in [1, 2, 3, 4, 5, 6, 7, 8, 14]:
		var aircraft: Node = load("res://Aircraft/Aircraft_%d.tscn" % number).instantiate()
		assert(not aircraft.get_node("ControlEngine").RequireThrottleReleaseAfterManualStart, "Fixed-wing startup was changed")
		aircraft.free()
	print("[HelicopterManualStartupThrottleSmoketest] PASS helicopters=9,10,11,12,13,15")
	quit()
