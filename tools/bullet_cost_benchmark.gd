extends SceneTree

## Rendered scaling benchmark for the current physical bullet implementation.

const BULLET_SCENE_PATH := "res://Projectiles/Bullet/bullet.tscn"
const WARMUP_S := 0.75
const SAMPLE_S := 1.5
const CHURN_WARMUP_S := 1.5
const CHURN_SAMPLE_S := 3.0
const CHURN_RATE_PER_S := 100.0
const CHURN_LIFETIME_S := 1.1

var _world: Node3D = null
var _bullet_scene: PackedScene = null
var _bullets: Array[Node] = []
var _spawn_serial: int = 0
var _results_by_requested_count: Dictionary = {}

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	Engine.max_fps = 0
	_build_world()
	await process_frame
	_bullet_scene = load(BULLET_SCENE_PATH) as PackedScene
	if _bullet_scene == null:
		push_error("[BulletCostBenchmark] Could not load bullet scene")
		quit(1)
		return
	# Load shared bullet sounds/materials before recording baseline.
	_spawn_bullet(0, 0.1)
	await create_timer(0.15).timeout
	await _clear_bullets()
	await _wait_seconds(2.0)
	print("[BulletCostBenchmark] renderer=%s" % RenderingServer.get_current_rendering_driver_name())

	for requested_count in [0, 50, 100, 200, 400, 200, 100, 50, 0]:
		await _clear_bullets()
		for i in range(requested_count):
			_spawn_bullet(i, 100.0)
		var result := await _measure_fixed_phase(requested_count)
		if not _results_by_requested_count.has(requested_count):
			_results_by_requested_count[requested_count] = []
		(_results_by_requested_count[requested_count] as Array).append(result)

	var baseline := _average_results(_results_by_requested_count[0])
	for requested_count in [50, 100, 200, 400]:
		var result := _average_results(_results_by_requested_count[requested_count])
		_print_scaling_result(requested_count, baseline, result)

	await _clear_bullets()
	var churn_result := await _measure_churn_phase()
	var fixed_100 := _average_results(_results_by_requested_count[100])
	_print_churn_result(fixed_100, churn_result)

	await _clear_bullets()
	_world.queue_free()
	await process_frame
	quit(0)

func _build_world() -> void:
	_world = Node3D.new()
	root.add_child(_world)
	var camera := Camera3D.new()
	_world.add_child(camera)
	camera.position = Vector3(0.0, 25.0, 80.0)
	camera.far = 1000.0
	camera.look_at(Vector3(0.0, 18.0, -50.0), Vector3.UP)
	camera.current = true
	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.04, 0.05, 0.07)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.35, 0.35, 0.4)
	environment.ambient_light_energy = 0.5
	environment_node.environment = environment
	_world.add_child(environment_node)

func _spawn_bullet(index: int, lifetime_s: float) -> void:
	var pool: Node = root.get_node_or_null("BulletPool")
	var bullet: Node = pool.call("acquire", _bullet_scene, _world, Transform3D(Basis.IDENTITY, _get_spawn_position(index))) as Node if pool else null
	var bullet_script: Script = bullet.get_script() if bullet != null else null
	if bullet_script == null or bullet_script.resource_path != "res://Projectiles/Bullet/bullet.gd":
		push_error("[BulletCostBenchmark] Spawned projectile is not Bullet")
		if bullet != null:
			bullet.queue_free()
		return
	bullet.lifetime = lifetime_s
	bullet.gravity_scale = 0.0
	bullet.tracer_hidden_physics_frames = 0
	bullet.fire(Vector3(10.0, 0.0, 0.0), null)
	_bullets.append(bullet)
	_spawn_serial += 1

func _get_spawn_position(index: int) -> Vector3:
	var column := index % 20
	var row := (index / 20) % 20
	var layer := (index / 400) % 4
	return Vector3(
		(float(column) - 9.5) * 2.6 - 18.0,
		4.0 + float(row) * 1.8,
		-35.0 - float(layer) * 7.0
	)

