extends SceneTree
var failures: Array[String] = []

func _initialize() -> void: run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)

func press(button: int) -> void:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	event.pressed = true
	root.push_input(event)
	event.pressed = false
	root.push_input(event)

func run() -> void:
	await process_frame
	for node in root.get_children(): node.process_mode = Node.PROCESS_MODE_DISABLED
	root.get_node("PauseMenu").visible = false
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var previous := Camera3D.new()
	scene.add_child(previous)
	previous.make_current()
	var subjects: Array[Node3D] = []
	for i in 2:
		var vehicle := Node3D.new()
		vehicle.name = "Aircraft_%d" % i
		scene.add_child(vehicle)
		vehicle.add_to_group("aircraft")
		subjects.append(vehicle)
	var controller: Node = load("res://Scenario/Trailer/TrailerAircraftCameras.gd").new()
	scene.add_child(controller)
	controller.set_process(false)
	controller.camera.interpolated_target = false
	paused = true
	for slot in 5:
		controller.select_slot(slot, subjects[0])
		if controller.anchored: press(JOY_BUTTON_A)
		var position: Vector3 = controller.camera.global_position
		press(JOY_BUTTON_A)
		check(controller.anchored and controller.slot == slot, "A anchors same slot %d" % slot)
		check(controller.camera.global_position.distance_to(position) < 0.001, "anchor preserves position")
		var local_position: Vector3 = controller.camera.offset.origin
		subjects[0].position += Vector3(4, 2, -5)
		subjects[0].rotation.z += 0.3
		controller._process(0.1)
		var followed_position: Vector3 = subjects[0].global_transform * local_position if slot < 3 else position
		check(controller.camera.global_position.distance_to(followed_position) < 0.001, "aim lock preserves mounted following or free world position")
		var direction: Vector3 = (controller._focus_point() - followed_position).normalized()
		check((-controller.camera.global_basis.z).dot(direction) > 0.9999, "aim follows subject")
		var shift := Vector3(5000, 0, -3000)
		subjects[0].position -= shift
		controller.apply_origin_shift(shift)
		controller._process(0.1)
		check(controller.camera.global_position.distance_to(followed_position - shift) < 0.002, "anchor origin shift")
		var before: Transform3D = controller.camera.global_transform
		press(JOY_BUTTON_A)
		check(not controller.anchored and controller.camera.global_transform.is_equal_approx(before), "unanchor preserves entire view")
		var relative: Transform3D = controller.camera.offset
		subjects[0].position += Vector3(5, 3, 1)
		controller._process(0.1)
		var expected: Transform3D = subjects[0].global_transform * relative if slot < 3 else before
		check(controller.camera.global_transform.is_equal_approx(expected), "unanchor restores original attachment")
		press(JOY_BUTTON_A)
		controller.select_slot((slot + 1) % 5)
		controller.select_slot(slot)
		check(controller.anchored, "anchor selection remembered")
		press(JOY_BUTTON_A)
	controller.select_slot(0, subjects[0])
	press(JOY_BUTTON_X)
	check(controller.subject == subjects[1], "X next vehicle")
	press(JOY_BUTTON_X)
	check(controller.subject == subjects[0], "X vehicle wraps")
	press(JOY_BUTTON_Y)
	check(controller.slot == 1, "Y next camera")
	root.get_node("PauseMenu").visible = true
	press(JOY_BUTTON_A)
	check(not controller.anchored, "menu blocks film shortcuts")
	root.get_node("PauseMenu").visible = false
	controller.active = false
	controller.piloting = true
	press(JOY_BUTTON_A)
	press(JOY_BUTTON_X)
	press(JOY_BUTTON_Y)
	check(not controller.active and controller.slot == 1 and controller.subject == subjects[0], "pilot controls not intercepted")
	controller.piloting = false
	controller.active = true
	for view in 5:
		controller.select_slot(view, subjects[0])
		controller.move_speed_level = 4
		press(JOY_BUTTON_DPAD_UP)
		controller._process(0.0)
		check(controller.camera.move_speed == 20.0, "D-pad up doubles speed in view %d" % view)
		press(JOY_BUTTON_DPAD_DOWN)
		controller._process(0.0)
		check(controller.camera.move_speed == 10.0, "D-pad down halves speed in view %d" % view)
		for aim_lock in [false, true]:
			controller._set_anchored(aim_lock)
			controller.camera.motion = Vector3.ZERO
			controller._pad_axes[JOY_AXIS_LEFT_X] = 1.0
			var start: Vector3 = controller.camera.global_position
			controller._process(0.1)
			var slow_distance: float = controller.camera.global_position.distance_to(start)
			press(JOY_BUTTON_DPAD_UP)
			start = controller.camera.global_position
			controller._process(0.1)
			var fast_distance: float = controller.camera.global_position.distance_to(start)
			check(absf(fast_distance - slow_distance * 2.0) < 0.005, "actual translation doubles view=%d anchored=%s" % [view, aim_lock])
			controller._pad_axes[JOY_AXIS_LEFT_X] = 0.0
			press(JOY_BUTTON_DPAD_DOWN)
			controller._process(0.0)
	var held := InputEventJoypadButton.new()
	held.button_index = JOY_BUTTON_DPAD_UP
	held.pressed = true
	root.push_input(held)
	root.push_input(held)
	check(controller.move_speed_level == 5, "held/repeated button steps once")
	held.pressed = false
	root.push_input(held)
	for i in 20: press(JOY_BUTTON_DPAD_UP)
	controller._process(0.0)
	check(controller.camera.move_speed == 320.0, "maximum speed capped")
	controller.camera.motion = Vector3(320, 0, 0)
	press(JOY_BUTTON_DPAD_DOWN)
	check(controller.camera.motion == Vector3.ZERO, "slowing clears old fast motion")
	for i in 20: press(JOY_BUTTON_DPAD_DOWN)
	controller._process(0.0)
	check(controller.camera.move_speed == 0.625, "minimum speed capped")
	controller.cycle_vehicle()
	controller.select_slot(0)
	controller._process(0.0)
	check(controller.camera.move_speed == 0.625, "speed follows camera/vehicle switches")
	paused = false
	press(JOY_BUTTON_DPAD_UP)
	controller._process(0.0)
	check(controller.camera.move_speed == 1.25, "speed also changes while running")
	root.get_node("PauseMenu").visible = true
	press(JOY_BUTTON_DPAD_UP)
	check(controller.move_speed_level == 1, "menu navigation cannot change filming speed")
	root.get_node("PauseMenu").visible = false
	controller.active = false
	controller.piloting = true
	press(JOY_BUTTON_DPAD_UP)
	check(controller.move_speed_level == 1, "cockpit D-pad unchanged")
	controller.piloting = false
	controller.active = true
	controller.release_camera()
	paused = false
	scene.queue_free()
	await process_frame
	print("TRAILER_CAMERA_PAD_%s failures=%s" % ["PASS" if failures.is_empty() else "FAIL", failures])
	quit(0 if failures.is_empty() else 1)
