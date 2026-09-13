extends SceneTree
var failures: Array[String] = []
var carrier: Node3D
var model: Node3D

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func ticks(count: int) -> void:
	for i in count:
		await physics_frame

func character_at(point: Vector3) -> CharacterBody3D:
	var character := CharacterBody3D.new()
	carrier.add_child(character)
	character.global_position = point
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.28
	capsule.height = 1.7
	shape.shape = capsule
	shape.position.y = 0.85
	character.add_child(shape)
	return character

func run() -> void:
	carrier = Node3D.new()
	root.add_child(carrier)
	model = load("res://Models/LandCarrier/CarrierWithInterior.tscn").instantiate()
	model.rotation.y = PI
	carrier.add_child(model)
	var doors: Array[Node3D] = []
	for child in model.get_children():
		if child.get_script() == load("res://LandCarrier/CarrierSlidingDoor.gd"):
			doors.append(child)
	check(doors.size() == 16, "Expected 16 doors")
	await ticks(3)
	var characters: Array[CharacterBody3D] = []
	for door in doors:
		check(door.openness == 0.0, "Initially closed: " + door.name)
		characters.append(character_at(door.to_global(Vector3(0, 0.05, 1.3))))
	await ticks(55)
	for door in doors:
		check(door.openness > 0.99, "Approach opens: " + door.name)
		for leaf in door._leaves:
			check(leaf.shape.disabled, "Open collider cleared: " + door.name)
	# Keep the model translated and rotated during occupancy.
	carrier.position = Vector3(125, 40, -85)
	carrier.rotation.y = 0.7
	await ticks(12)
	for door in doors:
		check(door.occupied, "Moving-carrier sensor: " + door.name)
	var extra := character_at(doors[0].to_global(Vector3(0, 0.05, -1.3)))
	for actor in characters:
		actor.queue_free()
	await ticks(130)
	check(doors[0].openness > 0.99, "Second occupant keeps door open")
	for i in range(1, doors.size()):
		check(doors[i].openness < 0.01, "Closes after exit: " + doors[i].name)
	extra.queue_free()
	await ticks(90)
	check(doors[0].openness < 1.0 and doors[0].openness > 0.0, "Closing transition started")
	extra = character_at(doors[0].to_global(Vector3(0, 0.05, 0)))
	await ticks(45)
	check(doors[0].openness > 0.99, "Re-entry reverses closing")
	extra.queue_free()
	carrier.transform = Transform3D.IDENTITY
	# Hold doors open while testing the connected stair route.
	for door in doors:
		door.set_physics_process(false)
		door.openness = 1.0
		door._apply_pose()
	await ticks(3)
	var walking = load("res://LandCarrier/CarrierInteriorWalking.gd").new(carrier)
	for door in doors:
		var approach := 0.32 if door.name == "SD_01_PortExit" else 0.55
		var start := carrier.to_local(door.to_global(Vector3(0, 0, approach)))
		var end := carrier.to_local(door.to_global(Vector3(0, 0, -0.55)))
		var result: Vector3 = walking.constrain(start, end)
		check(result.distance_to(end) < 0.1, "Walk through open door %s: %s expected %s" % [door.name, result, end])
	var points := [Vector3(20.42, -3.65, 0.04), Vector3(20.42, -7.8, 2.41),
		Vector3(19.32, -7.8, 2.41), Vector3(19.32, -3.55, 4.78),
		Vector3(19.32, -2.8, 4.78), Vector3(20.42, -2.8, 4.78), Vector3(20.42, -8.6, 7.765),
		Vector3(19.32, -8.6, 7.765), Vector3(19.32, -3.9, 7.765),
		Vector3(19.32, -1.5, 8.853), Vector3(21.6, -1.5, 8.853)]
	var position := from_blender(points[0])
	for i in range(1, points.size()):
		var target := from_blender(points[i])
		for step in 180:
			var direction := Vector3(target.x - position.x, 0, target.z - position.z)
			if direction.length() < 0.025:
				break
			position = walking.constrain(position, position + direction.limit_length(0.05))
		check(position.distance_to(target) < 0.13, "Stair waypoint %d reached %s expected %s" % [i, position, target])
		if position.distance_to(target) > 0.13:
			break
	points.reverse()
	for i in range(1, points.size()):
		var target := from_blender(points[i])
		for step in 180:
			var direction := Vector3(target.x - position.x, 0, target.z - position.z)
			if direction.length() < 0.025:
				break
			position = walking.constrain(position, position + direction.limit_length(0.05))
		check(position.distance_to(target) < 0.25, "Stair descent waypoint %d reached %s expected %s" % [i, position, target])
		if position.distance_to(target) > 0.25:
			break
	print("CARRIER_INTERIOR_SMOKE ", "PASS" if failures.is_empty() else failures)
	carrier.queue_free()
	await ticks(2)
	quit(0 if failures.is_empty() else 1)

func from_blender(blender: Vector3) -> Vector3:
	return Vector3(-blender.x, blender.z, blender.y)
