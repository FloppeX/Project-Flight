extends SceneTree


var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var test_root := Node3D.new()
	root.add_child(test_root)
	current_scene = test_root

	var carrier_scene := load("res://LandCarrier/LandCarrier2.tscn") as PackedScene
	_expect(carrier_scene != null, "LandCarrier2 scene did not load")
	if carrier_scene == null:
		_finish()
		return

	var carrier := carrier_scene.instantiate() as Node3D
	carrier.process_mode = Node.PROCESS_MODE_DISABLED
	test_root.add_child(carrier)
	await process_frame

	var walk_area := carrier.get_node_or_null("CommanderWalkArea")
	var commander := carrier.get_node_or_null("Commander") as CharacterBody3D
	var elevator := carrier.get_node_or_null("CarrierModel/Superstructure elevator") as MeshInstance3D
	var human := carrier.get_node_or_null("CarrierModel/human") as MeshInstance3D
	_expect(walk_area != null, "CommanderWalkArea is missing")
	_expect(commander != null, "Commander is missing")
	_expect(elevator != null, "bridge elevator mesh is missing")
	if walk_area == null or commander == null or elevator == null:
		_finish()
		return
	# This suite tests the legacy two-deck polygon/railing controller with physics
	# disabled. The mesh-backed interior controller requires active colliders and
	# is covered by CarrierStairWalkingSmoketest and carrier_interior/game_smoke.
	walk_area.set("_interior_walking", null)

	var lower_y := float(walk_area.get("_lower_floor_y"))
	var upper_y := float(walk_area.get("_upper_floor_y"))
	var lower_elevator_top_y := float(walk_area.get("_elevator_top_y"))
	var expected_travel := upper_y - lower_elevator_top_y
	var resolved_travel := float(walk_area.call("get_resolved_elevator_travel_m"))
	_expect(
		is_equal_approx(resolved_travel, expected_travel),
		"derived elevator travel %.4f did not match geometry %.4f"
			% [resolved_travel, expected_travel]
	)
	_expect(
		resolved_travel > 4.4 and resolved_travel < 4.6,
		"scaled bridge produced unexpected elevator travel %.4f" % resolved_travel
	)

	var authored_start := commander.position
	var lower_triangles := walk_area.get("_lower_triangles") as Array[PackedVector2Array]
	var human_position := carrier.to_local(human.global_position) if human != null else authored_start
	human_position.y = lower_y
	var human_walkable := human != null and bool(walk_area.call(
		"_is_walkable_floor_position",
		Vector2(human_position.x, human_position.z),
		lower_triangles
	))
	var expected_spawn := human_position if human_walkable else authored_start
	var spawn := walk_area.call(
		"constrain_commander_position",
		commander.position,
		commander.position
	) as Vector3
	_expect(
		Vector2(spawn.x, spawn.z).distance_to(Vector2(expected_spawn.x, expected_spawn.z)) < 0.01,
		"Commander did not use the valid imported marker or its valid authored fallback"
	)
	_expect(is_equal_approx(spawn.y, lower_y), "Commander spawn did not use lower floor height")
	print("[CommanderWalkAreaScaleSmoketest] geometry human_walkable=%s spawn=%s travel_m=%.4f lower_y=%.4f upper_y=%.4f" % [
		str(human_walkable), str(spawn), resolved_travel, lower_y, upper_y,
	])

	commander.position = spawn
	var elevator_min := walk_area.get("_elevator_min_xz") as Vector2
	var elevator_max := walk_area.get("_elevator_max_xz") as Vector2
	var elevator_center := (elevator_min + elevator_max) * 0.5
	for unused_step in range(600):
		var current_xz := Vector2(commander.position.x, commander.position.z)
		if current_xz.distance_to(elevator_center) < 0.05:
			break
		var next_xz := current_xz.move_toward(elevator_center, 0.05)
		var desired := Vector3(next_xz.x, commander.position.y, next_xz.y)
		var constrained := walk_area.call(
			"constrain_commander_position",
			commander.position,
			desired
		) as Vector3
		if constrained.distance_squared_to(commander.position) < 0.000001:
			break
		commander.position = constrained
	_expect(
		Vector2(commander.position.x, commander.position.z).distance_to(elevator_center) < 0.1,
		"scaled lower-floor walk surface did not connect the Commander spawn to the elevator"
	)
	_expect(
		bool(walk_area.call("_is_safely_on_elevator", commander.position)),
		"Commander could not safely board the scaled elevator footprint"
	)
	# A rider near the rear corner must arrive inside the new upper railing,
	# with room to walk out; the old center-only margin allowed body overlap.
	commander.position.x = elevator_min.x + 0.21
	commander.position.z = elevator_min.y + 0.21
	walk_area.call("_begin_elevator_trip")
	for unused_step in range(600):
		if not bool(walk_area.get("_elevator_moving")):
			break
		walk_area.call("_update_elevator_motion", 1.0 / 60.0)
	var final_elevator_top_y := float(walk_area.get("_elevator_top_y"))
	_expect(not bool(walk_area.get("_elevator_moving")), "bridge elevator did not finish its ascent")
	_expect(
		absf(final_elevator_top_y - upper_y) < 0.001,
		"bridge elevator stopped %.4f m away from upper floor"
			% absf(final_elevator_top_y - upper_y)
	)
	_expect(
		absf(commander.position.y - upper_y) < 0.001,
		"Commander did not remain on the bridge elevator platform"
	)
	var upper_center := Vector3(elevator_center.x, upper_y, elevator_center.y)
	var clear_arrival: Vector3 = walk_area.call("constrain_commander_position", commander.position, upper_center)
	_expect(clear_arrival.distance_to(upper_center) < 0.01, "rider arrived stuck inside an upper railing")
	await _test_railing_access(carrier, walk_area, commander, elevator_center, upper_y)

	walk_area.call("_begin_elevator_trip")
	for unused_step in range(600):
		if not bool(walk_area.get("_elevator_moving")):
			break
		walk_area.call("_update_elevator_motion", 1.0 / 60.0)
	var returned_elevator_top_y := float(walk_area.get("_elevator_top_y"))
	_expect(not bool(walk_area.get("_elevator_moving")), "bridge elevator did not finish its descent")
	_expect(
		absf(returned_elevator_top_y - lower_elevator_top_y) < 0.001,
		"bridge elevator did not return to its lower height"
	)
	_expect(
		absf(commander.position.y - lower_elevator_top_y) < 0.001,
		"Commander did not remain on the descending bridge elevator"
	)

	_finish()


