extends SceneTree

class BayStub:
	extends Node
	var stored_vehicles := 14
	var max_bay_capacity := 16

var _audio_capture: AudioEffectCapture
var _fixed_camera_transform: Transform3D


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	await process_frame
	var carrier := Node3D.new()
	root.add_child(carrier)
	var bay := BayStub.new()
	bay.name = "VehicleBayManager"
	carrier.add_child(bay)
	var stores: Node = load("res://LandCarrier/CarrierManager.gd").new()
	carrier.add_child(stores)
	var manager: Node = stores.get_replicator()
	manager.set_process(false)
	var console := root.get_node_or_null("CarrierConsole")
	if console == null:
		push_error("REPLICATOR_PAGE_RENDERED_PROBE_FAIL: CarrierConsole unavailable")
		quit(1)
		return
	console.call("show_page", "replicator", true)
	AudioServer.add_bus()
	var audio_bus := AudioServer.bus_count - 1
	AudioServer.set_bus_name(audio_bus, "ReplicatorProbe")
	_audio_capture = AudioEffectCapture.new()
	_audio_capture.buffer_length = 0.5
	AudioServer.add_bus_effect(audio_bus, _audio_capture)
	var page: Control = console.get("_replicator_page")
	var chamber: Node3D = page.get("_chamber")
	(chamber.get("_hum") as AudioStreamPlayer).bus = "ReplicatorProbe"
	await process_frame
	await process_frame
	_fixed_camera_transform = (chamber.get("_camera") as Camera3D).global_transform
	if "--preweld" in OS.get_cmdline_user_args():
		var success := await _capture_preweld(manager, chamber)
		console.call("set_open", false)
		carrier.free()
		quit(0 if success else 1)
		return
	await _save_frame("idle")
	manager.place_order("kmv_explorer", 1)
	manager.advance(0.01)
	manager.advance(1.0)
	await _save_frame("shield_lowering")
	manager.advance(1.0)
	for stage in range(5):
		manager.advance(9.0 if stage == 0 else 18.0)
		await _save_frame("stage_%d" % (stage + 1))
		if stage == 2 and "--opacity" in OS.get_cmdline_user_args():
			await _capture_opacity_comparison()
	manager.advance(9.0)
	await _save_frame("stowing")
	manager.advance(5.0)
	await _save_frame("shield_raising")
	manager.advance(2.0)
	await _save_frame("ready")
	manager.advance(1.5)
	await _save_frame("rollout")
	manager.advance(1.45)
	await _save_frame("rollout_exit")
	manager.advance(0.05)
	manager.advance(1.5)
	await _save_frame("platform_return")
	console.call("set_open", false)
	carrier.free()
	print("REPLICATOR_PAGE_RENDERED_PROBE_OK")
	quit(0)

func _capture_opacity_comparison() -> void:
	# Use the same keyboard route as the player rather than setting the material.
	var page: Control = root.get_node("CarrierConsole").get("_replicator_page")
	var expected: float = page.get_debug_snapshot().chamber.shield_opacity
	for sample in [{"key": KEY_PAGEUP, "presses": 3, "label": "shield_high"},
		{"key": KEY_PAGEDOWN, "presses": 12, "label": "shield_low"},
		{"key": KEY_PAGEUP, "presses": 9, "label": "shield_default"}]:
		for press in range(int(sample.presses)):
			var event := InputEventKey.new()
			event.keycode = sample.key
			event.pressed = true
			Input.parse_input_event(event)
			expected = clampf(expected + (0.05 if sample.key == KEY_PAGEUP else -0.05), 0.0, 1.0)
		await create_timer(0.4).timeout
		if not is_equal_approx(float(page.get_debug_snapshot().chamber.shield_opacity), expected):
			push_error("REPLICATOR_OPACITY_RENDER_FAIL: keyboard did not update shield")
			quit(1)
			return
		await _save_preweld_frame(str(sample.label))
	print("REPLICATOR_OPACITY_RENDER_PASS keyboard+live_material")

