extends SceneTree

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	_test_raised_arms_marker_geometry()
	_test_kia_portrait_treatment()
	if _failures.is_empty():
		print("[DownedPilotPresentationSmoketest] PASS")
		quit(0)
	else:
		for failure in _failures:
			push_error("[DownedPilotPresentationSmoketest] %s" % failure)
		quit(1)


func _test_raised_arms_marker_geometry() -> void:
	var tactical := root.get_node_or_null("WorldMapOverlay")
	_expect(tactical != null, "WorldMapOverlay autoload is available")
	if tactical == null:
		return
	var layer := tactical.get("_symbol_layer") as Control
	_expect(layer != null, "tactical map owns a symbol layer")
	if layer == null:
		return
	var geometry: Dictionary = layer.call("_downed_pilot_marker_geometry", Vector2(50.0, 50.0), 20.0)
	var head_center: Vector2 = geometry.get("head_center", Vector2.ZERO)
	var segments: Array = geometry.get("segments", [])
	_expect(segments.size() == 5, "downed-pilot symbol has torso, two arms, and two legs")
	if segments.size() >= 3:
		var left_arm := segments[1] as PackedVector2Array
		var right_arm := segments[2] as PackedVector2Array
		_expect(left_arm.size() == 3 and right_arm.size() == 3, "raised arms use readable shoulder/elbow/hand segments")
		if left_arm.size() == 3 and right_arm.size() == 3:
			_expect(left_arm[2].y < head_center.y and right_arm[2].y < head_center.y, "both hands are raised above the pilot's head")
			_expect(left_arm[2].x < head_center.x and right_arm[2].x > head_center.x, "raised arms spread to opposite sides")


func _test_kia_portrait_treatment() -> void:
	var personnel := root.get_node_or_null("PilotRosterOverlay")
	var pilot_roster := root.get_node_or_null("PilotRoster")
	_expect(personnel != null, "PilotRosterOverlay autoload is available")
	_expect(pilot_roster != null, "PilotRoster autoload is available")
	if personnel == null or pilot_roster == null:
		return
	var roster: Array = pilot_roster.call("get_carrier_roster")
	_expect(not roster.is_empty(), "pilot roster contains a portrait test subject")
	if roster.is_empty():
		return
	var alive_pilot: Dictionary = (roster[0] as Dictionary).duplicate(true)
	var killed_pilot := alive_pilot.duplicate(true)
	killed_pilot["is_alive"] = false
	killed_pilot["status"] = "killed"

	var host := Control.new()
	root.add_child(host)
	var killed_values: Array[String] = personnel.call("_pilot_values", killed_pilot)
	var killed_row := personnel.call("_make_row", killed_values, false, false, killed_pilot) as Control
	host.add_child(killed_row)
	var killed_portrait := killed_row.find_child("PortraitImage", true, false) as TextureRect
	var kia_overlay := killed_row.find_child("KIAOverlay", true, false) as ColorRect
	var kia_label := killed_row.find_child("KIALabel", true, false) as Label
	_expect(killed_portrait != null and killed_portrait.material is ShaderMaterial, "killed pilot portrait uses the grayscale material")
	_expect(kia_overlay != null and kia_label != null and kia_label.text == "KIA", "killed pilot portrait carries a lower KIA band")
	if killed_portrait != null and killed_portrait.material is ShaderMaterial:
		var shader := (killed_portrait.material as ShaderMaterial).shader
		_expect(shader != null and shader.code.contains("luminance"), "KIA portrait shader converts the image to luminance")

	var alive_values: Array[String] = personnel.call("_pilot_values", alive_pilot)
	var alive_row := personnel.call("_make_row", alive_values, false, false, alive_pilot) as Control
	host.add_child(alive_row)
	var alive_portrait := alive_row.find_child("PortraitImage", true, false) as TextureRect
	_expect(alive_portrait != null and alive_portrait.material == null, "living pilot portrait stays in color")
	_expect(alive_row.find_child("KIAOverlay", true, false) == null, "living pilot portrait has no KIA band")
	host.queue_free()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
