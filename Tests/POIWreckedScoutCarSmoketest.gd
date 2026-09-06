extends SceneTree

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	var nav_grid := root.get_node("TerrainNavGrid")
	var map_fog := root.get_node("MapFogOfWar")
	var poi_manager := root.get_node("POIManager")
	nav_grid.set_process(false)
	map_fog.set_process(false)
	poi_manager.set_process(false)

	_build_flat_test_grid(nav_grid)
	map_fog.call("_initialize_from_navgrid")

	var scene := Node3D.new()
	scene.name = "POIWreckedScoutCarSmoketest"
	root.add_child(scene)
	current_scene = scene

	var enemy_base := Node3D.new()
	enemy_base.add_to_group("enemy_bases")
	enemy_base.position = Vector3(1000.0, 0.0, 500.0)
	scene.add_child(enemy_base)

	poi_manager.call("_clear_world_sites")
	var pois: Array = poi_manager.get("_pois")
	pois.clear()
	poi_manager.call("_place_pois")
	# Prevent the normal deferred starter reveal from waiting for a campaign
	# carrier that this isolated smoke intentionally does not create.
	poi_manager.set("_starting_reveal_done", true)
	_expect(pois.size() == 11, "the normal campaign placement creates all POIs")
	if pois.is_empty():
		_finish()
		return

	var poi: Variant = pois[0]
	poi.set("discovered", true)
	var data: POIData = poi.get("data") as POIData
	_expect(data != null and data.title == "Wrecked Scout Car", "POI zero is the wrecked scout car")
	_expect(data != null and data.effect_id == "reveal_nearest_enemy_base", "the wreck has its intelligence effect")
	_expect(data != null and data.world_scene != null, "the wreck has a physical world scene")
	var world_site := poi.get("world_node") as Node3D
	_expect(is_instance_valid(world_site), "the wreck world scene was instantiated")
	if is_instance_valid(world_site):
		_expect(world_site.get_parent() == scene, "the wreck is attached to the active 3D scene")
		_expect(world_site.get_node_or_null("WreckPose/WreckedCarMesh") != null, "the authored wrecked-car mesh is visible")
		_expect(world_site.get_node_or_null("WreckPose/StaticBody3D/CollisionShape3D") != null, "the wreck has physical collision")
	var outpost: Variant = pois[9]
	var outpost_data := outpost.get("data") as POIData
	_expect(outpost_data != null and outpost_data.title == "Abandoned Outpost", "the former settlement slot is the abandoned outpost")
	_expect(outpost_data != null and outpost_data.effect_id == "reveal_nearby_poi_sites", "the outpost has its survey-record effect")
	var outpost_site := outpost.get("world_node") as Node3D
	_expect(is_instance_valid(outpost_site), "the abandoned outpost world scene was instantiated")
	if is_instance_valid(outpost_site):
		_expect(outpost_site.get_node_or_null("OutpostPose/RuinBuildingMesh") != null, "the authored ruin-building mesh is visible")
		_expect(outpost_site.get_node_or_null("OutpostPose/StaticBody3D/CollisionShape3D") != null, "the outpost has physical collision")

	poi_manager.call("_mark_poi_awaiting_orders", poi)
	_expect(bool(poi.get("awaiting_orders")), "field arrival changes the POI to awaiting orders")
	_expect(not bool(poi.get("revealed")), "field arrival does not consume the POI")
	_expect(bool(poi_manager.call("has_awaiting_orders")), "the manager exposes the pending decision")
	_expect(not bool(poi_manager.call("has_active_decision")), "the card does not open automatically")
	_expect(not paused, "the awaiting-orders notice does not pause play")
	var notice := poi_manager.get("_decision_notice") as CanvasLayer
	_expect(is_instance_valid(notice) and notice.visible, "the non-modal awaiting-orders notice is visible")
	var unresolved_state: Dictionary = poi_manager.call("capture_save_state")
	var unresolved_entries: Array = unresolved_state.get("pois", [])
	_expect(not (unresolved_entries[0] as Dictionary).has("outcome_world_pos"), "unresolved saves omit the non-finite outcome sentinel")

	_expect(bool(poi_manager.call("open_pending_decision", 0)), "the player can deliberately review the pending card")
	_expect(bool(poi_manager.call("has_active_decision")), "reviewing opens the card")
	_expect(paused, "the game pauses only after the player opens the card")
	poi_manager.call("_on_card_dismissed", 0)
	_expect(bool(poi.get("awaiting_orders")) and not bool(poi.get("revealed")), "deferring preserves the decision")
	_expect(not paused, "deferring returns to live play")

	var map_overlay := root.get_node("WorldMapOverlay")
	map_overlay.call("set_console_visible", true)
	await process_frame
	var map_click := InputEventMouseButton.new()
	map_click.button_index = MOUSE_BUTTON_LEFT
	map_click.pressed = true
	map_click.position = map_overlay.call("_world_to_map_local", poi.get("world_pos"))
	_expect(bool(map_overlay.call("_try_open_pending_poi", map_click)), "the pulsing tactical-map star reopens a deferred card")
	poi_manager.call("_on_card_confirmed", 0, 0)
	_expect(bool(poi.get("revealed")), "recovering the patrol log resolves the POI")
	_expect(not bool(poi.get("awaiting_orders")), "resolved POI no longer awaits orders")
	_expect(int(poi.get("resolved_choice")) == 0, "the chosen action is retained")
	_expect((poi.get("outcome_world_pos") as Vector3).distance_to(enemy_base.position) < 0.1, "the nearest enemy base is the intelligence target")
	_expect(bool(map_fog.call("is_world_explored", enemy_base.position)), "the enemy base location is revealed")
	_expect(bool(map_fog.call("is_world_explored", enemy_base.position + Vector3(4500.0, 0.0, 0.0))), "the revealed sector extends through 4.5 km")
	_expect(not bool(map_fog.call("is_world_explored", enemy_base.position + Vector3(6000.0, 0.0, 0.0))), "the revealed sector does not extend to 6 km")
	_expect(not bool(poi_manager.call("has_awaiting_orders")), "the pending indicator clears after resolution")
	_expect(not paused, "resolving the card resumes play")

	var resolved_state: Dictionary = poi_manager.call("capture_save_state")
	var resolved_entries: Array = resolved_state.get("pois", [])
	var resolved_entry := resolved_entries[0] as Dictionary
	_expect(resolved_entry.has("outcome_world_pos"), "resolved saves include the intelligence target")
	_expect(bool(poi_manager.call("restore_save_state", resolved_state)), "the POI state restores from a save")
	var restored_pois: Array = poi_manager.get("_pois")
	var restored: Variant = restored_pois[0]
	_expect(bool(restored.get("revealed")) and not bool(restored.get("awaiting_orders")), "restore preserves resolved state")
	_expect((restored.get("outcome_world_pos") as Vector3).distance_to(enemy_base.position) < 0.1, "restore preserves the revealed base location")

	# Resolve the second physical POI against a clean fog mask so its own map
	# effect, rather than the scout-car sector, is what makes the sites visible.
	map_fog.call("_initialize_from_navgrid")
	var restored_outpost: Variant = restored_pois[9]
	restored_outpost.set("discovered", true)
	var discovered_before: Dictionary = {}
	for candidate: Variant in restored_pois:
		if bool(candidate.get("discovered")):
			discovered_before[int(candidate.get("id"))] = true
	poi_manager.call("_mark_poi_awaiting_orders", restored_outpost)
	_expect(bool(poi_manager.call("open_pending_decision", 9)), "the abandoned outpost card opens from awaiting orders")
	poi_manager.call("_on_card_confirmed", 0, 9)
	_expect(bool(restored_outpost.get("revealed")), "recovering survey records resolves the outpost")
	var newly_discovered: Array[Variant] = []
	for candidate: Variant in restored_pois:
		var candidate_id := int(candidate.get("id"))
		if bool(candidate.get("discovered")) and not discovered_before.has(candidate_id):
			newly_discovered.append(candidate)
	_expect(newly_discovered.size() == 2, "outpost survey records discover exactly two unknown POIs")
	for candidate: Variant in newly_discovered:
		_expect(bool(map_fog.call("is_world_explored", candidate.get("world_pos"))), "each surveyed POI receives an actionable explored patch")
	var outpost_state: Dictionary = poi_manager.call("capture_save_state")
	var outpost_entries: Array = outpost_state.get("pois", [])
	_expect(bool((outpost_entries[9] as Dictionary).get("revealed", false)), "the resolved outpost is present in save state")

	map_overlay.call("set_console_visible", false)
	await process_frame
	_finish()


