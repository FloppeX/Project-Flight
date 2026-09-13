extends SceneTree

const FIELDS := ["_nodes", "_node_cl", "_cl_map", "_edge_starts", "_edge_nb", "_edge_cl"]
var _failures: Array[String] = []
var _cases := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	for child in root.get_children():
		child.process_mode = Node.PROCESS_MODE_DISABLED
	var terrain := load("res://Environment/LowPolyTerrain.gd").new() as Node3D
	terrain.set("generate_on_ready", false)
	root.add_child(terrain)
	terrain.set_process(false)
	var grid := root.get_node("TerrainNavGrid")
	var legacy := load("res://Tests/Fixtures/NavGraphLegacyBuilder.gd").new() as Node
	var candidate := load("res://AI/NavGraph.gd").new() as Node
	root.add_child(legacy)
	root.add_child(candidate)
	legacy.process_mode = Node.PROCESS_MODE_DISABLED
	candidate.process_mode = Node.PROCESS_MODE_DISABLED
	var rng := RandomNumberGenerator.new()
	rng.seed = 81239
	for profile in ["open_canyons", "layered_badlands"]:
		terrain.set("map_profile_id", profile)
		for cell in [24.0, 40.0, 41.3]:
			for mode in range(4):
				grid.call("_reset_bake_state")
				grid.set("_cols", 47)
				grid.set("_rows", 39)
				grid.set("cell_size_m", cell)
				grid.set("_origin_x", -971.25)
				grid.set("_origin_z", 823.125)
				var heights := PackedFloat32Array()
				heights.resize(47 * 39)
				var minimum := INF
				for z in 39:
					for x in 47:
						var h: float = 100.0
						if mode == 1:
							h += x * cell * tan(deg_to_rad(20.0))
						elif mode == 2:
							h += x * 2.0 + sin(z * 0.2) * 12.0 + rng.randf_range(-2.0, 2.0)
						elif mode == 3:
							h += 120.0 if x > 23 else 0.0
							if (x == 23 and z % 7 != 0) or (x == 8 and z == 17):
								h = -1e6
						heights[z * 47 + x] = h
						if h > -5e5:
							minimum = minf(minimum, heights[z * 47 + x])
				grid.set("_heights", heights)
				grid.set("_h_min_passable", minimum)
				grid.set("_is_baked", true)
				legacy.call("_reset_graph")
				candidate.call("_reset_graph")
				legacy.call("_build")
				candidate.call("_build")
				for field in FIELDS:
					_expect(legacy.get(field) == candidate.get(field), "%s cell=%s mode=%d differs: %s" % [profile, cell, mode, field])
				for graph in [legacy, candidate]:
					graph.set("_is_ready", true)
					graph.call("_build_spatial_index")
				var nodes: PackedVector3Array = candidate.get("_nodes")
				if nodes.size() >= 3:
					for clearance in [0.0, 80.0, 120.0]:
						var a := nodes[nodes.size() / 4]
						var b := nodes[nodes.size() * 3 / 4]
						_expect(legacy.call("find_path", a, b, clearance) == candidate.call("find_path", a, b, clearance), "path/tie-breaking differs")
				_cases += 1
	# Cache round-trip must retain the same graph, without changing existing caches.
	var cache_path := "user://navgraph_builder_equivalence_test.bin"
	candidate.call("_save", cache_path)
	legacy.call("_reset_graph")
	_expect(bool(legacy.call("_load", cache_path)), "cache round-trip failed")
	for field in FIELDS:
		_expect(legacy.get(field) == candidate.get(field), "cache field differs: " + field)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(cache_path))
	legacy.free()
	candidate.free()
	print("NAVGRAPH_BUILDER_EQUIVALENCE ", JSON.stringify({"cases": _cases, "status": "PASS" if _failures.is_empty() else "FAIL", "failures": _failures}))
	quit(0 if _failures.is_empty() else 1)

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		push_error(message)
