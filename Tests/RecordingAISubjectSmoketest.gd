extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run_test")

func run_test() -> void:
	await process_frame
	for node in root.get_children(): node.process_mode = Node.PROCESS_MODE_DISABLED
	var recorder := root.get_node("RecordingMode")
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var carrier := Node3D.new()
	carrier.name = "CarrierFixture"
	carrier.add_to_group("carrier")
	scene.add_child(carrier)
	var deck := MeshInstance3D.new()
	deck.mesh = BoxMesh.new()
	deck.mesh.size = Vector3(20, 1, 40)
	carrier.add_child(deck)
	var camera := Camera3D.new()
	scene.add_child(camera)
	camera.position = Vector3(22, 15, 25)
	camera.look_at(Vector3(0, 3, 0))
	camera.make_current()
	var sunlight := DirectionalLight3D.new()
	sunlight.rotation_degrees = Vector3(-45, -25, 0)
	scene.add_child(sunlight)
	var initial_actors: Array[Node3D] = [carrier]
	check(recorder.start_background_recording(initial_actors), "capture begins before retrieval")
	var aircraft := Node3D.new()
	aircraft.name = "AI_Aircraft_5"
	# Production hangar retrieval removes aircraft and adds ai_aircraft.
	aircraft.add_to_group("ai_aircraft")
	var model: Node3D = load("res://Models/Aircraft_5/aircraft_5_breakaway.glb").instantiate()
	aircraft.add_child(model)
	carrier.add_child(aircraft)
	aircraft.position = Vector3(0, 3, 8)
	recorder._physics_process(0.1)
	check(recorder.take.has_actor(aircraft), "AI-only retrieved aircraft discovered")
	check(recorder.take.subjects.size() == 2, "carrier and aircraft have separate tracks")
	check(recorder.take.subjects[0].get_child_count() == 1, "nested aircraft not also captured as carrier parts")
	aircraft.reparent(scene)
	aircraft.add_to_group("aircraft")
	recorder._physics_process(0.1)
	check(recorder.take.subjects.size() == 2, "membership in both groups does not duplicate subject")
	aircraft.remove_from_group("aircraft")
	for tick in 20:
		aircraft.position += Vector3(0, 0.12, -0.9)
		recorder._physics_process(0.1)
	var final_pose: Transform3D = aircraft.global_transform
	recorder.stop_recording()
	recorder.take.shots[0] = [{"time": 0.0, "pose": camera.global_transform, "fov": camera.fov, "mode": 0, "subject": -1, "aim": false}]
	var saved := "res://captures/recording/ai_subject_regression"
	check(recorder.take.save_to(saved) == OK, "take saves")
	var loaded = load("res://Recording/SceneTake.gd").new()
	check(loaded.load_from(saved), "saved take loads through export loader")
	root.add_child(loaded.world)
	scene.hide()
	loaded.seek(0.0)
	check(not loaded.subjects[1].visible, "late-spawn aircraft absent before birth")
	loaded.seek(0.1)
	check(loaded.subjects[1].visible, "aircraft visible on deck after retrieval")
	loaded.seek(loaded.duration())
	var visible_meshes := 0
	for child in loaded.subjects[1].get_children():
		if child is MeshInstance3D and child.is_visible_in_tree(): visible_meshes += 1
	check(visible_meshes > 0, "aircraft mesh visible after reload at launch endpoint")
	check(loaded.subjects[1].global_transform.is_equal_approx(final_pose), "launch motion preserved through save/load")
	if DisplayServer.get_name() != "headless":
		await process_frame
		camera.make_current()
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://captures/recording/ai_subject_replay.png")
	loaded.dispose()
	recorder.clear_take()
	scene.show()
	camera.make_current()
	check(recorder.start_background_recording(), "normal subject collection starts with AI already present")
	check(recorder.take.has_actor(aircraft), "AI-only aircraft included at recording start")
	recorder.stop_recording()
	recorder.clear_take()
	print("RECORDING_AI_SUBJECT_%s failures=%s" % ["PASS" if failures.is_empty() else "FAIL", failures])
	quit(0 if failures.is_empty() else 1)

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)
