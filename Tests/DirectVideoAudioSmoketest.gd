extends SceneTree
var failures: Array[String] = []
func _initialize() -> void: run.call_deferred()
func expect(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func run() -> void:
	Engine.max_fps = 60
	await process_frame
	for node in root.get_children(): node.process_mode = Node.PROCESS_MODE_DISABLED
	var capture := root.get_node("DirectVideoCapture")
	capture.process_mode = Node.PROCESS_MODE_ALWAYS
	root.get_node("PauseMenu").visible = false
	root.get_node("LoadingScreen").visible = false
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.make_current()
	var player := AudioStreamPlayer.new()
	world.add_child(player)
	var wave := AudioStreamWAV.new()
	wave.format = AudioStreamWAV.FORMAT_16_BITS
	wave.mix_rate = 48000
	wave.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wave.loop_end = 48000
	var bytes := PackedByteArray()
	bytes.resize(96000)
	for i in 48000: bytes.encode_s16(i * 2, roundi(24576 * sin(TAU * 440 * i / 48000.0)))
	wave.data = bytes
	player.stream = wave
	player.volume_db = 6.0
	AudioServer.set_bus_volume_db(0, linear_to_db(0.44))
	AudioServer.set_bus_mute(0, false)
	player.play()
	await create_timer(0.3).timeout
	Engine.max_fps = 60 # After deferred settings initialization.
	var effects_before := AudioServer.get_bus_effect_count(0)
	expect(capture.start_capture(), "start float recording")
	if not capture.recording:
		quit(1)
		return
	while capture._started_usec == 0: await process_frame
	if "--overflow" in OS.get_cmdline_user_args():
		await check_overflow(capture, effects_before)
		return
	var segments: Array = []
	segments.append({"name": "normal", "time": 0.0})
	await create_timer(30.0 if "--long" in OS.get_cmdline_user_args() else 2.0).timeout
	player.volume_db = 18.0
	segments.append({"name": "overload", "time": float(Time.get_ticks_usec() - capture._started_usec) / 1e6})
	await create_timer(2.0).timeout
	player.volume_db = 6.0
	AudioServer.set_bus_volume_db(0, linear_to_db(0.15))
	segments.append({"name": "quiet", "time": float(Time.get_ticks_usec() - capture._started_usec) / 1e6})
	await create_timer(2.0).timeout
	AudioServer.set_bus_mute(0, true)
	segments.append({"name": "mute", "time": float(Time.get_ticks_usec() - capture._started_usec) / 1e6})
	await create_timer(1.0).timeout
	AudioServer.set_bus_mute(0, false)
	AudioServer.set_bus_volume_db(0, linear_to_db(0.44))
	segments.append({"name": "hitch", "time": float(Time.get_ticks_usec() - capture._started_usec) / 1e6})
	await create_timer(0.5).timeout
	OS.delay_msec(250) # Audio thread must keep collecting through main-thread stalls.
	await create_timer(1.5).timeout
	expect(is_equal_approx(AudioServer.get_bus_volume_db(0), linear_to_db(0.44)), "capture did not alter live volume")
	capture.stop_capture()
	expect(AudioServer.get_bus_effect_count(0) == effects_before, "stop restores bus effects")
	var deadline := Time.get_ticks_msec() + 60000
	while capture.finalizing and Time.get_ticks_msec() < deadline: await process_frame
	expect(bool(capture.last_result.get("ok", false)), "float audio and MP4 finalized")
	if capture.last_result.get("ok", false):
		expect(capture.last_result.audio_peak_before_gain > 1.0, "float input retains previously clipped peaks")
		expect(capture.last_result.audio_over_limit_frames > 0, "overload exercised limiter")
		expect(capture.last_result.audio_discarded_frames == 0, "no audio frames lost through induced hitch")
		expect(absf(capture.last_result.audio_wall_drift_ms) < 100.0, "audio duration tracks wall clock")
	print("DIRECT_AUDIO_SEGMENTS ", JSON.stringify(segments))
	print("DIRECT_AUDIO_RESULT ", JSON.stringify(capture.last_result))
	print("DIRECT_VIDEO_AUDIO_%s failures=%s" % ["PASS" if failures.is_empty() else "FAIL", failures])
	quit(0 if failures.is_empty() else 1)

func check_overflow(capture: Node, effects_before: int) -> void:
	await create_timer(0.3).timeout
	OS.delay_msec(3500) # Exceed the actual power-of-two ring capacity on purpose.
	for frame in 3: await process_frame
	expect(not capture.recording, "audio overrun automatically stops recording")
	var deadline := Time.get_ticks_msec() + 60000
	while capture.finalizing and Time.get_ticks_msec() < deadline: await process_frame
	expect(not capture.last_result.get("ok", true), "overrun is not reported as successful video")
	expect(capture.last_result.get("audio_discarded_frames", 0) > 0, "discarded audio frames are counted")
	expect("Audio buffer overrun" in str(capture.last_result.get("error", "")), "failure names audio buffer overrun")
	expect(FileAccess.file_exists(capture.last_directory.path_join("audio.f32le")), "raw float audio retained after failure")
	expect(FileAccess.file_exists(capture.last_directory.path_join("frames.mjpeg")), "raw video retained after failure")
	expect(AudioServer.get_bus_effect_count(0) == effects_before, "failure restores audio effects")
	print("DIRECT_AUDIO_OVERRUN_RESULT ", JSON.stringify(capture.last_result))
	print("DIRECT_AUDIO_OVERRUN_%s failures=%s" % ["PASS" if failures.is_empty() else "FAIL", failures])
	quit(0 if failures.is_empty() else 1)
