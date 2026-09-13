extends SceneTree
## Read-only production audit: synthetic CPU/projection probes, not a gameplay benchmark.

class MeasuredRock:
	extends RockStream
	var evaluations := 0
	var evaluation_us := 0
	var support_us := 0
	var snap_us := 0
	func _evaluate_rock_cell(cell: Vector2i) -> Variant:
		var t := Time.get_ticks_usec()
		var value: Variant = super._evaluate_rock_cell(cell)
		evaluation_us += Time.get_ticks_usec() - t
		evaluations += 1
		return value
	func _has_stable_terrain_support(h: float, x: float, z: float, s: float) -> bool:
		var t := Time.get_ticks_usec()
		var value := super._has_stable_terrain_support(h, x, z, s)
		support_us += Time.get_ticks_usec() - t
		return value
	func _get_collision_surface_height(x: float, z: float, h: float) -> float:
		var t := Time.get_ticks_usec()
		var value := super._get_collision_surface_height(x, z, h)
		snap_us += Time.get_ticks_usec() - t
		return value

var results := {"rock": [], "vehicles": [], "limits": "Synthetic CPU probes; synchronous rock helper with snapping disabled; no rendered or busy-world raycast timings."}
var world: Node3D
var camera: Camera3D

func _initialize() -> void: call_deferred("_run")

func _run() -> void:
	for child in root.get_children(): child.process_mode = Node.PROCESS_MODE_DISABLED
	root.get_node("SaveGameManager").set("autosave_enabled", false)
	world = Node3D.new()
	root.add_child(world)
	camera = Camera3D.new()
	world.add_child(camera)
	camera.position = Vector3(0, 102, 0)
	camera.current = true
	await physics_frame
	await process_frame
	_probe_rocks()
	var floor_body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(3000, 1, 3000)
	collision.shape = shape
	floor_body.add_child(collision)
	floor_body.position = Vector3(0, 99.5, 0)
	world.add_child(floor_body)
	await physics_frame
	await process_frame
	var hit := world.get_world_3d().direct_space_state.intersect_ray(
		PhysicsRayQueryParameters3D.create(Vector3(0, 110, -100), Vector3(0, 90, -100)))
	if hit.is_empty():
		push_error("Diagnostic floor is not registered with physics; refusing invalid measurements")
		quit(1)
		return
	for path in ["GroundVehicle", "vehicle_enemy_buggy", "vehicle_enemy_pickup", "vehicle_enemy_battle_bus", "vehicle_friendly_light"]:
		await _probe_vehicle("res://GroundVehicle/%s.tscn" % path)
	var output := FileAccess.open("user://rock_wheel_diagnostic_shared_support.json", FileAccess.WRITE)
	output.store_string(JSON.stringify(results, "\t"))
	output.close()
	print("ROCK_WHEEL_DIAGNOSTIC ", JSON.stringify(results))
	world.free()
	quit()

func _probe_rocks() -> void:
	var terrain := (load("res://Environment/LowPolyTerrainPrototype.tscn") as PackedScene).instantiate() as LowPolyTerrain
	terrain.generate_on_ready = false
	terrain.use_streaming = false
	terrain.cell_size_m = 36.0
	terrain.seed = 22551
	terrain.plateau_height_m = 500.0
	terrain.base_height_offset_m = 220.0
	terrain.position.y = 62.0
	world.add_child(terrain)
	var rock := MeasuredRock.new()
	world.add_child(rock)
	rock.set_process(false)
	rock.snap_to_collision_surface = false # Geometry equivalence; no streamed collision in this fixture.
	rock.set("_terrain", terrain)
	for center in [Vector3.ZERO, Vector3(50, 0, 0), Vector3(8000, 0, 4000)]:
		_rock_sample(rock, center, "cold" if center == Vector3.ZERO else "edge" if center.x == 50 else "transfer")
	var before: Dictionary = rock.get("_cell_cache").duplicate()
	var offset := Vector3(8123.5, 0, 4100.25)
	terrain.position -= offset
	rock.position -= offset
	rock.apply_origin_shift(offset)
	_rock_sample(rock, Vector3(8000, 0, 4000) - offset, "same_place_after_origin_shift")
	var old_positions: Array[Vector3] = []
	for value in before.values():
		if value is Transform3D: old_positions.append(value.origin)
	var unchanged := 0
	for value in rock.get("_cell_cache").values():
		if value is Transform3D:
			for old in old_positions:
				if value.origin.distance_to(old) < 0.01:
					unchanged += 1
					break
	results["origin_rock_positions_preserved"] = unchanged
	results["origin_rock_previous_count"] = old_positions.size()
	rock.free()

func _rock_sample(rock: MeasuredRock, center: Vector3, label_: String) -> void:
	rock.evaluations = 0
	rock.evaluation_us = 0
	rock.support_us = 0
	rock.snap_us = 0
	var t := Time.get_ticks_usec()
	rock.call("_rebuild", center)
	var total := Time.get_ticks_usec() - t
	var row: Dictionary = rock.get_streaming_diagnostics()
	row.merge({"label": label_, "total_ms": total / 1000.0, "candidate_ms": rock.evaluation_us / 1000.0,
		"support_ms_nested": rock.support_us / 1000.0, "snap_ms_nested": rock.snap_us / 1000.0})
	results.rock.append(row)

