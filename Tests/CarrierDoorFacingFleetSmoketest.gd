extends SceneTree

var failures: Array[String] = []
var carrier: Node3D
var actor: CharacterBody3D

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func wait_for_overlap() -> void:
	await physics_frame
	await physics_frame
	await process_frame

func place_at_door(door: Node3D, distance: float, facing: bool) -> void:
	var center: Vector3 = door.get_aperture_center_local()
	var local_point := Vector3(center.x, 0.05, center.z + distance)
	actor.global_position = door.to_global(local_point)
	var target := door.to_global(Vector3(center.x, 0.05, center.z))
	target.y = actor.global_position.y
	var direction := (target - actor.global_position).normalized()
	actor.look_at(actor.global_position + direction * (1.0 if facing else -1.0), Vector3.UP)
	await wait_for_overlap()

func run() -> void:
	carrier = Node3D.new()
	root.add_child(carrier)
	var model := load("res://Models/LandCarrier/CarrierWithInterior.tscn").instantiate() as Node3D
	model.rotation.y = PI
	carrier.add_child(model)
	await process_frame
	await process_frame
	await process_frame
	var doors: Array[Node3D] = []
	for child in model.get_children():
		if child.get_script() == load("res://LandCarrier/CarrierSlidingDoor.gd"):
			child.set_physics_process(false)
			doors.append(child)
	check(doors.size() == 2, "Expected the two Land carrier 4 doors")
	actor = CharacterBody3D.new()
	carrier.add_child(actor)
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.28
	capsule.height = 1.7
	shape.shape = capsule
	shape.position.y = 0.85
	actor.add_child(shape)
	for door in doors:
		await place_at_door(door, 0.9, false)
		door._physics_process(0.05)
		check(door.openness == 0.0, "%s opened for a person looking away" % door.name)
		await place_at_door(door, 1.0, true)
		for step in 8:
			door._physics_process(0.05)
		check(door.openness > 0.99, "%s did not open for a facing person at one metre" % door.name)
		for leaf in door._leaves:
			check(leaf.shape.disabled, "%s retained a leaf collider while open" % door.name)
		await place_at_door(door, 0.2, false)
		door._physics_process(0.05)
		check(door.openness > 0.99, "%s closed at the 20 cm hold boundary" % door.name)
		await place_at_door(door, 0.21, false)
		for step in 8:
			door._physics_process(0.05)
		check(door.openness == 0.0, "%s stayed open beyond 20 cm while person looked away" % door.name)
		actor.global_position = Vector3(10000.0, 10000.0, 10000.0)
		await wait_for_overlap()
	print("CARRIER_DOOR_FACING_FLEET ", "PASS doors=2" if failures.is_empty() else failures)
	carrier.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
