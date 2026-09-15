extends SceneTree

var failures: Array[String] = []
func _initialize() -> void: run.call_deferred()

func run() -> void:
	await process_frame
	for node in root.get_children(): node.process_mode = Node.PROCESS_MODE_DISABLED
	root.get_node("PauseMenu").visible = false
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var vehicle := Node3D.new()
	scene.add_child(vehicle)
	vehicle.add_to_group("aircraft")
	var controller: Node = load("res://Scenario/Trailer/TrailerAircraftCameras.gd").new()
	scene.add_child(controller)
	controller.set_process(false)
	controller.camera.interpolated_target = false
	var reference: Camera3D = load("res://Recording/RecordingCamera.gd").new()
	scene.add_child(reference)
	# A second trailer rig supplies identical settings with a stationary subject.
	var stationary := Node3D.new()
	scene.add_child(stationary)
	reference.target = stationary
	reference.attachment = 3
	reference.move_speed = 10
	if "attachment_local_controls" in reference: reference.attachment_local_controls = true
	for slot in 3:
		for mode in ["straight", "turning", "aim", "combined"]:
			vehicle.transform = Transform3D.IDENTITY
			controller.select_slot(slot, vehicle)
			controller._clear_pad()
			reference.offset = controller.camera.offset
			reference.motion = Vector3.ZERO
			var moving: bool = mode != "aim"
			var aiming: bool = mode in ["aim", "combined"]
			controller._pad_axes[JOY_AXIS_LEFT_X] = 0.7 if moving else 0.0
			controller._pad_axes[JOY_AXIS_RIGHT_X] = 0.65 if aiming else 0.0
			controller._pad_axes[JOY_AXIS_RIGHT_Y] = -0.4 if aiming else 0.0
			var max_position := 0.0
			var max_angle := 0.0
			for frame in 120:
				var t := float(frame) / 60.0
				vehicle.position = Vector3(t * 100, 500 + t * 10, t * 80)
				vehicle.rotation = Vector3(sin(t) * 0.5, t * 1.2, sin(t * 1.5) * 1.0) if mode != "straight" else Vector3.ZERO
				var pad: Dictionary = controller._pad_motion()
				reference.move_camera(pad.move, pad.look * (1.4 / 60.0), 0.0, 1.0 / 60.0)
				controller._process(1.0 / 60.0)
				var actual: Transform3D = controller.camera.offset
				max_position = maxf(max_position, actual.origin.distance_to(reference.offset.origin))
				max_angle = maxf(max_angle, actual.basis.get_rotation_quaternion().angle_to(reference.offset.basis.get_rotation_quaternion()))
			print("MOVING_CAMERA_INPUT slot=%d mode=%s local_difference_m=%.6f angle_deg=%.6f" % [slot, mode, max_position, rad_to_deg(max_angle)])
			if max_position > 0.01 or max_angle > 0.002:
				failures.append("slot %d %s differs from stationary controls" % [slot, mode])
			controller._clear_pad()
			var released: Transform3D = controller.camera.offset
			vehicle.rotation += Vector3(0.3, 0.5, -0.3)
			controller._process(0.1)
			if not controller.camera.offset.is_equal_approx(released): failures.append("released input drifts")
	controller.release_camera(false)
	scene.queue_free()
	await process_frame
	print("TRAILER_MOVING_CAMERA_INPUT_%s failures=%s" % ["PASS" if failures.is_empty() else "FAIL", failures])
	quit(0 if failures.is_empty() else 1)
