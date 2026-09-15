extends SceneTree
var failures: Array[String] = []

func _initialize() -> void: run.call_deferred()

func expect(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func run() -> void:
	await process_frame
	for node in root.get_children(): node.process_mode = Node.PROCESS_MODE_DISABLED
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var previous := Camera3D.new()
	scene.add_child(previous)
	previous.make_current()
	var aircraft := Node3D.new()
	aircraft.name = "Aircraft_One"
	scene.add_child(aircraft)
	aircraft.add_to_group("aircraft")
	var second := Node3D.new()
	second.name = "Aircraft_Two"
	scene.add_child(second)
	second.add_to_group("ai_aircraft")
	var controller: Node = load("res://Scenario/Trailer/TrailerAircraftCameras.gd").new()
	scene.add_child(controller)
	controller.camera.interpolated_target = false
	root.get_node("PauseMenu").visible = false
	expect(controller.select_slot(0, aircraft), "first camera activates")
	expect(root.get_node("FlightDirector").trailer_camera_active, "gameplay camera yields")
	var pose: Transform3D = controller.camera.offset
	aircraft.transform = Transform3D(Basis.from_euler(Vector3(0.3, 1.2, -0.7)), Vector3(40, 80, -150))
	controller._process(0.016)
	expect(controller.camera.global_transform.is_equal_approx(aircraft.global_transform * pose), "camera follows position pitch yaw and roll")
	paused = true
	controller.camera.move_camera(Vector3.RIGHT, Vector2(0.2, -0.1), 0.3, 0.25)
	controller.camera.fov = 42
	var edited: Transform3D = controller.camera.offset
	controller.select_slot(1)
	controller.select_slot(0)
	expect(controller.camera.offset.is_equal_approx(edited) and controller.camera.fov == 42, "edited pose and zoom remembered per slot while paused")
	controller.cycle_aircraft()
	expect(controller.subject == second, "F4 target cycling")
	expect(not controller.camera.offset.is_equal_approx(edited), "other aircraft has independent camera poses")
	controller.cycle_aircraft(-1)
	expect(controller.camera.offset.is_equal_approx(edited), "returning to first aircraft restores its pose")
	var shift := Vector3(5000, 0, -3000)
	aircraft.global_position -= shift
	controller.apply_origin_shift(shift)
	controller._process(0.016)
	expect(controller.camera.offset.is_equal_approx(edited), "origin shift preserves attachment offset")
	var key := InputEventKey.new()
	key.keycode = KEY_F3
	key.pressed = true
	controller._input(key)
	expect(controller.slot == 2, "logical F3 event selects third slot")
	key.keycode = 0
	key.physical_keycode = KEY_F1
	controller._input(key)
	expect(controller.slot == 0, "physical F1 event selects first slot")
	var ground := Node3D.new()
	ground.name = "Ground_A"
	scene.add_child(ground)
	ground.add_to_group("ground_vehicles")
	var enemy_ground := Node3D.new()
	enemy_ground.name = "Ground_B"
	scene.add_child(enemy_ground)
	enemy_ground.add_to_group("ground_vehicles")
	enemy_ground.add_to_group("enemies")
	second.add_to_group("enemies")
	var carrier := Node3D.new()
	carrier.name = "Carrier"
	scene.add_child(carrier)
	carrier.add_to_group("carrier")
	expect(controller.vehicle_list().size() == 5, "all teams ground aircraft and carrier without duplicates")
	controller.select_slot(0, ground)
	controller.camera.offset.origin += Vector3(2, 1, 0)
	controller.camera.fov = 51
	var ground_pose: Transform3D = controller.camera.offset
	controller.select_slot(0, enemy_ground)
	expect(controller.camera.offset.is_equal_approx(ground_pose) and controller.camera.fov == 51, "ground vehicles share edited pose and zoom across teams")
	key.physical_keycode = KEY_DOWN
	root.push_input(key)
	expect(controller.slot == 1, "down arrow advances camera via viewport input")
	key.physical_keycode = KEY_UP
	root.push_input(key)
	expect(controller.slot == 0, "up arrow returns camera")
	root.push_input(key)
	expect(controller.slot == 4, "five camera views wrap backwards")
	key.physical_keycode = KEY_RIGHT
	root.push_input(key)
	expect(controller.subject == aircraft, "right arrow wraps from last vehicle to first")
	key.physical_keycode = KEY_LEFT
	root.push_input(key)
	expect(controller.subject == enemy_ground, "left arrow wraps to last vehicle")
	controller.select_slot(0, second)
	expect(not controller.camera.offset.is_equal_approx(ground_pose), "enemy aircraft has independent presets")
	controller.select_slot(0, aircraft)
	var cockpit := Node3D.new()
	cockpit.name = "CameraCockpit"
	aircraft.add_child(cockpit)
	cockpit.position = Vector3(0, 1.2, 2.0)
	var commander := Node3D.new()
	commander.name = "Commander"
	carrier.add_child(commander)
	commander.position = Vector3(5, 20, -4)
	var mounted_pose: Transform3D = controller.camera.global_transform
	controller.select_slot(3)
	expect(controller.camera.global_transform.is_equal_approx(mounted_pose), "free camera opens without snapping")
	aircraft.position += Vector3(10, 5, 1)
	controller._process(0.1)
	expect(controller.camera.global_transform.is_equal_approx(mounted_pose), "free camera does not follow moving vehicle")
	aircraft.position -= shift
	controller.apply_origin_shift(shift)
	controller._process(0.1)
	expect(controller.camera.global_position.distance_to(mounted_pose.origin - shift) < 0.01, "free camera retains rebased world position after process")
	controller.select_slot(4)
	var anchored_position: Vector3 = controller.camera.global_position
	aircraft.position += Vector3(7, 3, 4)
	aircraft.rotation.z += 0.5
	controller._process(0.1)
	expect(controller.camera.global_position.distance_to(anchored_position) < 0.001, "anchored camera holds world position while the aircraft moves and banks")
	expect((-controller.camera.global_basis.z).dot((cockpit.global_position - controller.camera.global_position).normalized()) > 0.9999, "pilot stays centred while vehicle moves and rolls")
	aircraft.position -= shift
	controller.apply_origin_shift(shift)
	controller._process(0.1)
	expect(controller.camera.global_position.distance_to(anchored_position - shift) < 0.001, "anchored world position survives origin shifts without following subject")
	var before_move: Vector3 = controller.camera.global_position
	controller._move_anchored(Vector3.RIGHT, Vector2.ZERO, 0.0, 0.25)
	expect(controller.camera.global_position.distance_to(before_move) > 1.0, "anchored view can translate freely while keeping aim lock")
	var after_move: Vector3 = controller.camera.global_position
	aircraft.position += Vector3(3, 7, -9)
	controller._process(0.1)
	expect(controller.camera.global_position.distance_to(after_move) < 0.001, "anchored view stops translating when operator releases input")
	aircraft.position += after_move - cockpit.global_position
	controller._process(0.1)
	expect(controller.camera.global_position.distance_to(after_move) < 0.001 and controller.camera.global_basis.is_finite(), "target at lens does not displace camera or invalidate its basis")
	aircraft.position += Vector3(0, 0, 5)
	controller._process(0.1)
	expect((-controller.camera.global_basis.z).dot((cockpit.global_position - after_move).normalized()) > 0.9999, "aim tracking resumes after target passes the lens")
	controller.select_slot(4, carrier)
	expect(controller._focus_node == commander and controller._focus_point().distance_to(commander.global_position + Vector3.UP * 1.8) < 0.01, "carrier anchored camera centres commander eye height")
	# Starting an aim lock must not mistake an opposite heading for 180-degree
	# roll. Test both level shots and deliberately authored optical-axis tilt.
	for heading in [0.0, PI * 0.5, PI, PI * 1.5]:
		for tilt in [0.0, 0.35, -0.5]:
			controller.select_slot(3, carrier)
			controller.camera.offset = Transform3D(Basis(Vector3.UP, heading) * Basis(Vector3.BACK, tilt), commander.global_position + Vector3(0, 2, 10))
			controller._process(0.0)
			controller.select_slot(4)
			expect(absf(wrapf(controller._orbit_roll - tilt, -PI, PI)) < 0.001, "anchored entry preserves actual tilt, not heading: heading=%.2f tilt=%.2f" % [heading, tilt])
			var anchored_basis: Basis = controller.camera.global_basis
			controller.select_slot(4)
			expect(controller.camera.global_basis.is_equal_approx(anchored_basis), "reselecting anchored view does not accumulate roll")
	for view in 5:
		controller.select_slot(view, aircraft)
		controller._clear_pad()
		var initial_basis: Basis = controller.camera.global_basis
		var button := InputEventJoypadButton.new()
		button.button_index = JOY_BUTTON_DPAD_RIGHT
		button.pressed = true
		root.push_input(button)
		expect(controller._pad_motion().roll == -1.0, "D-pad right uses reversed roll in view %d" % view)
		controller._process(0.3)
		expect(controller.camera.global_basis.x.dot(initial_basis.x) < 0.99, "D-pad rolls view %d" % view)
		expect(controller.camera.global_basis.x.dot(initial_basis.y) < -0.2, "D-pad right rotates in the requested direction in view %d" % view)
		button.pressed = false
		root.push_input(button)
		button.button_index = JOY_BUTTON_DPAD_LEFT
		button.pressed = true
		root.push_input(button)
		expect(controller._pad_motion().roll == 1.0, "D-pad left uses reversed roll in view %d" % view)
		button.pressed = false
		root.push_input(button)
		var rolled: Basis = controller.camera.global_basis
		controller._process(0.1)
		expect(controller.camera.global_basis.is_equal_approx(rolled), "roll stays fixed after release in view %d" % view)
		var axis := InputEventJoypadMotion.new()
		axis.axis = JOY_AXIS_TRIGGER_LEFT
		axis.axis_value = 1.0
		var fov: float = controller.camera.fov
		root.push_input(axis)
		controller._process(0.1)
		expect(controller.camera.fov > fov, "left trigger zooms out in view %d" % view)
		axis.axis_value = 0.0
		root.push_input(axis)
		axis.axis = JOY_AXIS_TRIGGER_RIGHT
		axis.axis_value = 1.0
		root.push_input(axis)
		controller._process(0.2)
		expect(controller.camera.fov < fov, "right trigger zooms in in view %d" % view)
		controller._on_pad_connection(0, false)
		expect(is_zero_approx(float(controller._pad_motion().zoom)), "disconnect clears held trigger")
		if view == 4:
			controller._move_anchored(Vector3.RIGHT, Vector2(0.3, 0.1), 0.2, 0.2)
			expect((-controller.camera.global_basis.z).dot((controller._focus_point() - controller.camera.global_position).normalized()) > 0.9999, "orbit movement and roll preserve aim lock")
	# Restore the original preset so the existing persistence assertion stays independent.
	var departing := Node3D.new()
	scene.add_child(departing)
	departing.add_to_group("ai_aircraft")
	controller.select_slot(3, departing)
	var detached_pose: Transform3D = controller.camera.global_transform
	departing.queue_free()
	await process_frame
	controller._process(0.1)
	expect(controller.active and controller.camera.global_transform.is_equal_approx(detached_pose), "free view survives former subject removal")
	controller.select_slot(0, aircraft)
	controller.camera.offset = edited
	controller.camera.fov = 42
	controller._save_pose()
	controller._process(0.01)
	var recorder := root.get_node("RecordingMode")
	var shot: Transform3D = controller.camera.global_transform
	expect(recorder.enter(), "Recording Mode accepts handoff")
	expect(not controller.active and not root.get_node("FlightDirector").trailer_camera_active, "trailer rig releases ownership for recording")
	expect(recorder.camera.global_transform.is_equal_approx(shot), "Recording Mode preserves composed shot")
	recorder.exit()
	root.get_node("PauseMenu").visible = false
	controller.select_slot(0, second)
	second.queue_free()
	await process_frame
	controller._process(0.016)
	expect(not controller.active and not root.get_node("FlightDirector").trailer_camera_active, "destroyed target safely releases camera")
	expect(previous.current, "returns to previous gameplay camera")
	controller.queue_free()
	await process_frame
	root.get_node("GameSession").reset_to_defaults()
	var replacement: Node = load("res://Scenario/Trailer/TrailerAircraftCameras.gd").new()
	scene.add_child(replacement)
	replacement.camera.interpolated_target = false
	replacement.select_slot(0, aircraft)
	expect(replacement.camera.offset.origin.distance_to(edited.origin) < 0.01 and replacement.camera.fov == 42, "camera presets survive controller replacement and session reset")
	replacement.release_camera()
	print("TRAILER_AIRCRAFT_CAMERAS_%s failures=%s" % ["PASS" if failures.is_empty() else "FAIL", failures])
	quit(0 if failures.is_empty() else 1)
