extends CanvasLayer

const FrameProfiler: Script = preload("res://Debug/FrameProfiler.gd")

const PERF_LOG_INTERVAL_S := 1.0
const DETAILED_REPORT_INTERVAL_S := 5.0
const PERF_FLUSH_INTERVAL_S := 10.0
const PERFORMANCE_REPORT_TOP_COUNT := 16
const HITCH_THRESHOLD_MS := 33.0
const SEVERE_HITCH_THRESHOLD_MS := 100.0
const HITCH_EVENT_COOLDOWN_S := 0.25
const HITCH_SCOPE_EVENT_THRESHOLD_MS := 0.5
const HITCH_SCOPE_EVENT_CAPACITY := 2048
const HITCH_SCOPE_TOP_COUNT := 12
const PERFORMANCE_MARK_ACTION: StringName = &"flight_log_mark"
const AMBIENT_HITCH_TRACE_SETTING := "debug/performance_logging/ambient_hitch_trace_enabled"

var _label: Label
var _perf_file: FileAccess = null
var _report_file: FileAccess = null
var _hitch_file: FileAccess = null
var _perf_elapsed_s: float = 0.0
var _perf_log_timer_s: float = 0.0
var _detailed_report_timer_s: float = 0.0
var _perf_flush_timer_s: float = 0.0
var _perf_log_path: String = ""
var _report_log_path: String = ""
var _hitch_log_path: String = ""
var _display_enabled: bool = false
var _capture_start_usec: int = 0
var _last_process_tick_usec: int = 0
var _last_hitch_event_elapsed_s: float = -INF
var _hitch_episode_peak_ms: float = 0.0
var _hitch_event_id: int = 0
var _performance_mark_action_was_pressed: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_capture_start_usec = Time.get_ticks_usec()
	_last_process_tick_usec = _capture_start_usec
	layer = 100
	set_process_input(true)
	_label = Label.new()
	_label.anchor_left = 1.0
	_label.anchor_top = 0.0
	_label.anchor_right = 1.0
	_label.anchor_bottom = 0.0
	_label.offset_left = -150
	_label.offset_top = 10
	_label.offset_right = -12
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_label.add_theme_font_size_override("font_size", 28)
	_label.add_theme_color_override("font_color", Color.WHITE)
	_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	_label.add_theme_constant_override("shadow_offset_x", 2)
	_label.add_theme_constant_override("shadow_offset_y", 2)
	add_child(_label)
	var settings := get_node_or_null("/root/PauseMenu")
	if settings != null and settings.has_method("get_show_fps_enabled"):
		_display_enabled = bool(settings.call("get_show_fps_enabled"))
	_label.visible = _display_enabled

	var full_performance_logging := _performance_logging_requested()
	if full_performance_logging:
		_open_perf_log()
		_open_performance_report()
		_open_hitch_log()
		_enable_performance_report_profiler("performance_report")
	elif bool(ProjectSettings.get_setting(AMBIENT_HITCH_TRACE_SETTING, true)):
		# Ordinary editor/game runs retain only the cheap event-driven trace. This
		# deliberately skips the one-second metrics scan and five-second detailed
		# scene traversal used by a full logged session.
		_open_hitch_log()
		_enable_performance_report_profiler("ambient_hitch_trace")


func _performance_logging_requested() -> bool:
	if bool(ProjectSettings.get_setting("debug/performance_logging/enabled", false)):
		return true
	for argument in OS.get_cmdline_user_args():
		if argument == "--perf-log":
			return true
	var env_value: String = OS.get_environment("PROJECT_FLIGHT_PERF_LOG").strip_edges().to_lower()
	return env_value in ["1", "true", "yes", "on"]

func _exit_tree() -> void:
	if _perf_file != null:
		_perf_file.flush()
		_perf_file.close()
	if _report_file != null:
		_report_file.flush()
		_report_file.close()
	if _hitch_file != null:
		_hitch_file.flush()
		_hitch_file.close()

func _process(delta: float) -> void:
	var now_usec: int = Time.get_ticks_usec()
	var previous_process_tick_usec: int = _last_process_tick_usec
	var wall_delta_ms: float = float(maxi(now_usec - previous_process_tick_usec, 0)) * 0.001
	_last_process_tick_usec = now_usec
	if _display_enabled:
		_label.text = "%d FPS" % Engine.get_frames_per_second()
	_update_perf_log(delta)
	_update_hitch_trace(delta, wall_delta_ms, previous_process_tick_usec, now_usec)


func set_display_enabled(enabled: bool) -> void:
	_display_enabled = enabled
	if is_instance_valid(_label):
		_label.visible = _display_enabled


func is_display_enabled() -> bool:
	return _display_enabled

func _input(event: InputEvent) -> void:
	return
	if not (event is InputEventKey):
		return
	var key_event: InputEventKey = event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	if not key_event.ctrl_pressed:
		return
	if key_event.keycode == KEY_UP:
		var new_radius_up: float = ProjectileNew.adjust_hit_assist_radius_m(0.2)
		print("[Projectile] Hit assist radius: %.1fm" % new_radius_up)
	elif key_event.keycode == KEY_DOWN:
		var new_radius_down: float = ProjectileNew.adjust_hit_assist_radius_m(-0.2)
		print("[Projectile] Hit assist radius: %.1fm" % new_radius_down)

func _open_perf_log() -> void:
	var dir_path := "user://perf_logs"
	var absolute_dir := ProjectSettings.globalize_path(dir_path)
	var dir_result := DirAccess.make_dir_recursive_absolute(absolute_dir)
	if dir_result != OK:
		push_warning("[PerfLog] Could not create %s (err=%d)" % [dir_path, dir_result])
		return

	var stamp := Time.get_datetime_string_from_system(false, true).replace(":", "").replace("-", "").replace(" ", "_")
	_perf_log_path = "%s/perf_%s.csv" % [dir_path, stamp]
	_perf_file = FileAccess.open(_perf_log_path, FileAccess.WRITE)
	if _perf_file == null:
		push_warning("[PerfLog] Could not open %s (err=%d)" % [_perf_log_path, FileAccess.get_open_error()])
		return

	_perf_file.store_line(",".join([
		"elapsed_s",
		"fps",
		"process_ms",
		"physics_ms",
		"navigation_ms",
		"draw_calls",
		"render_objects",
		"render_primitives",
		"video_mem_mb",
		"texture_mem_mb",
		"buffer_mem_mb",
		"static_mem_mb",
		"node_count",
		"resource_count",
		"orphan_node_count",
		"physics_3d_active",
		"physics_3d_pairs",
		"physics_3d_islands",
		"camera_name",
		"camera_path",
		"camera_x",
		"camera_y",
		"camera_z",
		"terrain_chunks",
		"terrain_load_radius_chunks",
		"holo_present",
		"holo_visible",
		"holo_camera_distance_m",
		"holo_terrain_lines_visible",
		"holo_terrain_lines_instances",
		"nav_path_pending",
		"nav_path_running",
		"enemy_count",
		"ground_vehicle_count",
		"ground_platoon_count",
		"pilot_pool_created",
		"pilot_pool_available",
		"pilot_pool_checked_out",
		"pilot_pool_overflow_created_total",
		"pilot_pool_acquire_max_ms",
	]))
	_perf_file.flush()
	print("[PerfLog] Writing %s" % ProjectSettings.globalize_path(_perf_log_path))

