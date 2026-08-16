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
	for child in parachute.find_children("*", "MeshInstance3D", true, false):
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
	if physics_origin == null or absf(max_point.y - physics_origin.position.y) > 0.1:
		_fail("physics origin was not close to the canopy top")
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
	var deployed_parachute := pilot_body.get_node_or_null("Parachute") as Node3D
	if deployed_parachute == null or not bool(sequence.get("_parachute_deployed")):
		_fail("parachute did not deploy after the freefall timer")
		return
	var deployed_origin := deployed_parachute.get_node_or_null("PhysicsOrigin") as Marker3D
	if deployed_origin == null or pilot_body.to_local(deployed_origin.global_position).length() > 0.05:
		_fail("rigid-body origin was not rebased to the canopy top")
		return
	var ground_reference: Vector3 = sequence.call("_get_pilot_ground_reference_position")
	if not ground_reference.is_equal_approx(pilot.global_position):
		_fail("landing checks did not follow the pilot below the rebased origin")
		return
	if pilot_body.center_of_mass_mode != RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM \
			or pilot_body.center_of_mass.y > -5.0:
		_fail("pilot center of mass was not below the canopy origin")
		return
	var pilot_collision := pilot_body.get_node_or_null("PilotCollision") as CollisionShape3D
	if pilot_collision == null:
		_fail("pilot collision shape was not attached directly to the rigid body")
		return
	await create_timer(0.2).timeout
	if pilot_body.angular_velocity.length() < 0.001:
		_fail("canopy force did not produce pendulum angular motion")
		return
	var pilot_offset_world := pilot.global_position - pilot_body.global_position
	if Vector2(pilot_offset_world.x, pilot_offset_world.z).length() < 0.01:
		_fail("pilot did not swing laterally beneath the canopy origin")
		return

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
