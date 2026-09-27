extends SceneTree

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var host := Node3D.new()
	root.add_child(host)
	for scene_path in [
		"res://GroundVehicle/vehicle_friendly_light.tscn",
		"res://GroundVehicle/vehicle_enemy_pickup.tscn",
	]:
		var vehicle := (load(scene_path) as PackedScene).instantiate()
		host.add_child(vehicle)
		vehicle.global_position = Vector3.ZERO
		var target := Node3D.new()
		target.add_to_group("ground_vehicles")
		host.add_child(target)
		vehicle.set("current_target", target)
		var route_around_cliff := Vector3(300.0, 0.0, 0.0)
		_expect(
			bool(vehicle.call("_has_navigation_destination")),
			"%s did not treat a ground combat target as a navigation goal" % scene_path
		)

		target.global_position = Vector3(0.0, 0.0, 600.0)
		_expect(
			(vehicle.call("_select_steering_destination", route_around_cliff) as Vector3).is_equal_approx(route_around_cliff),
			"%s ignored its terrain route for a distant combat target" % scene_path
		)
		_expect(
			(vehicle.call("_apply_combat_mobility", route_around_cliff) as Vector3).is_equal_approx(route_around_cliff),
			"%s replaced its terrain route during combat" % scene_path
		)

		target.global_position = Vector3(0.0, 0.0, float(vehicle.get("combat_stop_distance_m")) - 1.0)
		_expect(
			(vehicle.call("_select_steering_destination", route_around_cliff) as Vector3).is_equal_approx(target.global_position),
			"%s did not face a nearby ground target at its firing stand-off" % scene_path
		)
		vehicle.queue_free()
		target.queue_free()
		await process_frame

	host.queue_free()
	await process_frame
	for failure in _failures:
		push_error(failure)
	print("GROUND_VEHICLE_CLIFF_ROUTING_%s" % ("PASS" if _failures.is_empty() else "FAIL"))
	quit(0 if _failures.is_empty() else 1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