func _open_performance_report() -> void:
	var dir_path := "user://perf_logs"
	var absolute_dir := ProjectSettings.globalize_path(dir_path)
	var dir_result := DirAccess.make_dir_recursive_absolute(absolute_dir)
	if dir_result != OK:
		push_warning("[PerformanceReport] Could not create %s (err=%d)" % [dir_path, dir_result])
		return

	_report_log_path = "%s/performance_report.log" % dir_path
	_report_file = FileAccess.open(_report_log_path, FileAccess.WRITE)
	if _report_file == null:
		push_warning("[PerformanceReport] Could not open %s (err=%d)" % [_report_log_path, FileAccess.get_open_error()])
		return

	_report_file.store_line("performance_report")
	_report_file.store_line("started=%s" % Time.get_datetime_string_from_system(false, true))
	_report_file.store_line("interval_s=%.1f" % DETAILED_REPORT_INTERVAL_S)
	_report_file.store_line("note=compute_top uses existing FrameProfiler labels via report capture; engine/internal work appears in process/render/navigation totals.")
	_report_file.store_line("")
	_report_file.flush()
	print("[PerformanceReport] Writing %s" % ProjectSettings.globalize_path(_report_log_path))


func _open_hitch_log() -> void:
	var dir_path := "user://perf_logs"
	var absolute_dir := ProjectSettings.globalize_path(dir_path)
	var dir_result := DirAccess.make_dir_recursive_absolute(absolute_dir)
	if dir_result != OK:
		push_warning("[PerfHitch] Could not create %s (err=%d)" % [dir_path, dir_result])
		return

	_hitch_log_path = "%s/hitch_events.csv" % dir_path
	_hitch_file = FileAccess.open(_hitch_log_path, FileAccess.WRITE)
	if _hitch_file == null:
		push_warning("[PerfHitch] Could not open %s (err=%d)" % [_hitch_log_path, FileAccess.get_open_error()])
		return

	_hitch_file.store_line(",".join([
		"event_id",
		"event_type",
		"elapsed_s",
		"wall_time",
		"process_frame",
		"physics_frame",
		"wall_delta_ms",
		"engine_delta_ms",
		"fps",
		"process_ms",
		"physics_ms",
		"navigation_ms",
		"draw_calls",
		"render_objects",
		"static_mem_mb",
		"node_count",
		"orphan_node_count",
		"camera_path",
		"camera_x",
		"camera_y",
		"camera_z",
		"terrain_chunks",
		"nav_path_pending",
		"nav_path_running",
		"enemy_count",
		"aircraft_count",
		"ai_aircraft_count",
		"ground_vehicle_count",
		"materializing_flights",
		"scope_top",
	]))
	_hitch_file.flush()
	print("[PerfHitch] Writing %s threshold_ms=%.1f mark_action=%s" % [
		ProjectSettings.globalize_path(_hitch_log_path),
		HITCH_THRESHOLD_MS,
		str(PERFORMANCE_MARK_ACTION),
	])


func _enable_performance_report_profiler(reason: String) -> void:
	FrameProfiler.configure_scope_event_capture(HITCH_SCOPE_EVENT_THRESHOLD_MS, HITCH_SCOPE_EVENT_CAPACITY)
	FrameProfiler.set_report_capture_enabled(true, reason)

func _update_perf_log(delta: float) -> void:
	if _perf_file == null and _report_file == null and _hitch_file == null:
		return
	_perf_elapsed_s = float(maxi(Time.get_ticks_usec() - _capture_start_usec, 0)) * 0.000001
	_perf_log_timer_s += maxf(delta, 0.0)
	_detailed_report_timer_s += maxf(delta, 0.0)
	_perf_flush_timer_s += maxf(delta, 0.0)
	if _perf_log_timer_s >= PERF_LOG_INTERVAL_S:
		_perf_log_timer_s = 0.0
		if _perf_file != null:
			var perf_sample_start_usec: int = FrameProfiler.begin("FPSCounter.engine_metrics_sample")
			_write_perf_sample()
			FrameProfiler.end("FPSCounter.engine_metrics_sample", perf_sample_start_usec)
	if _report_file != null and _detailed_report_timer_s >= DETAILED_REPORT_INTERVAL_S:
		_detailed_report_timer_s = 0.0
		var detailed_sample_start_usec: int = FrameProfiler.begin("FPSCounter.detailed_report_sample")
		_write_performance_report_sample()
		FrameProfiler.end("FPSCounter.detailed_report_sample", detailed_sample_start_usec)
	if _perf_flush_timer_s >= PERF_FLUSH_INTERVAL_S:
		_perf_flush_timer_s = 0.0
		if _perf_file != null:
			_perf_file.flush()
		if _report_file != null:
			_report_file.flush()
		if _hitch_file != null:
			_hitch_file.flush()

