extends CanvasLayer

const PERF_LOG_INTERVAL_S := 1.0

var _label: Label
var _hit_assist_label: Label
var _perf_file: FileAccess = null
var _perf_elapsed_s: float = 0.0
var _perf_log_timer_s: float = 0.0
var _perf_log_path: String = ""

func _ready() -> void:
	layer = 100
	set_process_input(true)
	_label = Label.new()
	_label.anchor_left = 1.0
	_label.anchor_top = 0.0
	_label.anchor_right = 1.0
	_label.anchor_bottom = 0.0
	_label.offset_left = -80
	_label.offset_top = 5
	_label.offset_right = -5
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_label.add_theme_font_size_override("font_size", 14)
	_label.add_theme_color_override("font_color", Color.WHITE)
	_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	_label.add_theme_constant_override("shadow_offset_x", 1)
	_label.add_theme_constant_override("shadow_offset_y", 1)
	add_child(_label)

	_hit_assist_label = Label.new()
	_hit_assist_label.anchor_left = 0.0
	_hit_assist_label.anchor_top = 0.0
	_hit_assist_label.anchor_right = 0.0
	_hit_assist_label.anchor_bottom = 0.0
	_hit_assist_label.offset_left = 8
	_hit_assist_label.offset_top = 8
	_hit_assist_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_hit_assist_label.add_theme_font_size_override("font_size", 16)
	_hit_assist_label.add_theme_color_override("font_color", Color(0.85, 1.0, 0.85, 1.0))
	_hit_assist_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 1.0))
	_hit_assist_label.add_theme_constant_override("shadow_offset_x", 1)
	_hit_assist_label.add_theme_constant_override("shadow_offset_y", 1)
	add_child(_hit_assist_label)
	_open_perf_log()

func _process(delta: float) -> void:
	_label.text = "%d FPS" % Engine.get_frames_per_second()
	_hit_assist_label.text = "Hit Assist Radius: %.1fm" % ProjectileNew.get_hit_assist_radius_m()
	_update_perf_log(delta)

func _input(event: InputEvent) -> void:
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
	]))
	_perf_file.flush()
	print("[PerfLog] Writing %s" % ProjectSettings.globalize_path(_perf_log_path))

func _update_perf_log(delta: float) -> void:
	if _perf_file == null:
		return
	_perf_elapsed_s += maxf(delta, 0.0)
	_perf_log_timer_s += maxf(delta, 0.0)
	if _perf_log_timer_s < PERF_LOG_INTERVAL_S:
		return
	_perf_log_timer_s = 0.0
	_write_perf_sample()

func _write_perf_sample() -> void:
	var camera := _get_active_camera()
	var camera_pos := camera.global_position if camera != null else Vector3.ZERO
	var terrain := get_tree().get_first_node_in_group("terrain_provider")
	var holomap := _find_first_node_named(get_tree().current_scene, "BridgeHologram")
	var holo_distance := camera.global_position.distance_to((holomap as Node3D).global_position) if camera != null and holomap is Node3D else -1.0
	var holo_lines := holomap.get_node_or_null("TerrainLines") as MultiMeshInstance3D if holomap != null else null
	var holo_multimesh := holo_lines.multimesh if holo_lines != null else null

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
	]
	_perf_file.store_line(",".join(values))
	_perf_file.flush()

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
