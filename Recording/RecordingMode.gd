extends Node
## Short visual takes and independent camera shots. Export runs in a separate
## renderer process; the interactive game never pretends it is encoding video.
const Take = preload("res://Recording/SceneTake.gd")
const Rig = preload("res://Recording/RecordingCamera.gd")
var active := false
var recording := false
var replay := false
var playing := false
var camera: Camera3D
var take: RefCounted
var elapsed := 0.0
var playhead := 0.0
var sample_accumulator := 0.0
var selected_shot := 0
var play_shot := false
var last_saved_directory := ""
var _subjects: Array[Node3D] = []
var _selected_subject := 0
var _previous_camera: Camera3D
var _previous_mouse := Input.MOUSE_MODE_VISIBLE
var _canvases: Dictionary = {}
var _suspended: Array = []
var _scene_visibility := true
var _layer: CanvasLayer
var _panel: PanelContainer
var _status: Label
var _timeline: HSlider
var _subject_picker: OptionButton
var _attachment_picker: OptionButton
var _shot_picker: OptionButton
var _message := ""
var _mouse_look := Vector2.ZERO
var _export_pid := -1
var _export_file := ""
var _export_result := ""
var _open_dialog: FileDialog
var _replay_master_muted := false
var _capture_center := Vector3.ZERO
var _discovery_accumulator := 0.0
var _sampling_usec_total := 0
var _sampling_usec_max := 0
var _sampling_count := 0
var _clock_physics_frame := -1
var background_recording := false
var _background_take := false
var _capture_scene: WeakRef
var _badge_layer: CanvasLayer
var _badge: Label
var _notice_until_ms := 0

func capture_time() -> float:
	# Spawn/retire callbacks can run before our late physics callback. Timestamp
	# them on that same tick, not the preceding sample. Render effects use elapsed.
	return elapsed + (get_physics_process_delta_time() if Engine.is_in_physics_frame() and _clock_physics_frame != Engine.get_physics_frames() else 0.0)

func capture_transient(node: Node3D, kind: String) -> void:
	if not recording or take == null or not is_instance_valid(node) or not node.is_inside_tree(): return
	if (node.global_position + take.origin_offset).distance_to(_capture_center) > 1800.0: return
	take.combat.begin(take, node, capture_time(), kind)

func end_transient(id: int) -> void:
	if recording and take != null: take.combat.end(take, id, capture_time())

func _ready() -> void:
	if not InputMap.has_action("toggle_background_recording"):
		InputMap.add_action("toggle_background_recording")
		var key := InputEventKey.new()
		# F8 is Godot's stop-project shortcut in editor-launched games.
		key.physical_keycode = KEY_F9
		key.ctrl_pressed = true
		InputMap.action_add_event("toggle_background_recording", key)
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 1000
	process_physics_priority = 1000 # Sample after normal actor physics updates.
	add_to_group("origin_shifter")
	add_to_group("target_camera_focus_provider")
	_build_ui()
	_build_background_badge()

func enter() -> bool:
	if active: return true
	if not get_tree().current_scene is Node3D: return false
	if background_recording: stop_recording()
	var source_camera := get_viewport().get_camera_3d()
	get_tree().call_group("trailer_aircraft_cameras", "release_camera")
	_previous_camera = get_viewport().get_camera_3d()
	_previous_mouse = Input.mouse_mode
	camera = Rig.new()
	camera.name = "RecordingCamera"
	add_child(camera)
	if is_instance_valid(source_camera): FlightDirector._copy_camera_view_state(source_camera, camera)
	camera.attach(null, 0)
	active = true
	FlightDirector.recording_camera_active = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_layer.show()
	_panel.show()
	_collect_subjects()
	_suppress_ui()
	camera.make_current()
	_message = "Compose while paused. RUN / RECORD hands player aircraft to AI."
	if _background_take and take != null: return enter_replay()
	return true

