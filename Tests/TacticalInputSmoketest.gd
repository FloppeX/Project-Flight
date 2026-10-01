extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	var console := root.get_node("CarrierConsole")
	var tactical := root.get_node("WorldMapOverlay")
	console.show_page("tactical", true)
	await process_frame
	# Dispatch through the viewport so earlier input handlers participate.
	for expected in ["air_wing", "personnel", "ground_bay", "carrier", "replicator", "tactical"]:
		_shoulder(JOY_BUTTON_RIGHT_SHOULDER)
		_expect(console.get_current_page() == expected, "RB should select " + expected)
	_shoulder(JOY_BUTTON_LEFT_SHOULDER)
	_expect(console.get_current_page() == "replicator", "LB should wrap backwards")
	console.show_page("tactical", true)
	await process_frame
	var assets: Array = tactical.get("_asset_buttons")
	var asset: Button = assets[0].button
	# Test both ends and the middle of the visible asset box.
	for fraction in [0.03, 0.5, 0.97]:
		tactical.call("_cancel_draft")
		await process_frame
		_click(asset.get_global_rect().position + asset.size * Vector2(fraction, 0.5))
		await process_frame
		_expect(tactical.get("_mission_popup").visible, "asset box did not open menu at " + str(fraction))
		var missions: Array = tactical.get("_mission_buttons")
		var mission: Button = missions[0].button
		_click(mission.get_global_rect().position + mission.size * Vector2(fraction, 0.5))
		await process_frame
		_expect(not tactical.get("_mission_popup").visible, "mission box did not activate at " + str(fraction))
		_expect(str(tactical.get("_selected_mission_id")) == str(missions[0].id), "mission selection did not start draft")
		_expect(tactical.get("_draft_points").is_empty(), "menu click leaked through to the map")
	if DisplayServer.get_name() != "headless":
		asset.emit_signal("pressed")
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://logs/tactical_input_preview.png")
	console.set_open(false)
	# Cycling through Carrier starts a background scene load. Let it finish before
	# engine shutdown, which otherwise reports missing dependencies from that job.
	var carrier_scene := "res://LandCarrier/LandCarrier2.tscn"
	if ResourceLoader.load_threaded_get_status(carrier_scene) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		ResourceLoader.load_threaded_get(carrier_scene)
	if failures.is_empty():
		print("TACTICAL_INPUT_PASS shoulders=all_tabs mouse=asset_and_mission_box_edges")
	else:
		for failure in failures:
			push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _shoulder(index: JoyButton) -> void:
	for pressed in [true, false]:
		var event := InputEventJoypadButton.new()
		event.button_index = index
		event.pressed = pressed
		root.push_input(event, true)

func _click(position: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = position
	root.push_input(motion, true)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = position
		event.global_position = position
		event.button_index = MOUSE_BUTTON_LEFT
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		event.pressed = pressed
		root.push_input(event, true)

func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
