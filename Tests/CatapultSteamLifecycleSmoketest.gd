extends SceneTree

class Controller extends Node3D:
	var launch_steam_enabled := true
	var _launching := false
	var _latched := true
	var _aircraft: RigidBody3D
	var shuttle: Node3D

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var failures: Array[String] = []
	for cycle in 3:
		var controller := Controller.new()
		root.add_child(controller)
		controller.shuttle = Node3D.new()
		controller.add_child(controller.shuttle)
		controller._aircraft = RigidBody3D.new()
		controller._aircraft.freeze = true
		controller.add_child(controller._aircraft)
		var steam := preload("res://Effects/CatapultSteam.gd").new()
		controller.add_child(steam)
		await physics_frame
		if steam.emitting: failures.append("idle must not emit")
		controller._launching = true
		for frame in 60:
			controller.shuttle.position.z += 0.8
			await physics_frame
		if not steam.emitting: failures.append("launch must emit")
		controller._launching = false
		await physics_frame
		await physics_frame
		if steam.emitting: failures.append("abort or release must stop emission")
		steam.apply_origin_shift(Vector3(1000, 0, 0))
		if steam.emitting: failures.append("origin reset must preserve stopped emission")
		controller.queue_free()
		for frame in 5: await process_frame
	for failure in failures: push_error(failure)
	print("CATAPULT_STEAM_LIFECYCLE_%s" % ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)