func _build_flat_test_grid(nav_grid: Node) -> void:
	const SIZE := 151
	nav_grid.set("cell_size_m", 100.0)
	nav_grid.set("body_clearance_cells", 1)
	nav_grid.set("_cols", SIZE)
	nav_grid.set("_rows", SIZE)
	nav_grid.set("_origin_x", -7500.0)
	nav_grid.set("_origin_z", -7500.0)
	var heights := PackedFloat32Array()
	heights.resize(SIZE * SIZE)
	heights.fill(0.0)
	nav_grid.set("_heights", heights)
	nav_grid.set("_h_min_passable", 0.0)
	nav_grid.set("query_cell_size_m", 100.0)
	nav_grid.set("_query_cols", SIZE)
	nav_grid.set("_query_rows", SIZE)
	nav_grid.set("_query_origin_x", -7500.0)
	nav_grid.set("_query_origin_z", -7500.0)
	nav_grid.set("_query_heights", heights.duplicate())
	nav_grid.set("_query_height_variation", heights.duplicate())
	nav_grid.set("_query_max_heights", heights.duplicate())
	nav_grid.set("_query_is_baked", true)
	nav_grid.set("_is_baked", true)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	paused = false
	if _failures.is_empty():
		print("[POIWreckedScoutCarSmoketest] PASS")
		quit(0)
		return
	for failure in _failures:
		push_error("[POIWreckedScoutCarSmoketest] %s" % failure)
	print("[POIWreckedScoutCarSmoketest] FAIL %s" % _failures)
	quit(1)
