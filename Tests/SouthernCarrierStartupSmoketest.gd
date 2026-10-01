extends SceneTree

var failures: Array[String] = []
var ready_heading := Vector3.ZERO
var ready_distance_from_south := INF

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var profile := "open_canyons"
	var seed_value := 22551
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--profile="): profile = arg.get_slice("=", 1)
		if arg.begins_with("--seed="): seed_value = int(arg.get_slice("=", 1))
	var nav := root.get_node("TerrainNavGrid")
	var graph := root.get_node("NavGraph")
	root.get_node("GameSession").configure_new_game("Pathfinder", Color.WHITE, Color.BLACK, 0, 0, profile)
	if not OS.get_cmdline_user_args().has("--full-map"):
		nav.bake_half_extent_m = 6000.0
	nav.rebake_at_center(Vector3.ZERO)
	var scene := (load("res://Main_Scene.tscn") as PackedScene).instantiate()
	var carrier := scene.get_node("LandCarrier")
	carrier.startup_placement_seed = seed_value
	carrier.initial_placement_completed.connect(func() -> void:
		ready_heading = carrier.global_basis.z
		ready_distance_from_south = nav._origin_z + (nav._rows - 1) * nav.cell_size_m - carrier.global_position.z)
	root.add_child(scene)
	current_scene = scene
	var start := Time.get_ticks_msec()
	while not graph.is_ready() or not carrier.is_initial_placement_complete():
		if Time.get_ticks_msec() - start > 240000:
			_expect(false, "startup timed out")
			break
		await process_frame
	var position: Vector3 = carrier.global_position
	var heading: Vector3 = carrier.global_basis.z
	_expect(ready_distance_from_south >= 1499.0 and ready_distance_from_south <= 3001.0,
		"carrier was not in the southern start band at placement completion: %s" % ready_distance_from_south)
	_expect(ready_heading.dot(Vector3.FORWARD) >= 0.70, "north-facing heading was not applied before placement signal")
	_expect(nav.is_stable_footprint(position.x, position.z, 320.0, 30.0, 30.0), "unstable footprint")
	_expect(nav.is_directional_launch_corridor_clear(position.x, position.z, heading.x, heading.z, 800.0, 140.0, 80.0), "blocked launch corridor")
	_expect(graph.can_anchor(position, 120.0), "carrier cannot join navigation graph")
	_expect(carrier._waypoint_positions.is_empty(), "startup issued an unwanted automatic order")
	if profile == "open_canyons":
		_expect(not carrier._startup_site.is_empty(), "region was not selected around a clearing")
		if not carrier._startup_site.is_empty():
			var expected: Vector3 = carrier._startup_site.position
			_expect(Vector2(position.x - expected.x, position.z - expected.z).length() < 1.0,
				"baked navigation rejected the preselected clearing")
		_expect(absf(ready_distance_from_south - 2000.0) < 1.0, "selected region did not frame the start 2 km from south")
	print("SOUTHERN_CARRIER_STARTUP ", JSON.stringify({"status": "PASS" if failures.is_empty() else "FAIL",
		"profile": profile, "seed": seed_value, "position": str(position), "heading": str(ready_heading),
		"south_margin_m": ready_distance_from_south, "failures": failures}))
	quit(0 if failures.is_empty() else 1)

func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)
