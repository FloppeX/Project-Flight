extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var craft: RigidBody3D = load("res://Aircraft/Aircraft_5.tscn").instantiate()
	craft.freeze = true
	scene.add_child(craft)
	var pilot: Node = craft.get_node("AIPilot")
	pilot.set_physics_process(false)
	pilot.aircraft = craft
	pilot.current_state = pilot.State.MISSED_APPROACH
	pilot._bolter_go_around = true
	pilot.throttle_input = 1.0
	_check(not pilot.notify_arresting_catch(), "uncaught aircraft lost escape ownership")
	_check(pilot.current_state == pilot.State.MISSED_APPROACH, "uncaught escape state changed")
	craft.set_meta("arresting_engaged", true)
	craft.set_meta("controls_disabled", true)
	_check(pilot.notify_arresting_catch(), "catch not accepted with deck-owned controls")
	_check(pilot.current_state == pilot.State.LANDING, "caught aircraft retained missed approach")
	_check(not pilot.is_landing_go_around_active(), "caught aircraft retained go-around flag")
	_check(pilot.throttle_input == 0.0, "catch retained escape throttle")
	var retries: int = pilot._recovery_go_around_attempt_count
	pilot._begin_missed_approach()
	_check(pilot.current_state == pilot.State.LANDING and pilot._recovery_go_around_attempt_count == retries,
		"late wave-off overrode capture")
	_check(not pilot.request_landing_wave_off("test"), "external wave-off accepted while caught")
	_check(pilot.notify_arresting_catch(), "repeated catch notification not idempotent")
	# Exercise the real cable callback ordering: deck listeners must see capture
	# ownership already reconciled, before they disable all pilot controls.
	craft.set_meta("arresting_engaged", false)
	pilot.current_state = pilot.State.MISSED_APPROACH
	pilot._bolter_go_around = true
	var cable: Node3D = load("res://LandCarrier/ArrestingCable.gd").new()
	cable.visualize_cable = false
	scene.add_child(cable)
	cable.set_physics_process(false)
	var hook := Area3D.new()
	craft.add_child(hook)
	hook.add_to_group("tailhook")
	cable.cable_engaged.connect(func(_aircraft: RigidBody3D):
		_check(pilot.current_state == pilot.State.LANDING and not pilot._bolter_go_around,
			"deck received catch before pilot ownership was reconciled"))
	_check(cable._engage_hook_area(hook, "ownership_smoke"), "real cable catch failed")
	cable._release()
	cable.free()
	craft.set_meta("arresting_engaged", true)
	pilot._passive_debug_only = true
	pilot.current_state = pilot.State.IDLE
	_check(not pilot.notify_arresting_catch() and pilot.current_state == pilot.State.IDLE,
		"player observer entered autopilot landing")
	craft.free()
	print("RECOVERY_CATCH_OWNERSHIP ", "PASS" if failures.is_empty() else "FAIL", " ", failures)
	quit(0 if failures.is_empty() else 1)

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)
