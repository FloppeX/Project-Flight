extends Node3D

var failures: Array[String] = []

func check(okay: bool, reason: String) -> void:
	if not okay:
		failures.append(reason)
		push_error(reason)

func _ready() -> void:
	run.call_deferred()

func run() -> void:
	for node in get_tree().root.get_children():
		if node != self:
			node.process_mode = Node.PROCESS_MODE_DISABLED
	var platoon := GroundVehiclePlatoon.new()
	platoon.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(platoon)
	var vehicles: Array[CharacterBody3D] = []
	var reverse_m: Array[float] = [0.0, 0.0, 0.0, 0.0]
	for index in 4:
		var vehicle := load("res://GroundVehicle/ground_vehicle_1.tscn").instantiate() as CharacterBody3D
		vehicle.disable_mode = CollisionObject3D.DISABLE_MODE_KEEP_ACTIVE
		vehicle.process_mode = Node.PROCESS_MODE_DISABLED
		vehicle.position = Vector3((index - 1.5) * 30.0, 2.0, 0.0)
		vehicle.rotation.y = float(index) * PI * 0.5
		vehicle.use_waypoint_pathfinding = false
		add_child(vehicle)
		vehicle.platoon = platoon
		platoon.register_vehicle(vehicle)
		vehicles.append(vehicle)
	await get_tree().physics_frame
	# Isolate horizontal navigation: real authored vehicle bodies/formation
	# orders and collision motion, without terrain or vertical suspension ticks.
	var goal := Vector3(0, 2, -600)
	platoon.set_move_objective(goal)
	for tick in 1400:
		for index in vehicles.size():
			var vehicle := vehicles[index]
			vehicle._refresh_drive_command(0.05)
			vehicle._apply_cached_drive_motion(0.05, true)
			reverse_m[index] += maxf(-vehicle.velocity.dot(vehicle.global_basis.z), 0.0) * 0.05
		if tick % 100 == 0:
			await get_tree().physics_frame
		if tick == 600:
			for vehicle in vehicles:
				check(vehicle.global_basis.z.dot(Vector3.FORWARD) > 0.75, "Explorer cruised facing away from the goal")
	for index in vehicles.size():
		var vehicle := vehicles[index]
		print("EXPLORER_TRAVEL index=", index, " position=", vehicle.position, " reverse_m=", reverse_m[index])
		check(vehicle.position.distance_to(goal) < 90.0, "Explorer %d did not reach platoon destination" % index)
		check(reverse_m[index] < 3.0, "Explorer %d traveled backwards" % index)
		vehicle.queue_free()
	platoon.queue_free()
	await get_tree().process_frame
	print("EXPLORER_FORWARD_TRAVEL_", "PASS" if failures.is_empty() else "FAIL", " ", failures)
	get_tree().quit(0 if failures.is_empty() else 1)