func _clear_bullets() -> void:
	for bullet in _bullets:
		if bullet != null and is_instance_valid(bullet) and bullet.get_parent() == _world:
			var pool: Node = root.get_node_or_null("BulletPool")
			if pool:
				pool.call("release", bullet)
	_bullets.clear()
	await process_frame
	await process_frame
	await physics_frame
	var pool_after_release: Node = root.get_node_or_null("BulletPool")
	if pool_after_release and pool_after_release.has_method("clear_inactive"):
		pool_after_release.call("clear_inactive")
	await process_frame

func _measure_fixed_phase(requested_count: int) -> Dictionary:
	await _wait_seconds(WARMUP_S)
	var result := await _sample_seconds(SAMPLE_S, false)
	print("[BulletCostBenchmark] PHASE fixed requested=%d live=%d frame=%.3fms p95=%.3fms process=%.3fms physics=%.3fms draws=%.0f objects=%.0f primitives=%.0f nodes=%.0f active_physics=%.0f" % [
		requested_count,
		_count_live_bullets(),
		result.frame_ms,
		result.frame_p95_ms,
		result.process_ms,
		result.physics_ms,
		result.draw_calls,
		result.render_objects,
		result.primitives,
		result.nodes,
		result.active_physics,
	])
	return result

func _measure_churn_phase() -> Dictionary:
	var spawn_accumulator := 0.0
	var last_us := Time.get_ticks_usec()
	var warmup_end_us := last_us + int(CHURN_WARMUP_S * 1000000.0)
	while Time.get_ticks_usec() < warmup_end_us:
		await process_frame
		var now_us := Time.get_ticks_usec()
		spawn_accumulator = _spawn_due(float(now_us - last_us) * 0.000001, spawn_accumulator)
		last_us = now_us
	var result := await _sample_churn_seconds(CHURN_SAMPLE_S, spawn_accumulator)
	result["live_bullets"] = _count_live_bullets()
	print("[BulletCostBenchmark] PHASE churn rate=%.0f/s lifetime=%.1fs live=%d frame=%.3fms p95=%.3fms process=%.3fms physics=%.3fms draws=%.0f objects=%.0f primitives=%.0f nodes=%.0f active_physics=%.0f" % [
		CHURN_RATE_PER_S,
		CHURN_LIFETIME_S,
		result.live_bullets,
		result.frame_ms,
		result.frame_p95_ms,
		result.process_ms,
		result.physics_ms,
		result.draw_calls,
		result.render_objects,
		result.primitives,
		result.nodes,
		result.active_physics,
	])
	return result

func _sample_churn_seconds(duration_s: float, initial_spawn_accumulator: float) -> Dictionary:
	var samples := _new_sample_arrays()
	var spawn_accumulator := initial_spawn_accumulator
	var last_us := Time.get_ticks_usec()
	var end_us := last_us + int(duration_s * 1000000.0)
	while Time.get_ticks_usec() < end_us:
		await process_frame
		var now_us := Time.get_ticks_usec()
		var delta_s := float(now_us - last_us) * 0.000001
		spawn_accumulator = _spawn_due(delta_s, spawn_accumulator)
		_append_sample(samples, float(now_us - last_us) * 0.001)
		last_us = now_us
	return _summarize_samples(samples)

func _spawn_due(delta_s: float, accumulator: float) -> float:
	accumulator += delta_s * CHURN_RATE_PER_S
	while accumulator >= 1.0:
		_spawn_bullet(_spawn_serial, CHURN_LIFETIME_S)
		accumulator -= 1.0
	return accumulator

func _wait_seconds(duration_s: float) -> void:
	var end_us := Time.get_ticks_usec() + int(duration_s * 1000000.0)
	while Time.get_ticks_usec() < end_us:
		await process_frame

func _sample_seconds(duration_s: float, _unused: bool) -> Dictionary:
	var samples := _new_sample_arrays()
	var last_us := Time.get_ticks_usec()
	var end_us := last_us + int(duration_s * 1000000.0)
	while Time.get_ticks_usec() < end_us:
		await process_frame
		var now_us := Time.get_ticks_usec()
		_append_sample(samples, float(now_us - last_us) * 0.001)
		last_us = now_us
	return _summarize_samples(samples)

