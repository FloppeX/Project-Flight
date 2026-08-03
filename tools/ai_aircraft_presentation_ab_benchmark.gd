extends Node3D

## Rendered A/B benchmark for dormant AI aircraft presentation branches.
## Run windowed, not headless:
## godot --windowed --resolution 1280x720 --path . res://tools/ai_aircraft_presentation_ab_benchmark.tscn

const AIRCRAFT_SCENE := preload("res://Aircraft/Aircraft_5.tscn")
const PresentationDormancy := preload("res://Aircraft/AircraftPresentationDormancy.gd")
const AIRCRAFT_COUNT := 10
const WARMUP_S := 2.0
const SAMPLE_S := 4.0

var _world: Node3D
var _camera: Camera3D
var _aircraft: Array[RigidBody3D] = []
var _dormancy_sessions: Array = []
var _attached_results: Array[Dictionary] = []
var _detached_results: Array[Dictionary] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	Engine.max_fps = 0
	_build_world()
	await _spawn_aircraft()
	_disable_existing_player_presentation_updates()
	print("[AircraftPresentationAB] aircraft=%d renderer=%s attached_nodes=%d" % [
		_aircraft.size(),
		RenderingServer.get_current_rendering_driver_name(),
		_count_tree_nodes(get_tree().root),
	])

	await _measure_phase("cache_warmup")
	for detached in [false, true, true, false]:
		await _set_presentation_detached(detached)
		var result := await _measure_phase("presentation_%s" % ("detached" if detached else "attached"))
		if detached:
			_detached_results.append(result)
		else:
			_attached_results.append(result)

	var attached := _average_results(_attached_results)
	var detached := _average_results(_detached_results)
	_print_comparison(attached, detached)
	await _set_presentation_detached(false)
	for session in _dormancy_sessions:
		session.dispose()
	await get_tree().process_frame
	get_tree().quit(0)


func _build_world() -> void:
	_world = self

	_camera = Camera3D.new()
	_camera.name = "BenchmarkCamera"
	_camera.far = 5000.0
	_camera.fov = 70.0
	_camera.position = Vector3(0.0, 140.0, 550.0)
	_world.add_child(_camera)
	_camera.look_at(Vector3(0.0, 380.0, -500.0), Vector3.UP)
	_camera.current = true

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, -25.0, 0.0)
	sun.shadow_enabled = true
	_world.add_child(sun)

	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.34, 0.42, 0.55)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.7, 0.72, 0.78)
	environment.ambient_light_energy = 0.8
	environment_node.environment = environment
	_world.add_child(environment_node)

	var visual_budget := get_node_or_null("/root/EnemyVisualBudget")
	if visual_budget != null:
		visual_budget.set("enabled", false)


func _spawn_aircraft() -> void:
	for i in range(AIRCRAFT_COUNT):
		var aircraft := AIRCRAFT_SCENE.instantiate() as RigidBody3D
		if aircraft == null:
			continue
		aircraft.name = "BenchmarkAircraft_%02d" % i
		var column := i % 5
		var row := i / 5
		aircraft.position = Vector3((float(column) - 2.0) * 150.0, 360.0 + float(row) * 100.0, -250.0 - float(row) * 450.0)
		aircraft.rotation.y = PI
		aircraft.gravity_scale = 0.0
		if "prevent_below_terrain" in aircraft:
			aircraft.set("prevent_below_terrain", false)
		_world.add_child(aircraft)
		aircraft.linear_velocity = Vector3(0.0, 0.0, -95.0)
		_aircraft.append(aircraft)
		_dormancy_sessions.append(PresentationDormancy.new(aircraft))
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame


func _disable_existing_player_presentation_updates() -> void:
	var visual_budget := get_node_or_null("/root/EnemyVisualBudget")
	if visual_budget == null:
		return
	for aircraft in _aircraft:
		var cache: Dictionary = visual_budget.call("_get_cache_for_root", aircraft)
		visual_budget.call("_apply_ai_aircraft_player_only_budget", aircraft, false, cache)
		visual_budget.call("_apply_ai_aircraft_detail_budget", visual_budget.call("_resolve_ref_array", cache.get("ai_detail_refs", [])), false)
		visual_budget.call("_apply_aircraft_audio_budget", visual_budget.call("_resolve_ref_array", cache.get("audio_refs", [])), false)
		aircraft.set_meta("visual_budget_ai_detail_enabled", false)
		aircraft.set_meta("visual_budget_ai_audio_enabled", false)


