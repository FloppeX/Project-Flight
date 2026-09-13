extends SceneTree

class TestCraft:
	extends RigidBody3D
	var current_health: float = 100.0

class WaveoffPilot:
	extends Node
	var current_state: int = 0
	func get_landing_remaining_to_touchdown_m() -> float:
		return -100.0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	# Load the scenario's scene dependencies after project autoloads exist.
	var observer: Variant = Node3D.new()
	observer.set_script(load("res://Tests/Fixtures/FullRecoveryCycleObserver.gd"))
	root.add_child(observer)
	observer._observe_through_stow = true
	observer._stage = observer.Stage.ROLLING
	observer.rolling_active_aircraft_max = 3
	observer._friendly_launches = 3
	var aircraft: Array[TestCraft] = []
	for index in range(3):
		var craft := TestCraft.new()
		craft.freeze = true
		root.add_child(craft)
		aircraft.append(craft)
		observer._register_aircraft(craft, null, 1)
		observer._cycle_observations[craft.get_instance_id()]["wire_caught"] = true
	observer._poll_cycle_observations(2.1)
	assert(observer._stage == observer.Stage.ROLLING, "catches and stops must not complete a stow test")
	observer._cycle_observations[aircraft[0].get_instance_id()]["destroyed"] = true
	observer._poll_cycle_observations(0.1)
	assert(observer._stage == observer.Stage.ROLLING, "first loss must not abort the rest of the cohort")
	observer._on_cycle_aircraft_stored(aircraft[1])
	observer._poll_cycle_observations(0.1)
	assert(observer._stage == observer.Stage.ROLLING, "must wait for last aircraft")
	observer._on_cycle_aircraft_stored(aircraft[2])
	observer._poll_cycle_observations(0.1)
	assert(observer._stage == observer.Stage.COMPLETE, "all three terminal outcomes must finish the observation")
	observer._finalize_completed_run()
	assert(observer.test_result.status == "FAIL", "a destroyed member must fail the cohort even if the others stow")
	observer._cycle_observations[aircraft[0].get_instance_id()]["destroyed"] = false
	observer._on_cycle_aircraft_stored(aircraft[0])
	observer._completion_handled = false
	observer._finalize_completed_run()
	assert(observer.test_result.status == "PASS", "three healthy stopped and stowed catches must pass")
	observer._cycle_observations[aircraft[0].get_instance_id()]["stopped"] = false
	observer._completion_handled = false
	observer._finalize_completed_run()
	assert(observer.test_result.status == "FAIL", "storage without observed stop must not pass")
	var waveoff_pilot := WaveoffPilot.new()
	root.add_child(waveoff_pilot)
	# Resolve after autoloads exist, as with the observer above. Referencing the
	# global class at parse time pulls RadioComms in before it is registered.
	var pilot_model: Variant = load("res://AI/AIPilot.gd")
	waveoff_pilot.current_state = pilot_model.State.MISSED_APPROACH
	var waveoff_craft := aircraft[0]
	waveoff_craft.position.y = 120.0
	waveoff_craft.linear_velocity = Vector3(0.0, 5.0, 60.0)
	observer._aircraft_records[waveoff_craft.get_instance_id()]["alive"] = true
	observer._aircraft_records[waveoff_craft.get_instance_id()]["pilot"] = waveoff_pilot
	observer._desert_recovery_mode = true
	observer.desert_recovery_forced_waveoff_remaining_m = 200.0
	observer._forced_waveoff_aircraft_id = waveoff_craft.get_instance_id()
	observer._forced_waveoff_triggered = true
	observer._forced_waveoff_trigger_altitude_m = 100.0
	observer._stage = observer.Stage.ROLLING
	observer._poll_desert_forced_waveoff_test()
	assert(observer._forced_waveoff_cleared and observer._stage == observer.Stage.ROLLING, "combined test must continue after escape clearance")
	observer._elapsed_s = 100.0
	observer._poll_desert_forced_waveoff_test()
	assert(observer._stage == observer.Stage.ROLLING, "cleared escape must not later time out")
	observer._observe_through_stow = false
	observer._forced_waveoff_cleared = false
	observer._poll_desert_forced_waveoff_test()
	assert(observer._stage == observer.Stage.COMPLETE, "standalone escape test must still finish at clearance")
	observer._observe_through_stow = true
	observer._forced_waveoff_cleared = false
	observer._cycle_observations[waveoff_craft.get_instance_id()]["stopped"] = true
	observer._completion_handled = false
	observer._finalize_completed_run()
	assert(observer.test_result.status == "FAIL", "a catch without actual escape clearance must not pass a combined waveoff test")
	waveoff_pilot.free()
	for craft in aircraft:
		craft.free()
	observer.free()
	print("FULL_RECOVERY_CYCLE_OBSERVER_SMOKETEST PASS")
	quit()
