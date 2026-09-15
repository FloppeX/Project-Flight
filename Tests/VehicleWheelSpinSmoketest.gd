extends SceneTree
## Run headless for regressions; add -- --render for actual-mesh previews.

var failures: Array[String] = []
var report: Array = []
const DT := 1.0 / 60.0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	for child in root.get_children():
		child.process_mode = Node.PROCESS_MODE_DISABLED
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
	camera.current = true
	var sun := DirectionalLight3D.new()
	world.add_child(sun)
	sun.rotation_degrees = Vector3(-35, -45, 0)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.12, 0.15, 0.18)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.7
	world.add_child(environment)
	for scene_name in ["GroundVehicle", "vehicle_enemy_buggy", "vehicle_enemy_pickup", "vehicle_enemy_battle_bus", "vehicle_friendly_light"]:
		var host = load("res://GroundVehicle/%s.tscn" % scene_name).instantiate()
		host.position = Vector3(0, 101, -100)
		world.add_child(host)
		_stop(host)
		await physics_frame
		await process_frame
		var support = host._wheel_support
		support.refresh(host, true)
		_expect(host._suspension_has_ground, scene_name + ": grounded")
		support._update_wheel_spin(host, DT)
		var roots: Array[Transform3D] = []
		var markers: Array[Transform3D] = []
		for i in host._all_wheel_nodes.size():
			roots.append(host._all_wheel_nodes[i].transform)
			markers.append(host._wheel_contact_nodes[i].transform)
		host.position.z += 0.3
		support._update_wheel_spin(host, DT)
		var radii: Array = []
		for i in support.rolling_wheels.size():
			var state: Dictionary = support.rolling_wheels[i]
			var pivot: Node3D = host._all_wheel_nodes[i]
			var radius: float = state.radius * pivot.global_basis.y.length()
			var expected: float = Vector3(0, 0, 0.3).dot(pivot.global_basis.z.normalized()) / radius
			_expect(absf(angle_difference(expected, state.angle)) < 0.0001, scene_name + ": signed distance/radius")
			_expect(not state.visuals.is_empty(), scene_name + ": wheel mesh found")
			_expect(pivot.transform.is_equal_approx(roots[i]), scene_name + ": suspension pivot untouched")
			_expect(host._wheel_contact_nodes[i].transform.is_equal_approx(markers[i]), scene_name + ": contact marker untouched")
			for j in state.visuals.size():
				var center_in_visual: Vector3 = state.rest[j].affine_inverse() * state.center
				_expect((state.visuals[j].transform * center_in_visual).distance_to(state.center) < 0.0001, scene_name + ": axle stays centered")
			radii.append(snappedf(radius, 0.001))
		host.position.z -= 0.3
		support._update_wheel_spin(host, DT)
		_expect_zero(support, scene_name + ": reverse returns to original phase")
		support.steer(host, 0.4)
		for wheel in host._all_wheel_nodes:
			wheel.position.y += 0.2
		support._update_wheel_spin(host, DT)
		_expect_zero(support, scene_name + ": stationary steering/suspension")
		support.steer(host, 0.0)
		# Transport by a moving support must not be interpreted as driving.
		floor_body.position.z += 2.0
		host.position.z += 2.0
		support._update_wheel_spin(host, DT)
		_expect_zero(support, scene_name + ": carrier translation")
		floor_body.position.z -= 2.0
		host.position.z -= 2.0
		support._update_wheel_spin(host, DT)
		var relative_pose: Transform3D = floor_body.global_transform.affine_inverse() * host.global_transform
		floor_body.rotate_y(0.2)
		host.global_transform = floor_body.global_transform * relative_pose
		support._update_wheel_spin(host, DT)
		_expect_zero(support, scene_name + ": carrier rotation")
		floor_body.rotation = Vector3.ZERO
		host.global_transform = floor_body.global_transform * relative_pose
		support._update_wheel_spin(host, DT)
		host._suspension_has_ground = false
		host.position.z += 0.2
		support._update_wheel_spin(host, DT)
		_expect_zero(support, scene_name + ": airborne displacement ignored")
		host.position.z -= 0.2
		support._update_wheel_spin(host, DT)
		host._suspension_has_ground = true
		host.position.z += 1000.0
		support._update_wheel_spin(host, DT)
		_expect_zero(support, scene_name + ": teleport rejected")
		support.invalidate(host)
		host.position.z -= 1000.0
		support.refresh(host, true)
		support._update_wheel_spin(host, DT)
		_expect_zero(support, scene_name + ": origin shift/reset")
		report.append({"scene": scene_name, "wheel_radii_m": radii})
		if "--render" in OS.get_cmdline_user_args() and scene_name == "vehicle_enemy_buggy":
			# Actual authored wheel, three roll phases; camera follows chassis.
			for i in host._all_wheel_nodes.size():
				host._all_wheel_nodes[i].transform = roots[i]
			var wheel: Node3D = host._all_wheel_nodes[0]
			var state: Dictionary = support.rolling_wheels[0]
			for phase in 3:
				if phase > 0:
					host.position.z += float(state.radius) * PI / 4.0
					support._update_wheel_spin(host, DT)
				var target: Vector3 = wheel.global_transform * state.center
				var side := signf(wheel.position.x)
				camera.position = target + Vector3(side * 2.6, 0.6, 1.0)
				camera.look_at(target)
				for mesh in host.find_children("*", "MeshInstance3D", true, false):
					mesh.visible = true
				await process_frame
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png("user://vehicle_wheel_spin_%d.png" % phase)
		host.free()
	print("VEHICLE_WHEEL_SPIN_SMOKETEST " + JSON.stringify({"status": "PASS" if failures.is_empty() else "FAIL", "failures": failures, "scenes": report}))
	quit(0 if failures.is_empty() else 1)

func _expect_zero(support, label: String) -> void:
	for state in support.rolling_wheels:
		_expect(absf(angle_difference(0.0, state.angle)) < 0.0002, label)

func _expect(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)

func _stop(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child in node.get_children():
		_stop(child)