func _test_railing_access(
	carrier: Node3D,
	walk_area: Node,
	commander: CharacterBody3D,
	elevator_center: Vector2,
	upper_y: float
) -> void:
	var railing := carrier.get_node_or_null("AirOpsElevatorRailingCollision") as StaticBody3D
	_expect(railing != null, "upper landing railing has no physics body")
	if railing == null:
		return
	# The surrounding carrier is frozen by this test. Keep these bodies active
	# so the physics checks exercise the same colliders as normal gameplay.
	railing.process_mode = Node.PROCESS_MODE_ALWAYS
	await physics_frame
	await physics_frame
	var center := Vector3(elevator_center.x, upper_y, elevator_center.y)
	var original_transform := carrier.transform
	# The walking sweep uses carrier-local positions. Verify the same access after
	# relocation/rotation, as carriers move and the world periodically rebases.
	for pose in [original_transform, Transform3D(Basis(Vector3.UP, 0.7), Vector3(180, 20, -250))]:
		carrier.transform = pose
		carrier.force_update_transform()
		for direction in [Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD]:
			var outside: Vector3 = center + direction * 1.5
			var result: Vector3 = walk_area.call("constrain_commander_position", outside, center)
			_expect(result.distance_to(outside) < 0.01, "could board through closed railing side %s" % direction)
			result = walk_area.call("constrain_commander_position", center, outside)
			_expect(result.distance_to(center) < 0.01, "could leave through closed railing side %s" % direction)
			var far_side: Vector3 = center - direction * 1.5
			result = walk_area.call("constrain_commander_position", outside, far_side)
			_expect(result.distance_to(outside) < 0.01, "long movement tunneled through a railing")

		var entrance := center + Vector3.BACK * 1.5
		var entry: Vector3 = walk_area.call("constrain_commander_position", entrance, center)
		_expect(entry.distance_to(center) < 0.01, "open side prevented boarding")
		var exit_position: Vector3 = walk_area.call("constrain_commander_position", center, entrance)
		_expect(exit_position.distance_to(entrance) < 0.01, "open side prevented leaving")
		var outside_right := center + Vector3.RIGHT * 1.5
		var slide: Vector3 = walk_area.call("constrain_commander_position", outside_right, center + Vector3.BACK * 0.1)
		_expect(is_equal_approx(slide.x, outside_right.x) and slide.z > outside_right.z + 0.09,
			"diagonal movement did not slide along the railing")

	carrier.transform = original_transform
	carrier.force_update_transform()
	await physics_frame
	await physics_frame
	var space := carrier.get_world_3d().direct_space_state
	for direction in [Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK]:
		var from_local: Vector3 = center + direction * 1.5 + Vector3.UP * 0.6
		var to_local := center + Vector3.UP * 0.6
		var query := PhysicsRayQueryParameters3D.create(carrier.to_global(from_local), carrier.to_global(to_local), 1)
		query.exclude = [commander.get_rid()]
		var hit := space.intersect_ray(query)
		if direction == Vector3.BACK:
			_expect(hit.is_empty(), "physics collision blocks the authored open side")
		else:
			_expect(hit.get("collider") == railing, "railing side %s has no matching physical collider" % direction)
	commander.position = center


func _finish() -> void:
	if _failures.is_empty():
		print("[CommanderWalkAreaScaleSmoketest] PASS scaled_spawn=true walk_route=true boarding=true derived_travel=true ascent=true descent=true rider_alignment=true railing_three_sides=true open_side_access=true swept_collision=true translated_rotated_carrier=true")
		quit(0)
		return
	for failure in _failures:
		push_error("[CommanderWalkAreaScaleSmoketest] FAIL %s" % failure)
	quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