func _capture_preweld(manager: Node, chamber: Node3D) -> bool:
	var page: Control = root.get_node("CarrierConsole").get("_replicator_page")
	page._on_blueprint_pressed("bullets")
	manager.place_order("bullets", 1)
	manager.set_process(true)
	var saw_welding := false
	var saw_reveal := false
	var saw_finish := false
	var seen: Dictionary = {}
	var elapsed := 0.0
	while elapsed < 30.0:
		await process_frame
		elapsed += root.get_process_delta_time()
		var debug: Dictionary = chamber.get_debug_snapshot()
		if int(debug.welding_contacts) > 0 and not saw_welding:
			saw_welding = true
			if int(debug.visible_pieces) != 0:
				push_error("REPLICATOR_PREWELD_RENDER_FAIL: section appeared before first welding")
				return false
			await _save_preweld_frame("welding_before_reveal")
		for index in range((chamber.get("_pieces") as Array).size()):
			var piece: Dictionary = chamber.get("_pieces")[index]
			if not (piece.node as Node3D).visible or seen.has(index):
				continue
			seen[index] = true
			if float(piece.preweld_seconds) < 0.18 or int(piece.preweld_arm) < 0:
				push_error("REPLICATOR_PREWELD_RENDER_FAIL: visible section lacks prior welding")
				return false
		if int(debug.visible_pieces) > 0 and not saw_reveal:
			saw_reveal = true
			await _save_preweld_frame("first_welded_section")
		if manager.phase == "stowing":
			saw_finish = int(debug.visible_pieces) == int(debug.piece_count)
			await _save_preweld_frame("welded_crate_complete")
			break
	if not saw_welding or not saw_reveal or not saw_finish:
		push_error("REPLICATOR_PREWELD_RENDER_FAIL: incomplete weld/reveal/finish sequence")
		return false
	print("REPLICATOR_PREWELD_RENDER_PASS sections=%d elapsed=%f" % [seen.size(), elapsed])
	return true

func _save_preweld_frame(label: String) -> void:
	await RenderingServer.frame_post_draw
	var capture := root.get_texture().get_image()
	var path := ProjectSettings.globalize_path("user://replicator_%s.png" % label)
	if capture == null or capture.save_png(path) != OK:
		push_error("REPLICATOR_PREWELD_RENDER_FAIL: capture unavailable")
		quit(1)
	print("REPLICATOR_PREWELD_FRAME " + path)

func _save_frame(label: String) -> void:
	# This mode captures separated timeline snapshots, skipping the time between
	# them. The --preweld mode above exercises uninterrupted real-time fabrication.
	var feed_page: Control = root.get_node("CarrierConsole").get("_replicator_page")
	var chamber: Node3D = feed_page.get("_chamber")
	chamber.resume_feed()
	chamber.set_feed_state(feed_page._manager().chamber_snapshot(), true)
	if label == "stage_3":
		_audio_capture.clear_buffer()
	await create_timer(0.4).timeout
	if not (chamber.get("_camera") as Camera3D).global_transform.is_equal_approx(_fixed_camera_transform):
		push_error("REPLICATOR_PAGE_RENDERED_PROBE_FAIL: chamber camera moved during %s" % label)
		quit(1)
		return
	if label == "stage_3":
		var page: Control = root.get_node("CarrierConsole").get("_replicator_page")
		for attempt in range(120):
			if int(page.get_debug_snapshot().chamber.welding_contacts) == 4:
				break
			await create_timer(0.1).timeout
		if int(page.get_debug_snapshot().chamber.welding_contacts) != 4:
			push_error("REPLICATOR_PAGE_RENDERED_PROBE_FAIL: all four arms never weld simultaneously")
			quit(1)
			return
		var samples := _audio_capture.get_buffer(_audio_capture.get_frames_available())
		var peak := 0.0
		for sample in samples:
			peak = maxf(peak, maxf(absf(sample.x), absf(sample.y)))
		print("REPLICATOR_HUM_CAPTURE frames=%d peak=%f" % [samples.size(), peak])
		if peak <= 0.00001:
			push_error("REPLICATOR_PAGE_RENDERED_PROBE_FAIL: silent hum")
			quit(1)
			return
	await RenderingServer.frame_post_draw
	var capture := root.get_texture().get_image()
	if capture == null:
		push_error("REPLICATOR_PAGE_RENDERED_PROBE_FAIL: rendering unavailable")
		quit(1)
		return
	var absolute_path := ProjectSettings.globalize_path("user://replicator_%s.png" % label)
	var error := capture.save_png(absolute_path)
	if error != OK:
		push_error("REPLICATOR_PAGE_RENDERED_PROBE_FAIL: save error %d" % error)
		quit(1)
	print("REPLICATOR_FRAME path=%s size=%s" % [absolute_path, str(capture.get_size())])