func _write_perf_sample() -> void:
	if _perf_file == null:
		return
	var camera := _get_active_camera()
	var camera_pos := camera.global_position if camera != null else Vector3.ZERO
	var terrain := get_tree().get_first_node_in_group("terrain_provider")
	var holomap := _find_first_node_named(get_tree().current_scene, "BridgeHologram")
	var holo_distance := camera.global_position.distance_to((holomap as Node3D).global_position) if camera != null and holomap is Node3D else -1.0
	var holo_lines := holomap.get_node_or_null("TerrainLines") as MultiMeshInstance3D if holomap != null else null
	var holo_multimesh := holo_lines.multimesh if holo_lines != null else null
	var nav_scheduler: Node = get_node_or_null("/root/NavPathScheduler")
	var nav_pending: int = int(nav_scheduler.call("get_pending_count")) if nav_scheduler != null and nav_scheduler.has_method("get_pending_count") else -1
	var nav_running: int = int(nav_scheduler.call("get_running_count")) if nav_scheduler != null and nav_scheduler.has_method("get_running_count") else -1
	var enemy_count: int = get_tree().get_nodes_in_group("enemies").size()
	var ground_vehicle_count: int = get_tree().get_nodes_in_group("ground_vehicles").size()
	var ground_platoon_count: int = get_tree().get_nodes_in_group("ground_vehicle_platoons").size()
	var pilot_pool_counts: Dictionary = _collect_cockpit_pilot_pool_counts()

	var values: Array[String] = [
		"%.3f" % _perf_elapsed_s,
		str(Engine.get_frames_per_second()),
		"%.3f" % (Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0),
		"%.3f" % (Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0),
		"%.3f" % (Performance.get_monitor(Performance.TIME_NAVIGATION_PROCESS) * 1000.0),
		"%.0f" % Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"%.0f" % Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		"%.0f" % Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		"%.3f" % (Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) * 0.000001),
		"%.3f" % (Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) * 0.000001),
		"%.3f" % (Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED) * 0.000001),
		"%.3f" % (Performance.get_monitor(Performance.MEMORY_STATIC) * 0.000001),
		"%.0f" % Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		"%.0f" % Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT),
		"%.0f" % Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),
		"%.0f" % Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS),
		"%.0f" % Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS),
		"%.0f" % Performance.get_monitor(Performance.PHYSICS_3D_ISLAND_COUNT),
		_csv_text(camera.name if camera != null else ""),
		_csv_text(str(camera.get_path()) if camera != null else ""),
		"%.3f" % camera_pos.x,
		"%.3f" % camera_pos.y,
		"%.3f" % camera_pos.z,
		str(_get_terrain_chunk_count(terrain)),
		str(int(terrain.get("load_radius_chunks")) if terrain != null and _object_has_property(terrain, "load_radius_chunks") else -1),
		str(1 if holomap != null else 0),
		str(1 if holomap is Node3D and (holomap as Node3D).visible else 0),
		"%.3f" % holo_distance,
		str(holo_multimesh.visible_instance_count if holo_multimesh != null else -1),
		str(holo_multimesh.instance_count if holo_multimesh != null else -1),
		str(nav_pending),
		str(nav_running),
		str(enemy_count),
		str(ground_vehicle_count),
		str(ground_platoon_count),
		str(int(pilot_pool_counts["created"])),
		str(int(pilot_pool_counts["available"])),
		str(int(pilot_pool_counts["checked_out"])),
		str(int(pilot_pool_counts["overflow_created_total"])),
		"%.3f" % float(pilot_pool_counts["acquire_max_ms"]),
	]
	_perf_file.store_line(",".join(values))


func _update_hitch_trace(
		engine_delta_s: float,
		wall_delta_ms: float,
		window_start_usec: int,
		window_end_usec: int) -> void:
	if _hitch_file == null:
		return
	var mark_pressed: bool = InputMap.has_action(PERFORMANCE_MARK_ACTION) \
			and Input.is_action_pressed(PERFORMANCE_MARK_ACTION)
	if mark_pressed and not _performance_mark_action_was_pressed:
		_write_hitch_event(
			"player_mark",
			engine_delta_s,
			wall_delta_ms,
			window_start_usec,
			window_end_usec
		)
	_performance_mark_action_was_pressed = mark_pressed

	if wall_delta_ms < HITCH_THRESHOLD_MS:
		_hitch_episode_peak_ms = 0.0
		return
	var previous_episode_peak_ms: float = _hitch_episode_peak_ms
	_hitch_episode_peak_ms = maxf(_hitch_episode_peak_ms, wall_delta_ms)
	var is_new_peak: bool = previous_episode_peak_ms <= 0.0 \
			or wall_delta_ms >= previous_episode_peak_ms * 1.5
	if _perf_elapsed_s - _last_hitch_event_elapsed_s < HITCH_EVENT_COOLDOWN_S and not is_new_peak:
		return
	var event_type := "severe_hitch" if wall_delta_ms >= SEVERE_HITCH_THRESHOLD_MS else "hitch"
	_write_hitch_event(
		event_type,
		engine_delta_s,
		wall_delta_ms,
		window_start_usec,
		window_end_usec
	)
	_last_hitch_event_elapsed_s = _perf_elapsed_s


func _write_hitch_event(
		event_type: String,
		engine_delta_s: float,
		wall_delta_ms: float,
		window_start_usec: int,
		window_end_usec: int) -> void:
	if _hitch_file == null:
		return
	_hitch_event_id += 1
	var camera: Camera3D = _get_active_camera()
	var camera_pos: Vector3 = camera.global_position if camera != null else Vector3.ZERO
	var terrain: Node = get_tree().get_first_node_in_group("terrain_provider")
	var nav_scheduler: Node = get_node_or_null("/root/NavPathScheduler")
	var nav_pending: int = int(nav_scheduler.call("get_pending_count")) \
			if nav_scheduler != null and nav_scheduler.has_method("get_pending_count") else -1
	var nav_running: int = int(nav_scheduler.call("get_running_count")) \
			if nav_scheduler != null and nav_scheduler.has_method("get_running_count") else -1
	var enemy_ops_counts: Dictionary = _collect_enemy_ops_counts()
	var scope_rows: Array[Dictionary] = FrameProfiler.summarize_scope_events(
		window_start_usec,
		window_end_usec,
		HITCH_SCOPE_TOP_COUNT
	)
	var values: Array[String] = [
		str(_hitch_event_id),
		event_type,
		"%.3f" % _perf_elapsed_s,
		_csv_text(Time.get_datetime_string_from_system(false, true)),
		str(Engine.get_process_frames()),
		str(Engine.get_physics_frames()),
		"%.3f" % wall_delta_ms,
		"%.3f" % (maxf(engine_delta_s, 0.0) * 1000.0),
		str(Engine.get_frames_per_second()),
		"%.3f" % (Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0),
		"%.3f" % (Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0),
		"%.3f" % (Performance.get_monitor(Performance.TIME_NAVIGATION_PROCESS) * 1000.0),
		"%.0f" % Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"%.0f" % Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		"%.3f" % (Performance.get_monitor(Performance.MEMORY_STATIC) * 0.000001),
		"%.0f" % Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		"%.0f" % Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),
		_csv_text(str(camera.get_path()) if camera != null else ""),
		"%.3f" % camera_pos.x,
		"%.3f" % camera_pos.y,
		"%.3f" % camera_pos.z,
		str(_get_terrain_chunk_count(terrain)),
		str(nav_pending),
		str(nav_running),
		str(get_tree().get_nodes_in_group("enemies").size()),
		str(get_tree().get_nodes_in_group("aircraft").size()),
		str(get_tree().get_nodes_in_group("ai_aircraft").size()),
		str(get_tree().get_nodes_in_group("ground_vehicles").size()),
		str(int(enemy_ops_counts.get("materializing_flights", -1))),
		_csv_text(_format_scope_rows(scope_rows)),
	]
	_hitch_file.store_line(",".join(values))


