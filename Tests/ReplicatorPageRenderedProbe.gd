extends SceneTree

const OUTPUT_PATH := "user://replicator_page_concept.png"


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	await process_frame
	var console := root.get_node_or_null("CarrierConsole")
	if console == null:
		push_error("REPLICATOR_PAGE_RENDERED_PROBE_FAIL: CarrierConsole unavailable")
		quit(1)
		return
	console.call("show_page", "replicator", true)
	await process_frame
	await process_frame
	await create_timer(0.2).timeout
	var image := root.get_texture().get_image()
	var absolute_path := ProjectSettings.globalize_path(OUTPUT_PATH)
	var error := image.save_png(absolute_path)
	console.call("set_open", false)
	if error != OK:
		push_error("REPLICATOR_PAGE_RENDERED_PROBE_FAIL: save error %d" % error)
		quit(1)
		return
	print("REPLICATOR_PAGE_RENDERED_PROBE_OK path=%s size=%s" % [absolute_path, str(image.get_size())])
	quit(0)
