extends SceneTree

const DOOR_SCRIPT := preload("res://LandCarrier/CarrierSlidingDoor.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var carrier := (load("res://LandCarrier/LandCarrier2.tscn") as PackedScene).instantiate() as Node3D
	carrier.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(carrier)
	current_scene = carrier
	carrier.process_mode = Node.PROCESS_MODE_INHERIT
	await physics_frame
	await physics_frame
	await process_frame

	var model := carrier.get_node("CarrierModel") as Node3D
	var commander := carrier.get_node("Commander") as CharacterBody3D
	var camera := commander.get_node("Camera3D") as Camera3D
	var walk := carrier.get_node("CommanderWalkArea")
	commander.set_physics_process(false)
	walk.set_physics_process(false)
	assert(camera.current, "Walking camera is not active")

	for door_name in ["ExteriorDoorForward", "ExteriorDoorAft"]:
		var door := model.get_node_or_null(door_name) as Node3D
		assert(door != null and door.get_script() == DOOR_SCRIPT, "%s was not reconstructed from Land carrier 4" % door_name)
		var aperture: Vector3 = door.get_aperture_center_local()
		var threshold := Vector3(aperture.x, door._aperture_base_y, aperture.z)
		var near_point := threshold + Vector3(0.0, 0.0, 0.8)
		var approach_point := carrier.to_local(door.to_global(threshold + Vector3(0.0, 0.0, 1.8)))
		var walk_target := carrier.to_local(door.to_global(near_point))
		var walked := approach_point
		for i in 40:
			walked = walk.constrain_commander_position(walked, walked.move_toward(walk_target, 0.05))
		assert(walked.distance_to(walk_target) < 0.03, "%s cannot be approached through the authored floor" % door_name)

		commander.global_position = door.to_global(near_point)
		var target := door.to_global(threshold)
		commander.look_at(Vector3(target.x, commander.global_position.y, target.z), Vector3.UP)
		for i in 24:
			await physics_frame
		assert(door._sensor.get_overlapping_bodies().has(commander), "%s sensor does not detect the commander" % door_name)
		assert(door.openness < 0.001, "%s opened while the player view faced away" % door_name)
		commander.rotate_y(PI)
		for i in 30:
			await physics_frame
		assert(door.openness > 0.99, "%s did not open while the player viewed it" % door_name)
		for leaf in door._leaves:
			assert(leaf.shape.disabled, "%s open leaf still blocks passage" % door_name)
		commander.global_position = door.to_global(threshold + Vector3(0.0, 0.0, 2.0))
		for i in 30:
			await physics_frame
	print("CARRIER_DOOR_COMMANDER_FACING PASS")
	quit(0)
