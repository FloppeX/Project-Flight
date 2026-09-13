extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var carrier: Node3D = load("res://LandCarrier/LandCarrier2.tscn").instantiate()
	# Reproduce the runtime failure mode before the scene enters the tree: both
	# legacy authored references point at the roof and Commander physics is not
	# running, so movement cannot be relied on to repair the spawn.
	var commander := carrier.get_node("Commander") as CharacterBody3D
	var reference: Node3D = carrier.get_node("CarrierModel/human")
	var model := carrier.get_node("CarrierModel") as Node3D
	var rooftop_position := Vector3(-19.5, 15.0, -4.0)
	commander.position = rooftop_position
	reference.position = model.transform.affine_inverse() * rooftop_position
	commander.set_physics_process(false)
	carrier.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(carrier)
	current_scene = carrier
	disable_logic(carrier)
	carrier.process_mode = Node.PROCESS_MODE_INHERIT
	await physics_frame
	await physics_frame
	var walk := carrier.get_node("CommanderWalkArea")
	assert(walk._interior_walking != null, "Main carrier uses interior movement")
	assert(walk._initialized, "Walk area initialized")
	assert(absf(walk.get_resolved_elevator_travel_m() - 4.49) < 0.03, "Elevator travel preserved")
	var marker: Node3D = carrier.get_node("CommanderBridgeSpawn")
	assert(Vector2(commander.position.x, commander.position.z).distance_to(Vector2(marker.position.x, marker.position.z)) < 0.01, "Bridge initialization did not override rooftop references")
	assert(absf(commander.position.y - walk._lower_floor_y) < 0.03, "Commander starts on bridge floor")
	assert(not commander.is_physics_processing(), "Regression setup unexpectedly enabled Commander physics")
	var head := commander.position + Vector3.UP * 1.8
	var roof_query := PhysicsRayQueryParameters3D.create(carrier.to_global(head), carrier.to_global(head + Vector3.UP * 2.0), 1 << 20)
	roof_query.hit_back_faces = true
	assert(not carrier.get_world_3d().direct_space_state.intersect_ray(roof_query).is_empty(), "Commander starts inside below bridge ceiling")
	for direction in [Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK]:
		var enclosure_query := PhysicsRayQueryParameters3D.create(
			carrier.to_global(head),
			carrier.to_global(head + direction * 6.0),
			1 << 20
		)
		enclosure_query.hit_back_faces = true
		var enclosure_hit := carrier.get_world_3d().direct_space_state.intersect_ray(enclosure_query)
		assert(not enclosure_hit.is_empty(), "Commander spawn is not enclosed toward %s" % direction)
		var enclosure_distance := head.distance_to(carrier.to_local(enclosure_hit.position))
		assert(enclosure_distance > 1.5, "Commander spawn is still against an exterior threshold toward %s" % direction)
	var body_query := PhysicsShapeQueryParameters3D.new()
	body_query.shape = walk._interior_walking.capsule
	body_query.collision_mask = 1 << 20
	body_query.transform = carrier.global_transform * Transform3D(Basis.IDENTITY, commander.position + Vector3.UP * 1.05)
	assert(carrier.get_world_3d().direct_space_state.intersect_shape(body_query, 1).is_empty(), "Bridge spawn has body clearance")
	print("COMMANDER_BRIDGE_SPAWN PASS ", commander.position)
	for door in carrier.get_node("CarrierModel").get_children():
		if door.get_script() == load("res://LandCarrier/CarrierSlidingDoor.gd"):
			door.openness = 1.0
			door._apply_pose()
	await physics_frame
	await physics_frame
	var center: Vector2 = (walk._elevator_min_xz + walk._elevator_max_xz) * 0.5
	walk._initial_position_resolved = true
	commander.position = Vector3(center.x, walk._lower_floor_y, -1.6)
	var target := Vector3(center.x, walk._lower_floor_y, center.y)
	print("GAME_TRANSFORM ",carrier.global_transform, " MODEL=",carrier.get_node("CarrierModel").global_transform)
	for i in 150:
		commander.position = walk.constrain_commander_position(commander.position, commander.position.move_toward(target, 0.05))
	print("ELEVATOR_APPROACH ", commander.position, " target=", target)
	assert(commander.position.distance_to(target) < 0.08, "Corridor connects to elevator")
	walk._begin_elevator_trip()
	for i in 300:
		if walk._elevator_moving:
			walk._update_elevator_motion(1.0 / 60.0)
	await physics_frame
	await physics_frame
	assert(absf(commander.position.y - walk._upper_floor_y) < 0.01, "Elevator carries commander upstairs")
	var exit := Vector3(center.x, walk._upper_floor_y, center.y + 2.0)
	for i in 60:
		commander.position = walk.constrain_commander_position(commander.position, commander.position.move_toward(exit, 0.05))
	assert(commander.position.distance_to(exit) < 0.08, "Observation room exit clear")
	print("CARRIER_INTERIOR_GAME_SMOKE PASS")
	carrier.queue_free()
	await process_frame
	quit()

func disable_logic(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child in node.get_children():
		disable_logic(child)
