extends SceneTree

const TERRAIN_SCRIPT: Script = preload("res://Environment/LowPolyTerrain.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var terrain := TERRAIN_SCRIPT.new() as LowPolyTerrain
	terrain.generate_on_ready = false
	terrain.use_streaming = false
	terrain.cell_size_m = 36.0
	terrain.seed = 22551
	terrain.base_height_offset_m = 220.0
	root.add_child(terrain)

	# The public colour query initializes the exact noise set used by streamed meshes.
	terrain.get_surface_color(Vector3.ZERO)
	var dominant_counts := PackedInt32Array([0, 0, 0, 0])
	var strongest_weights := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
	var strongest_positions := PackedVector3Array([Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO])
	var accent_counts := PackedInt32Array([0, 0, 0])
	var strongest_accents := PackedFloat32Array([0.0, 0.0, 0.0])
	var strongest_accent_positions := PackedVector3Array([Vector3.ZERO, Vector3.ZERO, Vector3.ZERO])
	var dominance_total := 0.0
	var transition_samples := 0
	var sample_count := 0
	var adjacent_comparisons := 0
	var adjacent_matches := 0
	var previous_row := PackedInt32Array()

	for z in range(-24000, 24001, 1000):
		var current_row := PackedInt32Array()
		for x in range(-24000, 24001, 1000):
			var position := Vector3(float(x), 0.0, float(z))
			var weights: Vector4 = terrain._color_region_weights(position)
			var weight_sum := weights.x + weights.y + weights.z + weights.w
			_expect(absf(weight_sum - 1.0) <= 0.0001, "regional weights were not normalized at %s" % position)
			var dominant_index := _dominant_component(weights)
			if not current_row.is_empty():
				adjacent_comparisons += 1
				if current_row[current_row.size() - 1] == dominant_index:
					adjacent_matches += 1
			var column_index := current_row.size()
			if column_index < previous_row.size():
				adjacent_comparisons += 1
				if previous_row[column_index] == dominant_index:
					adjacent_matches += 1
			current_row.append(dominant_index)
			var dominance := weights[dominant_index]
			dominant_counts[dominant_index] += 1
			dominance_total += dominance
			sample_count += 1
			if dominance < 0.65:
				transition_samples += 1
			if dominance > strongest_weights[dominant_index]:
				strongest_weights[dominant_index] = dominance
				strongest_positions[dominant_index] = position

			var accent_weights: Vector3 = terrain._color_region_accent_weights(weights)
			var accent_index := _dominant_accent(accent_weights)
			var accent_weight := accent_weights[accent_index]
			if accent_weight >= 0.50:
				accent_counts[accent_index] += 1
			if accent_weight > strongest_accents[accent_index]:
				strongest_accents[accent_index] = accent_weight
				strongest_accent_positions[accent_index] = position
		previous_row = current_row

	for region_index in range(4):
		_expect(dominant_counts[region_index] >= 20, "colour region %d did not occupy a meaningful map area" % region_index)
		_expect(strongest_weights[region_index] >= 0.80, "colour region %d never became visually dominant" % region_index)
	_expect(sample_count > 0 and dominance_total / float(sample_count) >= 0.62, "regional palette remained too evenly averaged")
	_expect(transition_samples >= 20, "regional borders were too abrupt or absent")
	var adjacent_match_ratio := float(adjacent_matches) / float(maxi(adjacent_comparisons, 1))
	_expect(adjacent_match_ratio >= 0.78, "colour districts still change too frequently at one-kilometre intervals")
	for accent_index in range(3):
		_expect(accent_counts[accent_index] >= 20, "accent colour region %d did not occupy a meaningful map area" % accent_index)
		_expect(strongest_accents[accent_index] >= 0.90, "accent colour region %d never became visually distinct" % accent_index)

	var repeat_position := Vector3(7200.0, 0.0, -11300.0)
	_expect(
		terrain._color_region_weights(repeat_position).is_equal_approx(terrain._color_region_weights(repeat_position)),
		"colour districts were not deterministic"
	)

	var representative_colors: Array[Color] = []
	var representative_cliff_colors: Array[Color] = []
	for region_index in range(4):
		representative_colors.append(terrain.get_surface_color(strongest_positions[region_index]))
		var cliff_position := strongest_positions[region_index]
		cliff_position.y = terrain.base_height_offset_m + terrain.plateau_height_m - terrain.canyon_max_depth_m * 0.45
		representative_cliff_colors.append(
			terrain._surface_color_for_sample(cliff_position, Vector3.RIGHT, 7000 + region_index)
		)
	for accent_index in range(3):
		representative_colors.append(terrain.get_surface_color(strongest_accent_positions[accent_index]))
	var widest_color_distance := 0.0
	for first_index in range(representative_colors.size()):
		for second_index in range(first_index + 1, representative_colors.size()):
			widest_color_distance = maxf(
				widest_color_distance,
				_color_distance(representative_colors[first_index], representative_colors[second_index])
			)
	_expect(widest_color_distance >= 0.12, "representative terrain districts remained too similar in colour")
	var widest_cliff_color_distance := 0.0
	for first_index in range(representative_cliff_colors.size()):
		for second_index in range(first_index + 1, representative_cliff_colors.size()):
			widest_cliff_color_distance = maxf(
				widest_cliff_color_distance,
				_color_distance(representative_cliff_colors[first_index], representative_cliff_colors[second_index])
			)
	_expect(widest_cliff_color_distance >= 0.10, "cliff walls remained uniformly coloured across terrain districts")
	_expect(
		representative_cliff_colors[1].r > representative_cliff_colors[1].b + 0.08,
		"red-oxide district did not produce a warmer cliff wall"
	)
	_expect(
		representative_cliff_colors[3].b > representative_cliff_colors[3].r + 0.02,
		"cool-mineral district did not produce a blue-grey cliff wall"
	)

	print("TERRAIN_COLOR_REGIONS_SMOKETEST ", JSON.stringify({
		"status": "PASS" if _failures.is_empty() else "FAIL",
		"dominant_counts": Array(dominant_counts),
		"strongest_weights": Array(strongest_weights),
		"accent_counts": Array(accent_counts),
		"strongest_accents": Array(strongest_accents),
		"average_dominance": dominance_total / float(maxi(sample_count, 1)),
		"adjacent_match_ratio": adjacent_match_ratio,
		"transition_samples": transition_samples,
		"widest_color_distance": widest_color_distance,
		"widest_cliff_color_distance": widest_cliff_color_distance,
		"representative_cliff_colors": representative_cliff_colors,
		"failures": _failures,
	}))
	terrain.queue_free()
	quit(0 if _failures.is_empty() else 1)


func _dominant_component(weights: Vector4) -> int:
	var dominant_index := 0
	var dominant_weight := weights.x
	for index in range(1, 4):
		if weights[index] > dominant_weight:
			dominant_index = index
			dominant_weight = weights[index]
	return dominant_index


func _dominant_accent(weights: Vector3) -> int:
	var dominant_index := 0
	var dominant_weight := weights.x
	for index in range(1, 3):
		if weights[index] > dominant_weight:
			dominant_index = index
			dominant_weight = weights[index]
	return dominant_index


func _color_distance(a: Color, b: Color) -> float:
	return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		push_error("[TerrainColorRegionsSmoketest] %s" % message)
