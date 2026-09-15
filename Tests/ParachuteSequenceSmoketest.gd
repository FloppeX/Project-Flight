extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := Node3D.new()
	scene.name = "ParachuteSequenceSmoketest"
	root.add_child(scene)
	current_scene = scene

	var sequence_script := load("res://Aircraft/EjectionSequence.gd") as Script
	if sequence_script == null:
		_fail("ejection sequence script did not load")
		return
	var sequence := Node.new()
	sequence.set_script(sequence_script)
	scene.add_child(sequence)
	if not is_equal_approx(float(sequence.get("seat_separation_delay_s")), 3.0):
		_fail("default seat ride was not three seconds")
		return
	if not is_equal_approx(float(sequence.get("parachute_deploy_delay_s")), 1.0):
		_fail("default post-separation freefall was not one second")
		return

	var packed := load("res://Aircraft/Visuals/Parachute.tscn") as PackedScene
	if packed == null:
		_fail("parachute scene did not load")
		return
	var parachute := packed.instantiate() as Node3D
	scene.add_child(parachute)
	await process_frame
	var min_point := Vector3(INF, INF, INF)
	var max_point := Vector3(-INF, -INF, -INF)
	for child in parachute.get_node("Model").find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := child as MeshInstance3D
		var aabb := mesh_instance.get_aabb()
		for corner in [
			aabb.position,
			aabb.position + Vector3(aabb.size.x, 0.0, 0.0),
			aabb.position + Vector3(0.0, aabb.size.y, 0.0),
			aabb.position + Vector3(0.0, 0.0, aabb.size.z),
			aabb.position + Vector3(aabb.size.x, aabb.size.y, 0.0),
			aabb.position + Vector3(aabb.size.x, 0.0, aabb.size.z),
			aabb.position + Vector3(0.0, aabb.size.y, aabb.size.z),
			aabb.position + aabb.size,
		]:
			var point := parachute.to_local(mesh_instance.to_global(corner))
			min_point = min_point.min(point)
			max_point = max_point.max(point)
	var physics_origin := parachute.get_node_or_null("PhysicsOrigin") as Marker3D
	var pilot_mass := parachute.get_node_or_null("PilotMass") as Marker3D
	if physics_origin == null or absf(max_point.y - physics_origin.position.y) > 0.5:
		_fail("canopy force marker y=%s did not match mesh top=%s" % [physics_origin.position.y if physics_origin != null else NAN, max_point.y])
		return
	if pilot_mass == null or physics_origin.position.y - pilot_mass.position.y < 5.0:
		_fail("pilot mass point was not suspended below the canopy origin")
		return
	var measured_origin_y := physics_origin.position.y
	parachute.free()

	var pilot_body := RigidBody3D.new()
	pilot_body.name = "TestPilotBody"
	pilot_body.collision_layer = 0
	pilot_body.collision_mask = 0
	scene.add_child(pilot_body)
	pilot_body.global_position = Vector3(0, 1000, 0)
	pilot_body.linear_velocity = Vector3(3, 12, 0)
	var seat := Node3D.new()
	seat.name = "EjectionSeat"
	pilot_body.add_child(seat)
	var pilot := Node3D.new()
	pilot.name = "CockpitPilot"
	pilot_body.add_child(pilot)
	sequence.set("_pilot_body", pilot_body)
	sequence.set("seat_burn_duration_s", 0.01)
	sequence.set("seat_separation_delay_s", 0.02)
	sequence.set("parachute_deploy_delay_s", 0.15)
	sequence.call("_schedule_seat_separation")

	await create_timer(0.06).timeout
	if not bool(sequence.get("_seat_separated")) or pilot_body.has_node("EjectionSeat"):
		_fail("seat did not separate after the seat-ride timer")
		return
	if pilot_body.has_node("Parachute"):
		_fail("parachute opened without the post-separation delay")
		return

	await create_timer(0.16).timeout
	if bool(sequence.get("_parachute_deployed")) or pilot_body.linear_velocity.y <= 0.0:
		_fail("canopy must remain packed while pilot is still rising after the minimum delay")
		return
	await create_timer(1.5).timeout
	var deployed_parachute := pilot_body.get_node_or_null("Parachute") as Node3D
	if deployed_parachute == null or not bool(sequence.get("_parachute_deployed")):
		_fail("parachute did not deploy after the freefall timer")
		return
	var deployed_origin := deployed_parachute.get_node_or_null("PhysicsOrigin") as Marker3D
	if deployed_origin == null or pilot_body.to_local(deployed_origin.global_position).y < 5.0:
		_fail("canopy force point was not above the body")
		return
	var ground_reference: Vector3 = sequence.call("_get_pilot_ground_reference_position")
	if not ground_reference.is_equal_approx(pilot.global_position):
		_fail("landing checks did not follow the pilot below the rebased origin")
		return
	if pilot_body.center_of_mass_mode != RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM \
			or pilot_body.center_of_mass.length() > 0.01:
		_fail("pilot center of mass was not at the body origin")
		return
	var deployed_mass := deployed_parachute.get_node("PilotMass") as Node3D
	if deployed_mass.global_position.distance_to(pilot_body.global_position) > 0.05:
		_fail("body origin does not coincide with the pilot torso mass marker")
		return
	var pilot_collision := pilot_body.get_node_or_null("PilotCollision") as CollisionShape3D
	if pilot_collision == null:
		_fail("pilot collision shape was not attached directly to the rigid body")
		return
	await create_timer(0.8).timeout
	if pilot_body.angular_velocity.length() < 0.001:
		_fail("canopy force did not produce pendulum angular motion")
		return
	var pilot_offset_world := pilot.global_position - pilot_body.global_position
	if Vector2(pilot_offset_world.x, pilot_offset_world.z).length() < 0.01:
		_fail("pilot did not swing laterally beneath the canopy origin")
		return

	sequence.set("wind_velocity", Vector3.ZERO)
	sequence.set("wind_gust_speed_mps", 0.0)
	sequence.set("wind_gust_impulse_n", 0.0)
	# A rising open canopy must not generate upward drag or sustained ascent.
	pilot_body.linear_velocity = Vector3(0, 4, 0)
	pilot_body.angular_velocity = Vector3.ZERO
	await create_timer(0.35).timeout
	if pilot_body.linear_velocity.y >= 2.0:
		_fail("rising canopy did not lose upward speed under gravity")
		return
	await create_timer(6.0).timeout
	if pilot_body.linear_velocity.y >= -3.0 or pilot_body.linear_velocity.y < -9.0:
		_fail("open canopy did not settle into a bounded downward descent: %s" % pilot_body.linear_velocity)
		return
	# Displace the suspension, then release it without wind. It should cross back
	# through vertical and decay, rather than remaining tilted or gaining energy.
	pilot_body.rotation = Vector3(0, 0, deg_to_rad(12.0))
	pilot_body.angular_velocity = Vector3.ZERO
	pilot_body.linear_velocity = Vector3(0, -5.5, 0)
	var minimum_swing := 1.0
	var maximum_swing := 0.0
	for sample in range(60):
		await create_timer(0.1).timeout
		var swing := atan2(pilot_body.global_basis.x.y, pilot_body.global_basis.y.y)
		minimum_swing = minf(minimum_swing, swing)
		maximum_swing = maxf(maximum_swing, absf(swing))
	if minimum_swing >= -deg_to_rad(1.0) or maximum_swing > deg_to_rad(13.0) or absf(pilot_body.rotation.z) > deg_to_rad(8.0):
		_fail("suspension did not restore and damp: min=%.2f max=%.2f final=%.2f" % [rad_to_deg(minimum_swing), rad_to_deg(maximum_swing), rad_to_deg(pilot_body.rotation.z)])
		return
	print("[ParachutePendulum] PASS min_deg=%.2f max_deg=%.2f final_deg=%.2f vy=%.2f" % [rad_to_deg(minimum_swing), rad_to_deg(maximum_swing), rad_to_deg(pilot_body.rotation.z), pilot_body.linear_velocity.y])
	print("[ParachuteSequenceSmoketest] PASS seat=3.0s freefall=1.0s top=%.3f origin=%.3f com=%s swing=%.3f offset=%.3f" % [
		max_point.y,
		measured_origin_y,
		str(pilot_body.center_of_mass),
		pilot_body.angular_velocity.length(),
		Vector2(pilot_offset_world.x, pilot_offset_world.z).length(),
	])
	scene.free()
	quit(0)


func _fail(reason: String) -> void:
	push_error("[ParachuteSequenceSmoketest] FAIL %s" % reason)
	quit(1)
