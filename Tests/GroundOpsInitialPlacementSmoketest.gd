extends SceneTree


class PlacementCarrier:
	extends Node3D

	var placement_complete: bool = false

	func is_initial_placement_complete() -> bool:
		return placement_complete


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var manager: Node = root.get_node("GroundOpsManager")
	if bool(manager.get("maintain_carrier_escort")):
		_fail("normal play still enables automatic startup escort deployment")
		return

	var scene := Node3D.new()
	scene.name = "GroundOpsInitialPlacementSmoketest"
	root.add_child(scene)
	current_scene = scene
	var carrier := PlacementCarrier.new()
	carrier.add_to_group("carrier")
	scene.add_child(carrier)

	# Inject a valid idle bay so the only reason the queued deployment remains
	# pending is the production carrier-placement gate.
	var bay_script := load("res://LandCarrier/VehicleBayManager.gd") as Script
	var bay: Node = bay_script.new()
	manager.set("_carrier", carrier)
	manager.set("_vehicle_bay", bay)
	manager.set("_deploy_queue", [])
	manager.set("_deploying_platoon_name", "")
	manager.call("deploy", "Ember")
	var queued_before: Array = manager.get("_deploy_queue")
	if queued_before.size() != 1:
		_fail("test could not queue Ember deployment")
		return
	var ready_before: bool = bool(manager.call("_is_carrier_initial_placement_ready"))
	manager.call("_process_deploy_queue")
	var waiting_queue: Array = manager.get("_deploy_queue")
	if waiting_queue.size() != 1 or String(waiting_queue[0]) != "Ember":
		_fail("deployment queue advanced before carrier placement completed (ready=%s queue=%s has_method=%s)" % [
			str(ready_before),
			str(waiting_queue),
			str(carrier.has_method("is_initial_placement_complete")),
		])
		return

	carrier.placement_complete = true
	if not bool(manager.call("_is_carrier_initial_placement_ready")):
		_fail("carrier placement gate did not open after completion")
		return
	bay.free()

	print("[GroundOpsInitialPlacementSmoketest] PASS")
	quit(0)


func _fail(reason: String) -> void:
	push_error("[GroundOpsInitialPlacementSmoketest] FAIL %s" % reason)
	quit(1)
