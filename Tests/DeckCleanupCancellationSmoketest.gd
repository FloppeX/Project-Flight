extends SceneTree

class ElevatorStub extends Node3D:
	var shaft_depth := 10.0
	var platform_size := Vector3.ONE
	var platform_y := 0.0
	var down_calls := 0
	func move_platform_down() -> void: down_calls += 1
	func get_platform_local_y() -> float: return platform_y

var failures: Array[String] = []
var finished := false
func _initialize() -> void: run.call_deferred()

func cleanup(manager: Node, job: Dictionary) -> void:
	await manager._cleanup_parallel_launch_lane(job)
	finished = true

func run() -> void:
	await process_frame
	for node in root.get_children(): node.process_mode = Node.PROCESS_MODE_DISABLED
	for phase in ["descent", "tractor_move", "complete"]:
		var carrier := Node3D.new()
		root.add_child(carrier)
		var manager: Node = load("res://Tests/Fixtures/DeckTowSuspensionFixture.gd").new()
		carrier.add_child(manager)
		var elevator := ElevatorStub.new()
		carrier.add_child(elevator)
		var bots: Array[Node3D] = []
		if phase == "tractor_move":
			var bot := Node3D.new()
			carrier.add_child(bot)
			bots.append(bot)
			manager._tractor_home_transforms_local[bot.get_instance_id()] = Transform3D(Basis.IDENTITY, Vector3(100, 0, 0))
		var job := {"elevator": elevator, "tractors": bots, "lane_id": 0}
		finished = false
		cleanup(manager, job)
		await physics_frame
		if phase != "complete":
			# Reload removes old nodes before freeing them: validity alone is insufficient.
			root.remove_child(carrier)
		else:
			elevator.platform_y = -elevator.shaft_depth
		for frame in 3: await physics_frame
		if not finished: failures.append(phase + " task did not return cleanly")
		if phase == "complete":
			if not job.get("cleanup_complete", false): failures.append("normal cleanup never completed")
		else:
			if job.get("cleanup_complete", false): failures.append("cancelled cleanup marked successful")
			if phase == "tractor_move" and elevator.down_calls != 0: failures.append("cancelled movement advanced elevator")
		carrier.free()
	var platoon: Node3D = load("res://GroundVehicle/ground_vehicle_platoon.gd").new()
	root.add_child(platoon)
	platoon.set_physics_process(false)
	platoon._global_route_preview_jobs = 2
	platoon._is_route_preview_pathfinding = true
	root.remove_child(platoon)
	platoon._on_route_preview_job_result({"preview_pts": [], "status_code": 1})
	if platoon._global_route_preview_jobs != 1: failures.append("late route callback double-released shared budget")
	if platoon._is_route_preview_pathfinding: failures.append("removed platoon retained pending route state")
	platoon._global_route_preview_jobs = 0
	platoon.free()
	print("DECK_CLEANUP_CANCELLATION_%s failures=%s" % ["PASS" if failures.is_empty() else "FAIL", failures])
	quit(0 if failures.is_empty() else 1)
