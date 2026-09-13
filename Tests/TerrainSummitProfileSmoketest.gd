extends SceneTree

const TERRAIN_SCRIPT: Script = preload("res://Environment/LowPolyTerrain.gd")
const SAMPLE_HALF_EXTENT_M := 24000.0
const SAMPLE_SPACING_M := 360.0
const NEIGHBOR_SPACING_M := 72.0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var terrain := TERRAIN_SCRIPT.new() as LowPolyTerrain
	terrain.generate_on_ready = false
	terrain.seed = 22551
	terrain.plateau_height_m = 500.0
	root.add_child(terrain)

	var flattened := _sample_summit_stats(terrain)
	var legacy := TERRAIN_SCRIPT.new() as LowPolyTerrain
	legacy.generate_on_ready = false
	legacy.seed = terrain.seed
	legacy.plateau_height_m = terrain.plateau_height_m
	legacy.plateau_surface_amplitude_m = 60.0
	legacy.plateau_surface_frequency = 0.0014
	legacy.plateau_surface_octaves = 4
	legacy.flat_surface_undulation_amplitude_m = 12.0
	legacy.flat_surface_detail_amplitude_m = 4.5
	root.add_child(legacy)
	var jagged := _sample_summit_stats(legacy)
	print("[TerrainSummitProfileSmoketest] sampled flattened=%s legacy=%s" % [str(flattened), str(jagged)])

	# The alternate profile shares this script but not the Open Canyons summit
	# formula. Keep a direct route/height check here so terrain-only regressions
	# remain testable when broader session scripts fail to compile.
	var layered := TERRAIN_SCRIPT.new() as LowPolyTerrain
	layered.generate_on_ready = false
	layered.use_streaming = false
	layered.cell_size_m = 36.0
	layered.seed = terrain.seed
	layered.base_height_offset_m = 220.0
	layered.quant_step_m = 3.0
	layered.set_map_profile("layered_badlands")
	root.add_child(layered)
	var layered_validation := layered.validate_profile_routes(20.0, 36.0)
	var layered_min_height := INF
	var layered_max_height := -INF
	for layered_z in range(-20000, 20001, 4000):
		for layered_x in range(-20000, 20001, 4000):
			var layered_height := layered.get_height(Vector3(float(layered_x), 0.0, float(layered_z)))
			layered_min_height = minf(layered_min_height, layered_height)
			layered_max_height = maxf(layered_max_height, layered_height)
	var layered_height_span := layered_max_height - layered_min_height

	var failures: Array[String] = []
	_check(int(flattened.get("samples", 0)) >= 1000, "too few plateau samples", failures)
	_check(float(flattened.get("range_m", INF)) <= 22.0, "regional summit range exceeded 22 m", failures)
	_check(float(flattened.get("max_neighbor_delta_m", INF)) <= 1.5, "summit changed more than 1.5 m across 72 m", failures)
	_check(float(flattened.get("rms_neighbor_delta_m", INF)) <= 0.5, "summit RMS roughness exceeded 0.5 m across 72 m", failures)
	_check(float(flattened.get("range_m", 0.0)) >= 2.0, "summit variation was erased completely", failures)
	_check(float(flattened.get("range_m", INF)) <= float(jagged.get("range_m", 0.0)) * 0.30, "summit range was not reduced by at least 70 percent", failures)
	_check(float(flattened.get("rms_neighbor_delta_m", INF)) <= float(jagged.get("rms_neighbor_delta_m", 0.0)) * 0.40, "local summit roughness was not reduced by at least 60 percent", failures)
	_check(terrain.get_height_profile_revision() >= 2, "terrain height profile revision was not bumped", failures)
	_check(bool(layered_validation.get("valid", false)), "layered badlands protected routes regressed: %s" % str(layered_validation), failures)
	_check(int(layered_validation.get("route_count", 0)) == 3, "layered badlands route count changed", failures)
	_check(int(layered_validation.get("connector_count", 0)) == 4, "layered badlands connector count changed", failures)
	_check(layered_height_span >= 450.0, "layered badlands vertical range regressed", failures)

	if failures.is_empty():
		print("[TerrainSummitProfileSmoketest] PASS flattened_range_m=%.2f legacy_range_m=%.2f flattened_neighbor_max_m=%.2f legacy_neighbor_max_m=%.2f flattened_neighbor_rms_m=%.3f legacy_neighbor_rms_m=%.3f samples=%d revision=%d layered_max_grade_degrees=%.2f layered_height_span_m=%.2f" % [
			float(flattened["range_m"]),
			float(jagged["range_m"]),
			float(flattened["max_neighbor_delta_m"]),
			float(jagged["max_neighbor_delta_m"]),
			float(flattened["rms_neighbor_delta_m"]),
			float(jagged["rms_neighbor_delta_m"]),
			int(flattened["samples"]),
			terrain.get_height_profile_revision(),
			float(layered_validation.get("max_grade_degrees", -1.0)),
			layered_height_span,
		])
		quit(0)
		return
	for failure in failures:
		push_error("[TerrainSummitProfileSmoketest] FAIL %s" % failure)
	quit(1)