func _format_scope_rows(rows: Array[Dictionary]) -> String:
	if rows.is_empty():
		return "none"
	var parts: Array[String] = []
	for row in rows:
		parts.append("%s total_ms=%.3f max_ms=%.3f count=%d" % [
			str(row.get("label", "unknown")),
			float(row.get("total_us", 0)) * 0.001,
			float(row.get("max_us", 0)) * 0.001,
			int(row.get("count", 0)),
		])
	return " | ".join(parts)


func _write_performance_report_sample() -> void:
	if _report_file == null:
		return
	var camera: Camera3D = _get_active_camera()
	var terrain: Node = get_tree().get_first_node_in_group("terrain_provider")
	var holomap: Node = _find_first_node_named(get_tree().current_scene, "BridgeHologram")
	var holo_lines: MultiMeshInstance3D = holomap.get_node_or_null("TerrainLines") as MultiMeshInstance3D if holomap != null else null
	var holo_multimesh: MultiMesh = holo_lines.multimesh if holo_lines != null else null
	var nav_scheduler: Node = get_node_or_null("/root/NavPathScheduler")
	var nav_pending: int = int(nav_scheduler.call("get_pending_count")) if nav_scheduler != null and nav_scheduler.has_method("get_pending_count") else -1
	var nav_running: int = int(nav_scheduler.call("get_running_count")) if nav_scheduler != null and nav_scheduler.has_method("get_running_count") else -1
	var force_counts: Dictionary = _collect_force_counts()
	var enemy_ops_counts: Dictionary = _collect_enemy_ops_counts()
	var render_breakdown: Dictionary = _collect_render_breakdown(camera)
	var visual_budget_counts: Dictionary = _collect_enemy_visual_budget_counts()
	var pilot_pool_counts: Dictionary = _collect_cockpit_pilot_pool_counts()
	var static_presence_counts: Dictionary = _collect_static_presence_counts()
	var carrier_visual_budget_counts: Dictionary = _collect_carrier_visual_budget_counts()
	var profiler_rows: Array[Dictionary] = FrameProfiler.consume_report_rows(PERFORMANCE_REPORT_TOP_COUNT)

	_report_file.store_line("sample elapsed_s=%.3f wall_time=%s" % [_perf_elapsed_s, Time.get_time_string_from_system()])
	_report_file.store_line("  frame fps=%d process_ms=%.3f physics_ms=%.3f navigation_ms=%.3f" % [
		Engine.get_frames_per_second(),
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.TIME_NAVIGATION_PROCESS) * 1000.0,
	])
	_report_file.store_line("  render draw_calls=%.0f objects=%.0f primitives=%.0f video_mem_mb=%.3f texture_mem_mb=%.3f buffer_mem_mb=%.3f" % [
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) * 0.000001,
		Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) * 0.000001,
		Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED) * 0.000001,
	])
	_report_file.store_line("  render_breakdown geometry=%d visible_chain=%d frustum_origin=%d mesh=%d mesh_visible=%d multimesh=%d multimesh_visible=%d surfaces=%d visible_surfaces=%d shadow_on=%d transparent=%d multimesh_instances=%d multimesh_visible_instances=%d" % [
		int(render_breakdown["geometry"]),
		int(render_breakdown["visible_chain"]),
		int(render_breakdown["frustum_origin"]),
		int(render_breakdown["mesh"]),
		int(render_breakdown["mesh_visible"]),
		int(render_breakdown["multimesh"]),
		int(render_breakdown["multimesh_visible"]),
		int(render_breakdown["surfaces"]),
		int(render_breakdown["visible_surfaces"]),
		int(render_breakdown["shadow_on"]),
		int(render_breakdown["transparent"]),
		int(render_breakdown["multimesh_instances"]),
		int(render_breakdown["multimesh_visible_instances"]),
	])
	_report_file.store_line("  render_groups %s" % _format_render_buckets(render_breakdown["groups"] as Dictionary, 8))
	_report_file.store_line("  render_subtrees %s" % _format_render_buckets(render_breakdown["subtrees"] as Dictionary, 10))
	_report_file.store_line("  objects nodes=%.0f resources=%.0f orphan_nodes=%.0f static_mem_mb=%.3f physics3d_active=%.0f pairs=%.0f islands=%.0f" % [
		Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT),
		Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),
		Performance.get_monitor(Performance.MEMORY_STATIC) * 0.000001,
		Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS),
		Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS),
		Performance.get_monitor(Performance.PHYSICS_3D_ISLAND_COUNT),
	])
	_report_file.store_line("  forces enemies=%d enemy_air=%d enemy_ground=%d enemy_other=%d friendlies=%d friendly_air=%d friendly_ground=%d friendly_other=%d aircraft=%d ai_aircraft=%d gun_emplacements=%d buildings=%d enemy_bases=%d" % [
		int(force_counts["enemies"]),
		int(force_counts["enemy_air"]),
		int(force_counts["enemy_ground"]),
		int(force_counts["enemy_other"]),
		int(force_counts["friendlies"]),
		int(force_counts["friendly_air"]),
		int(force_counts["friendly_ground"]),
		int(force_counts["friendly_other"]),
		int(force_counts["aircraft"]),
		int(force_counts["ai_aircraft"]),
		int(force_counts["gun_emplacements"]),
		int(force_counts["buildings"]),
		int(force_counts["enemy_bases"]),
	])
	_report_file.store_line("  enemy_ops bases=%d virtual_flights=%d active_flights=%d materializing_flights=%d virtual_aircraft=%d virtual_platoons=%d active_platoons=%d virtual_ground_vehicles=%d service_interval=%.2f virtual_tick_interval=%.2f materializing_flight_tick_interval=%.2f active_tick_interval=%.2f max_ticks_per_service=%d last_due=%d last_ticked=%d service_passes=%d unit_ticks=%d flight_schedules=%d platoon_schedules=%d" % [
		int(enemy_ops_counts["bases"]),
		int(enemy_ops_counts["virtual_flights"]),
		int(enemy_ops_counts["active_flights"]),
		int(enemy_ops_counts["materializing_flights"]),
		int(enemy_ops_counts["virtual_aircraft"]),
		int(enemy_ops_counts["virtual_platoons"]),
		int(enemy_ops_counts["active_platoons"]),
		int(enemy_ops_counts["virtual_ground_vehicles"]),
		float(enemy_ops_counts["service_interval_s"]),
		float(enemy_ops_counts["virtual_tick_interval_s"]),
		float(enemy_ops_counts["materializing_flight_tick_interval_s"]),
		float(enemy_ops_counts["active_tick_interval_s"]),
		int(enemy_ops_counts["max_ticks_per_service"]),
		int(enemy_ops_counts["last_due"]),
		int(enemy_ops_counts["last_ticked"]),
		int(enemy_ops_counts["service_passes"]),
		int(enemy_ops_counts["unit_ticks"]),
		int(enemy_ops_counts["flight_schedules"]),
		int(enemy_ops_counts["platoon_schedules"]),
	])
	_report_file.store_line("  enemy_visual_budget enabled=%d candidates=%d touched=%d air=%d ground=%d human=%d near=%d mid=%d far=%d culled=%d shadow_nodes=%d shadows_disabled=%d effect_nodes=%d effects_disabled=%d player_only_disabled=%d presentation_aircraft_detached=%d presentation_nodes_detached=%d pre_tree_prepared_total=%d pre_tree_nodes_detached_total=%d contact_monitors_disabled=%d ai_detail_nodes=%d ai_detail_disabled=%d ai_audio_nodes=%d ai_audio_disabled=%d ai_engine_visual_disabled=%d ai_engine_audio_disabled=%d cache_roots=%d" % [
		1 if bool(visual_budget_counts["enabled"]) else 0,
		int(visual_budget_counts["candidate_count"]),
		int(visual_budget_counts["units_touched"]),
		int(visual_budget_counts["air_units"]),
		int(visual_budget_counts["ground_units"]),
		int(visual_budget_counts["human"]),
		int(visual_budget_counts["near"]),
		int(visual_budget_counts["mid"]),
		int(visual_budget_counts["far"]),
		int(visual_budget_counts["culled"]),
		int(visual_budget_counts["shadow_nodes"]),
		int(visual_budget_counts["shadows_disabled"]),
		int(visual_budget_counts["effect_nodes"]),
		int(visual_budget_counts["effects_disabled"]),
		int(visual_budget_counts["player_only_disabled"]),
		int(visual_budget_counts["presentation_aircraft_detached"]),
		int(visual_budget_counts["presentation_nodes_detached"]),
		int(visual_budget_counts["pre_tree_prepared_total"]),
		int(visual_budget_counts["pre_tree_nodes_detached_total"]),
		int(visual_budget_counts["aircraft_contact_monitors_disabled"]),
		int(visual_budget_counts["ai_detail_nodes"]),
		int(visual_budget_counts["ai_detail_disabled"]),
		int(visual_budget_counts["ai_audio_nodes"]),
		int(visual_budget_counts["ai_audio_disabled"]),
		int(visual_budget_counts["ai_engine_visual_disabled"]),
		int(visual_budget_counts["ai_engine_audio_disabled"]),
		int(visual_budget_counts["cache_roots"]),
	])
	_report_file.store_line("  cockpit_pilot_pool reserve=%d created=%d available=%d checked_out=%d peak_checked_out=%d acquire_count=%d release_count=%d overflow_created_total=%d failed_acquire_total=%d acquire_total_ms=%.3f acquire_max_ms=%.3f animation_prepare_count=%d animation_prepare_total_ms=%.3f animation_prepare_max_ms=%.3f" % [
		int(pilot_pool_counts["reserve_size"]),
		int(pilot_pool_counts["created"]),
		int(pilot_pool_counts["available"]),
		int(pilot_pool_counts["checked_out"]),
		int(pilot_pool_counts["peak_checked_out"]),
		int(pilot_pool_counts["acquire_count"]),
		int(pilot_pool_counts["release_count"]),
		int(pilot_pool_counts["overflow_created_total"]),
		int(pilot_pool_counts["failed_acquire_total"]),
		float(pilot_pool_counts["acquire_total_ms"]),
		float(pilot_pool_counts["acquire_max_ms"]),
		int(pilot_pool_counts["animation_prepare_count"]),
		float(pilot_pool_counts["animation_prepare_total_ms"]),
		float(pilot_pool_counts["animation_prepare_max_ms"]),
	])
	_report_file.store_line("  static_presence wind_proxies=%d wind_proxy_active=%d wind_turbines=%d gun_total=%d gun_presence_active=%d gun_presence_inactive=%d gun_turret_active=%d" % [
		int(static_presence_counts["wind_proxies"]),
		int(static_presence_counts["wind_proxy_active"]),
		int(static_presence_counts["wind_turbines"]),
		int(static_presence_counts["gun_total"]),
		int(static_presence_counts["gun_presence_active"]),
		int(static_presence_counts["gun_presence_inactive"]),
		int(static_presence_counts["gun_turret_active"]),
	])
	_report_file.store_line("  carrier_visual_budget tread_budget_enabled=%d tread_detail_active=%d tread_detail_distance_m=%.0f tread_far_update_interval_s=%.2f tread_count=%d" % [
		1 if bool(carrier_visual_budget_counts["tread_detail_budget_enabled"]) else 0,
		1 if bool(carrier_visual_budget_counts["tread_detail_active"]) else 0,
		float(carrier_visual_budget_counts["tread_detail_distance_m"]),
		float(carrier_visual_budget_counts["tread_far_update_interval_s"]),
		int(carrier_visual_budget_counts["tread_count"]),
	])
	_report_file.store_line("  nav pending=%d running=%d terrain_chunks=%d terrain_load_radius_chunks=%d holo_present=%d holo_visible=%d holo_lines_visible=%d holo_lines_instances=%d camera=%s path=%s" % [
		nav_pending,
		nav_running,
		_get_terrain_chunk_count(terrain),
		int(terrain.get("load_radius_chunks")) if terrain != null and _object_has_property(terrain, "load_radius_chunks") else -1,
		1 if holomap != null else 0,
		1 if holomap is Node3D and (holomap as Node3D).visible else 0,
		holo_multimesh.visible_instance_count if holo_multimesh != null else -1,
		holo_multimesh.instance_count if holo_multimesh != null else -1,
		camera.name if camera != null else "",
		str(camera.get_path()) if camera != null else "",
	])
	_report_file.store_line("  compute_top:")
	if profiler_rows.is_empty():
		_report_file.store_line("    none")
	else:
		for row in profiler_rows:
			var count: int = maxi(int(row["count"]), 1)
			_report_file.store_line("    %s total_ms=%.3f avg_ms=%.3f max_ms=%.3f count=%d" % [
				str(row["label"]),
				float(row["total_us"]) * 0.001,
				float(row["total_us"]) * 0.001 / float(count),
				float(row["max_us"]) * 0.001,
				count,
			])
	_report_file.store_line("")

