extends Node
signal capture_started
signal capture_stopped
## Live viewport pixels + Master bus audio. No replay subjects or desktop capture.
const FPS := 30
const MAX_SECONDS := 300.0
const MAX_QUEUE := 4
const OUTPUT_SIZE := Vector2i(1920, 1080)
const AudioWriter = preload("res://Recording/VideoAudioWriter.gd")
const AUDIO_BUFFER_SECONDS := 2.0
const AUDIO_QUEUE_SECONDS := 4.0
var recording := false
var finalizing := false
var last_directory := ""
var message := "Ctrl+F10: start/stop video · Ctrl+Shift+F10: open videos"
var last_result: Dictionary = {}
var _thread := Thread.new()
var _mutex := Mutex.new()
var _semaphore := Semaphore.new()
var _queue: Array[Dictionary] = []
var _worker_error := ""
var _audio: AudioEffectCapture
var _audio_rate := 48000
var _audio_discard_start := 0
var _audio_error := ""
var _queued_images := 0
var _queued_audio_frames := 0
var _scene: WeakRef
var _started_usec := 0
var _last_index := -1
var _dropped := 0
var _readback_usec := 0
var _readback_max_usec := 0
var _captured := 0
var _old_title := ""
var _canvases: Dictionary = {}
var _notice: CanvasLayer
var _label: Label
var _notice_until := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 2000
	RenderingServer.frame_pre_draw.connect(_before_draw)
	RenderingServer.frame_post_draw.connect(_after_draw)
	get_tree().node_added.connect(_track_new_canvas)
	_notice = CanvasLayer.new()
	_notice.layer = 150
	add_child(_notice)
	_label = Label.new()
	_label.position = Vector2(20, 270)
	_label.add_theme_font_size_override("font_size", 18)
	_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	_label.add_theme_constant_override("shadow_outline_size", 6)
	_notice.add_child(_label)
	_notice.hide()

func output_root() -> String:
	return ProjectSettings.globalize_path("user://videos")

func _notify(text: String) -> void:
	message = text
	_notice_until = Time.get_ticks_msec() + 12000
	print("[DirectVideo] ", text)

func toggle_capture() -> bool:
	if recording:
		stop_capture()
		return true
	return start_capture()

func start_capture() -> bool:
	if recording or finalizing:
		_notify("Video is already recording or finishing. Please wait.")
		return false
	var trailer := get_tree().get_first_node_in_group("trailer_scenario")
	if trailer != null and not trailer.ready_to_run:
		_notify("Wait for Trailer Scenario to finish staging before recording.")
		return false
	if not get_tree().current_scene is Node3D or DisplayServer.get_name() == "headless":
		_notify("Video capture needs a running, rendered scenario.")
		return false
	if RecordingMode.active or RecordingMode.recording or PauseMenu.is_photo_mode_active():
		_notify("Leave Recording/Photo Mode and stop replay-data capture before starting live video.")
		return false
	var ffmpeg := str(ProjectSettings.get_setting("recording/ffmpeg_path", ""))
	if ffmpeg.is_empty(): ffmpeg = ScreenshotCapture._find_ffmpeg_executable()
	if not FileAccess.file_exists(ffmpeg):
		_notify("FFmpeg not found. Set recording/ffmpeg_path to an ffmpeg executable.")
		return false
	var stamp := Time.get_datetime_string_from_system().replace(":", "-")
	last_directory = output_root().path_join("%s_%d" % [stamp, Time.get_ticks_usec()])
	if DirAccess.make_dir_recursive_absolute(last_directory) != OK:
		_notify("Cannot create video output folder.")
		return false
	_queue.clear()
	_queued_images = 0
	_queued_audio_frames = 0
	_audio_error = ""
	_worker_error = ""
	_started_usec = 0
	_last_index = -1
	_dropped = 0
	_readback_usec = 0
	_readback_max_usec = 0
	_captured = 0
	last_result = {}
	_scene = weakref(get_tree().current_scene)
	_audio_rate = int(AudioServer.get_mix_rate())
	_audio = AudioEffectCapture.new()
	_audio.buffer_length = AUDIO_BUFFER_SECONDS
	AudioServer.add_bus_effect(0, _audio)
	_old_title = get_window().title
	var error := _thread.start(_encode_worker.bind(ffmpeg, last_directory, _audio_rate))
	if error != OK:
		_remove_audio()
		_notify("Could not start video writer: %s" % error)
		return false
	recording = true
	_collect_capture_overlays(get_tree().root)
	_notify("VIDEO recording — %s stops. HUD hidden; camera cuts and game audio included." % ("AltGr" if trailer != null else "Ctrl+F10"))
	capture_started.emit()
	return true

