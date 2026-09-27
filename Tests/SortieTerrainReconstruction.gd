extends SceneTree
## Rebuild recorded terrain chunks and compare the public height API with physics.
## No flight replay: this checks geometry at recorded positions only.
var terrain: Node3D

func _initialize() -> void:
	_run.call_deferred()

func vector(value: Variant) -> Vector3:
	var parts := str(value).trim_prefix("(").trim_suffix(")").split(",")
	return Vector3(float(parts[0]), float(parts[1]), float(parts[2]))

func _run() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var source := FileAccess.open("res://logs/strike_sortie_control70.jsonl", FileAccess.READ)
	var samples: Array[Dictionary] = []
	var world := {}
	var crash := {}
	while not source.eof_reached():
		var line := source.get_line().strip_edges().trim_prefix("\ufeff")
		if line.is_empty(): continue
		var item: Variant = JSON.parse_string(line)
		if not item is Dictionary: continue
		if item.event == "WORLD_FRAME": world = item.data
		if item.event == "DESTROYED": crash = item
		if item.event == "SAMPLE" and float(item.t) >= 500.0 and not item.data.aircraft.is_empty():
			samples.append(item)
	if samples.is_empty() or crash.is_empty():
		push_error("Source trace missing")
		quit(1)
		return
	terrain = load("res://Environment/LowPolyTerrainPrototype.tscn").instantiate()
	var state := (load("res://Main_Scene.tscn") as PackedScene).get_state()
	for node_index in state.get_node_count():
		if state.get_node_name(node_index) != &"LowPolyTerrainPrototype": continue
		for property_index in state.get_node_property_count(node_index):
			var property := state.get_node_property_name(node_index, property_index)
			if property != &"script": terrain.set(property, state.get_node_property_value(node_index, property_index))
	terrain.set("generate_on_ready", false)
	terrain.set("use_streaming", true)
	terrain.set("seed", int(world.terrain_seed))
	terrain.set("map_profile_id", str(world.terrain_profile))
	scene.add_child(terrain)
	terrain.set_process(false)
	terrain.global_position = vector(samples.back().data.terrain_position)
	var impact := vector(crash.data.position)
	var api_height: float = terrain.get_height(impact)
	var raw_height: float = terrain._sample_height(terrain.to_local(impact).x, terrain.to_local(impact).z, terrain.get("_noises"))
	raw_height = round(raw_height / float(terrain.get("quant_step_m"))) * float(terrain.get("quant_step_m")) + terrain.global_position.y
	print("FRAME_CHECK seed=", terrain.get("seed"), " terrain=", terrain.global_position,
		" recorded=", crash.data.ground_y, " rebuilt=", api_height)
	if absf(raw_height - float(crash.data.ground_y)) > 1.0:
		push_error("Rebuilt terrain does not match recorded height; aborting interpretation")
		quit(1)
		return
	var chunks := {}
	for sample in samples:
		var point := vector(sample.data.aircraft[0].nav.aircraft_position)
		var local := terrain.to_local(point)
		var coord: Vector2i = terrain._world_to_chunk(local.x, local.z)
		chunks[coord] = true
	var impact_local := terrain.to_local(impact)
	var impact_coord: Vector2i = terrain._world_to_chunk(impact_local.x, impact_local.z)
	for x in range(-1, 2):
		for z in range(-1, 2): chunks[impact_coord + Vector2i(x, z)] = true
	for coord: Vector2i in chunks:
		var chunk: Node3D = terrain._build_chunk(coord.x, coord.y)
		if chunk != null: terrain.add_child(chunk)
	await physics_frame
	await physics_frame
	var rows: Array[Dictionary] = []
	for sample in samples:
		var craft: Dictionary = sample.data.aircraft[0]
		var point := vector(craft.nav.aircraft_position)
		var ray := ray_height(point)
		var api: float = terrain.get_height(point)
		rows.append({"t": sample.t, "position": point, "velocity": craft.velocity,
			"rotation": craft.rotation, "api_height": api, "logged_height": craft.terrain_y,
			"ray_height": ray.get("height"), "normal": ray.get("normal"),
			"controls": craft.controls, "nav": craft.nav,
			"api_clearance": point.y - api,
			"mesh_clearance": point.y - float(ray.get("height", NAN))})
	var nearby: Array[Dictionary] = []
	for x in [-12.0, -6.0, 0.0, 6.0, 12.0]:
		for z in [-12.0, -6.0, 0.0, 6.0, 12.0]:
			var point := impact + Vector3(x, 0, z)
			nearby.append({"point": point, "api": terrain.get_height(point), "mesh": ray_height(point)})
	var result := {"frame_verified": true, "terrain_position": terrain.global_position,
		"crash": crash, "impact_api_height": api_height, "impact_mesh": ray_height(impact),
		"impact_chunk": impact_coord, "samples": rows, "nearby": nearby}
	var file := FileAccess.open("res://logs/sortie_terrain_corrected.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "\t"))
	file.close()
	print("TERRAIN_RECONSTRUCTION impact=", impact, " api=", api_height, " mesh=", ray_height(impact),
		" chunk=", impact_coord, " samples=", rows.size())
	var max_error := 0.0
	for row in rows:
		if row.ray_height == null:
			push_error("Missing collision surface")
			quit(1)
			return
		max_error = maxf(max_error, absf(float(row.api_height) - float(row.ray_height)))
	for row in nearby:
		max_error = maxf(max_error, absf(float(row.api) - float(row.mesh.height)))
	var started := Time.get_ticks_usec()
	for i in 10000:
		terrain.get_height(impact + Vector3(float(i % 100) * 0.12, 0, float(i % 71) * 0.12))
	var cache: Dictionary = terrain.get("_height_query_grids")
	var cache_bytes := 0
	for grid: Dictionary in cache.values():
		cache_bytes += (grid.heights as PackedFloat32Array).size() * 4
	print("TERRAIN_QUERY_COST warm_10000_ms=", (Time.get_ticks_usec() - started) / 1000.0,
		" cached_chunks=", cache.size(), " cached_height_bytes=", cache_bytes)
	print("TERRAIN_SURFACE_PARITY max_error_m=", max_error)
	quit(0 if max_error < 0.1 else 1)

func ray_height(point: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(Vector3(point.x, 3000, point.z), Vector3(point.x, -1000, point.z))
	var hit: Dictionary = (current_scene as Node3D).get_world_3d().direct_space_state.intersect_ray(query)
	return {"height": hit.position.y, "normal": hit.normal, "body": str(hit.collider.get_path())} if not hit.is_empty() else {}