func _set_presentation_detached(detached: bool) -> void:
	var affected_nodes := 0
	for session in _dormancy_sessions:
		if detached:
			affected_nodes += int(session.detach())
		else:
			session.restore()
	await get_tree().process_frame
	await get_tree().process_frame
	print("[AircraftPresentationAB] state=%s affected_nodes=%d tree_nodes=%.0f" % [
		"detached" if detached else "attached",
		affected_nodes,
		_count_tree_nodes(get_tree().root),
	])


func _measure_phase(label: String) -> Dictionary:
	var warmup_end_us := Time.get_ticks_usec() + int(WARMUP_S * 1000000.0)
	while Time.get_ticks_usec() < warmup_end_us:
		await get_tree().process_frame

	var frame_ms: Array[float] = []
	var process_ms: Array[float] = []
	var physics_ms: Array[float] = []
	var draw_calls: Array[float] = []
	var render_objects: Array[float] = []
	var primitives: Array[float] = []
	var sample_end_us := Time.get_ticks_usec() + int(SAMPLE_S * 1000000.0)
	var last_frame_us := Time.get_ticks_usec()
	while Time.get_ticks_usec() < sample_end_us:
		await get_tree().process_frame
		var now_us := Time.get_ticks_usec()
		frame_ms.append(float(now_us - last_frame_us) * 0.001)
		last_frame_us = now_us
		process_ms.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		physics_ms.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
		draw_calls.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		render_objects.append(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
		primitives.append(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))

	var result := {
		"frame_ms": _mean(frame_ms),
		"frame_p95_ms": _percentile(frame_ms, 0.95),
		"fps": 1000.0 / maxf(_mean(frame_ms), 0.001),
		"process_ms": _mean(process_ms),
		"physics_ms": _mean(physics_ms),
		"draw_calls": _mean(draw_calls),
		"render_objects": _mean(render_objects),
		"primitives": _mean(primitives),
		"nodes": float(_count_tree_nodes(get_tree().root)),
		"samples": frame_ms.size(),
	}
	print("[AircraftPresentationAB] PHASE %s frame=%.3fms p95=%.3fms fps=%.1f process=%.3fms physics=%.3fms draws=%.0f objects=%.0f primitives=%.0f nodes=%.0f samples=%d" % [
		label,
		result.frame_ms,
		result.frame_p95_ms,
		result.fps,
		result.process_ms,
		result.physics_ms,
		result.draw_calls,
		result.render_objects,
		result.primitives,
		result.nodes,
		result.samples,
	])
	return result


func _average_results(results: Array[Dictionary]) -> Dictionary:
	var averaged := {}
	for key in ["frame_ms", "frame_p95_ms", "fps", "process_ms", "physics_ms", "draw_calls", "render_objects", "primitives", "nodes"]:
		var values: Array[float] = []
		for result in results:
			values.append(float(result[key]))
		averaged[key] = _mean(values)
	return averaged


func _print_comparison(attached: Dictionary, detached: Dictionary) -> void:
	print("[AircraftPresentationAB] RESULT attached_frame=%.3fms detached_frame=%.3fms frame_change=%+.1f%% attached_p95=%.3fms detached_p95=%.3fms p95_change=%+.1f%% attached_physics=%.3fms detached_physics=%.3fms physics_change=%+.1f%% attached_nodes=%.0f detached_nodes=%.0f node_change=%+.1f%%" % [
		attached.frame_ms,
		detached.frame_ms,
		_percent_change(attached.frame_ms, detached.frame_ms),
		attached.frame_p95_ms,
		detached.frame_p95_ms,
		_percent_change(attached.frame_p95_ms, detached.frame_p95_ms),
		attached.physics_ms,
		detached.physics_ms,
		_percent_change(attached.physics_ms, detached.physics_ms),
		attached.nodes,
		detached.nodes,
		_percent_change(attached.nodes, detached.nodes),
	])


func _mean(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	var total := 0.0
	for value in values:
		total += value
	return total / float(values.size())


func _percentile(values: Array[float], percentile: float) -> float:
	if values.is_empty():
		return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	var index := clampi(int(round((sorted.size() - 1) * percentile)), 0, sorted.size() - 1)
	return sorted[index]


func _percent_change(before: float, after: float) -> float:
	if absf(before) <= 0.000001:
		return 0.0
	return (after - before) / before * 100.0


func _count_tree_nodes(node: Node) -> int:
	var total := 1
	for child in node.get_children():
		total += _count_tree_nodes(child)
	return total