func _before_draw() -> void:
	if not recording: return
	if PauseMenu.visible or LoadingScreen.visible or RecordingMode.active or PauseMenu.is_photo_mode_active():
		stop_capture("Stopped before menu / loading overlay")
		return
	# Hide only main-viewport overlays; cockpit/bridge instrument viewports stay.
	for item: Variant in _canvases:
		if is_instance_valid(item): item.hide()

func _collect_capture_overlays(node: Node) -> void:
	if node is Viewport and node != get_viewport(): return
	_track_new_canvas(node)
	for child in node.get_children(): _collect_capture_overlays(child)

func _track_new_canvas(node: Node) -> void:
	# One startup traversal plus new layers; never walk the whole battle every frame.
	if not recording or not (node is CanvasLayer or node is CanvasItem) or node.get_viewport() != get_viewport(): return
	if node is CanvasLayer and node.custom_viewport != null and node.custom_viewport != get_viewport(): return
	var ancestor: Node = node
	while ancestor != null and ancestor != get_viewport():
		if ancestor == PauseMenu or ancestor == LoadingScreen: return
		# Hide only UI roots: descendants already inherit their parent's visibility.
		if node is CanvasItem and ancestor != node and (ancestor is CanvasItem or ancestor is CanvasLayer): return
		ancestor = ancestor.get_parent()
	if not _canvases.has(node): _canvases[node] = node.visible

func _after_draw() -> void:
	if not recording: return
	var now := Time.get_ticks_usec()
	var index := 0 if _started_usec == 0 else int((now - _started_usec) * FPS / 1000000)
	if index <= _last_index: return
	_mutex.lock()
	var full := _queued_images >= MAX_QUEUE
	_mutex.unlock()
	if full:
		_dropped += 1
		return
	var image := get_viewport().get_texture().get_image()
	if image == null or image.is_empty():
		stop_capture("Viewport readback failed")
		return
	var cost := Time.get_ticks_usec() - now
	_readback_usec += cost
	_readback_max_usec = maxi(_readback_max_usec, cost)
	_captured += 1
	if _started_usec == 0:
		_started_usec = now
		# Discard pre-roll only; never clear the ring during a recording.
		_audio.clear_buffer()
		_audio_discard_start = _audio.get_discarded_frames()
	_last_index = index
	_push({"image": image, "index": index})

func _push(job: Dictionary) -> void:
	_mutex.lock()
	if job.has("image"): _queued_images += 1
	if job.has("audio"): _queued_audio_frames += job.audio.size()
	_queue.append(job)
	_mutex.unlock()
	_semaphore.post()

func _drain_audio() -> void:
	if _audio == null or _started_usec == 0: return
	if _audio.get_discarded_frames() > _audio_discard_start:
		_audio_error = "Audio buffer overrun — capture stopped; source files retained"
	var count := _audio.get_frames_available()
	if count == 0: return
	_mutex.lock()
	var overloaded := _queued_audio_frames + count > int(_audio_rate * AUDIO_QUEUE_SECONDS)
	_mutex.unlock()
	if overloaded:
		_audio_error = "Audio writer fell behind — capture stopped; source files retained"
		return
	# Bus effects run before the Master fader. Apply its output gain to the
	# recording copy in the worker, without touching live playback or bus routing.
	var gain := 0.0 if AudioServer.is_bus_mute(0) else db_to_linear(AudioServer.get_bus_volume_db(0))
	_push({"audio": _audio.get_buffer(count), "gain": gain})

