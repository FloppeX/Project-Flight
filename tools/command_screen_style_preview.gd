extends SceneTree

const TACTICAL_PREVIEW_PATH := "res://screenshots/command_screen_style_preview.png"
const MISSION_POPUP_PREVIEW_PATH := "res://screenshots/command_screen_mission_popup_preview.png"
const CONFIRM_PREVIEW_PATH := "res://screenshots/command_screen_confirm_preview.png"
const PERSONNEL_PREVIEW_PATH := "res://screenshots/command_screen_personnel_preview.png"
const PREVIEW_SIZE := Vector2i(1920, 1080)


func _initialize() -> void:
	call_deferred("_capture_preview")


func _capture_preview() -> void:
	DisplayServer.window_set_size(PREVIEW_SIZE)
	root.content_scale_size = PREVIEW_SIZE
	await process_frame
	await process_frame

	var console := root.get_node_or_null("CarrierConsole")
	if console == null:
		push_error("[CommandScreenStylePreview] CarrierConsole autoload unavailable")
		quit(1)
		return
	console.call("show_page", "tactical", true)

	await process_frame
	await process_frame
	RenderingServer.force_draw(false, 0.0)
	await process_frame
	if not _save_preview(TACTICAL_PREVIEW_PATH):
		quit(1)
		return
	var tactical := root.get_node_or_null("WorldMapOverlay")
	if tactical == null:
		push_error("[CommandScreenStylePreview] WorldMapOverlay autoload unavailable")
		quit(1)
		return
	var asset_entries_variant = tactical.get("_asset_buttons")
	var asset_entries: Array = asset_entries_variant if asset_entries_variant is Array else []
	if asset_entries.is_empty():
		push_error("[CommandScreenStylePreview] No asset buttons available")
		quit(1)
		return
	var asset_button := asset_entries[0].get("button") as Button
	asset_button.emit_signal("pressed")
	await process_frame
	RenderingServer.force_draw(false, 0.0)
	await process_frame
	if not _save_preview(MISSION_POPUP_PREVIEW_PATH):
		quit(1)
		return
	tactical.call("_begin_mission_draft", "CAP")
	var preview_points: Array[Vector3] = [Vector3(0.0, 800.0, 0.0)]
	tactical.set("_draft_points", preview_points)
	tactical.call("_refresh_ui")
	await process_frame
	RenderingServer.force_draw(false, 0.0)
	await process_frame
	if not _save_preview(CONFIRM_PREVIEW_PATH):
		quit(1)
		return

	console.call("show_page", "personnel", true)
	await process_frame
	await process_frame
	RenderingServer.force_draw(false, 0.0)
	await process_frame
	if not _save_preview(PERSONNEL_PREVIEW_PATH):
		quit(1)
		return
	quit()


func _save_preview(path: String) -> bool:
	var image := root.get_texture().get_image()
	var absolute_path := ProjectSettings.globalize_path(path)
	var error := image.save_png(absolute_path)
	if error != OK:
		push_error("[CommandScreenStylePreview] Failed to save preview: %s" % error)
		return false
	print("[CommandScreenStylePreview] Saved %s (%dx%d)" % [absolute_path, image.get_width(), image.get_height()])
	return true
