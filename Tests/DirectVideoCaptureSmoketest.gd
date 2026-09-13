extends SceneTree
var failures: Array[String] = []

func _initialize() -> void: run.call_deferred()

func expect(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		push_error(message)

func run() -> void:
	await process_frame
	for node in root.get_children(): node.process_mode = Node.PROCESS_MODE_DISABLED
	var capture := root.get_node("DirectVideoCapture")
	capture.process_mode = Node.PROCESS_MODE_ALWAYS
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world
	var trailer: Node
	if "--trailer-controls" in OS.get_cmdline_user_args():
		trailer = load("res://Scenario/Trailer/TrailerScenario.gd").new()
		world.add_child(trailer)
		trailer.ready_to_run = true
		paused = true
		var pause_key := InputEventKey.new()
		pause_key.keycode = KEY_SPACE
		pause_key.pressed = true
		root.push_input(pause_key)
		expect(not paused and trailer.started, "Space starts trailer action")
		pause_key.echo = true
		root.push_input(pause_key)
		expect(not paused, "Space repeat does not toggle")
		pause_key.echo = false
		root.push_input(pause_key)
		expect(paused, "Space pauses trailer")
	var cam_a := Camera3D.new()
	world.add_child(cam_a)
	cam_a.environment = Environment.new()
	cam_a.environment.background_mode = Environment.BG_COLOR
	cam_a.environment.background_color = Color(0.8, 0.04, 0.02)
	var cam_b := Camera3D.new()
	world.add_child(cam_b)
	cam_b.environment = Environment.new()
	cam_b.environment.background_mode = Environment.BG_COLOR
	cam_b.environment.background_color = Color(0.02, 0.05, 0.8)
	cam_a.make_current()
	if trailer != null:
		var subject := Node3D.new()
		world.add_child(subject)
		subject.add_to_group("ground_vehicles")
		var cameras := get_first_node_in_group("trailer_aircraft_cameras")
		cameras.select_slot(0, subject)
		var pause_key := InputEventKey.new()
		pause_key.physical_keycode = KEY_SPACE
		pause_key.pressed = true
		root.push_input(pause_key)
		expect(not paused and cameras.active, "Space resumes with mounted camera active")
		root.push_input(pause_key)
		expect(paused and cameras.active, "Space pauses without leaving mounted camera")
		cameras.release_camera()
	var box := MeshInstance3D.new()
	box.mesh = BoxMesh.new()
	box.position = Vector3(0, 0, -4)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color.YELLOW
	box.material_override = material
	world.add_child(box)
	var hud := CanvasLayer.new()
	world.add_child(hud)
	var cover := ColorRect.new()
	cover.size = Vector2(300, 300)
	cover.color = Color.GREEN
	hud.add_child(cover)
	var audio := AudioStreamPlayer.new()
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = 48000
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_end = 48000
	var samples := PackedByteArray()
	samples.resize(96000)
	for i in 48000: samples.encode_s16(i * 2, int(sin(TAU * 440 * i / 48000.0) * 8000))
	wav.data = samples
	audio.stream = wav
	world.add_child(audio)
	audio.play()
	await create_timer(1.0).timeout
	var effects_before := AudioServer.get_bus_effect_count(0)
	var key := InputEventKey.new()
	key.physical_keycode = KEY_F10
	key.ctrl_pressed = true
	key.pressed = true
	if trailer != null:
		key.physical_keycode = KEY_ALT
		key.location = KEY_LOCATION_LEFT
		key.alt_pressed = true
		root.push_input(key)
		expect(not capture.recording and paused, "left Ctrl+Alt does not record or unpause")
		key.location = KEY_LOCATION_RIGHT
	root.push_input(key)
	expect(capture.recording, "Ctrl+F10 starts direct video")
	if trailer != null:
		expect(not paused, "AltGr starts video and unpauses trailer")
		key.echo = true
		root.push_input(key)
		expect(capture.recording, "AltGr repeat does not stop capture")
		key.echo = false
	if capture.recording:
		var loose_overlay := ColorRect.new()
		loose_overlay.color = Color.MAGENTA
		loose_overlay.size = Vector2(300, 300)
		loose_overlay.position = Vector2(500, 0)
		world.add_child(loose_overlay) # Added after capture starts, without a CanvasLayer.
		var instrument_viewport := SubViewport.new()
		world.add_child(instrument_viewport)
		var instrument_control := ColorRect.new()
		instrument_viewport.add_child(instrument_control)
		await create_timer(2.0).timeout
		expect(not hud.visible, "HUD excluded from direct capture")
		expect(not loose_overlay.visible, "late overlay without CanvasLayer excluded")
		expect(instrument_control.visible, "instrument viewport UI preserved")
		loose_overlay.show()
		hud.show() # Simulate a dialogue system re-showing its panel during capture.
		await RenderingServer.frame_post_draw
		expect(not loose_overlay.visible and not hud.visible, "overlay re-show cannot leak into rendered frames")
		cam_b.make_current()
		for frame in 90:
			box.rotation.y += 0.025
			await process_frame
		await create_timer(2.0).timeout
		root.push_input(key)
		expect(not capture.recording and capture.finalizing, "Ctrl+F10 stops and finalizes")
		if trailer != null: expect(paused, "AltGr stop immediately pauses action during encoding")
		expect(hud.visible, "HUD restored")
		expect(loose_overlay.visible, "unlayered overlay visibility restored")
		expect(AudioServer.get_bus_effect_count(0) == effects_before, "audio bus restored")
		var deadline := Time.get_ticks_msec() + 60000
		while capture.finalizing and Time.get_ticks_msec() < deadline: await process_frame
		expect(not capture.finalizing and bool(capture.last_result.get("ok", false)), "playable MP4 encoding succeeded")
		print("DIRECT_VIDEO_RESULT ", JSON.stringify(capture.last_result))
		var first_directory: String = capture.last_directory
		audio.stop()
		expect(capture.start_capture(), "second recording starts after worker finalization")
		if trailer != null: expect(not paused, "API capture start also resumes trailer")
		await create_timer(0.75).timeout
		root.get_node("PauseMenu").visible = true
		await process_frame
		await process_frame
		expect(not capture.recording and root.get_node("PauseMenu").visible, "opening pause menu stops recording without hiding menu")
		if trailer != null: expect(paused, "automatic video stop also pauses trailer")
		expect(hud.visible and AudioServer.get_bus_effect_count(0) == effects_before, "second capture restores UI and audio")
		deadline = Time.get_ticks_msec() + 60000
		while capture.finalizing and Time.get_ticks_msec() < deadline: await process_frame
		expect(bool(capture.last_result.get("ok", false)) and capture.last_directory != first_directory, "silent second clip succeeds without overwriting first")
		print("DIRECT_VIDEO_SILENT_RESULT ", JSON.stringify(capture.last_result))
		ProjectSettings.set_setting("recording/ffmpeg_path", "res://missing_encoder.exe")
		expect(not capture.start_capture(), "missing encoder fails visibly without starting capture")
		if trailer != null: expect(paused, "failed recording start leaves trailer paused")
		expect(AudioServer.get_bus_effect_count(0) == effects_before, "failed start leaves audio bus unchanged")
		ProjectSettings.set_setting("recording/ffmpeg_path", null)
	print("DIRECT_VIDEO_CAPTURE_%s failures=%s" % ["PASS" if failures.is_empty() else "FAIL", failures])
	quit(0 if failures.is_empty() else 1)
