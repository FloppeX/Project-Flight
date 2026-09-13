extends SceneTree

const Builder := preload("res://UI/WorldMapTextureBuilder.gd")
var failures: Array[String] = []

func _initialize() -> void: call_deferred("_run")

func _run() -> void:
	for child in root.get_children(): child.process_mode = Node.PROCESS_MODE_DISABLED
	var grid := root.get_node("TerrainNavGrid")
	var graph := root.get_node("NavGraph")
	var cache := root.get_node("TerrainMapCache")
	cache.process_mode = Node.PROCESS_MODE_ALWAYS
	var heights := PackedFloat32Array()
	var clearance := PackedFloat32Array()
	for z in range(29):
		for x in range(31):
			heights.append(100 + x * 4 + sin(z * 0.2) * 15)
			clearance.append(160 if x > 10 else 80)
	grid.set("_cols", 31)
	grid.set("_rows", 29)
	grid.set("_heights", heights)
	grid.set("_is_baked", true)
	graph.set("_cl_map", clearance)
	graph.set("_is_ready", true)
	var expected := Builder.build_images()
	graph.emit_signal("graph_ready")
	await _wait_ready(cache)
	var textures: Dictionary = cache.call("get_textures")
	for key in ["relief", "mobility"]:
		_expect(textures.has(key), "missing " + key)
		if textures.has(key):
			_expect(textures[key].get_image().get_data() == expected[key].get_data(), "pixels changed: " + key)
	var radars: Array[Control] = []
	for _i in range(2):
		var radar := load("res://HUD/RadarCanvas.gd").new() as Control
		root.add_child(radar)
		radar.call("_ensure_terrain_map_cache")
		_expect(radar.get("_terrain_map_texture") == textures.get("relief"), "radar did not share texture")
		radars.append(radar)
	var tactical := root.get_node("WorldMapOverlay")
	tactical.call("_ensure_map_texture")
	_expect(tactical.get("_map_texture") == textures.get("relief"), "tactical map did not share texture")
	var before: Dictionary = cache.call("get_debug_snapshot")
	grid.call("apply_origin_shift", Vector3(8000, 0, -5000))
	for radar in radars:
		radar.call("apply_origin_shift", Vector3(8000, 0, -5000))
		radar.call("_ensure_terrain_map_cache")
	_expect(cache.call("get_textures").get("relief") == textures.relief, "origin shift discarded pixels")
	_expect(cache.call("get_debug_snapshot").build_count == before.build_count, "origin shift rebuilt map")
	# Force a completed/in-flight old generation to remain unconsumed, then rebake.
	cache.set_process(false)
	graph.emit_signal("graph_ready")
	cache.call("_start_build")
	graph.emit_signal("graph_invalidated")
	_expect(not radars[0].get("_terrain_map_ready"), "radar retained invalidated map")
	_expect(tactical.get("_map_texture") == null, "tactical retained invalidated map")
	var new_heights := heights.duplicate()
	for i in new_heights.size(): new_heights[i] = 100.0 + (i % 31) * 1.5
	grid.set("_heights", new_heights)
	graph.emit_signal("graph_ready")
	cache.set_process(true)
	await _wait_ready(cache)
	var latest: Dictionary = cache.call("get_textures")
	_expect(cache.call("get_debug_snapshot").discarded_count == 1, "stale worker result was not rejected")
	_expect(latest.get("relief") != textures.get("relief"), "rebake reused obsolete texture")
	var new_expected := Builder.build_images()
	if latest.has("relief"):
		_expect(latest.relief.get_image().get_data() == new_expected.relief.get_data(), "rebake pixels mismatch")
	for radar in radars: radar.free()
	print("TERRAIN_MAP_CACHE_SMOKETEST ", JSON.stringify({"status": "PASS" if failures.is_empty() else "FAIL", "failures": failures, "cache": cache.call("get_debug_snapshot")}))
	quit(0 if failures.is_empty() else 1)

func _wait_ready(cache: Node) -> void:
	var deadline := Time.get_ticks_msec() + 15000
	while cache.call("get_textures").is_empty() and Time.get_ticks_msec() < deadline:
		await process_frame
	_expect(not cache.call("get_textures").is_empty(), "cache readiness timed out")

func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)
