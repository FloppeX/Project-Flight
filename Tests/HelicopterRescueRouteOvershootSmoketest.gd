extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var ai := Node.new()
	root.add_child(ai)
	ai.set_script(load("res://AI/HelicopterPilot.gd") as Script)
	var previous := Vector3(-2559.0, 814.0, -1441.0)
	var final := Vector3(-2519.0, 828.0, -1401.0)
	var survivor := Vector3(-2501.0, 783.0, -1389.0)
	var overshot := Vector3(2210.0, 828.0, 2667.0)
	var path: Array[Vector3] = [previous, final]
	ai.set("_heightmap_path", path)
	ai.set("_heightmap_path_index", 1)

	if not bool(ai.call("_has_overshot_final_heightmap_waypoint", overshot, survivor)):
		_fail("did not recognize the live rescue route's terminal overrun")
		return
	if bool(ai.call("_has_overshot_final_heightmap_waypoint", previous, survivor)):
		_fail("replanned before reaching the final waypoint")
		return

	var route_dir := Vector3(final.x - previous.x, 0.0, final.z - previous.z).normalized()
	var goal_dir := Vector3(final.x - overshot.x, 0.0, final.z - overshot.z).normalized()
	if float(ai.call("_get_path_follow_blend", goal_dir, route_dir)) > 0.001:
		_fail("outbound final-segment tangent still overrides the rescue waypoint")
		return
	if float(ai.call("_get_path_follow_blend", route_dir, route_dir)) < 0.5:
		_fail("aligned route following lost its intended guidance")
		return

	print("HELICOPTER_RESCUE_ROUTE_OVERSHOOT_PASS")
	quit(0)


func _fail(reason: String) -> void:
	push_error("HELICOPTER_RESCUE_ROUTE_OVERSHOOT_FAIL %s" % reason)
	quit(1)
