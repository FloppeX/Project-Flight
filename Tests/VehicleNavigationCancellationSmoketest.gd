extends SceneTree

var failures: Array[String] = []

func _initialize() -> void: run.call_deferred()

func run() -> void:
	await process_frame
	for node in root.get_children(): node.process_mode = Node.PROCESS_MODE_DISABLED
	var scheduler: Node = root.get_node("NavPathScheduler")
	for phase in ["live", "detached", "queued"]:
		var world := Node3D.new()
		root.add_child(world)
		var platoon: Node3D = load("res://GroundVehicle/ground_vehicle_platoon.gd").new()
		world.add_child(platoon)
		platoon.set_physics_process(false)
		var vehicle: CharacterBody3D = load("res://Tests/Fixtures/NavigationCancellationVehicle.gd").new()
		world.add_child(vehicle)
		vehicle.assign_platoon(platoon)
		platoon.objective_type = platoon.ObjectiveType.ATTACK_NODE
		var target := Node3D.new()
		world.add_child(target)
		target.position = Vector3(100, 0, 0)
		platoon.attack_node = target
		var goal: Vector3 = vehicle._get_raw_navigation_destination()
		var path: Array[Vector3] = [goal * 0.5, goal]
		vehicle._is_pathfinding = true
		vehicle._nav_path_goal = Vector3.INF
		if phase == "detached": root.remove_child(world)
		if phase == "queued": vehicle.queue_free()
		scheduler._deliver_job({"callback": vehicle._on_navigation_path_job_result, "guard_coordinates": false}, {
			"best_path": path, "target": goal, "status_code": 0,
			"no_anchor_cooldown": 1.0, "path_cooldown": 1.0})
		if phase == "live":
			if vehicle._nav_path_goal != goal: failures.append("live navigation result was not installed")
		else:
			if vehicle._nav_path_goal != Vector3.INF: failures.append(phase + " navigation result was installed")
			vehicle._on_navigation_path_computed(path, goal, 0, 1.0, 1.0)
			if vehicle._nav_path_goal != Vector3.INF: failures.append(phase + " direct result was installed")
		if phase == "detached":
			if platoon._find_nearest_hostile(Vector3.ZERO, 1000.0) != null: failures.append("detached platoon searched enemies")
			if platoon._find_shared_hostile("attack", goal, 1000.0) != null: failures.append("detached platoon returned cached enemies")
		if vehicle._is_pathfinding: failures.append(phase + " left navigation pending")
		if phase == "live":
			world.remove_child(platoon)
			if vehicle._get_raw_navigation_destination() != vehicle.global_position: failures.append("live vehicle consulted detached platoon")
			platoon.free()
		world.free()
	print("VEHICLE_NAVIGATION_CANCELLATION_%s failures=%s" % ["PASS" if failures.is_empty() else "FAIL", failures])
	quit(0 if failures.is_empty() else 1)
