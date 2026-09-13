extends SceneTree

var failures: Array[String] = []

func _initialize() -> void: call_deferred("_run")

func _run() -> void:
	for child in root.get_children(): child.process_mode = Node.PROCESS_MODE_DISABLED
	var world := Node3D.new()
	root.add_child(world)
	var terrain := (load("res://Environment/LowPolyTerrainPrototype.tscn") as PackedScene).instantiate() as LowPolyTerrain
	terrain.generate_on_ready = false
	terrain.use_streaming = false
	world.add_child(terrain)
	var rock := RockStream.new()
	world.add_child(rock)
	rock.set_process(false)
	rock.snap_to_collision_surface = false
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.current = true
	camera.position = Vector3(0, 100, 0)
	var slices := 0
	while slices == 0 or rock.get_streaming_diagnostics().pending_cells > 0:
		rock._process(1.0 / 60.0)
		slices += 1
		if slices > 1000: break
	var initial := rock.get_streaming_diagnostics()
	_expect(slices > 1 and slices < 1000, "population was not bounded across slices")
	_expect(initial.rock_instances > 0, "fixture has no rocks")
	_expect(initial.max_slice_ms < 12.0, "population has an unbounded cold slice")
	var before: Dictionary = rock.get("_cell_cache").duplicate()
	var mesh: MultiMesh = rock.get("_mm")
	var offset := Vector3(8123.5, 0, -5901.25)
	terrain.position -= offset
	rock.position -= offset
	camera.position -= offset
	rock.apply_origin_shift(offset)
	rock._process(1.0 / 60.0)
	_expect(rock.get("_cell_cache") == before, "origin shift changed the rock set")
	_expect(rock.get("_mm") == mesh, "origin shift replaced the MultiMesh")
	# Retarget while a new footprint is still being populated.
	camera.position += Vector3(8000, 0, 4000)
	rock._process(1.0 / 60.0)
	camera.position -= Vector3(16000, 0, 8000)
	rock._process(1.0 / 60.0)
	_expect(rock.get("_pending").size() < 1400, "retarget accumulated obsolete work")
	rock.invalidate()
	_expect(rock.get("_cell_cache").is_empty() and rock.get("_pending").is_empty(), "rebake did not cancel old work")
	# Acceptance may finish before the collision chunk arrives. Wait, then snap.
	rock.snap_to_collision_surface = true
	rock.radius_m = 30
	rock.preload_margin_m = 0
	var center := camera.global_position
	rock._rebuild(center)
	var pending: Dictionary = rock.get("_snap_pending")
	_expect(not pending.is_empty(), "fixture lacks unresolved collision candidates")
	var floor_body := StaticBody3D.new()
	floor_body.add_to_group("terrain")
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(300, 1, 300)
	col.shape = shape
	floor_body.add_child(col)
	var first: Transform3D = pending.values()[0] if not pending.is_empty() else Transform3D.IDENTITY
	floor_body.position = rock.to_global(first.origin) + Vector3(0, 1, 0)
	world.add_child(floor_body)
	await physics_frame
	await process_frame
	rock.set("_next_snap_msec", 0)
	rock.set("_snap_queue", [])
	rock.set("_snap_index", 0)
	rock._process_work(Time.get_ticks_usec() + 100000)
	_expect(rock.get_streaming_diagnostics().rock_instances > 0, "late collision did not finalize rocks")
	print("ROCK_POPULATION_BUDGET_SMOKETEST ", JSON.stringify({"status": "PASS" if failures.is_empty() else "FAIL", "failures": failures, "slices": slices, "initial": initial}))
	world.free()
	quit(0 if failures.is_empty() else 1)

func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)
