extends SceneTree

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
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
		"layered_badlands"
	)
	# This smoke test verifies startup wiring, not the full 50 km bake. The full
	# route geometry is covered by LayeredMapProfileSmoketest.
	terrain_nav.set("bake_half_extent_m", 1000.0)
	terrain_nav.set("query_grid_enabled", false)
	terrain_nav.call("rebake_at_center", Vector3.ZERO)

	var packed := load("res://Main_Scene.tscn") as PackedScene
	_expect(packed != null, "main scene could not be loaded")
	if packed == null:
		quit(1)
		return
	var scene := packed.instantiate() as Node3D
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame

	var terrain := scene.get_node_or_null("LowPolyTerrainPrototype") as LowPolyTerrain
	_expect(terrain != null, "main scene terrain was not found")
	if terrain != null:
		_expect(terrain.get_map_profile_id() == "layered_badlands", "selected profile was not applied before terrain startup")
	var configured_center: Vector3 = scene.get("_scenario_play_area_center")
	_expect(Vector2(configured_center.x, configured_center.z).length() <= 0.1, "layered map did not use its deterministic play-area centre")
	var carrier := scene.get_node_or_null("LandCarrier")
	_expect(carrier != null, "carrier was not found")
	if carrier != null:
		_expect(not bool(carrier.get("automatic_patrol_enabled")), "carrier automatic patrol was unexpectedly enabled")

	print("LAYERED_MAP_STARTUP_SMOKETEST ", JSON.stringify({
		"status": "PASS" if _failures.is_empty() else "FAIL",
		"profile": terrain.get_map_profile_id() if terrain != null else "missing",
		"play_area_center": str(configured_center),
		"failures": _failures,
	}))
	quit(0 if _failures.is_empty() else 1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		push_error("[LayeredMapStartupSmoketest] %s" % message)
