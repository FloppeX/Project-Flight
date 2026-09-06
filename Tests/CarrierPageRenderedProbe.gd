extends SceneTree

const OUTPUT_PATH := "user://carrier_page_wireframe.png"
const PREVIEW_SIZE := Vector2i(1920, 1080)


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	DisplayServer.window_set_size(PREVIEW_SIZE)
	root.content_scale_size = PREVIEW_SIZE
	await process_frame
	await process_frame
	var console := root.get_node_or_null("CarrierConsole")
	if console == null:
		push_error("CARRIER_PAGE_RENDERED_PROBE_FAIL: CarrierConsole unavailable")
		quit(1)
		return
	console.call("show_page", "carrier", true)
	var load_deadline := Time.get_ticks_msec() + 10000
	while Time.get_ticks_msec() < load_deadline:
		var pending_snapshot: Dictionary = console.call("get_page_debug_snapshot", "carrier")
		var pending_wireframe: Dictionary = pending_snapshot.get("wireframe", {})
		if bool(pending_wireframe.get("model_loaded", false)) \
				or not bool(pending_wireframe.get("load_requested", true)):
			break
		await create_timer(0.02).timeout
	var user_args := OS.get_cmdline_user_args()
	if not user_args.is_empty():
		var carrier_page := console.get("_carrier_page") as Control
		if carrier_page != null:
			carrier_page.call("_select_system", str(user_args[0]))
	for _frame in range(8):
		await process_frame
	var carrier_snapshot: Dictionary = console.call("get_page_debug_snapshot", "carrier")
	var wireframe_snapshot: Dictionary = carrier_snapshot.get("wireframe", {})
	print("CARRIER_FEATURE_EDGES segments=%d triangles=%d build_ms=%.2f profile=%s" % [
		int(wireframe_snapshot.get("wire_segment_count", 0)),
		int(wireframe_snapshot.get("source_triangle_count", 0)),
		float(wireframe_snapshot.get("build_time_ms", 0.0)),
		str(wireframe_snapshot.get("build_profile_ms", {})),
	])
	RenderingServer.force_draw(false, 0.0)
	await process_frame
	var image := root.get_texture().get_image()
	var absolute_path := ProjectSettings.globalize_path(OUTPUT_PATH)
	var error := image.save_png(absolute_path)
	console.call("set_open", false)
	if error != OK:
		push_error("CARRIER_PAGE_RENDERED_PROBE_FAIL: save error %d" % error)
		quit(1)
		return
	print("CARRIER_PAGE_RENDERED_PROBE_OK path=%s size=%s" % [absolute_path, str(image.get_size())])
	quit(0)
