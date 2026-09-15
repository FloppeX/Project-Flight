extends SceneTree

var carrier: Node3D
var door: Node3D
var actor: CharacterBody3D
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func tick(point: Vector3, count: int = 1) -> void:
	for i in count:
		actor.global_position = door.to_global(point)
		await physics_frame
		await physics_frame
		await process_frame
		door._physics_process(0.05)

func run() -> void:
	carrier = Node3D.new()
	root.add_child(carrier)
	var model: Node3D = load("res://Models/LandCarrier/CarrierWithInterior.tscn").instantiate()
	carrier.add_child(model)
	for child in model.get_children():
		if child.get_script() == load("res://LandCarrier/CarrierSlidingDoor.gd"):
			child.set_physics_process(false)
			if door == null:
				door = child
	actor = CharacterBody3D.new()
	carrier.add_child(actor)
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.28
	capsule.height = 1.7
	shape.shape = capsule
	shape.position.y = 0.85
	actor.add_child(shape)
	await tick(Vector3(0, 0.05, 0.5), 12)
	check(door.openness == 0.0, "Stationary nearby person must not open door")
	await tick(Vector3(0.1, 0.05, 0.5))
	await tick(Vector3(0.2, 0.05, 0.5))
	check(door.openness == 0.0, "Walking parallel must not open door")
	await tick(Vector3(0.2, 0.05, 0.55))
	check(door.openness == 0.0, "Walking away must not open door")
	await tick(Vector3(0, 0.05, 0.9))
	await tick(Vector3(0, 0.05, 0.81))
	check(door.openness == 0.0, "Must remain closed beyond 80 cm")
	await tick(Vector3(0, 0.05, 0.79))
	check(door.openness > 0.0, "Approach inside 80 cm starts opening")
	await tick(Vector3(0, 0.05, 0.3), 8)
	check(door.openness > 0.99, "Fully opens within 0.4 seconds")
	for leaf in door._leaves:
		check(leaf.shape.disabled, "Open leaves clear their colliders")
	await tick(Vector3(0, 0.05, 0), 20)
	check(door.openness > 0.99, "Stopped person in threshold stays safe")
	await tick(Vector3(0, 0.05, -1.0), 19)
	check(door.openness == 0.0, "Closes behind person within 0.9 seconds")
	await tick(Vector3(0, 0.05, -0.81))
	check(door.openness == 0.0, "Reverse approach also respects 80 cm")
	await tick(Vector3(0, 0.05, -0.79))
	check(door.openness > 0.0, "Approach works from opposite side")
	await tick(Vector3(0, 0.05, -1), 20)
	await tick(Vector3(0, 0.05, -0.5))
	await tick(Vector3(0, 0.05, -1), 20)
	# Bring a stationary actor near without creating an approach sample.
	door._previous_positions.clear()
	await tick(Vector3(0, 0.05, 0.5), 2)
	for i in 12:
		carrier.position += Vector3(0.3, 0.02, -0.2)
		carrier.rotation.y += 0.03
		await tick(Vector3(0, 0.05, 0.5))
	check(door.openness == 0.0, "Moving and turning carrier cannot trigger stationary person")
	await tick(Vector3(0, 0.05, 0.4), 8)
	check(door.openness > 0.99, "Approach still works on transformed carrier")
	await tick(Vector3(0, 0.05, 1), 12)
	check(door.openness > 0.0 and door.openness < 1.0, "Closing begins after shortened delay")
	await tick(Vector3(0, 0.05, 0.2), 8)
	check(door.openness > 0.99, "Person entering threshold reverses closing")
	print("CARRIER_DOOR_APPROACH ", "PASS" if failures.is_empty() else str(failures))
	carrier.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
