extends "res://Tests/TacticalInputSmoketest.gd"

func _run() -> void:
	await process_frame
	var ops := root.get_node("AirOpsManager")
	ops.set_physics_process(false)
	var grid := root.get_node("TerrainNavGrid")
	grid.set_process(false)
	grid.set("_cols", 101)
	grid.set("_rows", 101)
	grid.set("cell_size_m", 10.0)
	grid.set("_is_baked", true)
	var heights := PackedFloat32Array()
	heights.resize(10201)
	grid.set("_heights", heights)
	var console := root.get_node("CarrierConsole")
	var tactical := root.get_node("WorldMapOverlay")
	var names: Array = ops.get_flight_names()
	var aircraft: Array[Node3D] = []
	for i in range(4):
		var plane := Node3D.new()
		root.add_child(plane)
		plane.add_to_group("friendlies")
		# Exercise both map silhouettes at different headings, including selected outlines.
		plane.set_meta("is_helicopter", i % 2 == 1)
		plane.rotation.y = float(i) * PI * 0.5
		plane.position = Vector3(550.0 + (i % 2) * 160.0, 500.0, 300.0 + (i / 2) * 330.0)
		aircraft.append(plane)
		ops.get_flight(names[i / 2]).register(plane)
	console.show_page("tactical", true)
	await process_frame
	await process_frame
	var symbols: Control = tactical.get("_symbol_layer")
	_expect(symbols.call("_aircraft_icon", aircraft[0]).resource_path.ends_with("plane.svg"), "fixed-wing marker must use the supplied plane shape")
	_expect(symbols.call("_aircraft_icon", aircraft[1]).resource_path.ends_with("helicopter.svg"), "helicopter marker must use the supplied rotor shape")
	for selected in [0, 1, -1]:
		var asset_buttons: Array = tactical.get("_asset_buttons")
		for asset in asset_buttons:
			if (selected >= 0 and asset.name == names[selected]) or (selected == -1 and asset.name == "Ember"):
				var button: Button = asset.button
				_click(button.get_global_rect().get_center())
				break
		await process_frame
		_expect(symbols.get("_selected_flight_name") == (names[selected] if selected >= 0 else ""), "flight click did not update marker selection")
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			var screenshot := root.get_texture().get_image()
			for i in range(aircraft.size()):
				var point: Vector2 = symbols.get_global_transform() * Vector2(symbols.call("_world_to_map", aircraft[i].position))
				var whites := _white_pixels(screenshot, point)
				_expect((whites > 30) == (selected >= 0 and i / 2 == selected), "wrong outline for aircraft %d with flight %d selected: %d white pixels" % [i, selected, whites])
			screenshot.save_png("res://logs/tactical_flight_selection_%d.png" % selected)
	# Membership is resolved each draw, so losses and transfers cannot retain a stale outline.
	for index in [0, 2, 1, 3]:
		tactical.call("_cancel_draft")
		var point: Vector2 = symbols.get_global_transform() * Vector2(symbols.call("_world_to_map", aircraft[index].position))
		_click(point + Vector2(6, 0))
		await process_frame
		_expect(tactical.get("_selected_asset_name") == names[index / 2], "clicking a plane must select its flight")
		_expect(symbols.get("_selected_flight_name") == names[index / 2], "map click must update all flight outlines")
		_expect(tactical.get("_mission_popup").visible, "map selection must open the flight mission menu")
	# The same pixel hit area works with zoom and pan, and does not steal draft clicks.
	tactical.call("_cancel_draft")
	tactical.set("_map_zoom", 2.0)
	tactical.set("_map_view_center_uv", Vector2(0.65, 0.45))
	tactical.call("_apply_map_view")
	var zoom_point: Vector2 = symbols.get_global_transform() * Vector2(symbols.call("_world_to_map", aircraft[0].position))
	_click(zoom_point)
	await process_frame
	_expect(tactical.get("_selected_asset_name") == names[0], "zoomed plane click must select its flight")
	tactical.call("_begin_mission_draft", "PATROL")
	var other_point: Vector2 = symbols.get_global_transform() * Vector2(symbols.call("_world_to_map", aircraft[2].position))
	_click(other_point)
	_expect(tactical.get("_selected_asset_name") == names[0], "mission placement must not switch flights")
	_expect(not tactical.get("_draft_points").is_empty(), "plane click during Patrol must still place the mission target")
	aircraft[0].free()
	console.set_open(false)
	for plane in aircraft:
		if is_instance_valid(plane):
			plane.free()
	if failures.is_empty():
		print("TACTICAL_FLIGHT_SELECTION_PASS click=switch_and_clear outlines=selected_members_only")
	else:
		for failure in failures:
			push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _white_pixels(screenshot: Image, center: Vector2) -> int:
	var count := 0
	for y in range(int(center.y) - 24, int(center.y) + 25):
		for x in range(int(center.x) - 24, int(center.x) + 25):
			if x < 0 or y < 0 or x >= screenshot.get_width() or y >= screenshot.get_height():
				continue
			var color := screenshot.get_pixel(x, y)
			if color.r > 0.92 and color.g > 0.92 and color.b > 0.92:
				count += 1
	return count
