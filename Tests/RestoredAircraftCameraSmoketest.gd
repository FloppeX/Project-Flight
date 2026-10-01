extends Node

class TestAircraft:
	extends RigidBody3D
	var current_health := 100.0
	var max_health := 100.0

func _ready() -> void:
	var deck := FlightDeckManager.new()
	var source := TestAircraft.new()
	source.freeze = true
	source.scene_file_path = "res://Aircraft/Aircraft_5.tscn"
	add_child(source)
	var legacy: Dictionary = {"pilot_id": 28, "airframe_id": "test-airframe"}
	for key in FlightDeckManager.EJECTION_INSTANCE_METADATA:
		legacy[key] = true
	legacy["ejected_pilot_body"] = NodePath("/root/OldPilotBody")
	for key in legacy:
		source.set_meta(key, legacy[key])
	var data := deck._extract_aircraft_data(source)
	var restored := TestAircraft.new()
	restored.freeze = true
	add_child(restored)
	var camera := Camera3D.new()
	camera.name = "CameraChase"
	restored.add_child(camera)
	restored.add_to_group("friendlies")
	deck._restore_aircraft_metadata(restored, legacy)
	var failures: Array[String] = []
	for key in FlightDeckManager.EJECTION_INSTANCE_METADATA:
		if data.metadata.has(key) or restored.has_meta(key):
			failures.append("Old ejection flag persisted: %s" % key)
	if restored.get_meta("pilot_id", -1) != 28 or restored.get_meta("airframe_id", "") != "test-airframe":
		failures.append("Restoration lost pilot or airframe identity")
	if not FlightDirector._get_friendly_aircraft().has(restored):
		failures.append("Restored aircraft is absent from camera cycle")
	if not FlightDirector._is_camera_cycle_excluded(source):
		failures.append("Genuinely abandoned source became selectable")
	deck.free()
	for failure in failures:
		push_error(failure)
	print("RESTORED_AIRCRAFT_CAMERA_%s" % ("PASS" if failures.is_empty() else "FAIL"))
	get_tree().quit(0 if failures.is_empty() else 1)
