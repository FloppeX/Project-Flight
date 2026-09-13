extends SceneTree
var failures: Array[String] = []
func _initialize() -> void: call_deferred("_run")

func _run() -> void:
	await process_frame
	for node in root.get_children(): node.process_mode = Node.PROCESS_MODE_DISABLED
	var mode := root.get_node("RecordingMode")
	mode.process_mode = Node.PROCESS_MODE_ALWAYS
	var director := root.get_node("FlightDirector")
	var pause := root.get_node("PauseMenu")
	pause.process_mode = Node.PROCESS_MODE_ALWAYS
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var aircraft := RigidBody3D.new()
	aircraft.freeze = true
	aircraft.add_to_group("aircraft")
	scene.add_child(aircraft)
	var hull := MeshInstance3D.new()
	hull.mesh = BoxMesh.new()
	hull.mesh.size = Vector3(3, 0.3, 2)
	aircraft.add_child(hull)
	var camera := Camera3D.new()
	var cockpit := Node3D.new()
	cockpit.name = "CameraCockpit"
	aircraft.add_child(cockpit)
	camera.name = "Camera3D"
	cockpit.add_child(camera)
	camera.position = Vector3(3, 2, 5)
	camera.look_at(Vector3.ZERO)
	camera.make_current()
	var mount: Node3D = load("res://Aircraft/CockpitPilot.tscn").instantiate()
	aircraft.add_child(mount)
	mount.set_presentation_active(true)
	var pilot: Node3D = mount.get_pilot_visual()
	pilot.set("_cockpit_camera", camera)
	pilot.call("_update_head_visibility", true)
	check(pilot.get("_last_head_hidden"), "normal cockpit hides pilot head")
	var overlay := CanvasLayer.new()
	scene.add_child(overlay)
	var hud := Label.new()
	hud.position = Vector2(20, 20)
	hud.text = "GAMEPLAY HUD — retained during recording"
	overlay.add_child(hud)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.1, 0.15, 0.2)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color.WHITE
	env.environment.ambient_light_energy = 0.8
	scene.add_child(env)
	director.current_viewed_aircraft = aircraft
	director.is_player_controlling = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var original_mouse := Input.mouse_mode
	var original_camera_pose := camera.global_transform
	var key := InputEventKey.new()
	key.physical_keycode = KEY_F9
	key.ctrl_pressed = true
	key.pressed = true
	check(key.is_action_pressed("toggle_background_recording", false, true), "Ctrl+F9 is bound")
	var old_key := InputEventKey.new()
	old_key.physical_keycode = KEY_F8
	old_key.pressed = true
	check(not old_key.is_action_pressed("toggle_background_recording"), "editor stop key F8 is not bound to recording")
	var plain_key := key.duplicate() as InputEventKey
	plain_key.ctrl_pressed = false
	root.push_input(plain_key)
	check(not mode.recording, "plain F9 does not start recording")
	var extra_modifier := key.duplicate() as InputEventKey
	extra_modifier.shift_pressed = true
	root.push_input(extra_modifier)
	check(not mode.recording, "Ctrl+Shift+F9 does not start recording")
	root.push_input(key)
	check(mode.background_recording and not mode.active and mode.camera == null, "Ctrl+F9 captures without editor camera")
	var repeat_key := key.duplicate() as InputEventKey
	repeat_key.echo = true
	root.push_input(repeat_key)
	check(mode.background_recording, "held recording shortcut does not toggle repeatedly")
	check(not paused and director.is_player_controlling and not director.recording_camera_active, "start preserves gameplay ownership")
	check(camera.current and camera.global_transform.is_equal_approx(original_camera_pose) and Input.mouse_mode == original_mouse, "start preserves view and mouse")
	check(overlay.visible, "start preserves HUD")
	pilot.call("_update_head_visibility", true)
	check(pilot.get("_last_head_hidden"), "background capture does not reveal live pilot head")
	var unmasked := 0
	for index in mode.take.sources.size():
		var source: Variant = mode.take.sources[index].get_ref()
		if source is MeshInstance3D and not source.is_visible_in_tree() and mode.take.frames[0].visible[index]: unmasked += 1
	check(unmasked > 0, "recorded pilot restores first-person masked meshes independently")
	for tick in 12:
		aircraft.position.x += 0.1
		await physics_frame
	mode._update_background_badge()
	check(mode._badge_layer.visible and mode._badge.text.begins_with("REC"), "background indicator shown")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://captures/recording/background_live.png")
	pause._open()
	var before: float = mode.elapsed
	for tick in 3: await physics_frame
	check(is_equal_approx(before, mode.elapsed), "pause stops capture time")
	check(pause._recording_button.text == "STOP RECORDING", "pause offers stop")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://captures/recording/background_pause.png")
	pause._close()
	var camera2 := Camera3D.new()
	scene.add_child(camera2)
	camera2.position = Vector3(-3, 2, 6)
	camera2.look_at(Vector3.ZERO)
	camera2.make_current()
	await process_frame
	check(camera2.current and overlay.visible, "camera switching remains available during capture")
	var offset := Vector3(1000, 0, 0)
	scene.position -= offset
	mode.apply_origin_shift(offset)
	for tick in 4: await physics_frame
	check(mode.take.origin_offset == offset, "background origin compensation active")
	root.push_input(key)
	check(not mode.recording and not paused and director.is_player_controlling and camera2.current, "Ctrl+F9 stop preserves live gameplay")
	var retained: RefCounted = mode.take
	mode._unhandled_key_input(key)
	check(mode.take == retained and not mode.recording, "Ctrl+F9 never overwrites a pending take")
	pause._open()
	check(mode.enter() and mode.replay, "opening editor automatically replays background take")
	check(paused and not overlay.visible and director.is_player_controlling, "replay pauses without surrendering control assignment")
	mode.seek(0.0)
	mode.camera.attach(null, 0)
	mode.camera.position = Vector3(3, 2, 5)
	mode.camera.look_at(Vector3.ZERO)
	mode.camera.attach(null, 0)
	mode.add_key()
	var saved: String = mode.save_take()
	check(not saved.is_empty(), "background take saves with camera shot")
	var loaded: RefCounted = load("res://Recording/SceneTake.gd").new()
	check(loaded.load_from(saved), "background take reloads in existing format")
	loaded.dispose()
	mode.exit()
	check(paused and camera2.current and director.is_player_controlling and overlay.visible, "editor exit restores paused gameplay")
	mode.clear_take()
	pause._close()
	# Pause-menu start resumes play, stop leaves an already-open menu paused.
	pause._open()
	pause._toggle_background_recording()
	check(mode.background_recording and not paused and not pause.visible, "pause-menu start resumes gameplay")
	await physics_frame
	pause._open()
	pause._toggle_background_recording()
	check(not mode.recording and paused and pause.visible, "pause-menu stop keeps pause menu open")
	mode.clear_take()
	pause._close()
	check(mode.start_background_recording(), "limit test starts")
	mode.elapsed = 120.0
	mode._physics_process(0.1)
	check(not mode.recording and not paused and director.is_player_controlling, "automatic take limit never pauses gameplay")
	mode.clear_take()
	check(mode.start_background_recording(), "scene-transition test starts")
	var next_scene := Node3D.new()
	root.add_child(next_scene)
	current_scene = next_scene
	paused = true
	mode._physics_process(0.1)
	check(not mode.recording and paused and mode.take != null, "scene change stops safely even while paused and retains take")
	mode.clear_take()
	director.current_viewed_aircraft = null
	director.is_player_controlling = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await process_frame
	print("[BackgroundRecordingSmoketest] %s failures=%s saved=%s" % ["PASS" if failures.is_empty() else "FAIL", failures, saved])
	quit(0 if failures.is_empty() else 1)

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)
