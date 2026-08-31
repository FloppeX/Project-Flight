extends Node

const MAIN_MENU_SCENE := preload("res://UI/MainMenu.tscn")
const EXPECTED_NAMES := [
	"AERIAL QUARTER",
	"OVERHEAD ORBIT",
	"HILLTOP",
	"GROUND APPROACH",
	"LONG LENS",
]
const EXPECTED_FOV := [38.0, 34.0, 28.0, 50.0, 21.0]


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var menu := MAIN_MENU_SCENE.instantiate() as Node3D
	get_tree().root.add_child(menu)
	await get_tree().process_frame
	await get_tree().process_frame

	var camera := menu.get("_camera") as Camera3D
	var carrier := menu.get("_carrier_root") as Node3D
	if camera == null or carrier == null:
		_fail("startup camera or carrier was not created")
		return
	if carrier.get("_track_mark_root") == null or carrier.get("_track_mark_multimesh") == null:
		_fail("startup carrier did not initialize its track-mark pool")
		return
	var startup_marks: Array = carrier.get("_track_mark_entries") as Array
	if startup_marks.is_empty():
		_fail("startup carrier did not begin with a short settled trail")
		return
	var carrier_forward := carrier.global_transform.basis.z.normalized()
	var farthest_mark_distance := 0.0
	for entry_variant in startup_marks:
		var entry := entry_variant as Dictionary
		var mark_transform := entry.get("transform", Transform3D.IDENTITY) as Transform3D
		var relative_mark := mark_transform.origin - carrier.global_position
		farthest_mark_distance = maxf(farthest_mark_distance, relative_mark.length())
		if relative_mark.dot(carrier_forward) > 0.1:
			_fail("startup trail extended ahead of the carrier heading")
			return
	if farthest_mark_distance > 100.0:
		_fail("startup trail retained a placement teleport (%.1f m)" % farthest_mark_distance)
		return
	var settled_body_y := carrier.global_position.y
	carrier.call("_update_tread_visuals", 1.0 / 60.0, carrier.global_transform)
	if absf(carrier.global_position.y - settled_body_y) > 0.05:
		_fail("startup carrier body was still settling vertically on its first frame")
		return
	var deck_lights := carrier.get_node_or_null("DeckLights")
	if deck_lights == null:
		_fail("startup carrier deck lights were not created")
		return
	var surface_light_count := 0
	var marker_count := 0
	for child in deck_lights.get_children():
		if child is Light3D:
			surface_light_count += 1
		elif child is MeshInstance3D:
			marker_count += 1
	if surface_light_count != 0:
		_fail("marker-only startup deck lights still created %d surface lights" % surface_light_count)
		return
	if marker_count == 0:
		_fail("marker-only startup deck lights did not retain emissive markers")
		return
	if int(menu.call("get_main_camera_shot_count")) != EXPECTED_NAMES.size():
		_fail("startup camera sequence did not expose all five shots")
		return

	var positions: Array[Vector3] = []
	for shot_index in range(EXPECTED_NAMES.size()):
		menu.call("preview_main_camera_shot", shot_index, 0.35)
		var shot_name := str(menu.call("get_main_camera_shot_name"))
		if shot_name != EXPECTED_NAMES[shot_index]:
			_fail("shot %d was named %s instead of %s" % [shot_index, shot_name, EXPECTED_NAMES[shot_index]])
			return
		if not is_equal_approx(camera.fov, float(EXPECTED_FOV[shot_index])):
			_fail("%s used FOV %.1f instead of %.1f" % [shot_name, camera.fov, EXPECTED_FOV[shot_index]])
			return
		var distance_m := camera.global_position.distance_to(carrier.global_position)
		if distance_m < 180.0 or distance_m > 1000.0:
			_fail("%s distance %.1f m was outside the intended scale range" % [shot_name, distance_m])
			return
		positions.append(camera.global_position)

	for i in range(positions.size()):
		for j in range(i + 1, positions.size()):
			if positions[i].distance_to(positions[j]) < 80.0:
				_fail("camera shots %d and %d were not compositionally distinct" % [i, j])
				return

	menu.call("preview_main_camera_shot", 1, 0.10)
	var orbit_a := camera.global_position
	menu.call("preview_main_camera_shot", 1, 0.82)
	var orbit_b := camera.global_position
	if orbit_a.distance_to(orbit_b) < 300.0:
		_fail("overhead shot did not visibly circle the carrier")
		return

	menu.call("preview_main_camera_shot", 3, 0.35)
	var ground_anchor := camera.global_position
	menu.call("_position_exterior_camera")
	if camera.global_position.distance_to(ground_anchor) > 0.01:
		_fail("ground camera did not remain planted at its fixed position")
		return
	var terrain_y := float(menu.call("_terrain_height_at", ground_anchor))
	if not is_nan(terrain_y) and ground_anchor.y < terrain_y + 5.9:
		_fail("ground camera was not kept safely above the terrain")
		return

	menu.queue_free()
	await get_tree().process_frame
	print("[StartupCameraSequenceSmoketest] PASS shots=5 deck_lights=marker_only modes=orbit+hilltop+ground+long_lens")
	get_tree().quit(0)


func _fail(reason: String) -> void:
	push_error("[StartupCameraSequenceSmoketest] FAIL %s" % reason)
	get_tree().quit(1)