func exit() -> void:
	if not active: return
	if recording: stop_recording()
	if replay: leave_replay()
	active = false
	FlightDirector.recording_camera_active = false
	for item: Variant in _canvases:
		if is_instance_valid(item): item.visible = _canvases[item]
	_canvases.clear()
	_layer.hide()
	Input.mouse_mode = _previous_mouse
	if is_instance_valid(_previous_camera): FlightDirector._force_current_camera(_previous_camera)
	else: FlightDirector._activate_view()
	if is_instance_valid(camera): camera.queue_free()
	camera = null
	get_tree().paused = true
	PauseMenu.visible = true
	PauseMenu._show_screen("main")

func _collect_subjects() -> void:
	_subjects.clear()
	for group in Take.SUBJECT_GROUPS:
		for node in get_tree().get_nodes_in_group(group):
			if node is Node3D and is_instance_valid(node) and not _subjects.has(node): _subjects.append(node)
	var viewed: Variant = FlightDirector.current_viewed_aircraft
	if is_instance_valid(viewed) and not _subjects.has(viewed): _subjects.append(viewed)
	_selected_subject = maxi(0, _subjects.find(viewed))
	_refresh_subject_picker()

func _refresh_subject_picker() -> void:
	_subject_picker.clear()
	var subjects: Array = take.subjects if replay and take != null else _subjects
	for subject in subjects:
		_subject_picker.add_item(str(subject.get_meta("display_name", subject.name)) if is_instance_valid(subject) else "<removed>")
	_selected_subject = clampi(_selected_subject, 0, maxi(0, subjects.size() - 1))
	if not subjects.is_empty(): _subject_picker.select(_selected_subject)

func _subject() -> Node3D:
	var subjects: Array = take.subjects if replay and take != null else _subjects
	if _selected_subject >= subjects.size(): return null
	return subjects[_selected_subject] if is_instance_valid(subjects[_selected_subject]) else null

func _handoff() -> void:
	if FlightDirector.is_player_controlling: FlightDirector._return_control_to_ai()

func is_target_camera_focusing_node(node: Node3D) -> bool:
	return recording and take != null and is_instance_valid(node) and take.focuses(node)

func _discover_subjects() -> void:
	# Lifetime slots: a removed actor keeps its ID so old frames/camera keys
	# cannot accidentally point at its replacement. Bounds stay at take origin.
	var changed := false
	for group in Take.SUBJECT_GROUPS:
		for candidate in get_tree().get_nodes_in_group(group):
			if not is_instance_valid(candidate) or not candidate is Node3D: continue
			if take.has_actor(candidate): continue
			if (candidate.global_position + take.origin_offset).distance_to(_capture_center) > 1800.0: continue
			if take.add_actor(candidate):
				if not _subjects.has(candidate): _subjects.append(candidate)
				changed = true
	if changed: _refresh_subject_picker()

func toggle_run() -> void:
	if replay:
		playing = not playing
	else:
		_handoff()
		get_tree().paused = not get_tree().paused

func start_recording(actors: Array[Node3D] = []) -> bool:
	if not active or recording or replay: return false
	if not _begin_capture(actors, camera.global_position, false): return false
	_handoff()
	get_tree().paused = false
	return true

func start_background_recording(actors: Array[Node3D] = []) -> bool:
	if active or recording or replay or PauseMenu.is_photo_mode_active(): return false
	if not get_tree().current_scene is Node3D: return false
	var live_camera := get_viewport().get_camera_3d()
	if not is_instance_valid(live_camera): return false
	_collect_subjects()
	return _begin_capture(actors, live_camera.global_position, true)

func toggle_background_recording() -> bool:
	if background_recording:
		stop_recording()
		return true
	var started := start_background_recording()
	if not started:
		_notice_until_ms = Time.get_ticks_msec() + 6000
	return started

