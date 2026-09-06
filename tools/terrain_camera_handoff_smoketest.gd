extends Node3D

const TEST_TIMEOUT_S: float = 4.0
const HANDOFF_MAX_VISIBLE_DELAY_S: float = 1.5

var _failures: Array[String] = []

func _ready() -> void:
	var camera_a := Camera3D.new()
	camera_a.name = "CameraA"
	add_child(camera_a)
	camera_a.global_position = Vector3(-600.0, 600.0, 0.0)
	camera_a.look_at(Vector3(-600.0, 0.0, 0.0), Vector3.FORWARD)
	camera_a.current = true

	var camera_b := Camera3D.new()
	camera_b.name = "CameraB"
	add_child(camera_b)
	camera_b.global_position = Vector3(600.0, 600.0, 0.0)
	camera_b.look_at(Vector3(600.0, 0.0, 0.0), Vector3.FORWARD)

	var terrain := LowPolyTerrain.new()
	terrain.name = "HandoffTerrain"
	terrain.generate_on_ready = false
	terrain.generate_collision = false
	terrain.quads_x = 96
	terrain.quads_z = 96
	terrain.cell_size_m = 20.0
	terrain.chunk_quads_x = 8
	terrain.chunk_quads_z = 8
	terrain.load_radius_chunks = 2
	terrain.unload_margin_chunks = 0
	terrain.stream_preload_ahead_m = 0.0
	# A deliberately slow ordinary interval proves that camera identity changes
	# take the immediate handoff path instead of waiting for this timer.
	terrain.stream_update_interval_s = 2.0
	terrain.max_chunk_builds_per_update = 1
	terrain.initial_chunk_builds_per_update = 1
	terrain.max_chunk_finalizes_per_frame = 1
	terrain.camera_handoff_builds_per_frame = 9
	terrain.camera_handoff_finalizes_per_frame = 9
	terrain.camera_handoff_priority_duration_s = 1.0
	terrain.camera_handoff_min_jump_chunks = 2
	terrain.camera_handoff_priority_radius_chunks = 1
	terrain.quant_step_m = 0.0
	terrain.cliff_planform_straighten_strength = 0.0
	terrain.cliff_planform_jitter_strength = 0.0
	terrain.cliff_washboard_suppress_strength = 0.0
	add_child(terrain)
	terrain.rebuild()

	var initial_visible: bool = await _wait_for_chunk(terrain, camera_a.global_position, TEST_TIMEOUT_S)
	_assert(initial_visible, "initial camera chunk did not become visible")
	if not initial_visible:
		_finish(terrain, -1.0)
		return

	await get_tree().process_frame
	# A cinematic transfer should prefetch the destination without following the
	# temporary camera across every intermediate chunk or retiring the source ring.
	var start_ms: int = Time.get_ticks_msec()
	terrain.begin_view_transition_streaming(camera_b)
	await get_tree().process_frame
	var prefetch_stats: Dictionary = terrain.get_streaming_stats()
	_assert(bool(prefetch_stats.get("view_transition_active", false)), "explicit transition prefetch did not activate")
	var switched_visible: bool = await _wait_for_chunk(terrain, camera_b.global_position, TEST_TIMEOUT_S)
	var visible_delay_s: float = float(Time.get_ticks_msec() - start_ms) / 1000.0
	_assert(switched_visible, "prefetched destination camera chunk did not become visible")
	_assert(terrain.is_chunk_loaded_at_world_position(camera_a.global_position), "source terrain was retired before camera arrival")

	camera_a.current = false
	camera_b.current = true
	terrain.end_view_transition_streaming()
	await get_tree().process_frame
	var handoff_stats: Dictionary = terrain.get_streaming_stats()
	_assert(bool(handoff_stats.get("camera_handoff_active", false)), "camera switch did not activate terrain handoff priority")
	_assert(not bool(handoff_stats.get("view_transition_active", true)), "transition prefetch remained active after arrival")
	_assert(visible_delay_s < HANDOFF_MAX_VISIBLE_DELAY_S, "terrain handoff waited too long: %.3f s" % visible_delay_s)
	var source_released := await _wait_for_chunk_unloaded(terrain, camera_a.global_position, TEST_TIMEOUT_S)
	_assert(source_released, "source terrain was not retired incrementally after arrival")
	_finish(terrain, visible_delay_s)

func _wait_for_chunk(terrain: LowPolyTerrain, world_position: Vector3, timeout_s: float) -> bool:
	var start_ms: int = Time.get_ticks_msec()
	while float(Time.get_ticks_msec() - start_ms) / 1000.0 < timeout_s:
		if terrain.is_chunk_loaded_at_world_position(world_position):
			return true
		await get_tree().process_frame
	return false

func _wait_for_chunk_unloaded(terrain: LowPolyTerrain, world_position: Vector3, timeout_s: float) -> bool:
	var start_ms: int = Time.get_ticks_msec()
	while float(Time.get_ticks_msec() - start_ms) / 1000.0 < timeout_s:
		if not terrain.is_chunk_loaded_at_world_position(world_position):
			return true
		await get_tree().process_frame
	return false

func _finish(terrain: LowPolyTerrain, visible_delay_s: float) -> void:
	print("TERRAIN_CAMERA_HANDOFF_SMOKETEST ", JSON.stringify({
		"visible_delay_s": visible_delay_s,
		"ordinary_stream_interval_s": terrain.stream_update_interval_s,
		"stats": terrain.get_streaming_stats(),
		"failures": _failures,
	}))
	get_tree().quit(0 if _failures.is_empty() else 1)

func _assert(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		push_error(message)
