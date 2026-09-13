extends SceneTree
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	for node in root.get_children(): node.process_mode = Node.PROCESS_MODE_DISABLED
	var mode := root.get_node("RecordingMode")
	mode.process_mode = Node.PROCESS_MODE_ALWAYS
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var aircraft := Node3D.new()
	aircraft.name = "Aircraft"
	scene.add_child(aircraft)
	aircraft.add_to_group("aircraft")
	var mesh := MeshInstance3D.new()
	mesh.name = "Wing"
	mesh.mesh = BoxMesh.new()
	aircraft.add_child(mesh)
	var pivot := Node3D.new()
	aircraft.add_child(pivot)
	var gear := MeshInstance3D.new()
	gear.name = "Gear"
	gear.mesh = CylinderMesh.new()
	pivot.add_child(gear)
	gear.position = Vector3(0, -2, 0)
	var carrier := Node3D.new()
	carrier.name = "Carrier"
	scene.add_child(carrier)
	carrier.add_to_group("carrier")
	var hull := MeshInstance3D.new()
	hull.mesh = BoxMesh.new()
	carrier.add_child(hull)
	var skeleton := Skeleton3D.new()
	aircraft.add_child(skeleton)
	skeleton.add_bone("Head")
	var camera := Camera3D.new()
	scene.add_child(camera)
	camera.position = Vector3(20, 10, 30)
	camera.make_current()
	var overlay := CanvasLayer.new()
	scene.add_child(overlay)
	overlay.visible = true
	_expect(mode.enter(), "mode enters")
	_expect(paused and not overlay.visible, "mode composes paused with HUD suppressed")
	var rig: Camera3D = mode.camera
	var original := rig.global_transform
	rig.attach(aircraft, 1)
	_expect(rig.global_transform.is_equal_approx(original), "attach does not jump")
	aircraft.position.x = 10
	rig.move_camera(Vector3.ZERO, Vector2.ZERO, 0.0, 0.0)
	_expect(rig.global_position.is_equal_approx(original.origin + Vector3(10, 0, 0)), "position attachment follows subject")
	rig.attach(null, 0)
	var detached := rig.global_transform
	aircraft.position.x = 20
	rig.move_camera(Vector3.ZERO, Vector2.ZERO, 0.0, 0.0)
	_expect(rig.global_transform.is_equal_approx(detached), "detach stays put")
	rig.attach(aircraft, 2)
	aircraft.rotation.z = 0.8
	rig.move_camera(Vector3.ZERO, Vector2.ZERO, 0.0, 0.0)
	_expect(rig.global_basis.is_equal_approx(detached.basis), "heading mode ignores subject roll")
	rig.attach(aircraft, 3)
	aircraft.rotation.z = 1.0
	rig.move_camera(Vector3.ZERO, Vector2.ZERO, 0.0, 0.0)
	_expect(not rig.global_basis.is_equal_approx(detached.basis), "full attachment inherits roll")
	aircraft.transform = Transform3D.IDENTITY
	var actors: Array[Node3D] = [aircraft, carrier]
	_expect(mode.start_recording(actors), "recording starts")
	# Exact samples make the interpolation assertions independent of wall time.
	mode.recording = false
	aircraft.position = Vector3(100, 0, 0)
	pivot.rotation.z = PI / 2.0
	carrier.position.z = 20
	skeleton.set_bone_pose_position(0, Vector3(0, 3, 0))
	mode.take.sample(2.0)
	mode.elapsed = 2.0
	var live_position := aircraft.global_position
	_expect(mode.enter_replay(), "replay starts")
	mode.seek(1.0)
	_expect(mode.take.subjects[0].global_position.is_equal_approx(Vector3(50, 0, 0)), "midpoint interpolates")
	for copy in mode.take.copies:
		if copy is Skeleton3D:
			_expect(copy.get_bone_pose_position(0).is_equal_approx(Vector3(0, 1.5, 0)), "skeletal pose interpolates")
	_expect(aircraft.global_position == live_position, "scrub does not mutate live aircraft")
	_expect(not scene.visible and aircraft.process_mode == Node.PROCESS_MODE_DISABLED, "live scene hidden and disabled")
	mode.seek(2.0)
	var gear_copy: Node3D = mode.take.copies[2]
	_expect(gear_copy.global_position.distance_to(gear.global_position) < 0.001, "nested gear transform captured")
	mode.seek(0.0)
	_expect(mode.take.subjects[0].global_position.is_zero_approx(), "backwards seek restores beginning")
	rig.attach(mode.take.subjects[0], 1)
	mode.add_key()
	mode.seek(2.0)
	rig.move_camera(Vector3.RIGHT, Vector2.ZERO, 0.0, 0.25)
	mode.add_key()
	mode.selected_shot = 1
	rig.attach(mode.take.subjects[1], 2)
	mode.add_key()
	_expect(mode.take.shots[0].size() == 2 and mode.take.shots[1].size() == 1, "shots have independent keys")
	var directory: String = mode.save_take()
	_expect(not directory.is_empty(), "take saves")
	var loaded: RefCounted = load("res://Recording/SceneTake.gd").new()
	_expect(loaded.load_from(directory), "take reloads")
	root.add_child(loaded.world)
	loaded.seek(1.0)
	_expect(loaded.subjects[0].global_position.is_equal_approx(Vector3(50, 0, 0)), "saved take retains movement")
	loaded.dispose()
	mode.leave_replay()
	_expect(scene.visible and aircraft.global_position == live_position, "live scene restored unchanged")
	# Limit guard and freed-source handling.
	_expect(not mode.take.sample(121.0), "take length is bounded")
	gear.free()
	_expect(mode.take.sample(3.0), "freed mesh does not crash recorder")
	mode.exit()
	_expect(overlay.visible and not root.get_node("FlightDirector").recording_camera_active, "exit restores HUD and camera ownership")
	mode.clear_take()
	_expect(mode.enter(), "mode re-enters")
	_expect(mode.open_take(directory), "saved take opens through recording UI API")
	mode.leave_replay()
	mode.clear_take()
	_expect(mode.start_recording(actors), "second live take starts")
	for frame in range(12):
		aircraft.position.x += 1.0
		await physics_frame
	mode.stop_recording()
	_expect(mode.take.frames.size() >= 5 and mode.take.duration() > 0.1, "physics sampling records a running scene")
	var before_shift := aircraft.global_position
	aircraft.position -= Vector3(4000, 0, 0)
	carrier.position -= Vector3(4000, 0, 0)
	mode.take.origin_offset += Vector3(4000, 0, 0)
	mode.take.sample(mode.take.duration() + 0.1)
	_expect((mode.take.frames.back().poses[0] as Transform3D).origin.is_equal_approx(before_shift), "origin shift does not jump recorded world coordinates")
	mode.exit()
	mode.clear_take()
	print("[RecordingModeSmoketest] %s failures=%s saved=%s" % ["PASS" if failures.is_empty() else "FAIL", failures, directory])
	quit(0 if failures.is_empty() else 1)

func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)