func _begin_capture(actors: Array[Node3D], center: Vector3, background: bool) -> bool:
	var video := get_node_or_null("/root/DirectVideoCapture")
	if video != null and (video.recording or video.finalizing):
		_message = "Stop direct video and wait for it to finish before recording replay data."
		return false
	if take != null:
		_message = "Save this take first, then CLEAR TAKE before recording another."
		return false
	if actors.is_empty():
		var subject := _subject()
		if is_instance_valid(subject): actors.append(subject)
		for candidate in _subjects:
			if actors.size() >= Take.MAX_SUBJECTS: break
			if is_instance_valid(candidate) and not actors.has(candidate) and (candidate.is_in_group("carrier") or candidate.global_position.distance_to(center) < 1800.0):
				actors.append(candidate)
	take = Take.new()
	if not take.build(get_tree().current_scene, actors, center):
		_message = take.warning if not take.warning.is_empty() else "No subjects available."
		take.dispose()
		take = null
		return false
	# Keep visual copies out of the live tree until replay. Hidden environment
	# nodes would still affect the live viewport if we merely hid their parent.
	background_recording = background
	_background_take = background
	recording = true
	take.sample(0.0)
	_capture_scene = weakref(get_tree().current_scene)
	_capture_center = center
	_discovery_accumulator = 0.0
	_sampling_usec_total = 0
	_sampling_usec_max = 0
	_sampling_count = 0
	elapsed = 0.0
	sample_accumulator = 0.0
	recording = true
	_clock_physics_frame = Engine.get_physics_frames()
	for effect in get_tree().get_nodes_in_group("recording_transient"):
		if effect is Node3D: capture_transient(effect, str(effect.get_meta("recording_kind", "effect")))
	_message = "Recording scene data (%d subjects), NOT video/audio." % actors.size()
	return true

func stop_recording() -> void:
	if not recording: return
	var was_background := background_recording
	recording = false
	take.sample(elapsed)
	take.release_presentation()
	background_recording = false
	if not was_background: get_tree().paused = true
	_message = "Take captured. REPLAY to scrub and film; SAVE TAKE to preserve it."
	print("[RecordingMode] capture subjects=%d tracks=%d frames=%d estimated_mib=%.2f sample_mean_ms=%.3f sample_max_ms=%.3f warning=%s" % [
		take.subjects.size(), take.copies.size(), take.frames.size(), take.estimated_bytes / 1048576.0,
		_sampling_usec_total / float(maxi(1, _sampling_count)) / 1000.0, _sampling_usec_max / 1000.0, take.warning])

func enter_replay() -> bool:
	if take == null or take.frames.is_empty(): return false
	if recording: stop_recording()
	if replay: return true
	get_tree().paused = true
	# Pause even PROCESS_MODE_ALWAYS gameplay nodes; do not touch their state.
	_replay_master_muted = AudioServer.is_bus_mute(0)
	AudioServer.set_bus_mute(0, true)
	for node in get_tree().root.get_children():
		if node != self: _suspend_tree(node)
	_scene_visibility = get_tree().current_scene.visible
	get_tree().current_scene.hide()
	add_child(take.world)
	take.world.show()
	replay = true
	playing = false
	play_shot = false
	_refresh_subject_picker()
	camera.global_position += take.origin_offset
	camera.attach(null, 0)
	_attachment_picker.select(0)
	seek(0.0)
	_message = "REPLAY: live world suspended. Add keys to shot A or B at different times."
	return true

func _suspend_tree(node: Node) -> void:
	_suspended.append([weakref(node), node.process_mode])
	node.process_mode = Node.PROCESS_MODE_DISABLED
	for child in node.get_children(): _suspend_tree(child)

func leave_replay() -> void:
	if not replay: return
	replay = false
	playing = false
	play_shot = false
	camera.attach(null, 0)
	camera.aim_target = null
	camera.global_position -= take.origin_offset
	camera.attach(null, 0)
	remove_child(take.world)
	get_tree().current_scene.visible = _scene_visibility
	for item in _suspended:
		var node: Variant = item[0].get_ref()
		if is_instance_valid(node): node.process_mode = item[1]
	_suspended.clear()
	AudioServer.set_bus_mute(0, _replay_master_muted)
	_refresh_subject_picker()
	get_tree().paused = true
	_message = "Live world restored at the end of the take; still paused."

func seek(time: float) -> void:
	if not replay: return
	playhead = clampf(time, 0.0, take.duration())
	take.seek(playhead)
	if play_shot: camera.apply_keys(take.shots[selected_shot], playhead, take.subjects)
	_timeline.set_value_no_signal(playhead)

