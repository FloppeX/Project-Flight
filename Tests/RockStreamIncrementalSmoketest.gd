extends SceneTree


class FlatTerrain:
	extends LowPolyTerrain

	func get_height(_world_pos: Vector3) -> float:
		return 100.0


class ModerateSlopeTerrain:
	extends LowPolyTerrain

	func get_height(world_pos: Vector3) -> float:
		return world_pos.x * tan(deg_to_rad(35.0))


class NearbyCliffTerrain:
	extends LowPolyTerrain

	func get_height(world_pos: Vector3) -> float:
		return 80.0 if world_pos.x >= 12.0 else 0.0


var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	# Keep this test independent of terrain generation, collision baking, and
	# rendering. A small circle is enough to prove the cache boundary behavior.
	var terrain_nav := root.get_node_or_null("TerrainNavGrid")
	_expect(terrain_nav != null, "TerrainNavGrid autoload is missing")
	if terrain_nav != null:
		terrain_nav.set("query_grid_enabled", false)
		terrain_nav.set("_query_is_baked", false)

	var terrain := FlatTerrain.new()
	terrain.generate_on_ready = false
	terrain.use_streaming = false
	root.add_child(terrain)
	var rock := RockStream.new()
	root.add_child(rock)
	rock.set_process(false)
	rock.radius_m = 100.0
	rock.preload_margin_m = 0.0
	rock.cell_size_m = 25.0
	rock.density_per_cell = 1.0
	rock.detail_mask_strength = 0.0
	rock.basin_density_bonus = 0.0
	rock.broken_ground_density_bonus = 0.0
	rock.snap_to_collision_surface = false
	rock.support_check_margin_m = 0.0
	rock.support_check_rings = 1
	rock.support_check_direction_count = 4
	rock.max_instances = 2000
	rock.set("_terrain", terrain)
	rock.set("_rock_mesh", BoxMesh.new())
	rock.set("_rock_local_min_y", -0.5)
	rock.set("_rock_local_height", 1.0)
	rock.set("_rock_local_planform_radius", 0.5)
	rock.call("_build_detail_mask")

	rock.call("_rebuild", Vector3.ZERO)
	var first: Dictionary = rock.call("get_streaming_diagnostics")
	_expect(int(first.evaluated_cells) > 40, "initial rebuild did not evaluate the full stream circle")
	_expect(int(first.reused_cells) == 0, "initial rebuild unexpectedly reused cells")
	_expect(int(first.rock_instances) > 0, "flat-terrain rebuild produced no rock instances")

	var retained_cell := Vector2i.ZERO
	var retained_transform := Transform3D.IDENTITY
	var found_retained_rock := false
	var first_cache: Dictionary = rock.get("_cell_cache")
	for cell_variant in first_cache.keys():
		var cell: Vector2i = cell_variant
		var value: Variant = first_cache[cell]
		var cell_center := Vector2(
			float(cell.x) * rock.cell_size_m + rock.cell_size_m * 0.5,
			float(cell.y) * rock.cell_size_m + rock.cell_size_m * 0.5
		)
		if value is Transform3D and cell_center.distance_to(Vector2(50.0, 0.0)) <= rock.radius_m:
			retained_cell = cell
			retained_transform = value as Transform3D
			found_retained_rock = true
			break
	_expect(found_retained_rock, "could not find an occupied cell shared by both stream circles")

	rock.call("_rebuild", Vector3(50.0, 0.0, 0.0))
	var second: Dictionary = rock.call("get_streaming_diagnostics")
	_expect(int(second.reused_cells) > int(first.cached_cells) * 0.55, "50 m movement reused too few cached cells")
	_expect(int(second.evaluated_cells) < int(first.evaluated_cells) * 0.45, "50 m movement reevaluated too much of the circle")
	if found_retained_rock:
		var second_cache: Dictionary = rock.get("_cell_cache")
		_expect(second_cache.has(retained_cell), "shared occupied cell was dropped from the cache")
		if second_cache.has(retained_cell):
			var current_transform: Transform3D = second_cache[retained_cell]
			_expect(current_transform.is_equal_approx(retained_transform), "shared rock transform changed after stream movement")

	var moderate_slope := ModerateSlopeTerrain.new()
	rock.set("_terrain", moderate_slope)
	rock.support_check_margin_m = 20.0
	_expect(
		bool(rock.call("_has_stable_terrain_support", 0.0, 0.0, 0.0, 1.0)),
		"ordinary 35-degree terrain was incorrectly suppressed"
	)
	var nearby_cliff := NearbyCliffTerrain.new()
	rock.set("_terrain", nearby_cliff)
	_expect(
		not bool(rock.call("_has_stable_terrain_support", 0.0, 0.0, 0.0, 1.0)),
		"nearby steep face did not suppress rock placement"
	)

	print("ROCK_STREAM_INCREMENTAL_SMOKETEST ", JSON.stringify({
		"status": "PASS" if _failures.is_empty() else "FAIL",
		"initial": first,
		"shifted_50m": second,
		"failures": _failures,
	}))
	rock.queue_free()
	terrain.queue_free()
	moderate_slope.free()
	nearby_cliff.free()
	await process_frame
	quit(0 if _failures.is_empty() else 1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		push_error("[RockStreamIncrementalSmoketest] %s" % message)
