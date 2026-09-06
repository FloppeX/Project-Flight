extends SceneTree

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	var overlay := root.get_node_or_null("WorldMapOverlay")
	_expect(overlay != null, "WorldMapOverlay autoload is available")
	if overlay == null:
		_finish()
		return

	overlay.call("set_console_visible", true)
	await process_frame
	var map_input := overlay.get("_map_input") as Control
	var horizontal_pan := overlay.get("_horizontal_pan") as HScrollBar
	var vertical_pan := overlay.get("_vertical_pan") as VScrollBar
	_expect(map_input != null and map_input.size.x > 100.0, "map viewport has a usable size")
	_expect(horizontal_pan != null and vertical_pan != null, "horizontal and vertical pan bars exist")
	if map_input == null:
		_finish(overlay)
		return

	_reset_view(overlay)
	var anchor := map_input.size * Vector2(0.76, 0.31)
	var anchor_before: Vector2 = overlay.call("_viewport_to_map_uv", anchor)
	overlay.call("_zoom_map_at", 1, anchor)
	var anchor_after: Vector2 = overlay.call("_viewport_to_map_uv", anchor)
	var zoom_after_anchor := float(overlay.get("_map_zoom"))
	_expect(is_equal_approx(zoom_after_anchor, 1.5), "one zoom-in step reaches 1.5x")
	_expect(anchor_before.distance_to(anchor_after) <= 0.0005, "cursor-centred zoom preserves the map point under the cursor")
	_expect(horizontal_pan != null and is_equal_approx(horizontal_pan.page, 1.0 / zoom_after_anchor), "pan-bar page size follows zoom")

	var center_before_pan: Vector2 = overlay.get("_map_view_center_uv")
	var view_rect: Rect2 = overlay.call("_get_map_view_uv_rect")
	overlay.call("_on_horizontal_pan_changed", 1.0 - view_rect.size.x)
	var center_after_pan: Vector2 = overlay.get("_map_view_center_uv")
	_expect(center_after_pan.x > center_before_pan.x, "horizontal pan bar moves the visible map window")
	var center_before_vertical_pan: Vector2 = overlay.get("_map_view_center_uv")
	overlay.call("_on_vertical_pan_changed", 1.0 - view_rect.size.y)
	var center_after_vertical_pan: Vector2 = overlay.get("_map_view_center_uv")
	_expect(center_after_vertical_pan.y > center_before_vertical_pan.y, "vertical pan bar moves the visible map window")

	_reset_view(overlay)
	var left_click := InputEventMouseButton.new()
	left_click.button_index = MOUSE_BUTTON_LEFT
	left_click.pressed = true
	left_click.position = anchor
	overlay.call("_on_map_gui_input", left_click)
	_expect(float(overlay.get("_map_zoom")) > 1.0, "left mouse zooms in while browsing")
	var right_click := InputEventMouseButton.new()
	right_click.button_index = MOUSE_BUTTON_RIGHT
	right_click.pressed = true
	right_click.position = anchor
	overlay.call("_on_map_gui_input", right_click)
	_expect(is_equal_approx(float(overlay.get("_map_zoom")), 1.0), "right mouse zooms out while browsing")

	_reset_view(overlay)
	overlay.set("_selected_asset_kind", 1) # AssetKind.FLIGHT
	overlay.set("_selected_asset_name", "Archer")
	overlay.set("_selected_mission_id", "CAS")
	overlay.set("_draft_points", [])
	overlay.call("_on_map_gui_input", left_click)
	_expect(is_equal_approx(float(overlay.get("_map_zoom")), 1.0), "left mouse keeps its target-placement meaning while drafting")
	var draft_points: Array = overlay.get("_draft_points")
	_expect(draft_points.size() == 1, "target-placement click adds a draft point")
	overlay.call("_on_map_gui_input", right_click)
	_expect(is_equal_approx(float(overlay.get("_map_zoom")), 1.0), "right mouse keeps its waypoint-removal meaning while drafting")
	draft_points = overlay.get("_draft_points")
	_expect(draft_points.is_empty(), "waypoint-removal click removes the draft point")
	overlay.call("_cancel_draft")

	_reset_view(overlay)
	var right_trigger := InputEventJoypadMotion.new()
	right_trigger.axis = JOY_AXIS_TRIGGER_RIGHT
	right_trigger.axis_value = 1.0
	overlay.call("_input", right_trigger)
	_expect(float(overlay.get("_map_zoom")) > 1.0, "right trigger zooms in")
	var right_release := InputEventJoypadMotion.new()
	right_release.axis = JOY_AXIS_TRIGGER_RIGHT
	right_release.axis_value = 0.0
	overlay.call("_input", right_release)
	var left_trigger := InputEventJoypadMotion.new()
	left_trigger.axis = JOY_AXIS_TRIGGER_LEFT
	left_trigger.axis_value = 1.0
	overlay.call("_input", left_trigger)
	_expect(is_equal_approx(float(overlay.get("_map_zoom")), 1.0), "left trigger zooms out")

	_finish(overlay)


func _reset_view(overlay: Node) -> void:
	overlay.set("_map_zoom", 1.0)
	overlay.set("_map_view_center_uv", Vector2(0.5, 0.5))
	overlay.set("_right_trigger_pressed", false)
	overlay.set("_left_trigger_pressed", false)
	overlay.call("_apply_map_view")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish(overlay: Node = null) -> void:
	if overlay != null:
		overlay.call("set_console_visible", false)
	if _failures.is_empty():
		print("[WorldMapZoomSmoketest] PASS")
		quit(0)
		return
	for failure in _failures:
		push_error("[WorldMapZoomSmoketest] %s" % failure)
	print("[WorldMapZoomSmoketest] FAIL %s" % _failures)
	quit(1)
