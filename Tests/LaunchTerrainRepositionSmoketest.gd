extends SceneTree


class CliffTerrain:
	extends Node3D

	func get_height(world_position: Vector3) -> float:
		return 220.0 if world_position.z > 100.0 else 0.0


class CarrierDouble:
	extends Node3D

	var requested: bool = false
	var cleared: bool = false
	var requested_direction: Vector3 = Vector3.ZERO
	var navigation_order_active: bool = true

	func request_launch_corridor_reposition(direction: Vector3) -> bool:
		requested = true
		cleared = false
		requested_direction = direction
		return true

	func clear_launch_corridor_reposition() -> void:
		cleared = true
		requested = false

	func is_launch_corridor_reposition_active() -> bool:
		return requested

	func has_active_navigation_order() -> bool:
		return navigation_order_active


class LaunchConstraintDouble:
	extends Node

	func is_carrier_recovery_constraint_active() -> bool:
		return true

	func get_carrier_recovery_speed_limit_mps() -> float:
		return 0.0

	func is_launch_constraint_active() -> bool:
		return true


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := Node3D.new()
	scene.name = "LaunchTerrainRepositionSmoketest"
	root.add_child(scene)
	current_scene = scene

	var terrain := CliffTerrain.new()
	terrain.add_to_group("terrain_provider")
	scene.add_child(terrain)

	var carrier := CarrierDouble.new()
	carrier.position = Vector3(0.0, 40.0, 0.0)
	scene.add_child(carrier)
	var deck_manager := Node.new()
	carrier.add_child(deck_manager)
	deck_manager.set_script(load("res://LandCarrier/FlightDeckManager.gd") as Script)
	deck_manager.set("_ai_launch_queue", 1)
	deck_manager.set("launch_terrain_auto_reposition_delay_s", 0.0)

	if bool(deck_manager.call("_launch_needs_carrier_constraint")):
		_fail("cliff-ahead launch unexpectedly constrained the carrier to a straight heading")
		return
	if not carrier.requested:
		_fail("blocked launch did not request carrier repositioning")
		return
	var original_forward := Vector3.FORWARD
	if carrier.requested_direction.dot(original_forward) > 0.75:
		_fail("reposition direction still pointed substantially into the cliff")
		return
	var selected_direction := carrier.requested_direction
	carrier.clear_launch_corridor_reposition()
	carrier.navigation_order_active = false
	deck_manager.call("_request_launch_terrain_reposition")
	if carrier.requested:
		_fail("FlightDeckManager requested a terrain reposition while HOLD was active")
		return
	carrier.navigation_order_active = true
	deck_manager.call("_request_launch_terrain_reposition")
	if not carrier.requested:
		_fail("FlightDeckManager did not resume terrain reposition authority for an active route")
		return

	carrier.rotation.y = atan2(selected_direction.x, selected_direction.z)
	if not bool(deck_manager.call("_launch_needs_carrier_constraint")):
		_fail("clear launch heading did not restore the straight-launch constraint")
		return
	if not carrier.cleared:
		_fail("temporary carrier reposition was not released after the corridor cleared")
		return

	var live_carrier := CharacterBody3D.new()
	scene.add_child(live_carrier)
	live_carrier.set_script(load("res://LandCarrier/LandCarrier.gd") as Script)
	if bool(live_carrier.call("request_launch_corridor_reposition", Vector3.RIGHT)):
		_fail("held LandCarrier accepted an autonomous launch reposition")
		return
	var launch_constraint := LaunchConstraintDouble.new()
	launch_constraint.name = "FlightDeckManager"
	live_carrier.add_child(launch_constraint)
	var held_constraint: Dictionary = live_carrier.call("_apply_recovery_motion_constraint", 0.0, 0.0, 0.1)
	if absf(float(held_constraint.get("speed", -1.0))) > 0.001:
		_fail("launch constraint created carrier speed while HOLD was active")
		return

	var active_route: Array[Vector3] = [Vector3(1000.0, 0.0, 0.0)]
	live_carrier.set("_raw_waypoints", active_route)
	if not bool(live_carrier.call("request_launch_corridor_reposition", Vector3.RIGHT)):
		_fail("LandCarrier rejected a valid temporary reposition during an active route")
		return
	live_carrier.call("_refresh_drive_command", 1.0)
	if float(live_carrier.get("_drive_target_speed_mps")) <= 0.0 \
			or absf(float(live_carrier.get("_drive_target_yaw_rate_rad_s"))) <= 0.0001:
		_fail("LandCarrier did not generate moving turn commands for the temporary reposition")
		return
	var routed_constraint: Dictionary = live_carrier.call("_apply_recovery_motion_constraint", 0.0, 0.0, 0.1)
	if float(routed_constraint.get("speed", 0.0)) < float(live_carrier.get("launch_constraint_min_speed_mps")):
		_fail("launch constraint no longer preserves minimum speed for an active route")
		return
	live_carrier.call("hold_position")
	if bool(live_carrier.call("is_launch_corridor_reposition_active")):
		_fail("HOLD did not cancel the active launch reposition")
		return
	var held_after_route: Dictionary = live_carrier.call("_apply_recovery_motion_constraint", 0.0, 0.0, 0.1)
	if absf(float(held_after_route.get("speed", -1.0))) > 0.001:
		_fail("launch constraint resumed movement after HOLD cancelled the route")
		return

	print("[LaunchTerrainRepositionSmoketest] PASS held=authoritative routed=move_and_turn clear=resume_route")
	quit(0)


func _fail(reason: String) -> void:
	push_error("[LaunchTerrainRepositionSmoketest] FAIL %s" % reason)
	quit(1)