func _sample_summit_stats(terrain: LowPolyTerrain) -> Dictionary:
	var noises: Dictionary = terrain.call("_build_noises")
	var minimum_height := INF
	var maximum_height := -INF
	var maximum_neighbor_delta := 0.0
	var squared_neighbor_delta_sum := 0.0
	var neighbor_count := 0
	var sample_count := 0
	var z := -SAMPLE_HALF_EXTENT_M
	while z <= SAMPLE_HALF_EXTENT_M:
		var x := -SAMPLE_HALF_EXTENT_M
		while x <= SAMPLE_HALF_EXTENT_M:
			if _is_full_plateau(terrain, noises, x, z):
				var height: float = float(terrain.call("_sample_height", x, z, noises))
				minimum_height = minf(minimum_height, height)
				maximum_height = maxf(maximum_height, height)
				sample_count += 1
				for offset: Vector2 in [Vector2(NEIGHBOR_SPACING_M, 0.0), Vector2(0.0, NEIGHBOR_SPACING_M)]:
					var neighbor_x: float = x + offset.x
					var neighbor_z: float = z + offset.y
					if not _is_full_plateau(terrain, noises, neighbor_x, neighbor_z):
						continue
					var neighbor_height: float = float(terrain.call("_sample_height", neighbor_x, neighbor_z, noises))
					var delta := absf(neighbor_height - height)
					maximum_neighbor_delta = maxf(maximum_neighbor_delta, delta)
					squared_neighbor_delta_sum += delta * delta
					neighbor_count += 1
			x += SAMPLE_SPACING_M
		z += SAMPLE_SPACING_M
	return {
		"samples": sample_count,
		"range_m": maximum_height - minimum_height if sample_count > 0 else INF,
		"max_neighbor_delta_m": maximum_neighbor_delta,
		"rms_neighbor_delta_m": sqrt(squared_neighbor_delta_sum / float(maxi(neighbor_count, 1))),
	}


func _is_full_plateau(terrain: LowPolyTerrain, noises: Dictionary, x: float, z: float) -> bool:
	var warp_noise := noises["canyon_warp"] as FastNoiseLite
	var wx := x + warp_noise.get_noise_2d(x, z) * terrain.canyon_warp_amplitude_m
	var wz := z + warp_noise.get_noise_2d(x + 6000.0, z - 8000.0) * terrain.canyon_warp_amplitude_m
	var main_raw := absf((noises["main_canyon"] as FastNoiseLite).get_noise_2d(wx, wz))
	var tributary_raw := absf((noises["tributary"] as FastNoiseLite).get_noise_2d(wx + wz * 0.28, wz - wx * 0.22))
	return main_raw >= terrain.canyon_floor_width + terrain.canyon_cliff_width \
			and tributary_raw >= terrain.canyon_floor_width * 0.75 + terrain.canyon_cliff_width * 0.85


func _check(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
