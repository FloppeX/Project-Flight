extends SceneTree

const CARRIER_SCENE := preload("res://Models/LandCarrier/CarrierWithInterior.tscn")
const DOOR_SCRIPT := preload("res://LandCarrier/CarrierSlidingDoor.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures := PackedStringArray()
	var carrier := CARRIER_SCENE.instantiate() as Node3D
	root.add_child(carrier)
	await process_frame
	await process_frame
	await process_frame

	var source := load("res://Models/LandCarrier/Land carrier 4.glb").instantiate() as Node3D
	for mesh_name in ["main hull", "Flight deck", "Elevators", "superstructure main island", "superstructure floor lower", "superstructure floor upper", "Superstructure elevator"]:
		var source_mesh := source.get_node_or_null(mesh_name) as MeshInstance3D
		var mounted_mesh := carrier.get_node_or_null(mesh_name) as MeshInstance3D
		_expect(source_mesh != null and mounted_mesh != null and mounted_mesh.visible, "%s is not the mounted Land carrier 4 mesh" % mesh_name, failures)
		if source_mesh and mounted_mesh:
			_expect((source_mesh.transform * source_mesh.get_aabb()).is_equal_approx(mounted_mesh.transform * mounted_mesh.get_aabb()), "%s moved relative to its GLB position" % mesh_name, failures)
	_expect(carrier.get_node_or_null("SD_02_FlightControlCorridor") == null, "old interior geometry remains mounted", failures)
	_expect(carrier.get_node_or_null("InteriorSurfaceCollision") != null, "island walking collision is missing", failures)
	_expect(carrier.get_node_or_null("FlightDeckWalkingCollision") != null, "flight-deck walking collision is missing", failures)

	var doors: Array[Node] = []
	for child in carrier.get_children():
		if child.get_script() == DOOR_SCRIPT:
			doors.append(child)
	_expect(doors.size() == 2, "expected the two Land carrier 4 doors, found %d" % doors.size(), failures)
	for door_name in ["ExteriorDoorForward", "ExteriorDoorAft"]:
		var door := carrier.get_node_or_null(door_name) as Node3D
		_expect(door != null, "%s was not reconstructed" % door_name, failures)
		if door:
			_expect(door.get_child_count() >= 6, "%s is missing frame, leaves, or runtime collision" % door_name, failures)
			var left := door.get_node_or_null("CarrierSlidingDoor_LeftLeaf_001" if door_name == "ExteriorDoorForward" else "CarrierSlidingDoor_LeftLeaf_002")
			var right := door.get_node_or_null("CarrierSlidingDoor_RightLeaf_001" if door_name == "ExteriorDoorForward" else "CarrierSlidingDoor_RightLeaf_002")
			_expect(left != null and is_equal_approx(float(left.get_meta("open_offset_x_m", 0.0)), -0.615), "%s left leaf travel is invalid" % door_name, failures)
			_expect(right != null and is_equal_approx(float(right.get_meta("open_offset_x_m", 0.0)), 0.615), "%s right leaf travel is invalid" % door_name, failures)
			if left and right:
				var closed_left_x: float = left.position.x
				var closed_right_x: float = right.position.x
				door.set("openness", 1.0)
				door.call("_apply_pose")
				_expect(left.position.x < closed_left_x and right.position.x > closed_right_x, "%s leaves do not separate along the imported local door axis" % door_name, failures)

	carrier.free()
	source.free()
	if failures.is_empty():
		print("CARRIER_4_INTEGRATION_SMOKETEST_OK")
		quit(0)
		return
	for failure in failures:
		push_error("[Carrier4IntegrationSmoketest] %s" % failure)
	quit(1)


func _expect(condition: bool, message: String, failures: PackedStringArray) -> void:
	if not condition:
		failures.append(message)
