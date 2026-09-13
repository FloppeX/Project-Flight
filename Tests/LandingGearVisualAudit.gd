extends "res://Tests/FleetSuspensionSmoketest.gd"
## Diagnostic only: measure loaded support and visual geometry independently.

func mesh_bottom(node: Node) -> float:
	var bottom := INF
	if node is MeshInstance3D and node.mesh != null:
		var bounds: AABB = node.get_aabb()
		for i in 8:
			bottom = minf(bottom, node.to_global(bounds.get_endpoint(i)).y)
	for child in node.get_children(): bottom = minf(bottom, mesh_bottom(child))
	return bottom

func collect_rigs(node: Node, rigs: Array) -> void:
	if node is NoseGearRigVisual: rigs.append(node)
	for child in node.get_children(): collect_rigs(child, rigs)

func collect_gear_meshes(node: Node, out: Array) -> void:
	if node is MeshInstance3D and (str(node.name).to_lower().contains("gear") or str(node.name).to_lower().contains("skid")):
		out.append({"path": str(node.get_path()), "bottom_y": mesh_bottom(node)})
	for child in node.get_children(): collect_gear_meshes(child, out)

func measure(craft: RigidBody3D, gear: Node, rigs: Array, stage_name: String) -> Dictionary:
	var wheels: Array = gear.get("gear_collision_shapes")
	var visuals: Array = gear.get("gear_visuals")
	var wheel_rows := []
	for i in wheels.size():
		var visual_root: Node = visuals[i] if i < visuals.size() else null
		var rig: Node = null
		for candidate in rigs:
			if candidate.gear_index == i:
				rig = candidate
				visual_root = candidate.get("_wheel_pivot")
		var visual_y := mesh_bottom(visual_root) if is_instance_valid(visual_root) else INF
		wheel_rows.append({"index": i, "collider": str(wheels[i].name),
			"compression_m": gear.gear_compressions[i], "force_n": gear.gear_normal_forces_n[i],
			"contact": gear.gear_has_contact[i], "visual_bottom_y": visual_y,
			"visual_root": str(visual_root.get_path()) if is_instance_valid(visual_root) else "UNMAPPED",
			"visual_compression_m": rig.get("_visual_compression_m") if rig != null else null})
	var other_meshes := []
	if rigs.is_empty(): collect_gear_meshes(craft, other_meshes)
	return {"model": craft.scene_file_path.get_file(), "stage": stage_name,
		"body_y": craft.global_position.y, "mass": craft.mass, "spring_n_m": gear.spring_strength,
		"damping_ns_m": gear.spring_damping, "wheels": wheel_rows, "other_gear_meshes": other_meshes}

func _run() -> void:
	root.get_node("AirOpsManager").set("mission_tasking_enabled", false)
	var rendered := OS.get_cmdline_user_args().has("--render-audit")
	if rendered:
		root.size = Vector2i(1600, 900)
		root.content_scale_size = Vector2i(1600, 900)
	var output := FileAccess.open("user://landing_gear_visual_audit_20260911%s.json" % ("_rendered" if rendered else ""), FileAccess.WRITE)
	var results := []
	for model in [1, 2, 5, 9, 10, 11]:
		if rendered and model not in [2, 5]: continue
		var host := Node3D.new()
		root.add_child(host)
		current_scene = host
		var surface := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(100, 2, 100)
		shape.shape = box
		shape.position.y = -1
		surface.add_child(shape)
		host.add_child(surface)
		var audit_camera: Camera3D = null
		if rendered:
			var floor_mesh := MeshInstance3D.new()
			var plane := PlaneMesh.new()
			plane.size = Vector2(100, 100)
			floor_mesh.mesh = plane
			var material := StandardMaterial3D.new()
			material.albedo_color = Color(0.22, 0.28, 0.33)
			material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			material.cull_mode = BaseMaterial3D.CULL_DISABLED
			floor_mesh.material_override = material
			host.add_child(floor_mesh)
			for z in [-2.0, 0.0, 2.0, 4.0]:
				var line := MeshInstance3D.new()
				var line_box := BoxMesh.new()
				line_box.size = Vector3(30, 0.005, 0.025)
				line.mesh = line_box
				var line_material := StandardMaterial3D.new()
				line_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				line_material.albedo_color = Color(0.65, 0.75, 0.8)
				line.material_override = line_material
				line.position = Vector3(0, 0.004, z)
				host.add_child(line)
			var sun := DirectionalLight3D.new()
			sun.rotation_degrees = Vector3(-55, -25, 0)
			sun.shadow_enabled = true
			host.add_child(sun)
			var environment := WorldEnvironment.new()
			environment.environment = Environment.new()
			environment.environment.background_mode = Environment.BG_COLOR
			environment.environment.background_color = Color(0.12, 0.15, 0.19)
			environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
			environment.environment.ambient_light_color = Color.WHITE
			environment.environment.ambient_light_energy = 0.65
			host.add_child(environment)
			var camera := Camera3D.new()
			audit_camera = camera
			camera.projection = Camera3D.PROJECTION_ORTHOGONAL
			camera.size = 3.0
			host.add_child(camera)
			camera.global_position = Vector3(8, 2.5, 3)
			camera.look_at(Vector3(0, 1.0, -0.5))
			camera.make_current()
		var craft := _spawn("res://Aircraft/Aircraft_%d.tscn" % model, host)
		await process_frame
		await physics_frame
		_disable_updates(craft)
		craft.freeze = true
		var gear: Node = craft.get_node("LandingGear")
		gear.set("airborne_suspension_budget_enabled", false)
		gear.set("use_accel_lean", false)
		var manager: Node = load("res://LandCarrier/FlightDeckManager.gd").new()
		var placed: bool = manager.call("_place_aircraft_in_static_suspension_pose", craft, 0.0)
		var rigs := []
		collect_rigs(craft, rigs)
		for stage_name in ["static_load", "body_pushed_down_10cm"]:
			if stage_name != "static_load": craft.global_position.y -= 0.1
			for step in 5:
				await physics_frame
				gear.call("process_physic_frame", 1.0 / 60.0)
				for rig in rigs: rig.call("_update_pose", -1.0)
			var row := measure(craft, gear, rigs, stage_name)
			row["placement_success"] = placed
			results.append(row)
			print("GEAR_VISUAL_AUDIT ", JSON.stringify(row))
			if rendered:
				audit_camera.make_current()
				await process_frame
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png("user://gear_audit_%d_%s.png" % [model, stage_name])
		manager.free()
		host.queue_free()
		await process_frame
	output.store_string(JSON.stringify(results, "\t"))
	output.close()
	print("GEAR_VISUAL_AUDIT COMPLETE")
	quit()