func _probe_vehicle(path: String) -> void:
	var vehicle := (load(path) as PackedScene).instantiate() as CharacterBody3D
	vehicle.position = Vector3(0, 101, -600)
	world.add_child(vehicle)
	_stop_processing(vehicle)
	await physics_frame
	await process_frame
	vehicle.set("_cached_camera_visible", true)
	vehicle.call("_update_mesh_lod", 1.0)
	var wheels: Array = vehicle.get("_all_wheel_nodes")
	var details: Array = []
	for distance in [100.0, 600.0, 900.0]:
		vehicle.global_position = Vector3(0, 101, -distance)
		vehicle.global_basis = Basis.IDENTITY
		vehicle.set("_spring_initialized", false)
		vehicle.set("_suspension_probe_ready", false)
		var started := Time.get_ticks_usec()
		for _step in range(600): vehicle.call("_update_wheel_visuals", 1.0 / 60.0, true)
		var elapsed := Time.get_ticks_usec() - started
		details.append({"distance_m": distance, "update_mean_us": elapsed / 600.0,
			"detailed": vehicle.call("_should_use_detailed_suspension", 0.0),
			"wheel_range_m": vehicle.get("wheel_mesh_visibility_distance_m")})
	vehicle.global_position = Vector3(0, 101, -100)
	vehicle.global_basis = Basis.IDENTITY
	var started := Time.get_ticks_usec()
	for _i in range(300): vehicle.call("_refresh_suspension_targets")
	var refresh_mean := (Time.get_ticks_usec() - started) / 300.0
	var nominal: Array = vehicle.get("_wheel_nominal_positions")
	var contacts: Array = vehicle.get("_wheel_contact_nodes")
	var cached_contacts: Array = vehicle.get("_wheel_contact_local_positions")
	var cached_corner_before: Array = vehicle.get("_cached_corner_target_ys").duplicate()
	vehicle.call("apply_origin_shift", Vector3(4000, 0, 0))
	var cache_stays_ready: bool = vehicle.get("_suspension_probe_ready")
	var cache_unchanged: bool = vehicle.get("_cached_corner_target_ys") == cached_corner_before
	var max_contact_transform_error := 0.0
	for i in wheels.size():
		wheels[i].position = nominal[i]
		if contacts[i] != null:
			max_contact_transform_error = maxf(max_contact_transform_error,
				vehicle.to_local(contacts[i].global_position).distance_to(cached_contacts[i]))
	# A deliberately tilted chassis over a flat collision floor isolates the
	# vertical-ray versus local suspension-axis projection (not steady driving).
	vehicle.global_position = Vector3(0, 102, -100)
	vehicle.global_basis = Basis.from_euler(Vector3(deg_to_rad(30.0), 0, 0))
	vehicle.call("_refresh_suspension_targets")
	var targets: Array = vehicle.get("_cached_wheel_target_ys")
	var residual := 0.0
	var travel := 0.0
	for i in wheels.size():
		travel = maxf(travel, absf(targets[i] - nominal[i].y))
		wheels[i].position.y = targets[i]
		if contacts[i] != null: residual = maxf(residual, absf(contacts[i].global_position.y - 100.0))
	vehicle.set("wheel_max_extension_m", 10.0)
	vehicle.set("wheel_max_compression_m", 10.0)
	vehicle.call("_refresh_suspension_targets")
	var uncapped_targets: Array = vehicle.get("_cached_wheel_target_ys")
	var projection_error := 0.0
	for i in wheels.size():
		wheels[i].position.y = uncapped_targets[i]
		if contacts[i] != null: projection_error = maxf(projection_error, absf(contacts[i].global_position.y - 100.0))
	var right_front := vehicle.get_node_or_null("wheel_right_1") as Node3D
	var authored_yaw := right_front.rotation.y if right_front != null else 0.0
	vehicle.set("_drive_command_has_destination", true)
	vehicle.set("_drive_command_steer", 0.0)
	vehicle.set("_drive_command_throttle", 0.0)
	vehicle.call("_apply_cached_drive_motion", 0.0, false)
	var commanded_yaw := right_front.rotation.y if right_front != null else 0.0
	var mesh_count := 0
	var surfaces := 0
	for wheel in wheels:
		for mesh_node in wheel.find_children("*", "MeshInstance3D", true, false):
			mesh_count += 1
			if mesh_node.mesh != null: surfaces += mesh_node.mesh.get_surface_count()
	results.vehicles.append({"scene": path, "wheels": wheels.size(), "wheel_meshes": mesh_count,
		"wheel_surfaces": surfaces, "lod": details, "probe_refresh_mean_us": refresh_mean,
		"contact_transform_error_m": max_contact_transform_error,
		"tilted_capped_contact_residual_m": residual, "tilted_capped_wheel_travel_m": travel,
		"uncapped_projection_error_m": projection_error,
		"origin_keeps_ready": cache_stays_ready, "origin_keeps_corner_cache": cache_unchanged,
		"right_front_authored_yaw_deg": rad_to_deg(authored_yaw), "right_front_straight_yaw_deg": rad_to_deg(commanded_yaw)})
	vehicle.free()

func _stop_processing(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child in node.get_children(): _stop_processing(child)