func _remove_audio() -> void:
	if _audio == null: return
	for index in range(AudioServer.get_bus_effect_count(0) - 1, -1, -1):
		if AudioServer.get_bus_effect(0, index) == _audio: AudioServer.remove_bus_effect(0, index)

func stop_capture(reason: String = "") -> void:
	if not recording: return
	recording = false
	finalizing = true
	_remove_audio()
	# The effect retains its ring after removal; no new mixer writes can race
	# the final drain. Gain changes are sampled at main-frame granularity.
	_drain_audio()
	var discarded := maxi(0, _audio.get_discarded_frames() - _audio_discard_start)
	_audio = null
	var duration := (Time.get_ticks_usec() - _started_usec) / 1000000.0 if _started_usec != 0 else 0.0
	_push({"stop": true, "audio_error": _audio_error, "frames": maxi(1, ceili(duration * FPS)), "stats": {
		"audio_discarded_frames": discarded,
		"seconds": duration, "captured_frames": _captured, "queue_skips": _dropped,
		"readback_mean_ms": _readback_usec / maxf(_captured, 1) / 1000.0,
		"readback_max_ms": _readback_max_usec / 1000.0, "stop_reason": reason}})
	_restore_ui()
	_notify("Finishing video… " + reason)
	capture_stopped.emit()

func _restore_ui() -> void:
	for item: Variant in _canvases:
		if is_instance_valid(item): item.visible = _canvases[item]
	_canvases.clear()
	get_window().title = _old_title

func _process(_delta: float) -> void:
	if recording:
		_drain_audio()
		_mutex.lock()
		var error := _worker_error
		_mutex.unlock()
		if not _audio_error.is_empty(): error = _audio_error
		if not error.is_empty(): stop_capture(error)
		elif PauseMenu.visible or PauseMenu.is_photo_mode_active() or RecordingMode.active: stop_capture("Stopped before camera editor / pause menu")
		elif _scene.get_ref() != get_tree().current_scene: stop_capture("Scenario changed")
		elif _started_usec != 0:
			var elapsed := (Time.get_ticks_usec() - _started_usec) / 1000000.0
			get_window().title = "[VIDEO REC %02d:%02d] %s" % [int(elapsed) / 60, int(elapsed) % 60, _old_title]
			if elapsed >= MAX_SECONDS: stop_capture("Five-minute safety limit reached")
	if _thread.is_started() and not _thread.is_alive():
		last_result = _thread.wait_to_finish()
		finalizing = false
		_notify("Saved video: %s" % last_result.path if last_result.ok else "Video failed: %s — source files kept in %s" % [last_result.error, last_directory])
	_label.text = message
	_notice.visible = not recording and (finalizing or Time.get_ticks_msec() < _notice_until)

func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	var key: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
	if recording and key == KEY_ESCAPE:
		stop_capture("Stopped before pause menu")
		return
	if key != KEY_F10 or not event.ctrl_pressed or event.alt_pressed or event.meta_pressed: return
	if event.shift_pressed:
		DirAccess.make_dir_recursive_absolute(output_root())
		OS.shell_open(output_root())
	else:
		var focus := get_viewport().gui_get_focus_owner()
		if focus is LineEdit or focus is TextEdit: return
		var was_recording := recording
		if toggle_capture() and not was_recording and PauseMenu.visible: PauseMenu._close()
	get_viewport().set_input_as_handled()

