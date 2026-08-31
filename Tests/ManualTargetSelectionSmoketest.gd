extends SceneTree

const TARGETING_SCRIPT: Script = preload("res://addons/simplified_flightsim/aircraft_modules/Controls/ControlTargeting.gd")


class TestAircraft:
	extends Node3D

	var team: int = 1

	func get_team() -> int:
		return team


class TestTarget:
	extends Node3D

	signal destroyed(target: Node3D)

	var team: int = 2

	func get_team() -> int:
		return team

	func destroy_for_test() -> void:
		destroyed.emit(self)


class TestNoArgumentTarget:
	extends Node3D

	signal destroyed

	var team: int = 2

	func get_team() -> int:
		return team


var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := Node3D.new()
	scene.name = "ManualTargetSelectionSmoketest"
	root.add_child(scene)
	current_scene = scene

	var aircraft := TestAircraft.new()
	aircraft.name = "PlayerAircraft"
	scene.add_child(aircraft)
	var targeting = TARGETING_SCRIPT.new()
	targeting.name = "ControlTargeting"
	aircraft.add_child(targeting)
	targeting.setup(aircraft)

	var registered_air := _make_target(scene, "RegisteredAir", Vector3(0.0, 0.0, 1000.0), ["enemies", "aircraft"])
	var ground_vehicle := _make_target(scene, "GroundVehicle", Vector3(-500.0, 0.0, 1000.0), ["enemies", "ground_vehicles"])
	var structure := _make_target(scene, "Structure", Vector3(500.0, 0.0, 1000.0), ["enemies", "buildings"])
	var friendly := _make_target(scene, "Friendly", Vector3(0.0, 0.0, 800.0), ["enemies", "friendlies"])
	friendly.team = 1

	var registry := root.get_node_or_null("EnemyRegistry")
	_expect(registry != null, "EnemyRegistry autoload was unavailable")
	if registry != null:
		registry.call("register_enemy", registered_air, 2)

	var hostiles: Array = targeting.call("_get_hostile_targets") as Array
	_expect(hostiles.has(registered_air), "registered aircraft was missing from target candidates")
	_expect(hostiles.has(ground_vehicle), "unregistered ground vehicle was hidden by registry aircraft")
	_expect(hostiles.has(structure), "unregistered structure was hidden by registry aircraft")
	_expect(not hostiles.has(friendly), "friendly node in the enemies group became targetable")

	for i in range(10):
		targeting.process_physic_frame(0.2)
	_expect(targeting.current_target == null, "selector automatically acquired a target without D-pad input")

	_send_dpad(targeting, JOY_BUTTON_DPAD_RIGHT)
	_expect(targeting.current_target == registered_air, "first D-pad press did not choose the contact closest to the nose")
	_send_dpad(targeting, JOY_BUTTON_DPAD_RIGHT)
	_expect(targeting.current_target == structure, "D-pad right did not move to the contact on the right")
	_send_dpad(targeting, JOY_BUTTON_DPAD_LEFT)
	_expect(targeting.current_target == registered_air, "D-pad left did not return to the center contact")
	_send_dpad(targeting, JOY_BUTTON_DPAD_LEFT)
	_expect(targeting.current_target == ground_vehicle, "D-pad left did not move to the contact on the left")

	registered_air.position = Vector3(0.0, 0.0, 15000.0)
	targeting.set_target(registered_air)
	for i in range(10):
		targeting.process_physic_frame(0.2)
	_expect(targeting.current_target == registered_air, "selected target was dropped after leaving cycle range")
	_send_dpad(targeting, JOY_BUTTON_DPAD_RIGHT)
	_expect(targeting.current_target == structure, "out-of-range target bearing was not retained as the cycle anchor")

	ground_vehicle.position = Vector3(-15000.0, 0.0, 15000.0)
	structure.position = Vector3(15000.0, 0.0, 15000.0)
	targeting.set_target(ground_vehicle)
	_send_dpad(targeting, JOY_BUTTON_DPAD_RIGHT)
	_expect(targeting.current_target == ground_vehicle, "empty cycle range cleared the retained selection")
	ground_vehicle.destroy_for_test()
	_expect(targeting.current_target == null, "destroyed selected target was not cleared")
	for i in range(10):
		targeting.process_physic_frame(0.2)
	_expect(targeting.current_target == null, "destroyed target triggered automatic reselection")

	var no_argument_target := TestNoArgumentTarget.new()
	no_argument_target.name = "NoArgumentDestroyedTarget"
	scene.add_child(no_argument_target)
	no_argument_target.add_to_group("enemies")
	targeting.set_target(no_argument_target)
	no_argument_target.destroyed.emit()
	_expect(targeting.current_target == null, "zero-argument destroyed signal did not clear selection")

	targeting.set_target(structure)
	targeting.external_target_authority = true
	_send_dpad(targeting, JOY_BUTTON_DPAD_LEFT)
	_expect(targeting.current_target == structure, "manual D-pad input overrode external AI target authority")
	targeting.external_target_authority = false

	if registry != null:
		registry.call("unregister_enemy", registered_air, 2)
	await _finish(scene)


func _make_target(scene: Node3D, node_name: String, target_position: Vector3, groups: Array[String]) -> TestTarget:
	var target := TestTarget.new()
	target.name = node_name
	target.position = target_position
	scene.add_child(target)
	for group_name in groups:
		target.add_to_group(group_name)
	return target


func _send_dpad(targeting: Node, button_index: int) -> void:
	var event := InputEventJoypadButton.new()
	event.button_index = button_index
	event.pressed = true
	targeting.call("receive_input", event)


func _finish(scene: Node3D) -> void:
	var passed := _failures.is_empty()
	current_scene = null
	root.remove_child(scene)
	scene.free()
	await process_frame
	if passed:
		print("[ManualTargetSelectionSmoketest] PASS input=dpad_left_right authority=manual retention=until_destroyed candidates=registry_plus_groups")
		quit(0)
		return
	print("[ManualTargetSelectionSmoketest] %d failure(s)" % _failures.size())
	quit(1)


func _expect(condition: bool, description: String) -> void:
	if condition:
		return
	_failures.append(description)
	push_error("[ManualTargetSelectionSmoketest] FAIL: %s" % description)
