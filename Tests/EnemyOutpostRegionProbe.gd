extends Node

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var root := get_tree().root
	root.get_node("GameSession").configure_new_game("Outpost Probe", Color.WHITE, Color.BLACK, 0, 0, "open_canyons")
	root.get_node("LoadingScreen").begin_scenario_load()
	var scene := load("res://Main_Scene.tscn").instantiate() as Node3D
	scene.set("randomize_play_area_each_run", false)
	root.add_child(scene)
	get_tree().current_scene = scene
	var manager := root.get_node("EnemyBaseManager")
	var started := Time.get_ticks_msec()
	while manager.outposts.is_empty() and Time.get_ticks_msec() - started < 240000:
		await get_tree().process_frame
	var failures: Array[String] = []
	if manager.outposts.size() != 6:
		failures.append("Expected six naturally placed outposts, got %d" % manager.outposts.size())
	if manager.bases.size() != 1:
		failures.append("Expected a separate main enemy base")
	# Exercise normal scheduled deployment, not a direct call to the allocator.
	var deployment_started := Time.get_ticks_msec()
	var helicopter_sections := 0
	while helicopter_sections < 6 and Time.get_ticks_msec() - deployment_started < 45000:
		await get_tree().process_frame
		helicopter_sections = 0
		for base in manager.bases:
			for flight: EnemyVirtualFlight in EnemyOpsManager._get_flights(base):
				if not flight.outpost_id.is_empty():
					helicopter_sections += 1
	if helicopter_sections != 6:
		failures.append("Expected six deployed helicopter sections, got %d" % helicopter_sections)
	for base in manager.bases:
		if EnemyOpsManager._count_deployed_aircraft(base) < 1:
			failures.append("Main base did not deploy fixed-wing patrols")
	print("OUTPOST_REGION_HELICOPTER_SECTIONS ", helicopter_sections)
	var occupied_sectors: Dictionary = {}
	var center := TerrainNavGrid.get_bake_center()
	var half_extent := TerrainNavGrid.bake_half_extent_m
	for station: EnemyOutpost in manager.outposts:
		var relative := (station.global_position - center) / half_extent
		var column := -1 if relative.x < -0.275 else (1 if relative.x > 0.275 else 0)
		var sector := Vector2i(column, -1 if relative.z < 0.0 else 1)
		if occupied_sectors.has(sector):
			failures.append("Outposts clustered in sector %s" % sector)
		occupied_sectors[sector] = true
		for base in manager.bases:
			if station.global_position.distance_to(base.global_position) < 3000.0:
				failures.append("Outpost overlaps main base: " + station.outpost_id)
		for other in manager.outposts:
			if other != station and station.global_position.distance_to(other.global_position) < 6000.0:
				failures.append("Outposts too close: " + station.outpost_id)
		if station.get_node_or_null("VehicleBay") == null:
			failures.append("Missing vehicle bay for " + station.outpost_id)
		if manager._find_outpost_compound_pads(station.global_position).size() != 4:
			failures.append("Unsuitable compound terrain for " + station.outpost_id)
		var min_height := INF
		var max_height := -INF
		for dx in [-8.0, 0.0, 8.0]:
			for dz in [-8.0, 0.0, 8.0]:
				var h := EnemyOutpost.sample_terrain_height(station.global_position.x + dx, station.global_position.z + dz)
				min_height = minf(min_height, h)
				max_height = maxf(max_height, h)
		if station.global_position.y > min_height + 0.1 or max_height - station.global_position.y > 1.6:
			failures.append("Unsuitable terrain footprint for " + station.outpost_id)
		print("OUTPOST_REGION_STATION ", station.outpost_id, " ", station.global_position, " footprint=", min_height, "..", max_height)
	print("ENEMY_OUTPOST_REGION_", "OK" if failures.is_empty() else "FAILED", " ", failures)
	get_tree().quit(0 if failures.is_empty() else 1)