func _encode_worker(ffmpeg: String, directory: String, audio_rate: int) -> Dictionary:
	# The worker touches only private images/files, never the live scene tree.
	var raw_path := directory.path_join("frames.mjpeg")
	var raw := FileAccess.open(raw_path, FileAccess.WRITE)
	var audio := AudioWriter.new(directory, audio_rate)
	var last_jpeg := PackedByteArray()
	var written := 0
	var failure := "" if raw != null else "Cannot write frame stream"
	var stop: Dictionary
	while true:
		_semaphore.wait()
		_mutex.lock()
		var job: Dictionary = _queue.pop_front()
		if job.has("image"): _queued_images -= 1
		if job.has("audio"): _queued_audio_frames -= job.audio.size()
		_mutex.unlock()
		if job.has("stop"):
			stop = job
			break
		if failure.is_empty() and job.has("audio"):
			if not audio.append(job.audio, float(job.gain)):
				failure = "Game audio write failed (disk full or invalid samples)"
		elif failure.is_empty():
			var source: Image = job.image
			source.convert(Image.FORMAT_RGB8)
			if source.get_size() != OUTPUT_SIZE:
				var factor := minf(float(OUTPUT_SIZE.x) / source.get_width(), float(OUTPUT_SIZE.y) / source.get_height())
				source.resize(maxi(1, roundi(source.get_width() * factor)), maxi(1, roundi(source.get_height() * factor)), Image.INTERPOLATE_BILINEAR)
				var fitted := Image.create(OUTPUT_SIZE.x, OUTPUT_SIZE.y, false, Image.FORMAT_RGB8)
				fitted.fill(Color.BLACK)
				fitted.blit_rect(source, Rect2i(Vector2i.ZERO, source.get_size()), (OUTPUT_SIZE - source.get_size()) / 2)
				source = fitted
			var jpeg := source.save_jpg_to_buffer(0.9)
			if last_jpeg.is_empty(): last_jpeg = jpeg
			# Duplicate missed frame intervals, never accelerate the action or audio.
			while written < int(job.index):
				raw.store_buffer(last_jpeg)
				written += 1
			raw.store_buffer(jpeg)
			written += 1
			last_jpeg = jpeg
			if raw.get_error() != OK: failure = "Frame stream write failed (disk full?)"
		if not failure.is_empty():
			_mutex.lock()
			_worker_error = failure
			_mutex.unlock()
	if raw != null:
		while failure.is_empty() and not last_jpeg.is_empty() and written < int(stop.frames):
			raw.store_buffer(last_jpeg)
			written += 1
		if raw.get_error() != OK: failure = "Frame stream write failed (disk full?)"
		raw.close()
	var wav_path := directory.path_join("audio.wav")
	var audio_failure := audio.finish(ffmpeg, wav_path)
	if failure.is_empty(): failure = audio_failure
	if failure.is_empty(): failure = str(stop.get("audio_error", ""))
	if written == 0: failure = "No rendered frames captured"
	var output := directory.path_join("video.mp4")
	var encoder_output: Array = []
	if failure.is_empty():
		var args := PackedStringArray(["-hide_banner", "-loglevel", "error", "-n", "-f", "mjpeg", "-framerate", str(FPS), "-i", raw_path, "-i", wav_path, "-map", "0:v:0", "-map", "1:a:0", "-c:v", "libx264", "-preset", "veryfast", "-crf", "18", "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "192k", "-af", "apad", "-t", str(float(written) / FPS), "-movflags", "+faststart", output])
		var exit_code := OS.execute(ffmpeg, args, encoder_output, true, false)
		if exit_code != 0 or not FileAccess.file_exists(output): failure = "FFmpeg exit %d: %s" % [exit_code, str(encoder_output)]
	var stats: Dictionary = stop.stats
	stats.merge(audio.stats())
	stats["output_frames"] = written
	stats["repeated_frames"] = maxi(0, written - int(stats.captured_frames))
	stats["ok"] = failure.is_empty()
	stats["error"] = failure
	stats["path"] = output
	stats["audio_wall_drift_ms"] = (float(stats.audio_seconds) - float(stats.seconds)) * 1000.0
	var manifest := FileAccess.open(directory.path_join("capture.json"), FileAccess.WRITE)
	if manifest != null: manifest.store_string(JSON.stringify(stats, "\t"))
	# Only this recording's generated raw frames, after successful MP4 encoding.
	# Keep the WAV for editing, and retain everything on failure for recovery.
	if failure.is_empty():
		DirAccess.remove_absolute(raw_path)
		DirAccess.remove_absolute(audio.path)
	return stats

func _exit_tree() -> void:
	if recording: stop_capture("Game closing")
	if _thread.is_started(): _thread.wait_to_finish()
