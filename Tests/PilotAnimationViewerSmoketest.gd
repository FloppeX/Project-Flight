extends SceneTree

const VIEWER_SCENE := preload("res://tools/PilotAnimationViewer.tscn")
const OUTPUT_PATH := "res://screenshots/pilot_animation_viewer.png"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1600, 900)
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var viewer := VIEWER_SCENE.instantiate() as Node3D
	viewport.add_child(viewer)
	for frame in range(10):
		await process_frame

	var pilot := viewer.get_node_or_null("Pilot") as Node3D
	var player := viewer.get_node_or_null("Pilot/BakedAnimationPlayer") as AnimationPlayer
	var selector := viewer.find_child("ClipSelector", true, false) as OptionButton
	var timeline := viewer.find_child("Timeline", true, false) as HSlider
	if pilot == null or player == null or selector == null or timeline == null:
		_fail("viewer is missing its pilot or playback controls")
		return
	if player.current_animation != "piloting" or not player.is_playing():
		_fail("viewer did not start with the piloting animation")
		return
	if selector.item_count < 13 or timeline.max_value < 1.0:
		_fail("viewer did not expose the baked animation library")
		return

	RenderingServer.force_draw(false, 0.0)
	await process_frame
	var image := viewport.get_texture().get_image()
	if image == null or image.is_empty() or image.save_png(OUTPUT_PATH) != OK:
		_fail("viewer screenshot could not be saved")
		return
	print("[PilotAnimationViewerSmoketest] PASS default=piloting clips=%d output=%s" % [
		selector.item_count, ProjectSettings.globalize_path(OUTPUT_PATH),
	])
	quit(0)


func _fail(reason: String) -> void:
	push_error("[PilotAnimationViewerSmoketest] FAIL %s" % reason)
	quit(1)
