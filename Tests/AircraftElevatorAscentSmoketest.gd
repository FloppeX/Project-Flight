extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var carrier := (load("res://LandCarrier/LandCarrier2.tscn") as PackedScene).instantiate() as Node3D
	carrier.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(carrier)
	current_scene = carrier
	await process_frame
	var manager := carrier.get_node("FlightDeckManager")
	var elevator := carrier.get_node("Elevator2") as Node3D
	var marker := carrier.get_node("elevator_marker_2") as Node3D
	manager.elevator = elevator
	manager.elevator_pickup_marker = marker
	var aircraft_scene := load("res://Aircraft/Aircraft_15.tscn") as PackedScene
	var entry: Dictionary = manager.call("_make_stored_aircraft_entry", "Aircraft_15", aircraft_scene, aircraft_scene.resource_path)
	if entry.is_empty():
		_fail("could not reserve a pilot for Aircraft 15")
		return
	var aircraft := manager.call("_create_aircraft_at_hangar_level", entry, elevator, marker) as RigidBody3D
	if not is_instance_valid(aircraft):
		_fail("hangar retrieval did not create Aircraft 15")
		return
	if not bool(manager.call("_aircraft_footprint_inside_elevator", aircraft, elevator)):
		_fail("created Aircraft 15 crosses the lift before ascent")
		return
	for _frame in range(3):
		await process_frame
	if not is_instance_valid(aircraft) or not bool(manager.call("_aircraft_footprint_inside_elevator", aircraft, elevator)):
		_fail("Aircraft 15 shifted outside the lift during spawn settle")
		return
	# The spawn cache is deliberately discarded after presentation staging.
	# Recovery later needs to rebuild the footprint from the live Blender model.
	manager.call("_ensure_hangar_aircraft_presentation_complete", aircraft)
	if aircraft.has_meta("elevator_model_footprint_points"):
		_fail("completed presentation retained the temporary footprint cache")
		return
	var recovery_pose: Dictionary = manager.call("_get_safe_elevator_parking_pose", aircraft, marker.global_position, elevator)
	if not bool(recovery_pose.get("valid", false)):
		_fail("post-flight recovery cannot rebuild the model footprint: %s" % recovery_pose.get("reason", "unknown"))
		return
	print("[AircraftElevatorAscentSmoketest] PASS local_root=%s" % elevator.to_local(aircraft.global_position))
	current_scene = null
	carrier.queue_free()
	await process_frame
	quit(0)


func _fail(reason: String) -> void:
	push_error("[AircraftElevatorAscentSmoketest] %s" % reason)
	quit(1)
