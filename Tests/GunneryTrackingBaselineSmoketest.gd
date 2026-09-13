extends Node

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var harness := preload("res://Scenario/GunneryTrackingBaseline.gd").new()
	var target := harness._create_lightweight_target()
	for i in 1000:
		target.take_damage(1000000.0)
	assert(target.current_health == target.max_health and target.damage_events == 1000)
	assert(harness.baseline_duration_s == 180.0)
	var scene := Node3D.new()
	add_child(scene)
	target.position = Vector3(0, 2000, 500)
	target.freeze = true
	scene.add_child(target)
	var craft := (load("res://Aircraft/Aircraft_5.tscn") as PackedScene).instantiate()
	craft.position = Vector3(0, 2000, 0)
	craft.freeze = true
	scene.add_child(craft)
	await get_tree().process_frame
	await get_tree().process_frame
	var pilot: AIPilot = craft.get_node("AIPilot")
	pilot.set_physics_process(false)
	var original := {}
	for property in pilot.get_property_list():
		var key := String(property.name)
		if key.begins_with("dogfight_"):
			original[key] = pilot.get(key)
	var guns: Array[Node] = []
	harness._collect_guns(craft, guns)
	assert(guns.size() > 0)
	var spread: float = guns[0].spread_angle
	var trial := {"pilot": pilot, "shooter": craft, "target": target}
	harness._apply_candidate(trial)
	harness._finalize_trial_setup(trial)
	for key in original:
		assert(pilot.get(key) == original[key], "Production setting changed: " + key)
	assert(guns[0].spread_angle == spread)
	assert(guns[0].ammo_count == 1000000)
	var offset := Vector3(4000, 0, -500)
	var path_trial := {"target_initial_pos": Vector3(100, 1000, 520),
		"circle_center": Vector3(-380, 1000, 520),
		"diagnostic_previous": {"target_position": Vector3(100, 1000, 600)}}
	harness._trials.append(path_trial)
	harness.apply_origin_shift(offset)
	assert(path_trial.target_initial_pos == Vector3(100, 1000, 520) - offset)
	assert(path_trial.circle_center == Vector3(-380, 1000, 520) - offset)
	assert(path_trial.diagnostic_previous.target_position == Vector3(100, 1000, 600) - offset)
	assert(path_trial.origin_shift_count == 1)
	harness._trials.clear()
	harness._configure_target(target)
	var motion_trial := {"target": target, "path": "straight", "target_velocity": Vector3(0, 0, 78),
		"target_initial_pos": Vector3(0, 2000, 500)}
	harness._update_target(motion_trial, 1.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert(target.linear_velocity.distance_to(Vector3(0, 0, 78)) < 0.1)
	target.global_position -= offset
	motion_trial.target_initial_pos -= offset
	harness._update_target(motion_trial, 1.0 + 1.0 / 60.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert(target.linear_velocity.distance_to(Vector3(0, 0, 78)) < 0.1, "Rebase contaminated scripted target velocity")
	print("GUNNERY_TRACKING_BASELINE_SMOKETEST PASS immortal_hits=1000 preserved_dogfight_settings=%d guns=%d spread=%.2f duration=180s" % [original.size(), guns.size(), spread])
	scene.free()
	harness.free()
	get_tree().quit()
