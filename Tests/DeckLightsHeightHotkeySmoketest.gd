extends Node

const DECK_LIGHTS_SCRIPT := preload("res://LandCarrier/DeckLights.gd")

var _failures: PackedStringArray = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var deck_lights := DECK_LIGHTS_SCRIPT.new()
	deck_lights.start_marker_path = NodePath("Start")
	deck_lights.end_marker_path = NodePath("End")
	deck_lights.include_edges = false
	deck_lights.spacing_m = 5.0
	var start := Node3D.new()
	start.name = "Start"
	deck_lights.add_child(start)
	var end := Node3D.new()
	end.name = "End"
	end.position = Vector3(0.0, 0.0, 10.0)
	deck_lights.add_child(end)
	add_child(deck_lights)
	deck_lights.set_process_unhandled_input(false)

	var page_down := InputEventKey.new()
	page_down.keycode = KEY_PAGEDOWN
	page_down.pressed = true
	deck_lights._unhandled_input(page_down)
	_expect(is_equal_approx(float(deck_lights.debug_height_offset_m), -0.01), "Page Down did not lower all deck lights by one centimetre")
	_expect(_active_marker_height(deck_lights) < 0.45, "Page Down did not rebuild the visible marker below its starting height")
	var readout := deck_lights.get("_height_readout_label") as Label
	_expect(readout != null and readout.visible, "Page Down did not show the on-screen offset readout")
	if readout != null:
		_expect(readout.text.contains("-0.010 m"), "on-screen readout did not show the lowered offset")

	var page_up := InputEventKey.new()
	page_up.keycode = KEY_PAGEUP
	page_up.pressed = true
	deck_lights._unhandled_input(page_up)
	_expect(is_zero_approx(float(deck_lights.debug_height_offset_m)), "Page Up did not raise the deck lights by one centimetre")
	_expect(is_equal_approx(_active_marker_height(deck_lights), 0.45), "Page Up did not restore the visible marker height")
	if readout != null:
		_expect(readout.text.contains("+0.000 m"), "on-screen readout did not show the restored offset")

	var before_repeat := float(deck_lights.debug_height_offset_m)
	page_up.echo = true
	deck_lights._unhandled_input(page_up)
	_expect(is_equal_approx(float(deck_lights.debug_height_offset_m), before_repeat), "held-key repeat changed the deck-light offset")

	deck_lights.queue_free()
	if _failures.is_empty():
		print("DECK_LIGHT_HEIGHT_HOTKEY_SMOKETEST_OK")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error("[DeckLightsHeightHotkeySmoketest] %s" % failure)
	get_tree().quit(1)


func _active_marker_height(deck_lights: Node) -> float:
	for child in deck_lights.get_children():
		if child is MeshInstance3D and not child.is_queued_for_deletion():
			return (child as MeshInstance3D).global_position.y
	return INF


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
