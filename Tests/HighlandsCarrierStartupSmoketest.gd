extends SceneTree

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var profile := "canyon_highlands"
	var game_session := root.get_node_or_null("GameSession")
	var terrain_nav := root.get_node_or_null("TerrainNavGrid")
	_expect(game_session != null, "GameSession autoload is missing")
	_expect(terrain_nav != null, "TerrainNavGrid autoload is missing")
	if game_session == null or terrain_nav == null:
		quit(1)
		return
	game_session.call(
		"configure_new_game",
		"Pathfinder",
		Color.WHITE,
		Color.BLACK,
		0,
		0,
		profile
	)
	# Exercise real scene startup and player orders in an 12 km baked region.
	terrain_nav.set("bake_half_extent_m", 6000.0)
	terrain_nav.set("query_grid_enabled", true)
	terrain_nav.call("rebake_at_center", Vector3.ZERO)

	var packed := load("res://Main_Scene.tscn") as PackedScene
	_expect(packed != null, "main scene could not be loaded")
	if packed == null:
		quit(1)
		return
	var scene := packed.instantiate() as Node3D
	var startup_carrier := scene.get_node("LandCarrier")
	startup_carrier.startup_placement_seed = 22551
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame

	var terrain := scene.get_node_or_null("LowPolyTerrainPrototype") as LowPolyTerrain
	_expect(terrain != null, "main scene terrain was not found")
	if terrain != null:
		_expect(terrain.get_map_profile_id() == profile, "selected profile was not applied before terrain startup")
	var configured_center: Vector3 = scene.get("_scenario_play_area_center")
	_expect(Vector2(configured_center.x, configured_center.z).length() <= 0.1, "layered map did not use its deterministic play-area centre")
	var carrier := scene.get_node_or_null("LandCarrier")
	_expect(carrier != null, "carrier was not found")
	if carrier != null:
		_expect(not bool(carrier.get("automatic_patrol_enabled")), "carrier automatic patrol was unexpectedly enabled")

	var started := Time.get_ticks_msec()
	var graph := root.get_node("NavGraph")
	while carrier != null and (not graph.is_ready() or not carrier.is_initial_placement_complete()):
		if Time.get_ticks_msec() - started > 180000:
			_expect(false, "carrier startup navigation timed out")
			break
		await process_frame
	if carrier != null and graph.is_ready():
		var origin: Vector3 = carrier.global_position
		for desired in [Vector3(0, 0, -3000), Vector3(-3000, 0, 0), Vector3(3000, 0, 0)]:
			var target := Vector3.INF
			var best := INF
			for dz in range(-1400, 1401, 160):
				for dx in range(-1400, 1401, 160):
					var point: Vector3 = desired + Vector3(dx, 0, dz)
					var score := Vector2(dx, dz).length_squared()
					if score >= best or not terrain_nav.is_low_clear_position(point.x, point.z, 12.0): continue
					if not terrain_nav.is_stable_footprint(point.x, point.z, 320.0, 30.0, 30.0): continue
					point.y = terrain.get_height(point)
					if not graph.can_anchor(point, 80.0): continue
					target = point
					best = score
			_expect(target != Vector3.INF, "no natural valley near startup destination %s" % desired)
			if target == Vector3.INF: continue
			var path: Array = graph.find_path(origin, target, 80.0)
			_expect(path.size() > 2, "actual carrier spawn cannot reach baseline destination %s" % target)
		var destination := Vector3(0, terrain.get_height(Vector3.ZERO), 0)
		root.get_node("MapFogOfWar").reveal_circle(destination, 1000.0)
		var orders: Array[Vector3] = [destination]
		_expect(carrier.set_player_patrol_waypoints(orders), "actual player route rejected: %s" % carrier.get_last_player_route_error())
		var path_started := Time.get_ticks_msec()
		while carrier._waypoint_positions.is_empty() and Time.get_ticks_msec() - path_started < 20000:
			await process_frame
		_expect(not carrier._waypoint_positions.is_empty(), "player order produced no carrier waypoints")
		print("HIGHLANDS_CARRIER_SPAWN ", origin, " ordered_waypoints=", carrier._waypoint_positions.size())
	print("HIGHLANDS_CARRIER_STARTUP_SMOKETEST ", JSON.stringify({
		"status": "PASS" if _failures.is_empty() else "FAIL",
		"profile": terrain.get_map_profile_id() if terrain != null else "missing",
		"play_area_center": str(configured_center),
		"failures": _failures,
	}))
	quit(0 if _failures.is_empty() else 1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		push_error("[HighlandsCarrierStartupSmoketest] %s" % message)
