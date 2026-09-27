extends SceneTree
## Focused geometry check for the current two-door Land carrier 4 island.

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var carrier := load("res://Models/LandCarrier/CarrierWithInterior.tscn").instantiate() as Node3D
	root.add_child(carrier)
	await physics_frame
	await physics_frame
	await process_frame
	var doors: Array[Node] = []
	for child in carrier.get_children():
		if child.get_script() == load("res://LandCarrier/CarrierSlidingDoor.gd"):
			doors.append(child)
	assert(doors.size() == 2, "Expected the two Land carrier 4 sliding doors")
	var lower := carrier.get_node("superstructure floor lower") as MeshInstance3D
	var upper := carrier.get_node("superstructure floor upper") as MeshInstance3D
	var elevator := carrier.get_node("Superstructure elevator") as MeshInstance3D
	var lower_top := (lower.transform * lower.get_aabb()).end.y
	var upper_top := (upper.transform * upper.get_aabb()).end.y
	var elevator_top := (elevator.transform * elevator.get_aabb()).end.y
	assert(absf(lower_top - 8.863) < 0.03, "Lower island floor moved")
	assert(absf(upper_top - 13.344) < 0.03, "Upper island floor moved")
	assert(absf(lower_top - elevator_top) < 0.03, "Island elevator no longer meets the lower floor")
	assert(carrier.get_node_or_null("InteriorSurfaceCollision") != null, "Island walking collision missing")
	assert(carrier.get_node_or_null("FlightDeckWalkingCollision") != null, "Flight-deck walking collision missing")
	print("CARRIER_INTERIOR_SMOKE PASS doors=2 lower=%.3f upper=%.3f" % [lower_top, upper_top])
	carrier.queue_free()
	await process_frame
	quit()