extends SceneTree

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run")


func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)


func model_transform(node: Node3D) -> Transform3D:
	var result := node.transform
	var parent := node.get_parent()
	while parent is Node3D:
		result = parent.transform * result
		parent = parent.get_parent()
	return result


func run() -> void:
	var aircraft := (load("res://Aircraft/Aircraft_3.tscn") as PackedScene).instantiate() as RigidBody3D
	var controls := aircraft.get_node("ControlSurfaces")
	check(controls.bind_surfaces(), "Could not bind four controls")
	var surfaces: Array[MeshInstance3D] = []
	var rest: Array[Transform3D] = []
	var centers: Array[Vector3] = []
	for path: String in controls.SURFACE_PATHS:
		var surface := controls.get_node(path) as MeshInstance3D
		surfaces.append(surface)
		rest.append(surface.transform)
		centers.append(model_transform(surface) * surface.mesh.get_aabb().get_center())
		check_hinge(surface, surfaces.size() == 4)
	var aero := aircraft.get_node("SimpleAero")
	for sign_value in [-1.0, 1.0]:
		aero.actual_pitch_control = sign_value
		aero.actual_roll_control = sign_value
		aero.actual_yaw_control = sign_value
		controls._process(0.016)
		for index in range(4):
			var center := model_transform(surfaces[index]) * surfaces[index].mesh.get_aabb().get_center()
			var movement := center.x - centers[index].x if index == 3 else center.y - centers[index].y
			check(movement * sign_value * (-1.0 if index == 1 else 1.0) > 0.01,
				"Incorrect deflection direction for %s" % surfaces[index].name)
	controls.apply_control_surface_inputs(0.0, 0.0, 0.0)
	for index in range(4):
		check(surfaces[index].transform.is_equal_approx(rest[index]), "Neutral pose changed")
	aircraft.freeze = true
	root.add_child(aircraft)
	await process_frame
	aircraft.process_mode = Node.PROCESS_MODE_DISABLED
	if "--render" in OS.get_cmdline_user_args():
		await render_controls(aircraft, controls)
	var damage := aircraft.get_node("PartDamageModel")
	var gear := aircraft.get_node("LandingGear")
	check(bool(gear.get("lock_deployed")) and bool(gear.get("is_deployed")), "Godot landing gear is not fixed deployed")
	for collider_name in ["CenterGearCollider", "RightGearCollider", "LeftGearCollider"]:
		var collider := aircraft.get_node(collider_name) as CollisionShape3D
		check(not collider.disabled, "%s is disabled" % collider_name)
	for mesh_name in ["landing gear struts", "Cylinder", "Cylinder_002", "Cylinder_004", "Object_003", "MainWheelLeft", "MainGearSupportLeft"]:
		var baked := aircraft.get_node_or_null("Aircraft 3/" + mesh_name) as Node3D
		check(baked != null and baked.visible, "Blender gear is missing: " + mesh_name)
	for path in ["CenterGearCollider/nose gear pivot point/Aircraft nose gear", "RightGearCollider/right gear pivot point/Aircraft main gear", "LeftGearCollider/left gear pivot point/Aircraft main gear"]:
		var old_visual := aircraft.get_node_or_null(path) as Node3D
		check(old_visual != null and not old_visual.visible, "Godot gear visual is still visible: " + path)
	var expected_wheels := ["Cylinder_002", "MainWheelLeft", "Object_003"]
	var colliders := ["CenterGearCollider", "RightGearCollider", "LeftGearCollider"]
	var gear_visuals: Array = gear.get("gear_visuals")
	for index in range(expected_wheels.size()):
		var wheel := aircraft.get_node("Aircraft 3/" + expected_wheels[index]) as MeshInstance3D
		check(gear_visuals[index] == wheel, "LandingGear does not track Blender wheel " + expected_wheels[index])
		var world_center := wheel.global_transform * wheel.mesh.get_aabb().get_center()
		var collider := aircraft.get_node(colliders[index]) as CollisionShape3D
		check(world_center.distance_to(collider.global_position) < 0.6,
			"Blender wheel and collider do not line up: %s wheel=%s collider=%s" % [expected_wheels[index], world_center, collider.global_position])
	for zone in [&"left_wing", &"right_wing", &"horizontal_stabilizer", &"vertical_stabilizer"]:
		damage.damage_zone(zone, damage.get_zone_max_health(zone))
	controls.apply_control_surface_inputs(1.0, 1.0, 1.0)
	for surface in surfaces:
		check(not surface.visible, "Destroyed section left a visible control surface")
	if "--render" in OS.get_cmdline_user_args():
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://captures/aircraft3_controls/damaged.png")
	aircraft.queue_free()
	await process_frame
	for failure in failures:
		push_error(failure)
	if failures.is_empty():
		print("AIRCRAFT3_CONTROL_SURFACES_PASS directions=both hinges=4 damage_zones=4")
	quit(0 if failures.is_empty() else 1)


func render_controls(aircraft: Node3D, controls: Node) -> void:
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("273340")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.6
	root.add_child(environment)
	var light := DirectionalLight3D.new()
	root.add_child(light)
	light.rotation_degrees = Vector3(-40, -35, 0)
	light.light_energy = 1.8
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.make_current()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 14.0
	camera.position = aircraft.position + Vector3(9, 7, -12)
	camera.look_at(aircraft.position + Vector3(0, 0, -1))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://captures/aircraft3_controls"))
	for pose in [0.0, -1.0, 1.0]:
		controls.apply_control_surface_inputs(pose, pose, pose)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://captures/aircraft3_controls/pose_%d.png" % int(pose))
	controls.apply_control_surface_inputs(0.0, 0.0, 0.0)


func check_hinge(surface: MeshInstance3D, rudder: bool) -> void:
	# Verify actual mesh forward-edge endpoints remain fixed under deflection.
	var points: Array[Vector3] = []
	var low := INF
	var high := -INF
	var transform_value := model_transform(surface)
	for index in range(surface.mesh.get_surface_count()):
		for vertex: Vector3 in surface.mesh.surface_get_arrays(index)[Mesh.ARRAY_VERTEX]:
			var point := transform_value * vertex
			points.append(point)
			var span := point.y if rudder else point.x
			low = minf(low, span)
			high = maxf(high, span)
	for limit in [low, high]:
		var forward := -INF
		for point in points:
			if absf((point.y if rudder else point.x) - limit) < 0.0001:
				forward = maxf(forward, point.z)
		var edge: Array[Vector3] = []
		for point in points:
			if absf((point.y if rudder else point.x) - limit) < 0.0001 and absf(point.z - forward) < 0.0001 and not edge.has(point):
				edge.append(point)
		var endpoint := Vector3.ZERO
		for point in edge:
			endpoint += point
		endpoint /= edge.size()
		var local := transform_value.affine_inverse() * endpoint
		var moved := transform_value * (Basis(Vector3.UP if rudder else Vector3.RIGHT, 0.4) * local)
		check(moved.distance_to(endpoint) < 0.001, "%s hinge drifts" % surface.name)
