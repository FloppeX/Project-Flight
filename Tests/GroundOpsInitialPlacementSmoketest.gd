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
	manager.set_process(false)
	if not bool(manager.get("maintain_carrier_escort")):
		_fail("normal play does not enable automatic startup escort deployment")
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
	(manager.get("_deploy_queue") as Array).clear()
	manager.set("_deploying_platoon_name", "")
	manager.call("_process", 5.0)
	if not (manager.get("_deploy_queue") as Array).is_empty():
		_fail("automatic escort queued before carrier placement completed")
		return
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
	(manager.get("_deploy_queue") as Array).clear()
	# A player hold must survive automatic startup escort selection.
	manager.call("order_hold", "Ember")
	manager.call("_process", 5.0)
	var escort_queue: Array = manager.get("_deploy_queue")
	var escort: Node = manager.call("get_platoon", "Ferret")
	var platoon_script: Script = load("res://GroundVehicle/ground_vehicle_platoon.gd")
	if escort_queue.size() != 1 or escort_queue[0] != "Ferret" \
			or escort.objective_type != platoon_script.ObjectiveType.ESCORT_CARRIER \
			or escort.escort_node != carrier \
			or str(escort.get_meta("ops_order_source", "")) != "automatic":
		_fail("startup did not queue an automatic escort while respecting the player hold")
		return
	manager.call("_ensure_carrier_escort")
	if (manager.get("_deploy_queue") as Array).size() != 1:
		_fail("pending escort caused a duplicate deployment")
		return
	bay.free()

	print("[GroundOpsInitialPlacementSmoketest] PASS")
	quit(0)


func _fail(reason: String) -> void:
	push_error("[GroundOpsInitialPlacementSmoketest] FAIL %s" % reason)
	quit(1)