func _collect_force_counts() -> Dictionary:
	var result: Dictionary = {
		"enemies": 0,
		"enemy_air": 0,
		"enemy_ground": 0,
		"enemy_other": 0,
		"friendlies": 0,
		"friendly_air": 0,
		"friendly_ground": 0,
		"friendly_other": 0,
		"aircraft": get_tree().get_nodes_in_group("aircraft").size(),
		"ai_aircraft": get_tree().get_nodes_in_group("ai_aircraft").size(),
		"gun_emplacements": get_tree().get_nodes_in_group("gun_emplacements").size(),
		"buildings": get_tree().get_nodes_in_group("buildings").size(),
		"enemy_bases": get_tree().get_nodes_in_group("enemy_bases").size(),
	}

	var enemies: Array = get_tree().get_nodes_in_group("enemies")
	result["enemies"] = enemies.size()
	for node_value in enemies:
		var enemy_node: Node = node_value as Node
		if enemy_node == null:
			continue
		if enemy_node.is_in_group("ground_vehicles"):
			result["enemy_ground"] = int(result["enemy_ground"]) + 1
		elif enemy_node.is_in_group("aircraft") or enemy_node.is_in_group("ai_aircraft"):
			result["enemy_air"] = int(result["enemy_air"]) + 1
		else:
			result["enemy_other"] = int(result["enemy_other"]) + 1

	var friendlies: Array = get_tree().get_nodes_in_group("friendlies")
	result["friendlies"] = friendlies.size()
	for node_value in friendlies:
		var friendly_node: Node = node_value as Node
		if friendly_node == null:
			continue
		if friendly_node.is_in_group("ground_vehicles"):
			result["friendly_ground"] = int(result["friendly_ground"]) + 1
		elif friendly_node.is_in_group("aircraft") or friendly_node.is_in_group("ai_aircraft"):
			result["friendly_air"] = int(result["friendly_air"]) + 1
		else:
			result["friendly_other"] = int(result["friendly_other"]) + 1
	return result