func add_key() -> void:
	if not replay: return
	var keys: Array = take.shots[selected_shot]
	for index in range(keys.size() - 1, -1, -1):
		if absf(float(keys[index].time) - playhead) < 0.02: keys.remove_at(index)
	keys.append(camera.shot_key(playhead, _selected_subject))
	keys.sort_custom(func(a, b): return a.time < b.time)
	_message = "Shot %s: %d keys. PREVIEW SHOT plays its camera path." % ["A" if selected_shot == 0 else "B", keys.size()]

func save_take() -> String:
	if take == null or recording: return ""
	# Each save is a new directory; never overwrite the only saved version.
	var stamp := Time.get_datetime_string_from_system().replace(":", "-")
	var directory := "user://recordings/%s_%d" % [stamp, Time.get_ticks_msec()]
	var error: Error = take.save_to(directory)
	if error != OK:
		_message = "Save failed: %s" % error_string(error)
		return ""
	last_saved_directory = ProjectSettings.globalize_path(directory)
	_message = "Saved: %s" % last_saved_directory
	print("[RecordingMode] saved=%s" % last_saved_directory)
	return last_saved_directory

func export_shot() -> void:
	if take == null or take.shots[selected_shot].is_empty():
		_message = "Add at least one camera key to this shot before exporting."
		return
	if _export_pid > 0 and OS.is_process_running(_export_pid):
		_message = "An export is already running."
		return
	var directory := save_take()
	if directory.is_empty(): return
	_export_file = directory.path_join("shot_%s.avi" % ("A" if selected_shot == 0 else "B"))
	_export_result = directory.path_join("export_result.txt")
	var args := PackedStringArray(["--path", ProjectSettings.globalize_path("res://"),
		"--script", "res://Recording/ExportTake.gd", "--write-movie", _export_file,
		"--fixed-fps", "30", "--resolution", "1920x1080", "--",
		"--take", directory, "--shot", str(selected_shot)])
	_export_pid = OS.create_process(OS.get_executable_path(), args, false)
	_message = "Exporting silent shot in a separate renderer. Game sounds are not recorded yet." if _export_pid > 0 else "Could not launch the export renderer."

func open_take(directory: String) -> bool:
	if recording or take != null:
		_message = "Save and clear the current take before opening another."
		return false
	var loaded := Take.new()
	if not loaded.load_from(directory):
		loaded.dispose()
		_message = "Could not read that take."
		return false
	take = loaded
	last_saved_directory = directory
	return enter_replay()

func clear_take() -> void:
	if recording: return
	if replay: leave_replay()
	if take != null: take.dispose()
	take = null
	_background_take = false
	_message = "Take cleared from memory. Saved takes are untouched."

func apply_origin_shift(offset: Vector3) -> void:
	if replay: return
	if recording: take.origin_offset += offset
	if not active or not is_instance_valid(camera): return
	camera.global_position -= offset
	camera.offset = camera.anchor().affine_inverse() * camera.global_transform

func _physics_process(delta: float) -> void:
	if not recording: return
	var scene: Variant = _capture_scene.get_ref() if _capture_scene != null else null
	if not is_instance_valid(scene) or scene != get_tree().current_scene:
		stop_recording()
		_message = "Recording stopped because the scenario changed. Take retained; open Recording Mode to save it."
		return
	if get_tree().paused: return
	elapsed += delta
	_clock_physics_frame = Engine.get_physics_frames()
	sample_accumulator += delta
	_discovery_accumulator += delta
	if sample_accumulator >= 1.0 / 30.0:
		sample_accumulator = fmod(sample_accumulator, 1.0 / 30.0)
		var started := Time.get_ticks_usec()
		if _discovery_accumulator >= 0.1:
			_discovery_accumulator = fmod(_discovery_accumulator, 0.1)
			_discover_subjects()
		var captured: bool = take.sample(elapsed)
		var cost := Time.get_ticks_usec() - started
		_sampling_usec_total += cost
		_sampling_usec_max = maxi(_sampling_usec_max, cost)
		_sampling_count += 1
		if not captured:
			stop_recording()
			_message = take.warning

