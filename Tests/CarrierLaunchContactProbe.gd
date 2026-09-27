extends Node3D

var aircraft: RigidBody3D
var carrier: Node3D
var catapult: Node3D
var tick := 0
var failures: Array[String] = []
var aircraft_number := 5
var release_observation_ticks := 75

func _ready() -> void:
	call_deferred("run_probe")

func run_probe() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--aircraft="): aircraft_number = int(argument.get_slice("=", 1))
	carrier = load("res://LandCarrier/LandCarrier2.tscn").instantiate()
	add_child(carrier)
	await get_tree().process_frame
	await get_tree().process_frame
	catapult = carrier.get_node("Catapult1")
	catapult.debug_enabled = true
	var manager = carrier.get_node("FlightDeckManager")
	var scene_path := "res://Aircraft/Aircraft_%d.tscn" % aircraft_number
	var packed: PackedScene = load(scene_path)
	manager._queue_aircraft_scene_for_retrieval("Aircraft_%d" % aircraft_number, packed, scene_path)
	var deadline := Time.get_ticks_msec() + 90000
	var released_ticks := 0
	var release_speed := 0.0
	var minimum_exit_speed := INF
	var maximum_exit_vertical_speed := 0.0
	var walking_collision_contact := false
	while Time.get_ticks_msec() < deadline:
		await get_tree().physics_frame
		if not is_instance_valid(aircraft):
			for group in ["aircraft", "ai_aircraft"]:
				for node in get_tree().get_nodes_in_group(group):
					if node is RigidBody3D and str(node.name).begins_with("Aircraft_%d" % aircraft_number):
						aircraft = node
						aircraft.max_contacts_reported = 32
						aircraft.debug_damage = true
			continue
		var local := carrier.to_local(aircraft.global_position)
		if local.z < 50.0: continue
		tick += 1
		var relative_velocity := carrier.global_basis.inverse() * aircraft.linear_velocity
		if tick % 3 == 0:
			var nose = catapult._find_nose_gear_collider(aircraft)
			var error: Vector3 = catapult.shuttle.global_position - nose.global_position if is_instance_valid(nose) else Vector3.ZERO
			print("LAUNCH_SAMPLE tick=%d local=%s velocity=%s pitch=%.2f angular=%s launching=%s tow_error=%s shuttle_velocity=%s" % [tick, local, relative_velocity, rad_to_deg((carrier.global_basis.inverse() * aircraft.global_basis).get_euler().x), aircraft.angular_velocity, catapult._launching, error, catapult._actual_shuttle_velocity])
		var state := PhysicsServer3D.body_get_direct_state(aircraft.get_rid())
		if state != null:
			for i in range(state.get_contact_count()):
				var other: Object = state.get_contact_collider_object(i)
				if other is Node and other.name == "FlightDeckWalkingCollision": walking_collision_contact = true
				print("LAUNCH_CONTACT tick=%d self=%s other=%s shape=%s pos=%s normal=%s impulse=%s" % [tick, shape_name(aircraft, state.get_contact_local_shape(i)), other.name if other is Node else str(other), shape_name(other, state.get_contact_collider_shape(i)), state.get_contact_local_position(i), state.get_contact_local_normal(i), state.get_contact_impulse(i)])
		if released_ticks > 0 or aircraft.has_meta("carrier_launch_contact_grace_until_msec"):
			released_ticks += 1
			if released_ticks == 1: release_speed = relative_velocity.z
			if released_ticks <= 30:
				minimum_exit_speed = minf(minimum_exit_speed, relative_velocity.z)
				maximum_exit_vertical_speed = maxf(maximum_exit_vertical_speed, absf(relative_velocity.y))
		if released_ticks >= release_observation_ticks: break
	check(released_ticks >= release_observation_ticks, "aircraft must release and remain alive")
	check(minimum_exit_speed >= release_speed * 0.85, "bow exit must not lose more than 15 percent forward speed")
	check(maximum_exit_vertical_speed < 8.0, "bow exit must not deliver a vertical kick")
	check(not walking_collision_contact, "aircraft must not contact the walking-only deck")
	var walk_body := carrier.get_node("CarrierModel/FlightDeckWalkingCollision") as PhysicsBody3D
	var island_body := carrier.get_node("CarrierModel/InteriorSurfaceCollision") as PhysicsBody3D
	check(walk_body.collision_layer == 1 << 20, "walking deck stays on dedicated layer")
	check((island_body.collision_layer & 1) != 0, "island retains physical collision")
	var query := PhysicsRayQueryParameters3D.create(carrier.to_global(Vector3(-8, 3, 60)), carrier.to_global(Vector3(-8, -1, 60)), 1 << 20)
	query.hit_back_faces = true
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	check(not hit.is_empty() and hit.collider == walk_body, "commander walking query still finds flight deck")
	print("LAUNCH_CONTACT_PROBE_%s aircraft=%d release=%.2f min_exit=%.2f max_vertical=%.2f released_ticks=%d failures=%s" % ["PASS" if failures.is_empty() else "FAIL", aircraft_number, release_speed, minimum_exit_speed, maximum_exit_vertical_speed, released_ticks, failures])
	if is_instance_valid(aircraft): aircraft.queue_free()
	carrier.queue_free()
	for frame in 4: await get_tree().process_frame
	get_tree().quit(0 if failures.is_empty() else 1)

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func shape_name(body: Object, index: int) -> String:
	if not body is CollisionObject3D or index < 0: return str(index)
	var owner_id: int = body.shape_find_owner(index)
	var owner: Object = body.shape_owner_get_owner(owner_id)
	return str(owner.name) if owner is Node else str(index)