func _collect_enemy_ops_counts() -> Dictionary:
	var result: Dictionary = {
		"bases": 0,
		"virtual_flights": 0,
		"active_flights": 0,
		"materializing_flights": 0,
		"virtual_aircraft": 0,
		"virtual_platoons": 0,
		"active_platoons": 0,
		"virtual_ground_vehicles": 0,
		"service_interval_s": 0.0,
		"virtual_tick_interval_s": 0.0,
		"materializing_flight_tick_interval_s": 0.0,
		"active_tick_interval_s": 0.0,
		"max_ticks_per_service": 0,
		"last_due": 0,
		"last_ticked": 0,
		"service_passes": 0,
		"unit_ticks": 0,
		"flight_schedules": 0,
		"platoon_schedules": 0,
	}
	var ops: Node = get_node_or_null("/root/EnemyOpsManager")
	if ops == null:
		return result
	if ops.has_method("get_report_stats"):
		var stats_value: Variant = ops.call("get_report_stats")
		if stats_value is Dictionary:
			var stats: Dictionary = stats_value
			var stat_keys: Array[String] = [
				"service_interval_s",
				"virtual_tick_interval_s",
				"materializing_flight_tick_interval_s",
				"active_tick_interval_s",
				"max_ticks_per_service",
				"last_due",
				"last_ticked",
				"materializing_flights",
				"service_passes",
				"unit_ticks",
				"flight_schedules",
				"platoon_schedules",
			]
			for key: String in stat_keys:
				if stats.has(key):
					result[key] = stats[key]
	var bases_value: Variant = ops.get("bases")
	if not (bases_value is Array):
		return result
	var bases: Array = bases_value
	result["bases"] = bases.size()
	for base_value in bases:
		if not is_instance_valid(base_value):
			continue
		var base_object: Object = base_value as Object
		if ops.has_method("_get_flights"):
			var flights_value: Variant = ops.call("_get_flights", base_object)
			if flights_value is Array:
				for flight_value in flights_value:
					if not is_instance_valid(flight_value):
						continue
					var flight_object: Object = flight_value as Object
					result["virtual_flights"] = int(result["virtual_flights"]) + 1
					result["virtual_aircraft"] = int(result["virtual_aircraft"]) + _read_int_property(flight_object, "aircraft_count", 0)
					if _is_virtual_contact_active(flight_object):
						result["active_flights"] = int(result["active_flights"]) + 1
		if ops.has_method("_get_platoons"):
			var platoons_value: Variant = ops.call("_get_platoons", base_object)
			if platoons_value is Array:
				for platoon_value in platoons_value:
					if not is_instance_valid(platoon_value):
						continue
					var platoon_object: Object = platoon_value as Object
					result["virtual_platoons"] = int(result["virtual_platoons"]) + 1
					result["virtual_ground_vehicles"] = int(result["virtual_ground_vehicles"]) + _read_int_property(platoon_object, "vehicle_count", 0)
					if _is_virtual_contact_active(platoon_object):
						result["active_platoons"] = int(result["active_platoons"]) + 1
	return result

