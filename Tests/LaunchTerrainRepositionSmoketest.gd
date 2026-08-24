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

	carrier.rotation.y = atan2(carrier.requested_direction.x, carrier.requested_direction.z)
	if not bool(deck_manager.call("_launch_needs_carrier_constraint")):
		_fail("clear launch heading did not restore the straight-launch constraint")
		return
	if not carrier.cleared:
		_fail("temporary carrier reposition was not released after the corridor cleared")
		return

	var live_carrier := CharacterBody3D.new()
	scene.add_child(live_carrier)
	live_carrier.set_script(load("res://LandCarrier/LandCarrier.gd") as Script)
	if not bool(live_carrier.call("request_launch_corridor_reposition", Vector3.RIGHT)):
		_fail("LandCarrier rejected a valid temporary reposition request")
		return
	live_carrier.call("_refresh_drive_command", 1.0)
	if float(live_carrier.get("_drive_target_speed_mps")) <= 0.0 \
			or absf(float(live_carrier.get("_drive_target_yaw_rate_rad_s"))) <= 0.0001:
		_fail("LandCarrier did not generate moving turn commands for the temporary reposition")
		return

	print("[LaunchTerrainRepositionSmoketest] PASS blocked=move_and_turn clear=resume_route")
	quit(0)


func _fail(reason: String) -> void:
	push_error("[LaunchTerrainRepositionSmoketest] FAIL %s" % reason)
	quit(1)
