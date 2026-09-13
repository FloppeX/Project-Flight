extends SceneTree
var failures: Array[String] = []
func _initialize() -> void: call_deferred("_run")

func _run() -> void:
	await process_frame
	for node in root.get_children(): node.process_mode = Node.PROCESS_MODE_DISABLED
	var mode := root.get_node("RecordingMode")
	mode.process_mode = Node.PROCESS_MODE_ALWAYS
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.16, 0.18, 0.22)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.8
	scene.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, -25, 0)
	scene.add_child(light)
	var aircraft := Node3D.new()
	aircraft.name = "Aircraft"
	scene.add_child(aircraft)
	aircraft.add_to_group("aircraft")
	var mount: Node3D = load("res://Aircraft/CockpitPilot.tscn").instantiate()
	aircraft.add_child(mount)
	var dormant_camera := Node3D.new()
	dormant_camera.name = "CameraCockpit"
	aircraft.add_child(dormant_camera)
	var cockpit_camera := Camera3D.new()
	cockpit_camera.name = "Camera3D"
	dormant_camera.add_child(cockpit_camera)
	var budget := root.get_node("EnemyVisualBudget")
	var session: RefCounted = budget._get_cache_for_root(aircraft).presentation_session
	session.detach()
	check(mount.get_parent() == null, "pilot begins dormant")
	var carrier := Node3D.new()
	carrier.name = "LandCarrier"
	scene.add_child(carrier)
	carrier.add_to_group("carrier")
	var tread: Node3D = load("res://LandCarrier/CarrierTread.tscn").instantiate()
	carrier.add_child(tread)
	tread.position = Vector3(30, 0, 0)
	var camera := Camera3D.new()
	scene.add_child(camera)
	camera.position = Vector3(4, 2, 5)
	camera.look_at(Vector3(0, 1, 0))
	camera.make_current()
	budget.set_recording_occupants_active(aircraft, true, &"trailer_camera")
	mode.enter()
	var actors: Array[Node3D] = [aircraft, carrier]
	check(mode.start_recording(actors), "recording begins")
	paused = true
	check(mount.get_parent() == aircraft and mount.get_pilot_visual() != null, "recording attaches and acquires real pilot")
	budget.set_recording_occupants_active(aircraft, false, &"trailer_camera")
	check(mount._recording_presentation_active and mount.get_pilot_visual() != null, "releasing trailer camera cannot steal replay's pilot")
	budget.set_recording_occupants_active(aircraft, true, &"trailer_camera")
	check(dormant_camera.get_parent() == null, "cockpit camera remains dormant")
	mount.set_presentation_active(false)
	session.detach()
	budget._apply_ai_aircraft_player_only_budget(aircraft, false, budget._get_cache_for_root(aircraft))
	check(mount.get_parent() == aircraft and mount.get_pilot_visual() != null, "normal dormancy cannot steal pinned pilot")
	check(mount.is_visible_in_tree(), "visual budget does not hide pinned mount")
	var pilot: Node3D = mount.get_pilot_visual()
	pilot.set("_cockpit_camera", cockpit_camera)
	cockpit_camera.current = true
	pilot.call("_update_head_visibility", true)
	check(not pilot.get("_last_head_hidden"), "recorded pilot keeps head despite cockpit camera flag")
	var plates: MultiMeshInstance3D = tread.get_node("TrackPlates")
	var track := -1
	for index in range(mode.take.sources.size()):
		if mode.take.sources[index].get_ref() == plates: track = index
	check(track >= 0 and mode.take.frames[0].instances.has(track), "first frame includes plate data")
	var first: Transform3D = mode.take.frames[0].instances[track][0]
	for frame in range(1, 91):
		tread._advance_tracks(0.15)
		pilot.apply_static_baked_pose(&"piloting", frame / 30.0)
		mode.take.sample(frame / 30.0)
	var last: Transform3D = mode.take.frames.back().instances[track][0]
	check(not first.is_equal_approx(last), "production tread advances individual plates")
	mode.elapsed = 3.0
	mode.stop_recording()
	check(mount._recording_presentation_active and mount.get_pilot_visual() != null, "stopping replay capture cannot steal trailer camera's pilot")
	budget.set_recording_occupants_active(aircraft, false, &"trailer_camera")
	check(not mount._recording_presentation_active and mount.get_pilot_visual() == null, "stop returns unused pilot to pool")
	check(mount.get_parent() == null and dormant_camera.get_parent() == null, "original dormancy restored")
	check(not plates.has_meta("recording_instance_poses"), "capture metadata released")
	mode.enter_replay()
	mode.seek(0.0)
	var copy: MultiMeshInstance3D = mode.take.copies[track]
	if DisplayServer.get_name() != "headless":
		check(copy.multimesh.get_instance_transform(0).is_equal_approx(first), "rewind restores first plate transform")
	mode.seek(1.5)
	var middle: Transform3D = mode.take.frames[45].instances[track][0]
	if DisplayServer.get_name() != "headless":
		check(copy.multimesh.get_instance_transform(0).is_equal_approx(middle), "seek restores intermediate plate transform")
	mode.seek(0.0)
	mode.camera.attach(null, 0)
	mode.camera.global_position = Vector3(3, 1.7, 4)
	mode.camera.look_at(Vector3(0, 0.8, 0))
	mode.camera.attach(null, 0)
	mode.add_key()
	mode.selected_shot = 1
	mode._selected_subject = 1
	mode.camera.global_position = Vector3(53, 12, 20)
	mode.camera.look_at(Vector3(30, 5, 0))
	mode.camera.attach(null, 0)
	mode.add_key()
	var path: String = mode.save_take()
	var loaded: RefCounted = load("res://Recording/SceneTake.gd").new()
	check(loaded.load_from(path), "version 3 reloads")
	root.add_child(loaded.world)
	loaded.seek(1.5)
	if DisplayServer.get_name() != "headless":
		check(loaded.copies[track].multimesh.get_instance_transform(0).is_equal_approx(middle), "saved instance motion survives reload")
	loaded.dispose()
	mode._panel.hide()
	mode.play_shot = true
	DirAccess.make_dir_recursive_absolute("res://captures/recording")
	for shot in range(2):
		mode.selected_shot = shot
		mode.seek(1.5)
		for frame in range(3): await process_frame
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://captures/recording/presentation_%d.png" % shot)
	FileAccess.open("res://captures/recording/presentation_take_path.txt", FileAccess.WRITE).store_string(path)
	print("[RecordingPresentationSmoketest] %s failures=%s tracks=%d mib=%.2f take=%s" % ["PASS" if failures.is_empty() else "FAIL", failures, mode.take.copies.size(), mode.take.estimated_bytes / 1048576.0, path])
	mode.leave_replay()
	mode.clear_take()
	check(mode.start_recording(actors), "subsequent live take starts")
	for frame in range(120):
		carrier.position.z += 0.05
		await physics_frame
	mode.stop_recording()
	var live_track := -1
	for index in range(mode.take.sources.size()):
		if mode.take.sources[index].get_ref() == plates: live_track = index
	check(live_track >= 0 and mode.take.frames.back().instances.has(live_track), "live physics produces tread samples")
	if live_track >= 0 and mode.take.frames.back().instances.has(live_track):
		check(not (mode.take.frames[0].instances[live_track][0] as Transform3D).is_equal_approx(mode.take.frames.back().instances[live_track][0]), "live tread travel changes recorded instance data")
	print("[RecordingPresentationSmoketest] live %s frames=%d mean_ms=%.3f peak_ms=%.3f" % ["PASS" if failures.is_empty() else "FAIL", mode.take.frames.size(), mode._sampling_usec_total / float(maxi(mode._sampling_count, 1)) / 1000.0, mode._sampling_usec_max / 1000.0])
	mode.exit()
	mode.clear_take()
	session.restore(false)
	quit(0 if failures.is_empty() else 1)

func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		push_error(message)
