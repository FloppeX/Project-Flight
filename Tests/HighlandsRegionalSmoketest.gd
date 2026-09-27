extends SceneTree

const TERRAIN = preload("res://Environment/LowPolyTerrain.gd")
const PROFILE = preload("res://Environment/HighlandsProfile.gd")
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	for child in root.get_children():
		child.process_mode = Node.PROCESS_MODE_DISABLED
	var terrain := TERRAIN.new()
	terrain.generate_on_ready = false
	terrain.seed = 22551
	terrain.cell_size_m = 36.0
	terrain.plateau_height_m = 500.0
	terrain.base_height_offset_m = 220.0
	terrain.set_map_profile("canyon_highlands")
	root.add_child(terrain)
	terrain.set_process(false)
	terrain.get_surface_color(Vector3.ZERO)
	var levels := [0, 0, 0, 0, 0]
	var roomy := [0, 0, 0, 0, 0]
	var maximum := 0.0
	for z in range(-24000, 24001, 240):
		for x in range(-24000, 24001, 240):
			var h: float = terrain._sample_height(x, z, terrain._noises)
			var rise: float = h - 420.0 - PROFILE.floor_relief(x, z)
			maximum = maxf(maximum, rise)
			var level := clampi(roundi(rise / PROFILE.LEVEL_HEIGHT), 0, 4)
			if absf(rise - level * PROFILE.LEVEL_HEIGHT) > 8.0:
				continue
			levels[level] += 1
			var usable := true
			for direction in 8:
				var angle := direction * TAU / 8.0
				var px := x + cos(angle) * 250.0
				var pz := z + sin(angle) * 250.0
				var other: float = terrain._sample_height(px, pz, terrain._noises)
				if absf(other - h) > 12.0:
					usable = false
			if usable:
				roomy[level] += 1
	var upper: int = levels[1] + levels[2] + levels[3] + levels[4]
	_expect(float(levels[1] + levels[2]) / maxi(upper, 1) > 0.80, "one/two levels must dominate")
	_expect(levels[3] > levels[4] and levels[4] > 0, "third levels must outnumber rare fourth levels")
	_expect(maximum <= 721.0, "unexpected summit above four levels")
	for level in range(1, 5):
		_expect(roomy[level] > 0, "level %d has no usable 500 m footprint" % level)
	_expect(float(roomy[1] + roomy[2]) / maxi(levels[1] + levels[2], 1) > 0.35, "too little usable plateau area")
	print("HIGHLANDS_REGIONAL_TEST ", JSON.stringify({"status": "PASS" if failures.is_empty() else "FAIL", "level_samples": levels, "usable_500m_footprints": roomy, "maximum_rise": maximum, "failures": failures}))
	terrain.queue_free()
	quit(0 if failures.is_empty() else 1)

func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)
