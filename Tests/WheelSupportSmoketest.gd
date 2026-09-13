extends SceneTree

var failures: Array[String] = []
var report: Array = []

func _initialize() -> void: call_deferred("_run")

func _run() -> void:
	for child in root.get_children(): child.process_mode = Node.PROCESS_MODE_DISABLED
	var world := Node3D.new()
	root.add_child(world)
	var floor_body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(200, 1, 200)
	collision.shape = shape
	collision.position.y = -0.5
	floor_body.add_child(collision)
	floor_body.position = Vector3(0, 100, -100)
	world.add_child(floor_body)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.position = Vector3(0, 103, -90)
	camera.current = true
	for name_ in ["GroundVehicle", "vehicle_enemy_buggy", "vehicle_enemy_pickup", "vehicle_enemy_battle_bus", "vehicle_friendly_light"]:
		var host = (load("res://GroundVehicle/%s.tscn" % name_) as PackedScene).instantiate()
		host.position = Vector3(0, 101, -100)
		world.add_child(host)
		_stop(host)
		await physics_frame
		await process_frame
		var support = host.get("_wheel_support")
		for i in host._all_wheel_nodes.size():
			var marker: Node3D = host._wheel_contact_nodes[i]
			if marker != null:
				_expect(host.to_local(marker.global_position).distance_to(host._wheel_contact_local_positions[i]) < 0.001, name_ + ": contact transform")
		support.steer(host, 0.4)
		support.steer(host, 0.0)
		for i in host._all_wheel_nodes.size():
			_expect(host._all_wheel_nodes[i].basis.is_equal_approx(support.rest_bases[i]), name_ + ": steering rest basis")
		# Isolate projection from the separate travel cap.
		host.wheel_max_extension_m = 10.0
		host.wheel_max_compression_m = 10.0
		host.position.y = 102
		host.rotation.x = deg_to_rad(30)
		support.refresh(host, true)
		_expect(host._suspension_has_ground, name_ + ": no floor hits")
		var max_error := 0.0
		for i in host._all_wheel_nodes.size():
			host._all_wheel_nodes[i].position.y = host._cached_wheel_target_ys[i]
			if host._wheel_contact_nodes[i] != null:
				max_error = maxf(max_error, absf(host._wheel_contact_nodes[i].global_position.y - 100))
		_expect(max_error < 0.002, name_ + ": tilted projection")
		host.wheel_max_extension_m = 0.65
		host.wheel_max_compression_m = 0.6
		support.refresh(host, true)
		for i in host._all_wheel_nodes.size():
			var travel: float = host._cached_wheel_target_ys[i] - host._wheel_nominal_positions[i].y
			_expect(travel >= -0.6501 and travel <= 0.6001, name_ + ": travel cap")
		host.rotation = Vector3.ZERO
		host.position.y = 101
		support.refresh(host, true)
		_expect(support.last_probe_count == host._all_wheel_nodes.size(), name_ + ": duplicate contact rays")
		var before: float = host._cached_corner_target_ys[0]
		floor_body.position.y += 0.5
		support._update_targets(host)
		_expect(absf(host._cached_corner_target_ys[0] - before - 0.5) < 0.001, name_ + ": moving support cache")
		floor_body.position.y = 100
		# Real collision slope, full-rate chassis integration, no visual snapping.
		floor_body.rotation.x = deg_to_rad(10)
		await physics_frame
		await process_frame
		host._spring_initialized = false
		for _tick in 240:
			host.position.y += host._spring_velocity_y / 60.0
			support.update(host, 1.0 / 60.0, true, true)
		var settled_pitch: float = rad_to_deg(host.rotation.x)
		_expect(absf(settled_pitch - 10) < 1, name_ + ": slope support")
		# Half the footprint on a small step: mixed support must stay bounded.
		floor_body.rotation = Vector3.ZERO
		var step := StaticBody3D.new()
		var step_col := CollisionShape3D.new()
		var step_shape := BoxShape3D.new()
		step_shape.size = Vector3(10, 0.25, 10)
		step_col.shape = step_shape
		step.add_child(step_col)
		step.position = Vector3(0, 100.125, -94.5)
		world.add_child(step)
		await physics_frame
		await process_frame
		for _tick in 180:
			host.position.y += host._spring_velocity_y / 60.0
			support.update(host, 1.0 / 60.0, true, true)
		_expect(is_finite(host.position.y) and absf(host._spring_velocity_y) < 0.1, name_ + ": step stability")
		for i in host._all_wheel_nodes.size():
			var travel: float = host._all_wheel_nodes[i].position.y - host._wheel_nominal_positions[i].y
			_expect(travel >= -0.651 and travel <= 0.601, name_ + ": step travel")
		step.free()
		support.refresh(host, false, true)
		_expect(support.last_probe_count <= 3, name_ + ": coarse probe count")
		host.position.x = 1000
		support.refresh(host, true)
		_expect(not host._suspension_has_ground, name_ + ": lost physical support")
		host.apply_origin_shift(Vector3(4000, 0, 0))
		_expect(not host._suspension_probe_ready, name_ + ": origin invalidation")
		host.position = Vector3(0, 101, -690)
		camera.fov = 70
		_expect(not host._should_use_detailed_suspension(0), name_ + ": distant detail band")
		camera.fov = 12
		_expect(host._should_use_detailed_suspension(0), name_ + ": zoom detail override")
		camera.fov = 70
		report.append({"scene": name_, "projection_error_m": max_error, "settled_pitch_deg": settled_pitch})
		host.free()
		floor_body.rotation = Vector3.ZERO
		await physics_frame
		await process_frame
	print("WHEEL_SUPPORT_SMOKETEST ", JSON.stringify({"status": "PASS" if failures.is_empty() else "FAIL", "failures": failures, "cases": report}))
	world.free()
	quit(0 if failures.is_empty() else 1)

func _stop(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child in node.get_children(): _stop(child)

func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)