func _process(delta: float) -> void:
	_update_background_badge()
	if _export_pid > 0 and not OS.is_process_running(_export_pid):
		_message = "Export failed or was interrupted."
		if FileAccess.file_exists(_export_result) and FileAccess.get_file_as_string(_export_result).strip_edges() == "OK":
			_message = "Export complete (silent): %s" % _export_file
		print("[RecordingMode] %s" % _message)
		_export_pid = -1
	if not active: return
	_suppress_ui()
	if replay and playing:
		seek(playhead + delta)
		if playhead >= take.duration(): playing = false
	if not (replay and play_shot):
		var direction := Vector3.ZERO
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			direction = Vector3(float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)),
				float(Input.is_physical_key_pressed(KEY_E)) - float(Input.is_physical_key_pressed(KEY_Q)),
				float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W)))
		var roll := float(Input.is_physical_key_pressed(KEY_C)) - float(Input.is_physical_key_pressed(KEY_Z))
		camera.move_camera(direction, _mouse_look, roll, delta)
	_mouse_look = Vector2.ZERO
	camera.make_current()
	_timeline.max_value = maxf(take.duration(), 0.01) if take != null else 0.01
	_status.text = "%s  %.2f s  |  %s\n%s" % ["REC" if recording else ("REPLAY" if replay else "LIVE"), playhead if replay else elapsed,
		"PAUSED" if (not playing if replay else get_tree().paused) else "RUNNING", _message]
	if take != null and not take.warning.is_empty(): _status.text += "\nWARNING: " + take.warning

func _input(event: InputEvent) -> void:
	if not active: return
	if _open_dialog.visible: return
	if get_viewport().gui_get_focus_owner() is LineEdit and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_mouse_look += event.relative * 0.002
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if event.pressed else Input.MOUSE_MODE_VISIBLE
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_ESCAPE: exit()
			KEY_TAB:
				_panel.visible = not _panel.visible
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if _panel.visible else Input.MOUSE_MODE_CAPTURED
			KEY_SPACE: toggle_run()
			KEY_LEFT:
				playing = false
				seek(playhead - 1.0 / 30.0)
			KEY_RIGHT:
				playing = false
				seek(playhead + 1.0 / 30.0)
	# Let pointer events reach our GUI; consume keys so gameplay never fires guns.
	if not event is InputEventMouseButton and not event is InputEventMouseMotion:
		get_viewport().set_input_as_handled()

func _suppress_ui() -> void:
	var layers: Array[CanvasLayer] = []
	PauseMenu._collect_main_viewport_canvas_layers(get_tree().root, layers)
	for canvas in layers:
		if canvas == _layer: continue
		if not _canvases.has(canvas): _canvases[canvas] = canvas.visible
		canvas.hide()