func _collect_enemy_visual_budget_counts() -> Dictionary:
	var result: Dictionary = {
		"enabled": false,
		"candidate_count": 0,
		"units_touched": 0,
		"air_units": 0,
		"ground_units": 0,
		"human": 0,
		"near": 0,
		"mid": 0,
		"far": 0,
		"culled": 0,
		"shadow_nodes": 0,
		"shadows_disabled": 0,
		"effect_nodes": 0,
		"effects_disabled": 0,
		"player_only_disabled": 0,
		"presentation_aircraft_detached": 0,
		"presentation_nodes_detached": 0,
		"pre_tree_prepared_total": 0,
		"pre_tree_nodes_detached_total": 0,
		"aircraft_contact_monitors_disabled": 0,
		"ai_detail_nodes": 0,
		"ai_detail_disabled": 0,
		"ai_audio_nodes": 0,
		"ai_audio_disabled": 0,
		"ai_engine_visual_disabled": 0,
		"ai_engine_audio_disabled": 0,
		"cache_roots": 0,
	}
	var budget: Node = get_node_or_null("/root/EnemyVisualBudget")
	if budget == null or not budget.has_method("get_report_stats"):
		return result
	var stats_variant: Variant = budget.call("get_report_stats")
	if not (stats_variant is Dictionary):
		return result
	var stats: Dictionary = stats_variant
	for key in result.keys():
		if stats.has(key):
			result[key] = stats[key]
	return result


func _collect_cockpit_pilot_pool_counts() -> Dictionary:
	var result: Dictionary = {
		"reserve_size": 0,
		"created": 0,
		"available": 0,
		"checked_out": 0,
		"peak_checked_out": 0,
		"acquire_count": 0,
		"release_count": 0,
		"overflow_created_total": 0,
		"failed_acquire_total": 0,
		"acquire_total_ms": 0.0,
		"acquire_max_ms": 0.0,
		"animation_prepare_count": 0,
		"animation_prepare_total_ms": 0.0,
		"animation_prepare_max_ms": 0.0,
	}
	var pilot_pool: Node = get_node_or_null("/root/CockpitPilotPool")
	if pilot_pool == null or not pilot_pool.has_method("get_pool_stats"):
		return result
	var stats_variant: Variant = pilot_pool.call("get_pool_stats")
	if not (stats_variant is Dictionary):
		return result
	var stats: Dictionary = stats_variant
	for key in result.keys():
		if stats.has(key):
			result[key] = stats[key]
	return result

func _collect_static_presence_counts() -> Dictionary:
	var result: Dictionary = {
		"wind_proxies": 0,
		"wind_proxy_active": 0,
		"wind_turbines": get_tree().get_nodes_in_group("wind_turbines").size(),
		"gun_total": 0,
		"gun_presence_active": 0,
		"gun_presence_inactive": 0,
		"gun_turret_active": 0,
	}

	var proxies: Array = get_tree().get_nodes_in_group("wind_turbine_proxies")
	result["wind_proxies"] = proxies.size()
	for node_value in proxies:
		var proxy_node: Node = node_value as Node
		if proxy_node == null or not is_instance_valid(proxy_node):
			continue
		if proxy_node.has_method("is_activated") and bool(proxy_node.call("is_activated")):
			result["wind_proxy_active"] = int(result["wind_proxy_active"]) + 1

	var guns: Array = get_tree().get_nodes_in_group("gun_emplacements")
	result["gun_total"] = guns.size()
	for node_value in guns:
		var gun_node: Node = node_value as Node
		if gun_node == null or not is_instance_valid(gun_node):
			continue
		var presence_active: bool = true
		if gun_node.has_method("is_full_presence_active"):
			presence_active = bool(gun_node.call("is_full_presence_active"))
		if presence_active:
			result["gun_presence_active"] = int(result["gun_presence_active"]) + 1
		else:
			result["gun_presence_inactive"] = int(result["gun_presence_inactive"]) + 1
		if gun_node.has_method("is_turret_active") and bool(gun_node.call("is_turret_active")):
			result["gun_turret_active"] = int(result["gun_turret_active"]) + 1
	return result

func _collect_carrier_visual_budget_counts() -> Dictionary:
	var result: Dictionary = {
		"tread_detail_budget_enabled": false,
		"tread_detail_active": true,
		"tread_detail_distance_m": 0.0,
		"tread_far_update_interval_s": 0.0,
		"tread_count": 0,
	}
	var carrier: Node = get_tree().get_first_node_in_group("carrier")
	if carrier == null or not carrier.has_method("get_visual_budget_report_stats"):
		return result
	var stats_value: Variant = carrier.call("get_visual_budget_report_stats")
	if not (stats_value is Dictionary):
		return result
	var stats: Dictionary = stats_value
	for key in result.keys():
		if stats.has(key):
			result[key] = stats[key]
	return result

func _read_int_property(object: Object, property_name: String, default_value: int) -> int:
	if object == null or not _object_has_property(object, property_name):
		return default_value
	return int(object.get(property_name))

func _is_virtual_contact_active(object: Object) -> bool:
	if object == null or not _object_has_property(object, "vstate"):
		return false
	return int(object.get("vstate")) > 0

func _collect_render_breakdown(camera: Camera3D) -> Dictionary:
	var result: Dictionary = {
		"geometry": 0,
		"visible_chain": 0,
		"frustum_origin": 0,
		"mesh": 0,
		"mesh_visible": 0,
		"multimesh": 0,
		"multimesh_visible": 0,
		"surfaces": 0,
		"visible_surfaces": 0,
		"shadow_on": 0,
		"transparent": 0,
		"multimesh_instances": 0,
		"multimesh_visible_instances": 0,
		"groups": {},
		"subtrees": {},
	}
	var scene_root: Node = get_tree().current_scene
	if scene_root == null:
		return result
	_collect_render_breakdown_recursive(scene_root, scene_root, camera, result)
	return result

