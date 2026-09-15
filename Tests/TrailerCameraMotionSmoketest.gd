extends SceneTree
## Exercise the live interpolated path (the older fixture disables interpolation).
class MotionDriver extends Node:
	var vehicle: Node3D
	var elapsed := 0.0
	func _physics_process(delta: float) -> void:
		elapsed += delta
		vehicle.position = Vector3(elapsed * 3.0, 40 + sin(elapsed) * 4, 0)
		vehicle.rotation = Vector3(sin(elapsed) * 0.6, elapsed * 0.15, sin(elapsed * 0.7) * 0.8)

var failures: Array[String] = []
func _initialize() -> void: run.call_deferred()
func expect(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func run() -> void:
	await process_frame
	for node in root.get_children(): node.process_mode = Node.PROCESS_MODE_DISABLED
	root.get_node("PauseMenu").visible = false
	Engine.physics_ticks_per_second = 20
	Engine.max_fps = 60
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("7499b0")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.7
	scene.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, -25, 0)
	scene.add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(1000, 1000)
	ground.mesh = plane
	scene.add_child(ground)
	var aircraft: RigidBody3D = load("res://Aircraft/Aircraft_5.tscn").instantiate()
	aircraft.process_mode = Node.PROCESS_MODE_DISABLED
	aircraft.position = Vector3(0, 40, 0)
	scene.add_child(aircraft)
	aircraft.freeze = true
	aircraft.reset_physics_interpolation()
	var driver := MotionDriver.new()
	driver.vehicle = aircraft
	scene.add_child(driver)
	var controller: Node = load("res://Scenario/Trailer/TrailerAircraftCameras.gd").new()
	scene.add_child(controller)
	expect(controller.camera.interpolated_target, "live interpolation enabled")
	var render := "--render" in OS.get_cmdline_user_args()
	for slot in 3:
		controller.select_slot(slot, aircraft)
		var local_pose: Transform3D = controller.camera.offset
		var max_angle := 0.0
		var max_position := 0.0
		for frame in 100:
			await process_frame
			await RenderingServer.frame_post_draw
			var expected_pose: Transform3D = aircraft.get_global_transform_interpolated() * local_pose
			if frame > 5:
				max_angle = maxf(max_angle, controller.camera.global_basis.get_rotation_quaternion().angle_to(expected_pose.basis.get_rotation_quaternion()))
				max_position = maxf(max_position, controller.camera.global_position.distance_to(expected_pose.origin))
			if render and frame in [20, 80]:
				root.get_texture().get_image().save_png("res://captures/trailer_motion_slot_%d_frame_%d.png" % [slot, frame])
		print("TRAILER_MOTION slot=%d max_angle_deg=%.4f max_position_m=%.4f" % [slot, rad_to_deg(max_angle), max_position])
		expect(max_angle < 0.005 and max_position < 0.01, "mounted slot %d matches live interpolated full aircraft frame" % slot)
	# Render the actual aircraft while editing each mounted view, not just
	# passively following it. A stationary twin receives the exact same input.
	var reference: Camera3D = load("res://Recording/RecordingCamera.gd").new()
	scene.add_child(reference)
	reference.attachment = 3
	reference.target = scene
	reference.attachment_local_controls = true
	reference.move_speed = 10.0
	for slot in 3:
		controller.select_slot(slot, aircraft)
		reference.offset = controller.camera.offset
		reference.motion = Vector3.ZERO
		controller.camera.motion = Vector3.ZERO
		controller._pad_axes[JOY_AXIS_LEFT_X] = 0.55
		controller._pad_axes[JOY_AXIS_RIGHT_X] = 0.4
		controller._pad_axes[JOY_AXIS_RIGHT_Y] = -0.3
		var max_position := 0.0
		var max_angle := 0.0
		for frame in 60:
			await process_frame
			await RenderingServer.frame_post_draw
			var delta: float = controller.get_process_delta_time()
			var pad: Dictionary = controller._pad_motion()
			reference.move_camera(pad.move, pad.look * delta * 1.4, pad.roll, delta)
			var actual: Transform3D = controller.camera.offset
			max_position = maxf(max_position, actual.origin.distance_to(reference.offset.origin))
			max_angle = maxf(max_angle, actual.basis.get_rotation_quaternion().angle_to(reference.offset.basis.get_rotation_quaternion()))
			if render and frame == 59:
				root.get_texture().get_image().save_png("res://captures/trailer_moving_input_slot_%d.png" % slot)
		print("TRAILER_LIVE_INPUT slot=%d local_difference_m=%.6f angle_deg=%.6f" % [slot, max_position, rad_to_deg(max_angle)])
		expect(max_position < 0.01 and max_angle < 0.002, "live editing slot %d matches stationary controls" % slot)
		controller._clear_pad()
	reference.queue_free()
	for slot in 3:
		controller.select_slot(slot, aircraft)
		controller.toggle_anchored()
		var local_position: Vector3 = controller.camera.offset.origin
		for frame in 60:
			await process_frame
			await RenderingServer.frame_post_draw
			var expected: Vector3 = aircraft.get_global_transform_interpolated() * local_position
			expect(controller.camera.global_position.distance_to(expected) < 0.01, "anchored mounted camera %d travels with aircraft" % slot)
			var direction: Vector3 = (controller._focus_point() - controller.camera.global_position).normalized()
			expect((-controller.camera.global_basis.z).dot(direction) > 0.9999, "anchored mounted camera %d keeps pilot centred" % slot)
			if render and frame == 59:
				root.get_texture().get_image().save_png("res://captures/trailer_anchored_follow_slot_%d.png" % slot)
		controller.toggle_anchored()
	controller.select_slot(4)
	var fixed_position: Vector3 = controller.camera.global_position
	for frame in 100:
		await process_frame
		await RenderingServer.frame_post_draw
		expect(controller.camera.global_position.distance_to(fixed_position) < 0.001, "anchored camera remains world stationary")
		var focus: Vector3 = controller._focus_point()
		expect((-controller.camera.global_basis.z).dot((focus - fixed_position).normalized()) > 0.9999, "anchored aim tracks live pilot")
		if render and frame in [20, 80]:
			root.get_texture().get_image().save_png("res://captures/trailer_motion_anchored_%d.png" % frame)
	driver.set_physics_process(false)
	controller.select_slot(3)
	controller.camera.offset = Transform3D(Basis(Vector3.UP, PI), controller._focus_point() + Vector3(3, 1.2, 10))
	controller._process(0.0)
	controller.select_slot(4)
	expect(absf(controller._orbit_roll) < 0.001, "anchored reversal starts upright")
	expect(controller.camera.global_basis.y.dot(Vector3.UP) > 0.99, "aim lock does not invert horizon")
	if render:
		for frame in 5: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://captures/trailer_anchor_upright_entry.png")
	controller.release_camera(false)
	print("TRAILER_CAMERA_MOTION_%s failures=%s" % ["PASS" if failures.is_empty() else "FAIL", failures])
	quit(0 if failures.is_empty() else 1)
