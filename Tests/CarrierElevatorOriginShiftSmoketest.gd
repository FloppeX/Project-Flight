extends SceneTree

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world
	var carrier := Node3D.new()
	carrier.position = Vector3(-980, 522, 5253)
	world.add_child(carrier)
	var elevator: Node3D = load("res://LandCarrier/CarrierElevator.gd").new()
	carrier.add_child(elevator)
	root.get_node("FloatingOrigin").enabled = false
	for frame in 3: await physics_frame
	# Shift then retrieve in the same frame: top-level platform bodies must not
	# keep the old frame when the new aircraft's tie-down anchors are calculated.
	root.get_node("FloatingOrigin").shift_origin(Vector3(-980, 0, 5253))
	var body := RigidBody3D.new()
	body.mass = 1200
	body.gravity_scale = 0
	body.collision_layer = 0
	body.collision_mask = 0
	world.add_child(body)
	var expected := carrier.global_position + Vector3(0, -8, 0)
	body.global_position = expected
	PhysicsServer3D.body_set_state(body.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, body.global_transform)
	elevator.create_platform_restraint(body)
	for frame in 30: await physics_frame
	var error := body.global_position.distance_to(expected)
	print("ELEVATOR_ORIGIN_RESTRAINT_%s error_m=%.3f actual=%s expected=%s" % ["PASS" if error < 0.5 else "FAIL", error, body.global_position, expected])
	var second_shift := Vector3(8000, 0, -4000)
	root.get_node("FloatingOrigin").shift_origin(second_shift)
	expected -= second_shift
	for frame in 30: await physics_frame
	var attached_error := body.global_position.distance_to(expected)
	print("ELEVATOR_ATTACHED_SHIFT_%s error_m=%.3f" % ["PASS" if attached_error < 0.5 else "FAIL", attached_error])
	quit(0 if error < 0.5 and attached_error < 0.5 else 1)
