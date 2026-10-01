extends "res://Tests/TacticalInputSmoketest.gd"

func _run() -> void:
	await process_frame
	var ops := root.get_node("AirOpsManager")
	ops.set_process(false)
	var flight = ops.get_flight(ops.get_flight_names()[0])
	flight.set_physics_process(false)
	flight.mission = flight.Mission.NONE
	var craft := RigidBody3D.new()
	craft.freeze = true
	root.add_child(craft)
	craft.position = Vector3(4200, 800, 4500)
	craft.add_to_group("friendlies")
	var pilot = load("res://Tests/Fixtures/AttackOrderPilot.gd").new()
	pilot.name = "AIPilot"
	craft.add_child(pilot)
	pilot.set_physics_process(false)
	pilot.aircraft = craft
	pilot.current_state = pilot.State.SEARCH
	pilot._terrain_height_callable = func(_point: Vector3) -> float: return 0.0
	flight.register(craft)
	ops.assembly.plans[flight.flight_name] = {"ids": [], "scene": "", "loadout": "rocket_strike", "hold": false}
	_expect(ops.default_patrol_engagement(flight.flight_name) == "ground", "strike loadout defaults to ground patrol")
	var grid := root.get_node("TerrainNavGrid")
	grid.set_process(false)
	grid.set("_cols", 101)
	grid.set("_rows", 101)
	grid.set("cell_size_m", 100.0)
	grid.set("_is_baked", true)
	var heights := PackedFloat32Array()
	heights.resize(10201)
	grid.set("_heights", heights)
	var fog := root.get_node("MapFogOfWar")
	fog.call("_initialize_from_navgrid")
	fog.reveal_circle(Vector3(5000, 0, 5000), 10000.0)
	var console := root.get_node("CarrierConsole")
	var tactical := root.get_node("WorldMapOverlay")
	console.show_page("tactical", true)
	await process_frame
	await process_frame
	for entry in tactical._asset_buttons:
		if entry.name == flight.flight_name:
			_click(entry.button.get_global_rect().get_center())
			break
	await process_frame
	var ids: Array = []
	for entry in tactical._mission_buttons:
		ids.append(entry.id)
	_expect(ids == ["PATROL", "ATTACK", "RTB", "AUTO"], "flight menu exposes unified orders")
	for entry in tactical._mission_buttons:
		if entry.id == "PATROL":
			_click(entry.button.get_global_rect().get_center())
			break
	await process_frame
	_expect(tactical._patrol_controls.visible and tactical._draft_patrol_engagement == "ground", "patrol exposes loadout-based default")
	var input: Control = tactical._map_input
	_click(input.get_global_transform() * tactical._world_to_map_local(Vector3(6000, 0, 6000)))
	_expect(tactical._can_confirm_draft(), "patrol point is confirmable")
	var points: Array = tactical._draft_points.duplicate()
	for mode in ["air", "ground", "both"]:
		var button: Button = tactical._patrol_buttons[mode]
		_click(button.get_global_rect().position + button.size * Vector2(0.95, 0.5))
		_expect(tactical._draft_patrol_engagement == mode, "full patrol mode button is clickable: " + mode)
		_expect(tactical._draft_points == points, "engagement control does not alter route")
	if DisplayServer.get_name() != "headless":
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://logs/patrol_order_draft.png")
	tactical._confirm_draft()
	_expect(flight.patrol_engagement == "both" and flight.get_mission_name() == "PATROL", "confirmation submits selected patrol engagement")
	_expect(flight.mission_source == "player" and not ops._flight_can_take_tactical_order(flight), "automatic allocator cannot replace player patrol")
	_expect(pilot.current_air_task.metadata.patrol_engagement == "both", "pilot receives patrol engagement")
	_expect(not tactical._patrol_controls.visible, "controls disappear after confirmation")
	var status: Dictionary = tactical._get_selected_asset_status()
	_expect(tactical._ensure_cap_route_edit_draft(status), "existing patrol remains editable")
	_expect(tactical._draft_patrol_engagement == "both", "route editing preserves engagement")
	tactical._cancel_draft()
	tactical._begin_mission_draft("PATROL")
	_expect(tactical._draft_patrol_engagement == "both", "reopening patrol preserves chosen engagement")
	tactical._cancel_draft()
	console.set_open(false)
	flight.unregister(craft)
	craft.queue_free()
	await process_frame
	for failure in failures: push_error(failure)
	print("PATROL_ORDER_UI_%s failures=%s" % ["PASS" if failures.is_empty() else "FAIL", failures])
	quit(0 if failures.is_empty() else 1)
