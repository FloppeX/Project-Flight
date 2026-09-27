extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var carrier := (load("res://LandCarrier/LandCarrier2.tscn") as PackedScene).instantiate() as Node3D
	carrier.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(carrier)
	var manager := carrier.get_node("FlightDeckManager")
	var aircraft := (load("res://Aircraft/Aircraft_15.tscn") as PackedScene).instantiate() as RigidBody3D
	aircraft.process_mode = Node.PROCESS_MODE_DISABLED
	carrier.add_child(aircraft)
	await process_frame
	var model := aircraft.get_node("aircraft_15")
	print("[AircraftElevatorFootprintSmoketest] model_scene=%s" % model.scene_file_path)
	var staged_aircraft := (load("res://Aircraft/Aircraft_15.tscn") as PackedScene).instantiate() as RigidBody3D
	var pre_tree_points: Array = manager.call("_get_aircraft_model_footprint_points", staged_aircraft)
	staged_aircraft.set_meta("elevator_model_footprint_points", pre_tree_points)
	var detached_model := staged_aircraft.get_node("aircraft_15")
	staged_aircraft.remove_child(detached_model)
	var cached_points: Array = manager.call("_get_aircraft_model_footprint_points", staged_aircraft)
	if pre_tree_points.size() < 24 or cached_points.size() != pre_tree_points.size():
		_fail("Hangar presentation staging lost the pre-ascent footprint")
		return
	detached_model.free()
	staged_aircraft.free()
	for elevator_name in ["Elevator", "Elevator2"]:
		if elevator_name == "Elevator2":
			carrier.global_position = Vector3(120.0, 8.0, -95.0)
			carrier.rotation_degrees.y = 37.0
		var elevator := carrier.get_node(elevator_name) as Node3D
		var marker_name := "elevator_marker" if elevator_name == "Elevator" else "elevator_marker_2"
		var marker := carrier.get_node(marker_name) as Node3D
		manager.elevator = elevator
		manager.elevator_pickup_marker = marker
		var pose: Dictionary = manager.call("_get_safe_elevator_parking_pose", aircraft, marker.global_position)
		if not bool(pose.get("valid", false)):
			_fail("%s pose failed: %s" % [elevator_name, pose.get("reason", "unknown")])
			return
		var parked := Transform3D(Basis(Vector3.UP, manager.call("_get_carrier_forward_yaw")), pose.get("position"))
		var local_target: Vector3 = pose.get("elevator_local_position", Vector3.ZERO)
		if elevator.to_global(local_target).distance_to(parked.origin) > 0.01:
			_fail("%s target did not remain tied to the moving elevator" % elevator_name)
			return
		aircraft.global_transform = parked
		if not bool(manager.call("_aircraft_footprint_inside_elevator", aircraft)):
			_fail("%s final model footprint crosses the platform edge" % elevator_name)
			return
		var points: Array = manager.call("_get_aircraft_model_footprint_points", aircraft)
		var marker_pose := Transform3D(parked.basis, marker.global_position)
		var marker_bounds: Rect2 = manager.call("_get_elevator_footprint_bounds", elevator, marker_pose, points)
		if bool(manager.call("_elevator_footprint_bounds_inside", marker_bounds, elevator.platform_size, manager.aircraft_elevator_edge_clearance_m)):
			_fail("%s marker-centered pose unexpectedly contains Aircraft 15's tail" % elevator_name)
			return
		var bounds: Rect2 = manager.call("_get_elevator_footprint_bounds", elevator, parked, points)
		print("[AircraftElevatorFootprintSmoketest] %s root=%s bounds=%s" % [elevator_name, elevator.to_local(parked.origin), bounds])
		if points.size() < 24 or bounds.size.y < 10.0 or bounds.size.y > 14.2:
			_fail("%s Aircraft 15 tail was omitted or footprint dimensions are wrong" % elevator_name)
			return
		if elevator_name == "Elevator2":
			aircraft.global_position = elevator.to_global(local_target + Vector3(-8.0, 0.0, 8.0))
			var near_stage: Dictionary = manager.call("_get_elevator_approach_staging_pose", aircraft, local_target)
			var authored_approach := carrier.get_node("elevator_approach_marker_b") as Node3D
			var near_stage_world := elevator.to_global(near_stage.get("elevator_local_position", Vector3.ZERO))
			var model_radius := 0.0
			for point in points:
				model_radius = maxf(model_radius, Vector2(point.x, point.z).length())
			if not bool(near_stage.get("valid", false)) \
					or near_stage_world.distance_to(authored_approach.global_position) < 1.0 \
					or not bool(manager.call("_staging_turn_clear_of_elevators", near_stage_world, model_radius)):
				_fail("A near pickup did not get a staging turn clear of both lifts")
				return
			aircraft.global_rotation.y += PI * 0.5
			var near_tow_yaw: float = manager.call("_get_horizontal_tow_yaw", aircraft.global_position, near_stage_world)
			await manager.call("_align_aircraft_to_yaw", aircraft, near_tow_yaw)
			await manager.call("_tow_recovery_aircraft_to_point", aircraft, near_stage_world)
			await manager.call("_align_aircraft_forward_on_elevator", aircraft)
			await manager.call("_tow_recovery_aircraft_to_point", aircraft, elevator.to_global(local_target))
			if not bool(manager.call("_aircraft_footprint_inside_elevator", aircraft)):
				_fail("A near pickup did not finish centered on Elevator2")
				return
			# Hangar retrieval must do the same placement while the platform is
			# still down, before tractors and the aircraft begin the ascent.
			aircraft.global_position = marker.global_position + Vector3(0.0, -10.0, 0.0)
			aircraft.global_rotation.y += 0.6
			if not bool(manager.call("_position_retrieved_aircraft_before_ascent", aircraft, elevator, marker)) \
					or not bool(manager.call("_aircraft_footprint_inside_elevator", aircraft, elevator)):
				_fail("Aircraft 15 was not centered before retrieval ascent")
				return
		if elevator_name == "Elevator":
			# Tow toward the elevator, turn while still clear of it, then park.
			aircraft.global_position = elevator.to_global(local_target + Vector3(-12.0, 0.0, 35.0))
			aircraft.global_rotation.y += PI * 0.5
			manager.tractor_elevator_align_duration_s = 0.03
			manager.set("_aircraft_move_speed", 120.0)
			var stage: Dictionary = manager.call("_get_elevator_approach_staging_pose", aircraft, local_target)
			if not bool(stage.get("valid", false)):
				_fail("Aircraft 15 did not get an approach staging point")
				return
			var stage_world: Vector3 = elevator.to_global(stage["elevator_local_position"])
			var tow_direction := (stage_world - aircraft.global_position).normalized()
			var tow_yaw: float = manager.call("_get_horizontal_tow_yaw", aircraft.global_position, stage_world)
			await manager.call("_align_aircraft_to_yaw", aircraft, tow_yaw)
			var aircraft_forward := aircraft.global_transform.basis.z
			if aircraft_forward.dot(tow_direction) < 0.99:
				_fail("Aircraft 15 did not face its tow route after pickup")
				return
			await manager.call("_tow_recovery_aircraft_to_point", aircraft, stage_world)
			var stage_bounds: Rect2 = manager.call("_get_elevator_footprint_bounds", elevator, aircraft.global_transform, points)
			if stage_bounds.intersects(Rect2(-elevator.platform_size.x * 0.5, -elevator.platform_size.z * 0.5, elevator.platform_size.x, elevator.platform_size.z)):
				_fail("Aircraft 15 turned for the elevator while overlapping its opening")
				return
			await manager.call("_align_aircraft_forward_on_elevator", aircraft)
			await manager.call("_tow_recovery_aircraft_to_point", aircraft, elevator.to_global(local_target))
			if not bool(manager.call("_aircraft_footprint_inside_elevator", aircraft)):
				_fail("Aircraft 15 left the elevator edge after the actual align and tow")
				return
			if aircraft.global_transform.basis.z.dot(parked.basis.z) < 0.99:
				_fail("Aircraft 15 did not finish aligned with the elevator")
				return
	for number in [9, 10, 11, 12, 13]:
		var scene := load("res://Aircraft/Aircraft_%d.tscn" % number) as PackedScene
		var candidate := scene.instantiate() as RigidBody3D
		candidate.process_mode = Node.PROCESS_MODE_DISABLED
		carrier.add_child(candidate)
		var candidate_pose: Dictionary = manager.call("_get_safe_elevator_parking_pose", candidate, manager.elevator_pickup_marker.global_position)
		if not bool(candidate_pose.get("valid", false)):
			_fail("Aircraft %d did not get a safe helicopter elevator pose: %s" % [number, candidate_pose.get("reason", "unknown")])
			return
		candidate.queue_free()
		await process_frame
	var fixed_aircraft := (load("res://Aircraft/Aircraft_5.tscn") as PackedScene).instantiate() as RigidBody3D
	fixed_aircraft.process_mode = Node.PROCESS_MODE_DISABLED
	carrier.add_child(fixed_aircraft)
	var fixed_elevator := carrier.get_node("Elevator") as Node3D
	var fixed_marker := carrier.get_node("elevator_marker") as Node3D
	fixed_aircraft.global_position = fixed_marker.global_position + Vector3(0.0, -10.0, 0.0)
	if not bool(manager.call("_position_retrieved_aircraft_before_ascent", fixed_aircraft, fixed_elevator, fixed_marker)):
		_fail("Aircraft 5 could not be positioned before ascent")
		return
	var fixed_points: Array = manager.call("_get_aircraft_model_footprint_points", fixed_aircraft)
	var fixed_bounds: Rect2 = manager.call("_get_elevator_footprint_bounds", fixed_elevator, fixed_aircraft.global_transform, fixed_points)
	if (fixed_bounds.position + fixed_bounds.size * 0.5).length() > 0.05:
		_fail("Aircraft 5 was not centered before ascent")
		return
	fixed_aircraft.queue_free()
	await process_frame
	carrier.queue_free()
	print("[AircraftElevatorFootprintSmoketest] PASS")
	quit(0)


func _fail(reason: String) -> void:
	push_error("[AircraftElevatorFootprintSmoketest] %s" % reason)
	quit(1)
