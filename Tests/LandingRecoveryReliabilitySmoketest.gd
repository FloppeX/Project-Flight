extends SceneTree

const SIGHT = preload("res://AI/LandingSight.gd")

class Wire:
	extends Node3D
	func get_wire_center() -> Vector3:
		return global_position

class TestAircraft:
	extends RigidBody3D
	var current_health: float = 100.0

class Harness:
	extends "res://Scenario/LandingTestMode.gd"
	func _ready() -> void:
		set_physics_process(false)
	func _log(_message: String) -> void:
		pass
	func _trace_crash(_craft_name: String, _reason: String, _impact = null) -> void:
		pass
	func _finish(craft_name: String, outcome: String) -> void:
		if _attempts[craft_name].get("outcome", "") == "":
			_attempts[craft_name]["outcome"] = outcome

var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error(label)

func _run() -> void:
	_check(SIGHT.deck_entry_lateral_unreachable(31.0, 0.0, 1.0, 20.0, 4.0), "unreachable deck-side entry must escape")
	_check(not SIGHT.deck_entry_lateral_unreachable(31.0, -8.0, 2.0, 20.0, 4.0), "physically reachable aggressive entry must remain allowed")
	_check(SIGHT.roll_capture_input(0.1, 0.8, 2.0, 1.0) < 0.0, "roll servo must brake before crossing the target bank")
	_check(SIGHT.roll_capture_input(-0.8, 0.0, 2.0, 1.0) < -0.9, "terrain escape must actively level a banked aircraft")
	_check(is_zero_approx(SIGHT.roll_capture_input(0.0, 0.0, 2.0, 1.0)), "level aircraft must retain neutral roll")
	var stern_floor: float = SIGHT.deck_entry_sink_floor_mps(10.0, 2.0, -8.0)
	_check(stern_floor > -3.0, "low wheel path must arrest descent before the stern")
	_check(SIGHT.deck_entry_sink_floor_mps(60.0, 5.0, -5.0) < -10.0, "high wheel path must retain descent freedom")
	var early: Dictionary = SIGHT.settled_lateral_plan(0.0, 15.0, 3.0, 4.0, 0.6, 0.0)
	_check(early.accel_mps2 < -3.9, "short final must brake drift even when currently centred")
	_check(is_zero_approx(SIGHT.settled_lateral_plan(0.0, 0.0, 3.0, 4.0, 0.6, 0.0).accel_mps2), "settled short final must stay settled")
	var glide := deg_to_rad(5.9)
	_check(is_equal_approx(SIGHT.high_path_capture_sink_mps(-7.0, 100.0, 1000.0, 70.0, glide, -3.0, 12.0, 22.0, 350.0), -7.0), "on-path aircraft must retain existing sink cue")
	var high_sink: float = SIGHT.high_path_capture_sink_mps(-12.0, 220.0, 1000.0, 70.0, glide, -3.0, 12.0, 22.0, 350.0)
	_check(high_sink < -18.0 and high_sink >= -22.0, "high outer final must descend early within bounded authority")
	var unled_sink: float = SIGHT.high_path_capture_sink_mps(-8.0, 90.0, 600.0, 70.0, glide, -3.0, 12.0, 22.0, 350.0)
	var led_sink: float = SIGHT.high_path_capture_sink_mps(-8.0, 90.0, 600.0, 70.0, glide, -3.0, 12.0, 22.0, 350.0, -20.0)
	_check(led_sink > unled_sink and led_sink <= -8.0, "existing steep descent must unwind extra capture before crossing below the path")
	_check(is_equal_approx(SIGHT.high_path_capture_sink_mps(-12.0, 100.0, 300.0, 70.0, glide, -3.0, 12.0, 22.0, 350.0), -12.0), "extra descent authority must end before short final")
	_check(is_equal_approx(SIGHT.high_path_capture_sink_mps(-4.0, 30.0, 1000.0, 70.0, glide, -3.0, 12.0, 22.0, 350.0), -4.0), "low approach must not be pushed down")
	var high_wires := [{"valid": true, "time_s": 2.0, "vertical_m": 20.0}, {"valid": true, "time_s": 3.0, "vertical_m": 17.0}]
	_check(SIGHT.all_remaining_wires_too_high(high_wires, -10.0, 12.0, 0.6, 4.0, 4.0), "all clearly unreachable high wires must request escape")
	var recoverable_wires := high_wires.duplicate(true)
	recoverable_wires[1]["vertical_m"] = 7.0
	_check(not SIGHT.all_remaining_wires_too_high(recoverable_wires, -10.0, 12.0, 0.6, 4.0, 4.0), "a reachable last wire must preserve the attempt")
	_check(not SIGHT.all_remaining_wires_too_high([], -10.0, 12.0, 0.6, 4.0, 4.0), "missing wires must not invent a high-miss decision")
	_check(not SIGHT.all_remaining_wires_too_high(high_wires, NAN, 12.0, 0.6, 4.0, 4.0), "invalid telemetry must not trigger escape")
	_check(not SIGHT.all_remaining_wires_too_high(high_wires, -10.0, 12.0, 0.6, 1.0, 4.0), "high-miss decision must wait until its terminal horizon")
	var yaw_left: float = SIGHT.coordinated_terminal_rudder(-4.0, 70.0, 0.0, 0.0, 0.0)
	var yaw_right: float = SIGHT.coordinated_terminal_rudder(4.0, 70.0, 0.0, 0.0, 0.0)
	_check(yaw_left < -0.1 and is_equal_approx(yaw_left, -yaw_right), "terminal rudder must turn toward requested acceleration and mirror")
	_check(SIGHT.coordinated_terminal_rudder(4.0, 70.0, 0.1, 0.1, 0.0) < yaw_right, "measured excessive turn must reduce rudder")
	_check(is_zero_approx(SIGHT.coordinated_terminal_rudder(0.0, 70.0, 0.0, 0.0, 0.0)), "settled centreline must not command rudder")
	_check(absf(SIGHT.coordinated_terminal_rudder(40.0, 0.0, -3.0, -3.0, 1.0)) <= 0.7, "rudder must remain bounded at low speed")
	var plan: Dictionary = SIGHT.terminal_lateral_plan(100.0, 0.0, 20.0, 4.0, 0.0, 0.0)
	_check(absf(plan.predicted_lateral_m) < 0.1 and absf(plan.predicted_lateral_speed_mps) < 0.1, "reachable plan must arrive centred with zero sideways speed")
	var mirror: Dictionary = SIGHT.terminal_lateral_plan(-100.0, 0.0, 20.0, 4.0, 0.0, 0.0)
	_check(is_equal_approx(plan.accel_mps2, -mirror.accel_mps2), "left/right guidance must mirror")
	var impossible: Dictionary = SIGHT.terminal_lateral_plan(-141.0, 34.0, 4.0, 4.0, 0.6, 0.0)
	_check(impossible.saturated and absf(impossible.predicted_lateral_speed_mps) > 5.0, "impossible four-second arrival must expose terminal drift")
	_check(absf(impossible.accel_mps2) <= 4.0, "guidance must respect acceleration bound")
	_check(is_zero_approx(SIGHT.energy_aware_rescue_weight(86.0, 46.0, 35.0)), "overspeed must not demand rescue power")
	_check(is_equal_approx(SIGHT.energy_aware_rescue_weight(35.0, 46.0, 35.0), 1.0), "stall protection must retain full rescue power")
	_check(SIGHT.energy_aware_rescue_weight(55.0, 46.0, 35.0) > 0.0, "rescue taper must be continuous")
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var carrier := Node3D.new()
	carrier.add_to_group("carrier")
	scene.add_child(carrier)
	var last_wire: Wire
	for z in [10.0, 25.0, 40.0]:
		var wire := Wire.new()
		carrier.add_child(wire)
		wire.add_to_group("arresting_cable")
		wire.position.z = z
		last_wire = wire
	var craft := TestAircraft.new()
	craft.freeze = true
	scene.add_child(craft)
	var hook := Node3D.new()
	hook.name = "TailHook"
	craft.add_child(hook)
	var pilot := Node.new()
	pilot.set_script(load("res://AI/AIPilot.gd"))
	craft.add_child(pilot)
	pilot.set_process(false)
	pilot.set_physics_process(false)
	pilot.set("aircraft", craft)
	pilot.set("_recovery_retry_limit_reached", true)
	_check(not bool(pilot.call("_update_recovery_retry_cooldown", 30.0)), "default airframes must retain supervised retry exceptions")
	pilot.set("landing_bolter_retry_cooldown_s", 20.0)
	_check(not bool(pilot.call("_update_recovery_retry_cooldown", 20.0)), "missing landing reference must not authorize a retry")
	pilot.set("_approach_wp", [last_wire, last_wire, last_wire, last_wire, last_wire])
	pilot.set("_recovery_go_around_attempt_count", 3)
	_check(not bool(pilot.call("_update_recovery_retry_cooldown", 19.0)), "retry must wait through its cooldown")
	_check(bool(pilot.call("_update_recovery_retry_cooldown", 1.0)), "tuned airframe must leave permanent unqueued hold")
	_check(not bool(pilot.get("_recovery_retry_limit_reached")) and int(pilot.get("_recovery_go_around_attempt_count")) == 0, "new retry batch must reset the spent attempt budget")
	_check(not bool(pilot.get("_recovery_clearance_granted")), "retry must not grant itself deck clearance")
	var high_snapshot := {"valid": true, "wire_solutions": high_wires, "sink_rate_at_contact_mps": -10.0}
	pilot.set("_landing_sight_solution", high_snapshot)
	_check(not bool(pilot.call("_update_landing_high_miss_waveoff", 0.3)), "untuned airframes must retain their existing waveoff policy")
	pilot.set("landing_sight_high_miss_waveoff_enabled", true)
	_check(not bool(pilot.call("_update_landing_high_miss_waveoff", 0.1)), "one high projection must not cause a waveoff")
	_check(bool(pilot.call("_update_landing_high_miss_waveoff", 0.2)), "persistent high miss must trigger a waveoff")
	craft.set_meta("arresting_engaged", true)
	_check(not bool(pilot.call("_update_landing_high_miss_waveoff", 0.3)), "a physical catch must override the high-miss forecast")
	craft.set_meta("arresting_engaged", false)
	_check(not bool(pilot.call("_update_landing_high_miss_waveoff", 0.1)), "catch/reset must clear high-miss hysteresis")
	pilot.call("_clear_landing_sight_solution")
	craft.linear_velocity = Vector3(0.0, 0.0, 70.0)
	pilot.set("_landing_sight_solution", {"deck_normal": Vector3.UP, "deck_axis": Vector3.BACK,
		"lateral_plan": {"accel_mps2": -4.0}})
	pilot.call("_apply_landing_terminal_rudder", 0.1, 0.0)
	var unrotated_yaw: float = pilot.get("yaw_input")
	_check(unrotated_yaw < 0.0, "real pilot must emit left rudder for a left acceleration request")
	craft.rotation.y = 1.2
	craft.linear_velocity = craft.global_basis.z * 70.0
	pilot.set("_landing_sight_solution", {"deck_normal": Vector3.UP, "deck_axis": craft.global_basis.z,
		"lateral_plan": {"accel_mps2": -4.0}})
	pilot.call("_apply_landing_terminal_rudder", 0.1, 0.0)
	_check(is_equal_approx(unrotated_yaw, float(pilot.get("yaw_input"))), "terminal rudder must be invariant to carrier heading")
	pilot.set("_landing_observed_accel", Vector3.ONE)
	pilot.call("_clear_landing_sight_solution")
	_check(Vector3(pilot.get("_landing_observed_accel")).is_zero_approx(), "new landing picture must reset measured acceleration")
	craft.rotation = Vector3.ZERO
	craft.linear_velocity = Vector3.ZERO
	pilot.set("current_state", 14)
	pilot.set("altitude_agl", 5.0)
	craft.rotation.z = 0.6
	craft.linear_velocity = Vector3(0, -8, 70)
	_check(bool(pilot.call("_check_terrain_avoidance", 0.1)), "low recovery route must invoke terrain escape")
	_check(float(pilot.get("roll_input")) < -0.5, "real recovery terrain branch must actively undo existing bank")
	craft.rotation = Vector3.ZERO
	craft.linear_velocity = Vector3.ZERO
	var geometry := {"axis": Vector3.BACK}
	craft.position.z = 26.0
	var clearance: Dictionary = pilot.call("_landing_last_wire_clearance", geometry)
	_check(bool(clearance.get("valid", false)) and not bool(clearance.get("passed", true)), "middle wire must not trigger bolter")
	craft.position.z = 44.0
	clearance = pilot.call("_landing_last_wire_clearance", geometry)
	_check(bool(clearance.get("passed", false)), "hook beyond last wire must trigger bolter")
	last_wire.position.z = 60.0
	clearance = pilot.call("_landing_last_wire_clearance", geometry)
	_check(not bool(clearance.get("passed", true)), "moving last wire must move bolter boundary")
	craft.set_meta("arresting_engaged", true)
	_check(not bool(pilot.call("_should_start_missed_approach")), "engaged hook must suppress bolter")
	var harness := Harness.new()
	scene.add_child(harness)
	harness._attempts["test"] = {"node": craft, "outcome": "", "spawn_t": 0.0}
	harness._attempts["scrape"] = {"node": craft, "outcome": "", "crash_pending": true}
	craft.set_meta("arresting_engaged", false)
	await harness._resolve_pending_craft_crash("scrape", 3.7)
	_check(harness._attempts.scrape.outcome == "" and not harness._attempts.scrape.crash_pending,
		"surviving body contact without any wire catch must continue observation")
	craft.set_meta("arresting_engaged", true)
	craft.linear_velocity = Vector3(0.0, 0.0, 30.0)
	harness._observe_arrest("test", craft, 0.1)
	_check(harness._attempts.test.outcome == "" and harness._attempts.test.wire_caught, "engagement must remain provisional")
	craft.set_meta("arresting_engaged", false)
	harness._attempts.test.crash_pending = true
	await harness._resolve_pending_craft_crash("test", null)
	_check(harness._attempts.test.outcome == "" and not harness._attempts.test.crash_pending, "released catch must remain under stop observation")
	var manager := Node.new()
	manager.set_script(load("res://LandCarrier/FlightDeckManager.gd"))
	craft.set_meta("landing_test_observer_owned", true)
	manager.call("start_post_arrest_recovery", craft)
	_check(is_equal_approx(craft.linear_velocity.z, 30.0) and not bool(craft.get_meta("controls_disabled", false)), "test-owned arrest must not receive recovery stabilization")
	manager.free()
	craft.linear_velocity = Vector3.ZERO
	harness._observe_arrest("test", craft, 1.0)
	_check(harness._attempts.test.outcome == "", "one second stopped is not sufficient")
	craft.linear_velocity = Vector3(0.0, 0.0, 3.0)
	harness._observe_arrest("test", craft, 0.1)
	_check(is_zero_approx(harness._attempts.test.stop_stable_s), "movement must reset sustained stop")
	harness._on_craft_damaged(5.0, 95.0, "test")
	craft.current_health = 95.0
	craft.linear_velocity = Vector3.ZERO
	harness._observe_arrest("test", craft, 2.1)
	_check(harness._attempts.test.outcome == "CAUGHT" and harness._attempts.test.damage_taken == 5.0, "stopped catch must retain damage")
	harness._attempts["destroyed"] = {"node": craft, "outcome": "", "wire_caught": true}
	harness._on_craft_destroyed("destroyed")
	_check(harness._attempts.destroyed.outcome == "CRASH", "post-catch destruction must override provisional catch")
	scene.free()
	print("LANDING_RECOVERY_RELIABILITY_SMOKETEST %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)