func _build_ui() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 120
	add_child(_layer)
	_panel = PanelContainer.new()
	_panel.position = Vector2(20, 20)
	_layer.add_child(_panel)
	var box := VBoxContainer.new()
	_panel.add_child(box)
	_status = Label.new()
	_status.custom_minimum_size = Vector2(760, 52)
	box.add_child(_status)
	var hint := Label.new()
	hint.text = "RMB + WASD / Q E: move • mouse: aim • Z C: roll • Tab: clean view • Esc: exit\nSpace: run/pause • arrows: replay frame step • combat visuals supported; export is silent\nFor normal gameplay: exit this editor, then Ctrl+F9 starts/stops background recording."
	box.add_child(hint)
	var row := HBoxContainer.new()
	box.add_child(row)
	_button(row, "RUN / PAUSE", toggle_run)
	_button(row, "RECORD", func(): start_recording())
	_button(row, "STOP", stop_recording)
	_button(row, "REPLAY", func(): enter_replay())
	_button(row, "LIVE", leave_replay)
	_button(row, "SAVE TAKE", func(): save_take())
	_button(row, "OPEN TAKE", func(): _open_dialog.popup_centered(Vector2i(850, 550)))
	_button(row, "CLEAR TAKE", clear_take)
	var controls := HBoxContainer.new()
	box.add_child(controls)
	_subject_picker = OptionButton.new()
	controls.add_child(_subject_picker)
	_subject_picker.item_selected.connect(func(index): _selected_subject = index)
	_attachment_picker = OptionButton.new()
	for title in ["Detached", "Follow position", "Follow heading", "Fully attached"]: _attachment_picker.add_item(title)
	controls.add_child(_attachment_picker)
	_attachment_picker.item_selected.connect(func(mode): camera.attach(_subject(), mode))
	_button(controls, "ATTACH", func(): camera.attach(_subject(), _attachment_picker.selected))
	_button(controls, "LOOK AT", func(): camera.aim_target = null if is_instance_valid(camera.aim_target) else _subject())
	_button(controls, "FRAME", func():
		var subject := _subject()
		if is_instance_valid(subject):
			camera.attach(null, 0)
			camera.global_position = subject.global_position + Vector3(80, 35, 100)
			camera.look_at(subject.global_position)
			camera.attach(null, 0))
	var speed := SpinBox.new()
	speed.min_value = 0.2
	speed.max_value = 300
	speed.step = 0.2
	speed.value = 25
	speed.prefix = "m/s "
	controls.add_child(speed)
	speed.value_changed.connect(func(value):
		if is_instance_valid(camera): camera.move_speed = value)
	var fov := SpinBox.new()
	fov.min_value = 10
	fov.max_value = 110
	fov.value = 75
	fov.prefix = "FOV "
	controls.add_child(fov)
	fov.value_changed.connect(func(value):
		if is_instance_valid(camera): camera.fov = value)
	_timeline = HSlider.new()
	_timeline.step = 1.0 / 30.0
	box.add_child(_timeline)
	_timeline.value_changed.connect(func(value):
		playing = false
		seek(value))
	var shots := HBoxContainer.new()
	box.add_child(shots)
	_shot_picker = OptionButton.new()
	_shot_picker.add_item("Shot A")
	_shot_picker.add_item("Shot B")
	shots.add_child(_shot_picker)
	_shot_picker.item_selected.connect(func(index):
		selected_shot = index
		play_shot = false)
	_button(shots, "ADD / REPLACE KEY", add_key)
	_button(shots, "PREVIEW SHOT", func():
		play_shot = true
		seek(0.0)
		playing = true)
	_button(shots, "FREE CAMERA", func(): play_shot = false)
	_button(shots, "CLEAR SHOT", func():
		if take != null: take.shots[selected_shot].clear())
	_button(shots, "EXPORT SHOT", export_shot)
	_open_dialog = FileDialog.new()
	_open_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_open_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_open_dialog.filters = PackedStringArray(["take.bin ; Recorded take"])
	_open_dialog.current_dir = ProjectSettings.globalize_path("user://recordings")
	_open_dialog.file_selected.connect(func(path): open_take(path.get_base_dir()))
	_layer.add_child(_open_dialog)
	_layer.hide()

func _button(parent: Node, text: String, action: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.pressed.connect(action)
	parent.add_child(button)

func _unhandled_key_input(event: InputEvent) -> void:
	if active or not event.is_action_pressed("toggle_background_recording", false, true) or event.is_echo(): return
	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit: return
	toggle_background_recording()
	get_viewport().set_input_as_handled()

func _build_background_badge() -> void:
	_badge_layer = CanvasLayer.new()
	_badge_layer.layer = 121
	add_child(_badge_layer)
	_badge = Label.new()
	_badge.position = Vector2(20, 64)
	_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_badge.add_theme_color_override("font_shadow_color", Color.BLACK)
	_badge.add_theme_constant_override("shadow_outline_size", 5)
	_badge.add_theme_font_size_override("font_size", 18)
	_badge_layer.add_child(_badge)
	_badge_layer.hide()

func _update_background_badge() -> void:
	if _badge_layer == null: return
	_badge_layer.visible = not active and not PauseMenu.is_photo_mode_active() and (background_recording or (_background_take and take != null) or Time.get_ticks_msec() < _notice_until_ms)
	if not _badge_layer.visible: return
	if background_recording:
		_badge.text = "REC %05.1f s%s · Ctrl+F9 stops · %.1f / 128 MiB" % [elapsed, " (paused)" if get_tree().paused else "", take.estimated_bytes / 1048576.0]
		_badge.modulate = Color(1.0, 0.4, 0.3)
	else:
		_badge.text = "TAKE READY · Pause → Recording Mode to replay/save" if _background_take and take != null else _message
		_badge.modulate = Color(1.0, 0.8, 0.35)
	if take != null and not take.warning.is_empty(): _badge.text += "\n" + take.warning