func _collect_render_breakdown_recursive(node: Node, scene_root: Node, camera: Camera3D, result: Dictionary) -> void:
	if node is GeometryInstance3D:
		var geometry: GeometryInstance3D = node as GeometryInstance3D
		var visible_chain: bool = geometry.is_visible_in_tree()
		var frustum_origin: bool = false
		if visible_chain and camera != null and geometry is Node3D:
			frustum_origin = camera.is_position_in_frustum((geometry as Node3D).global_position)
		var surface_count: int = 0
		var multimesh_visible_instances: int = 0
		var multimesh_instances: int = 0

		result["geometry"] = int(result["geometry"]) + 1
		if visible_chain:
			result["visible_chain"] = int(result["visible_chain"]) + 1
		if frustum_origin:
			result["frustum_origin"] = int(result["frustum_origin"]) + 1
		if geometry.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			result["shadow_on"] = int(result["shadow_on"]) + 1
		if geometry.transparency > 0.001:
			result["transparent"] = int(result["transparent"]) + 1

		if geometry is MeshInstance3D:
			var mesh_instance: MeshInstance3D = geometry as MeshInstance3D
			result["mesh"] = int(result["mesh"]) + 1
			if visible_chain:
				result["mesh_visible"] = int(result["mesh_visible"]) + 1
			if mesh_instance.mesh != null:
				surface_count = mesh_instance.mesh.get_surface_count()
				result["surfaces"] = int(result["surfaces"]) + surface_count
				if visible_chain:
					result["visible_surfaces"] = int(result["visible_surfaces"]) + surface_count

		if geometry is MultiMeshInstance3D:
			var multimesh_instance: MultiMeshInstance3D = geometry as MultiMeshInstance3D
			result["multimesh"] = int(result["multimesh"]) + 1
			if visible_chain:
				result["multimesh_visible"] = int(result["multimesh_visible"]) + 1
			if multimesh_instance.multimesh != null:
				multimesh_instances = multimesh_instance.multimesh.instance_count
				multimesh_visible_instances = multimesh_instance.multimesh.visible_instance_count
				if multimesh_visible_instances < 0:
					multimesh_visible_instances = multimesh_instances
				result["multimesh_instances"] = int(result["multimesh_instances"]) + multimesh_instances
				if visible_chain:
					result["multimesh_visible_instances"] = int(result["multimesh_visible_instances"]) + multimesh_visible_instances

		var group_bucket: String = _get_render_group_bucket(node, scene_root)
		var subtree_bucket: String = _get_render_subtree_bucket(node, scene_root)
		_add_render_bucket(result["groups"] as Dictionary, group_bucket, visible_chain, frustum_origin, surface_count, multimesh_visible_instances)
		_add_render_bucket(result["subtrees"] as Dictionary, subtree_bucket, visible_chain, frustum_origin, surface_count, multimesh_visible_instances)

	for child in node.get_children():
		_collect_render_breakdown_recursive(child, scene_root, camera, result)

func _get_render_group_bucket(node: Node, scene_root: Node) -> String:
	var current: Node = node
	while current != null:
		if current.is_in_group("ground_vehicles"):
			return "ground_vehicles"
		if current.is_in_group("aircraft") or current.is_in_group("ai_aircraft"):
			return "aircraft"
		if current.is_in_group("enemy_bases") or current.is_in_group("gun_emplacements") or current.is_in_group("buildings"):
			return "enemy_structures"
		if current.is_in_group("terrain_provider") or str(current.name).findn("Terrain") != -1:
			return "terrain"
		if str(current.name).findn("BridgeHologram") != -1:
			return "bridge_hologram"
		if str(current.name).findn("LandCarrier") != -1:
			return "land_carrier"
		if str(current.name).findn("Particle") != -1 or str(current.name).findn("Effect") != -1:
			return "effects"
		if current == scene_root:
			break
		current = current.get_parent()
	return "other"

func _get_render_subtree_bucket(node: Node, scene_root: Node) -> String:
	var current: Node = node
	var previous: Node = node
	while current != null and current != scene_root:
		previous = current
		current = current.get_parent()
	return str(previous.name)

func _add_render_bucket(
		buckets: Dictionary,
		bucket_name: String,
		visible_chain: bool,
		frustum_origin: bool,
		surface_count: int,
		multimesh_visible_instances: int) -> void:
	var entry: Dictionary = buckets.get(bucket_name, {
		"geometry": 0,
		"visible": 0,
		"frustum": 0,
		"surfaces": 0,
		"visible_surfaces": 0,
		"multimesh_visible_instances": 0,
	})
	entry["geometry"] = int(entry["geometry"]) + 1
	entry["surfaces"] = int(entry["surfaces"]) + surface_count
	if visible_chain:
		entry["visible"] = int(entry["visible"]) + 1
		entry["visible_surfaces"] = int(entry["visible_surfaces"]) + surface_count
		entry["multimesh_visible_instances"] = int(entry["multimesh_visible_instances"]) + multimesh_visible_instances
	if frustum_origin:
		entry["frustum"] = int(entry["frustum"]) + 1
	buckets[bucket_name] = entry

func _format_render_buckets(buckets: Dictionary, max_count: int) -> String:
	if buckets.is_empty():
		return "none"
	var rows: Array[Dictionary] = []
	for bucket_name in buckets.keys():
		var entry: Dictionary = buckets[bucket_name]
		rows.append({
			"name": str(bucket_name),
			"geometry": int(entry.get("geometry", 0)),
			"visible": int(entry.get("visible", 0)),
			"frustum": int(entry.get("frustum", 0)),
			"visible_surfaces": int(entry.get("visible_surfaces", 0)),
			"multimesh_visible_instances": int(entry.get("multimesh_visible_instances", 0)),
		})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_score: int = int(a["visible_surfaces"]) + int(a["multimesh_visible_instances"]) + int(a["visible"])
		var b_score: int = int(b["visible_surfaces"]) + int(b["multimesh_visible_instances"]) + int(b["visible"])
		return a_score > b_score
	)
	var parts: Array[String] = []
	var limit: int = mini(maxi(max_count, 1), rows.size())
	for i in range(limit):
		var row: Dictionary = rows[i]
		parts.append("%s geom=%d vis=%d frustum=%d vis_surfaces=%d mm_vis=%d" % [
			str(row["name"]),
			int(row["geometry"]),
			int(row["visible"]),
			int(row["frustum"]),
			int(row["visible_surfaces"]),
			int(row["multimesh_visible_instances"]),
		])
	return " | ".join(parts)

func _get_active_camera() -> Camera3D:
	var viewport := get_viewport()
	if viewport == null:
		return null
	var camera := viewport.get_camera_3d()
	return camera if camera != null and is_instance_valid(camera) else null

func _get_terrain_chunk_count(terrain: Node) -> int:
	if terrain == null or not is_instance_valid(terrain):
		return -1
	var chunk_root := terrain.get_node_or_null("TerrainChunks")
	if chunk_root == null:
		return -1
	return chunk_root.get_child_count()

func _find_first_node_named(node: Node, node_name: String) -> Node:
	if node == null:
		return null
	if node.name == node_name:
		return node
	for child in node.get_children():
		var found := _find_first_node_named(child, node_name)
		if found != null:
			return found
	return null

func _object_has_property(object: Object, property_name: String) -> bool:
	if object == null:
		return false
	for info in object.get_property_list():
		if str(info.get("name", "")) == property_name:
			return true
	return false

func _csv_text(value: String) -> String:
	return "\"%s\"" % value.replace("\"", "\"\"")
