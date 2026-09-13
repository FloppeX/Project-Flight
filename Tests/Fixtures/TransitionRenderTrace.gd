extends RefCounted
## Test-only timing: render queries describe the last completed render frame,
## not necessarily the script frame sampled alongside them. Keep raw per-view
## values; disabled/WHEN_VISIBLE views can report stale times, so do not sum them.

var views: Dictionary = {}
var last_draw_ms := 0.0
var _draw_started := 0

func attach(tree: SceneTree) -> void:
	tree.node_added.connect(_node_added)
	_scan(tree.root)
	RenderingServer.frame_pre_draw.connect(_pre_draw)
	RenderingServer.frame_post_draw.connect(_post_draw)

func _scan(node: Node) -> void:
	_node_added(node)
	for child in node.get_children(): _scan(child)

func _node_added(node: Node) -> void:
	if node is Viewport:
		views[node.get_instance_id()] = weakref(node)
		RenderingServer.viewport_set_measure_render_time(node.get_viewport_rid(), true)

func _pre_draw() -> void: _draw_started = Time.get_ticks_usec()
func _post_draw() -> void:
	if _draw_started > 0: last_draw_ms = (Time.get_ticks_usec() - _draw_started) / 1000.0

func sample() -> Dictionary:
	var start := Time.get_ticks_usec()
	var timings: Array = []
	var expired: Array = []
	for id in views:
		var view := (views[id] as WeakRef).get_ref() as Viewport
		if not is_instance_valid(view):
			expired.append(id)
			continue
		if not view.is_inside_tree(): continue
		var rid := view.get_viewport_rid()
		timings.append({"id": id, "path": str(view.get_path()),
			"mode": view.render_target_update_mode if view is SubViewport else -1,
			"cpu_ms": RenderingServer.viewport_get_measured_render_time_cpu(rid),
			"gpu_ms": RenderingServer.viewport_get_measured_render_time_gpu(rid)})
	for id in expired: views.erase(id)
	return {"viewports": timings, "frame_setup_cpu_ms": RenderingServer.get_frame_setup_time_cpu(),
		"draw_wall_ms": last_draw_ms,
		"process_ms": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		"physics_ms": Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"video_mem_mb": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1000000.0,
		"pipelines": {"canvas": Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_CANVAS),
			"mesh": Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_MESH),
			"surface": Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_SURFACE),
			"draw": Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_DRAW)},
		"trace_sample_us": Time.get_ticks_usec() - start}
