extends SceneTree

var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func _run() -> void:
	# Keep the observer out of the tree so its scenario runner does not start.
	var observer := Node3D.new()
	observer.set_script(load("res://Scenario/LandingTestMode.gd"))
	var legacy := Node.new()
	_check(observer.call("_recovery_quality", {"stopped": false}) == "failed", "Failures stay failures")
	_check(observer.call("_recovery_quality", {"stopped": true}) == "stopped_damage_unknown", "Unknown damage is not a clean stop")
	_check(observer.call("_recovery_quality", {"stopped": true, "part_damage_observed": true, "part_health_loss": 0.0}) == "clean_stop", "Healthy stop is clean")
	_check(observer.call("_recovery_quality", {"stopped": true, "part_damage_observed": true, "part_health_loss": 10.0}) == "damaged_stop", "Surviving damage remains a successful stop with a cost")
	var missing: Dictionary = observer.call("_part_damage_snapshot", legacy)
	_check(not missing.part_damage_observed and missing.part_health_loss == -1.0,
		"Missing regional API must be unavailable, not healthy")
	legacy.free()
	missing = observer.call("_part_damage_snapshot", null)
	_check(not missing.part_damage_observed, "Freed or absent aircraft must be unavailable")
	for model in ["Aircraft_1", "Aircraft_2", "Aircraft_5"]:
		var packed := load("res://Aircraft/%s.tscn" % model) as PackedScene
		var craft := packed.instantiate() as RigidBody3D
		craft.freeze = true
		craft.position = Vector3(0, 1000, 0)
		root.add_child(craft)
		await process_frame
		await process_frame
		var initial_health := float(craft.get("current_health"))
		var initial_position := craft.global_position
		var before: Dictionary = observer.call("_part_damage_snapshot", craft)
		_check(before.part_damage_observed and is_zero_approx(before.part_health_loss),
			"%s must begin with observed healthy regions" % model)
		craft.set("_last_damage_ms", -100000)
		craft.call("take_damage", 10.0)
		var after: Dictionary = observer.call("_part_damage_snapshot", craft)
		_check(after.part_damage_observed and is_equal_approx(after.part_health_loss, 10.0),
			"%s must report regional loss despite unchanged aggregate health" % model)
		_check(is_equal_approx(float(craft.get("current_health")), initial_health),
			"%s regression must exercise independent regional health" % model)
		_check(craft.global_position == initial_position, "Telemetry must not move the aircraft")
		_check(is_zero_approx(before.part_health_loss), "Prior snapshots must remain independent")
		craft.queue_free()
		await process_frame
	observer.free()
	print("LANDING_DAMAGE_TELEMETRY_SMOKETEST %s models=3 regional_loss=10 legacy_health_unchanged=true" % [
		"PASS" if failures == 0 else "FAIL"])
	quit(0 if failures == 0 else 1)
