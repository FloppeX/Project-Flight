extends SceneTree

const Region = preload("res://Environment/CarrierStartRegion.gd")
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	# Use the authored terrain configuration before it enters the tree, exactly
	# as ScenarioManager does. Selection must not require a rendered/baked world.
	var scene := (load("res://Main_Scene.tscn") as PackedScene).instantiate()
	var terrain := scene.get_node("LowPolyTerrainPrototype") as LowPolyTerrain
	var settings: Dictionary = scene.get_node("LandCarrier").get_start_site_requirements()
	settings.nav_cell = 40.0
	var centers: Array[Vector3] = []
	var started := Time.get_ticks_msec()
	for seed_value in [1, 2, 3, 4, 5, 6, 42, 1337, 22551, 20260927]:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		var region := Region.find(terrain, 25000.0, 2000.0, settings, rng)
		_expect(not region.is_empty(), "no region for seed %d" % seed_value)
		if region.is_empty(): continue
		var center: Vector3 = region.center
		var site: Vector3 = region.position
		var heading: Vector3 = region.heading
		_expect(absf(center.z + 25000.0 - site.z - 2000.0) < 0.01, "wrong south margin")
		_expect(heading.dot(Vector3.FORWARD) >= 0.70, "south-facing site")
		_expect(absf(center.x - terrain.position.x) + 27000.0 <= terrain.quads_x * terrain.cell_size_m * 0.5, "map exceeds source terrain in x")
		_expect(absf(center.z - terrain.position.z) + 27000.0 <= terrain.quads_z * terrain.cell_size_m * 0.5, "map exceeds source terrain in z")
		_expect(is_equal_approx(site.y, terrain.get_local_height(site - terrain.position) + terrain.position.y), "incorrect terrain height")
		centers.append(center)
		print("CARRIER_START_REGION_SAMPLE seed=", seed_value, " attempts=", region.attempts, " center=", center)
	_expect(centers.size() > 1 and centers[0] != centers[1], "new games always select the same map")
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var repeat := Region.find(terrain, 25000.0, 2000.0, settings, rng)
	_expect(not repeat.is_empty() and repeat.center == centers[0], "diagnostic seed is not repeatable")
	_expect(Region.find(terrain, 60000.0, 2000.0, settings, rng).is_empty(), "impossible map size accepted")
	scene.free()
	print("CARRIER_START_REGION_SMOKETEST ", JSON.stringify({"status": "PASS" if failures.is_empty() else "FAIL",
		"samples": centers.size(), "elapsed_ms": Time.get_ticks_msec() - started, "failures": failures}))
	quit(0 if failures.is_empty() else 1)

func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)
