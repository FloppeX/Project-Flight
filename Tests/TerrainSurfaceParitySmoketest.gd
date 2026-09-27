extends SceneTree

var failures: Array[String] = []
var max_error := 0.0
var checked := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	for child in root.get_children():
		child.process_mode = Node.PROCESS_MODE_DISABLED
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var terrain := LowPolyTerrain.new()
	terrain.generate_on_ready = false
	terrain.quads_x = 57
	terrain.quads_z = 59
	terrain.cell_size_m = 12.0
	scene.add_child(terrain)
	terrain.set_process(false)
	var started := Time.get_ticks_msec()
	for streaming in [true, false]:
		for profile in ["open_canyons", "layered_badlands", "canyon_highlands"]:
			for quantization in [0.0, 3.0]:
				terrain.use_streaming = streaming
				terrain.map_profile_id = profile
				terrain.quant_step_m = quantization
				terrain.rebuild()
				terrain.set_process(false)
				# Query before any streamed collision chunks are available.
				var prior := terrain.get_height(Vector3(23.125, 0, -17.75))
				var collision_root := Node3D.new()
				terrain.add_child(collision_root)
				if streaming:
					for x in 3:
						for z in 3:
							collision_root.add_child(terrain._build_chunk(x, z))
				await physics_frame
				await physics_frame
				_check(absf(prior - terrain.get_height(Vector3(23.125, 0, -17.75))) < 0.001, "streaming changed query")
				# Interior points and both sides of chunk boundaries; unequal map dimensions
				# also exercise truncated edge chunks and the outermost cell.
				for gx in [0.001, 0.37, 13.21, 27.999, 28.001, 42.81, 55.999, 56.001, 56.999]:
					for gz in [0.001, 0.73, 17.83, 27.999, 28.001, 43.13, 55.999, 56.001, 58.999]:
						var point := Vector3(terrain._x0 + gx * 12.0, 0, terrain._z0 + gz * 12.0)
						var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 3000, point - Vector3.UP * 1000)
						var hit := scene.get_world_3d().direct_space_state.intersect_ray(query)
						_check(not hit.is_empty(), "missing terrain collision")
						if not hit.is_empty():
							var error := absf(float(hit.position.y) - terrain.get_height(point))
							max_error = maxf(max_error, error)
							_check(error < 0.02, "surface mismatch: %s %s %s at %s: %s" % [streaming, profile, quantization, point, error])
							checked += 1
				var shift := Vector3(1500, 62, -2300)
				terrain.position += shift
				_check(absf(terrain.get_height(Vector3(23.125, 0, -17.75) + shift) - prior - shift.y) < 0.002, "origin shift changed local surface")
				terrain.position -= shift
				_check(is_nan(terrain.get_height(Vector3(10000, 0, 10000))), "outside map must return NAN")
				_check(is_finite(terrain.get_height(Vector3(terrain._x0 + terrain._span_x, 0, terrain._z0 + terrain._span_z))), "outer boundary query failed")
				collision_root.free()
	# Rebuild must invalidate previously queried heights.
	terrain.quant_step_m = 0.0
	terrain.rebuild()
	var old := terrain.get_height(Vector3.ZERO)
	terrain.base_height_offset_m += 100.0
	terrain.rebuild()
	_check(absf(terrain.get_height(Vector3.ZERO) - old - 100.0) < 0.01, "rebuild left stale height cache")
	print("TERRAIN_SURFACE_PARITY ", {"status": "PASS" if failures.is_empty() else "FAIL", "samples": checked, "max_error_m": max_error, "elapsed_ms": Time.get_ticks_msec() - started, "failures": failures})
	quit(0 if failures.is_empty() else 1)

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)