func _new_sample_arrays() -> Dictionary:
	return {
		"frame_ms": [] as Array[float],
		"process_ms": [] as Array[float],
		"physics_ms": [] as Array[float],
		"draw_calls": [] as Array[float],
		"render_objects": [] as Array[float],
		"primitives": [] as Array[float],
		"nodes": [] as Array[float],
		"active_physics": [] as Array[float],
	}

func _append_sample(samples: Dictionary, frame_ms: float) -> void:
	(samples.frame_ms as Array[float]).append(frame_ms)
	(samples.process_ms as Array[float]).append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
	(samples.physics_ms as Array[float]).append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
	(samples.draw_calls as Array[float]).append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	(samples.render_objects as Array[float]).append(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
	(samples.primitives as Array[float]).append(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	(samples.nodes as Array[float]).append(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	(samples.active_physics as Array[float]).append(Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS))

func _summarize_samples(samples: Dictionary) -> Dictionary:
	return {
		"frame_ms": _mean(samples.frame_ms),
		"frame_p95_ms": _percentile(samples.frame_ms, 0.95),
		"process_ms": _mean(samples.process_ms),
		"physics_ms": _mean(samples.physics_ms),
		"draw_calls": _mean(samples.draw_calls),
		"render_objects": _mean(samples.render_objects),
		"primitives": _mean(samples.primitives),
		"nodes": _mean(samples.nodes),
		"active_physics": _mean(samples.active_physics),
	}

func _count_live_bullets() -> int:
	var count := 0
	var seen: Dictionary = {}
	for bullet in _bullets:
		if bullet != null and is_instance_valid(bullet) and bullet.get_parent() == _world and not bullet.is_queued_for_deletion():
			var instance_id: int = bullet.get_instance_id()
			if seen.has(instance_id):
				continue
			seen[instance_id] = true
			count += 1
	return count

func _average_results(results: Array) -> Dictionary:
	var averaged := {}
	for key in ["frame_ms", "frame_p95_ms", "process_ms", "physics_ms", "draw_calls", "render_objects", "primitives", "nodes", "active_physics"]:
		var values: Array[float] = []
		for result in results:
			values.append(float(result[key]))
		averaged[key] = _mean(values)
	return averaged

func _print_scaling_result(count: int, baseline: Dictionary, result: Dictionary) -> void:
	print("[BulletCostBenchmark] RESULT live=%d frame_delta=%+.3fms frame_change=%+.1f%% process_delta=%+.3fms physics_delta=%+.3fms draw_delta=%+.0f object_delta=%+.0f primitive_delta=%+.0f node_delta=%+.0f active_physics_delta=%+.0f" % [
		count,
		result.frame_ms - baseline.frame_ms,
		_percent_change(baseline.frame_ms, result.frame_ms),
		result.process_ms - baseline.process_ms,
		result.physics_ms - baseline.physics_ms,
		result.draw_calls - baseline.draw_calls,
		result.render_objects - baseline.render_objects,
		result.primitives - baseline.primitives,
		result.nodes - baseline.nodes,
		result.active_physics - baseline.active_physics,
	])

func _print_churn_result(fixed_100: Dictionary, churn: Dictionary) -> void:
	print("[BulletCostBenchmark] RESULT CHURN_100_PER_S live=%d versus_fixed_100 frame_delta=%+.3fms process_delta=%+.3fms physics_delta=%+.3fms node_delta=%+.0f" % [
		int(churn.live_bullets),
		churn.frame_ms - fixed_100.frame_ms,
		churn.process_ms - fixed_100.process_ms,
		churn.physics_ms - fixed_100.physics_ms,
		churn.nodes - fixed_100.nodes,
	])

func _mean(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var total := 0.0
	for value in values:
		total += float(value)
	return total / float(values.size())

func _percentile(values: Array, percentile: float) -> float:
	if values.is_empty():
		return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	var index := clampi(int(round((sorted.size() - 1) * percentile)), 0, sorted.size() - 1)
	return float(sorted[index])

func _percent_change(before: float, after: float) -> float:
	if absf(before) <= 0.000001:
		return 0.0
	return (after - before) / before * 100.0
