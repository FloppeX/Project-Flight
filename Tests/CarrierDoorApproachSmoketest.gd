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

func tick(point: Vector3, count: int = 1, facing := true) -> void:
	for i in count:
		actor.global_position = door.to_global(point)
		var doorway := door.to_global(Vector3(clampf(point.x, -0.5, 0.5), point.y, 0.0))
		var direction := doorway - actor.global_position
		direction.y = 0.0
		if direction.length_squared() > 0.000001:
			var target := actor.global_position + direction.normalized() * (1.0 if facing else -1.0)
			actor.look_at(target, Vector3.UP)
		await physics_frame
		await physics_frame
		await process_frame
		door._physics_process(0.05)

func run() -> void:
	carrier = Node3D.new()
	root.add_child(carrier)
	var model: Node3D = load("res://Models/LandCarrier/CarrierWithInterior.tscn").instantiate()
	carrier.add_child(model)
	await physics_frame
	await physics_frame
	await process_frame
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
	await tick(Vector3(0, 0.05, 0.9), 4, false)
	check(door.openness == 0.0, "Nearby person looking away must not open door")
	await tick(Vector3(0, 0.05, 1.21), 2, true)
	check(door.openness == 0.0, "Facing person beyond 1.2 metres must not open door")
	await tick(Vector3(0, 0.05, 1.2), 1, true)
	check(door.openness > 0.0, "Stationary facing person at 1.2 metres starts opening")
	await tick(Vector3(0, 0.05, 0.8), 8, true)
	check(door.openness > 0.99, "Fully opens within 0.4 seconds")
	for leaf in door._leaves:
		check(leaf.shape.disabled, "Open leaves clear their colliders")
	await tick(Vector3(0, 0.05, 0.2), 3, false)
	check(door.openness > 0.99, "Person at 20 cm holds an open door while looking away")
	await tick(Vector3(0, 0.05, 0.21), 3, true)
	check(door.openness > 0.99, "Facing person beyond 20 cm holds an open door")
	await tick(Vector3(0, 0.05, 0.21), 1, false)
	check(door.openness < 1.0, "Open door begins closing beyond 20 cm when person looks away")
	await tick(Vector3(0, 0.05, 0.8), 8, false)
	check(door.openness == 0.0, "Door finishes closing while person remains away-facing")
	await tick(Vector3(0, 0.05, -1.0), 1, true)
	check(door.openness > 0.0, "Facing trigger works from the reverse side")
	await tick(Vector3(0, 0.05, -0.8), 8, true)
	check(door.openness > 0.99, "Reverse-side facing person fully opens door")
	await tick(Vector3(0, 0.05, -0.8), 8, false)
	check(door.openness == 0.0, "Reverse-side away-facing person lets door close")
	for i in 12:
		carrier.position += Vector3(0.3, 0.02, -0.2)
		carrier.rotation.y += 0.03
		await tick(Vector3(0, 0.05, 0.8), 1, false)
	check(door.openness == 0.0, "Moving and turning carrier does not bypass facing requirement")
	await tick(Vector3(0, 0.05, 0.8), 8, true)
	check(door.openness > 0.99, "Facing trigger works on transformed carrier")
	await tick(Vector3(0, 0.05, 0.19), 2, false)
	check(door.openness > 0.99, "Transformed door retains 20 cm hold-open distance")
	print("CARRIER_DOOR_APPROACH ", "PASS" if failures.is_empty() else str(failures))
	carrier.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
