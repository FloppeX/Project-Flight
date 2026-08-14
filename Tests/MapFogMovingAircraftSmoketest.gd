extends SceneTree

class FriendlyAircraft:
	extends Node3D

	func get_team() -> int:
		return 1


class FriendlyCarrier:
	extends Node3D

	signal initial_placement_completed

	var placement_complete: bool = false

	func is_initial_placement_complete() -> bool:
		return placement_complete

	func complete_initial_placement(world_position: Vector3) -> void:
		global_position = world_position
		placement_complete = true
		initial_placement_completed.emit()


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var nav_grid: Node = root.get_node("TerrainNavGrid")
	var map_fog: Node = root.get_node("MapFogOfWar")
	nav_grid.set_process(false)
	nav_grid.set("cell_size_m", 40.0)
	nav_grid.set("_cols", 501)
	nav_grid.set("_rows", 501)
	nav_grid.set("_origin_x", -10000.0)
	nav_grid.set("_origin_z", -10000.0)
	var heights := PackedFloat32Array()
	heights.resize(501 * 501)
	heights.fill(0.0)
	nav_grid.set("_heights", heights)
	nav_grid.set("_is_baked", true)

	var scene := Node3D.new()
	scene.name = "MapFogMovingAircraftSmoketest"
	root.add_child(scene)
	current_scene = scene
	var carrier := FriendlyCarrier.new()
	carrier.add_to_group("carrier")
	var temporary_carrier_position := Vector3(0.0, 0.0, -7000.0)
	var final_carrier_position := Vector3(0.0, 0.0, 7000.0)
	carrier.position = temporary_carrier_position
	scene.add_child(carrier)

	map_fog.set("aircraft_reveal_radius_m", 600.0)
	map_fog.set("carrier_reveal_radius_m", 600.0)
	map_fog.set("observer_update_interval_s", 0.05)
	map_fog.call("_initialize_from_navgrid")
	await _wait_process_frames(3)
	if bool(map_fog.call("is_world_explored", temporary_carrier_position)):
		_fail("carrier temporary placement was permanently revealed")
		return
	carrier.complete_initial_placement(final_carrier_position)
	await _wait_process_frames(3)
	if not bool(map_fog.call("is_world_explored", final_carrier_position)):
		_fail("carrier final placement was not revealed")
		return
	if bool(map_fog.call("is_world_explored", temporary_carrier_position)):
		_fail("temporary carrier reveal survived placement reset")
		return

	var aircraft := FriendlyAircraft.new()
	# Air Ops launches use ai_aircraft and are intentionally removed from the
	# player-aircraft group during retrieval.
	aircraft.add_to_group("ai_aircraft")
	aircraft.add_to_group("friendlies")
	aircraft.position = Vector3(-4000.0, 800.0, 0.0)
	scene.add_child(aircraft)

	await _wait_process_frames(5)
	map_fog.call("_process", 0.1)
	if not bool(map_fog.call("is_world_explored", aircraft.global_position)):
		_fail("aircraft did not reveal its starting position")
		return

	var old_position := aircraft.global_position
	paused = true
	aircraft.global_position = Vector3(4000.0, 800.0, 0.0)
	await _wait_process_frames(5)
	# Keep this deterministic on uncapped headless runs where five rendered frames
	# can elapse before the real-time observer interval reaches 50 ms.
	map_fog.call("_process", 0.1)
	if not bool(map_fog.call("is_world_explored", aircraft.global_position)):
		_fail("aircraft did not reveal after moving")
		return
	if not bool(map_fog.call("is_world_explored", old_position)):
		_fail("the original reveal was not permanent")
		return
	var mask_texture: Texture2D = map_fog.call("get_mask_texture") as Texture2D
	if mask_texture == null:
		_fail("fog mask texture was unavailable")
		return
	var mask_image := mask_texture.get_image()
	var new_cell := Vector2i(350, 250)
	if mask_image.get_pixel(new_cell.x, new_cell.y).r < 0.5:
		_fail("uploaded fog texture did not contain the moved-aircraft reveal")
		return

	print("[MapFogMovingAircraftSmoketest] PASS old=%s new=%s" % [
		str(old_position),
		str(aircraft.global_position),
	])
	quit(0)


func _wait_process_frames(count: int) -> void:
	for _i in range(count):
		await process_frame


func _fail(reason: String) -> void:
	push_error("[MapFogMovingAircraftSmoketest] FAIL %s" % reason)
	quit(1)
