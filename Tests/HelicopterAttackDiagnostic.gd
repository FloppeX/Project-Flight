extends SceneTree

## Real aircraft/controllers/weapons; durable target, flat collidable terrain and
## a baked navigation grid. Intentionally NOT combat-hunt mode (it bypasses routes).
class Target extends StaticBody3D:
	var team := 2
	var linear_velocity := Vector3.ZERO
	var current_health := 1000.0
	var damage_total := 0.0
	func get_team() -> int: return team
	func take_damage(amount: float) -> void: damage_total += amount

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var model := 10
	var label := "baseline"
	var duration := 120.0
	var popup_terrain := false
	var air_target := false
	var rescue := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--model="): model = int(arg.get_slice("=", 1))
		elif arg.begins_with("--label="): label = arg.get_slice("=", 1)
		elif arg.begins_with("--duration="): duration = float(arg.get_slice("=", 1))
		elif arg == "--popup-terrain": popup_terrain = true
		elif arg == "--air-target": air_target = true
		elif arg == "--rescue": rescue = true
	assert(model in [9, 10, 11, 13])
	seed(20260911)
	for autoload_name in ["FlightDirector", "AirOpsManager", "EnemyOpsManager", "GroundOpsManager", "OperationsCoordinator", "NavGraph", "FloatingOrigin"]:
		var manager := root.get_node_or_null(autoload_name)
		if manager != null: manager.process_mode = Node.PROCESS_MODE_DISABLED
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var grid := root.get_node("TerrainNavGrid")
	grid.set_process(false)
	var heights := PackedFloat32Array()
	heights.resize(401 * 401)
	heights.fill(0.0)
	if popup_terrain:
		for z in range(401):
			for x in range(401):
				if absf(-8000.0 + x * 40) <= 800 and absf(-8000.0 + z * 40 + 520) <= 40:
					heights[z * 401 + x] = 110.0
	for prefix in ["", "_query"]:
		grid.set(prefix + "_cols", 401)
		grid.set(prefix + "_rows", 401)
		grid.set(prefix + "_origin_x", -8000.0)
		grid.set(prefix + "_origin_z", -8000.0)
		grid.set(prefix + "_heights", heights)
	grid.set("cell_size_m", 40.0)
	grid.set("query_cell_size_m", 40.0)
	grid.call("_begin_query_analysis")
	while int(grid.get("_query_analysis_gz")) < 401:
		grid.call("_analyze_query_rows")
	grid.set("_h_min_passable", 0.0)
	grid.set("_is_baked", true)
	grid.set("_query_is_baked", true)
	var ground := StaticBody3D.new()
	_add_box(ground, Vector3(16000, 50, 16000))
	ground.position.y = -25
	scene.add_child(ground)
	if popup_terrain:
		var ridge := StaticBody3D.new()
		_add_box(ridge, Vector3(1600, 110, 80))
		ridge.position = Vector3(0, 55, -520)
		scene.add_child(ridge)
	var target := Target.new()
	target.name = "DurableTarget"
	_add_box(target, Vector3(12, 8, 12))
	target.position.y = 4
	scene.add_child(target)
	target.add_to_group("ground_vehicles")
	if model == 13:
		target.team = 1
		target.add_to_group("carrier")
	if air_target:
		target.remove_from_group("ground_vehicles")
		target.remove_from_group("carrier")
		target.add_to_group("ai_aircraft")
		target.set_meta("is_helicopter", true)
		target.position.y = 140.0
		target.linear_velocity = Vector3(6, 0, 0)
		if rescue: target.rotation.y = PI
	var path := "res://Aircraft/Aircraft_%d.tscn" % model
	var craft := (load(path) as PackedScene).instantiate() as RigidBody3D
	craft.freeze = true
	craft.position = Vector3(300, 80, -2200)
	scene.add_child(craft)
	craft.set("team", 1)
	craft.linear_velocity = Vector3(0, 0, 35)
	await process_frame
	if model == 13:
		var section = load("res://Enemies/EnemyOutpostHelicopterFlight.gd").new()
		scene.add_child(section)
		section.home_position = Vector3.ZERO
		section.heading = Vector3.BACK
		section._patrol_waypoints.assign([Vector3(0, 140, 2000), Vector3(2000, 140, 0), Vector3(0, 140, -2000)])
		section._configure_materialized_enemy_aircraft(craft, "rockets", 0)
	else:
		craft.get_node("AIToggle").call("enable_ai")
	var pilot: Node = craft.get_node("HelicopterPilot")
	pilot.set("crash_log_enabled", false)
	pilot.set("combat_report_enabled", false)
	pilot.set("combat_tuning_enabled", false)
	# Airborne starts require a running engine, not a cold-start drop test.
	var engine: Node = pilot.get("engine")
	var trim := float(pilot.call("_get_collective_trim"))
	if model != 13:
		engine.set("is_engine_working", true)
		engine.set("current_power", trim)
		engine.set("target_power", trim)
		pilot.set("_collective_cmd", trim)
		(pilot.get("control_engine") as Node).call("set_target_power", trim)
	craft.position = Vector3(300, 140 if model == 13 else 80, -2200)
	craft.linear_velocity = Vector3(0, 0, 30 if model == 13 else 35)
	craft.angular_velocity = Vector3.ZERO
	if popup_terrain:
		craft.position = Vector3(0, 80, -680)
		craft.linear_velocity = Vector3.ZERO
	craft.set_meta("parking_brake", false)
	craft.freeze = false
	pilot.call("change_state", 2)
	if model != 13:
		pilot.call("command_attack_target", target)
	if rescue:
		var survivor := Node3D.new()
		scene.add_child(survivor)
		survivor.position = Vector3(0, 0, 2500)
		craft.position = Vector3(0, 140, -800)
		pilot.call("command_rescue", survivor)
	var result := {"model": model, "label": label, "status": "RUNNING", "duration_s": duration,
		"popup_terrain": popup_terrain, "popup_sha256": FileAccess.get_sha256("res://AI/HelicopterPopup.gd"),
		"hunt_mode": pilot.get("_combat_hunt_mode"), "pathfinding": pilot.get("use_heightmap_pathfinding"),
		"pilot_sha256": FileAccess.get_sha256("res://AI/HelicopterPilot.gd"),
		"escape_sha256": FileAccess.get_sha256("res://AI/HelicopterEscape.gd"),
		"diagnostic_sha256": FileAccess.get_sha256(get_script().resource_path),
		"flight_sha256": FileAccess.get_sha256("res://Aircraft/HelicopterFlight.gd"),
		"scene_sha256": FileAccess.get_sha256(path), "first_damage_s": -1.0,
		"states_s": {}, "trace": [], "min_range_m": 1e9, "min_agl_m": 1e9}
	var tick := 0
	result["air_target"] = air_target
	result["rescue"] = rescue
	result["attack_selected"] = false
	result["weapons_used"] = []
	var elapsed := 0.0
	while elapsed < duration and is_instance_valid(craft) and float(craft.get("current_health")) > 0:
		await physics_frame
		elapsed += 1.0 / Engine.physics_ticks_per_second
		target.position += target.linear_velocity / Engine.physics_ticks_per_second
		if not is_instance_valid(craft) or not is_instance_valid(pilot): break
		var phase := str(pilot.get("_atk_state"))
		if pilot.get("_atk_target") != null: result.attack_selected = true
		var kind := str(pilot.get("_atk_weapon_kind"))
		if not kind.is_empty() and not result.weapons_used.has(kind): result.weapons_used.append(kind)
		result.states_s[phase] = float(result.states_s.get(phase, 0.0)) + 1.0 / Engine.physics_ticks_per_second
		var range_m := Vector2(craft.position.x, craft.position.z).length()
		result.min_range_m = minf(result.min_range_m, range_m)
		var ground_y := 110.0 if popup_terrain and absf(craft.position.x) <= 800 and craft.position.z >= -560 and craft.position.z <= -480 else 0.0
		result.min_agl_m = minf(result.min_agl_m, craft.position.y - ground_y)
		if target.damage_total > 0 and result.first_damage_s < 0: result.first_damage_s = elapsed
		if tick % 30 == 0:
			result.trace.append({"t": elapsed, "state": phase, "range": range_m, "height": craft.position.y,
				"position": [craft.position.x, craft.position.y, craft.position.z],
				"nose_elevation": rad_to_deg(asin(craft.global_basis.z.y)),
				"aim_dot": pilot.get("_atk_last_aim_dot"), "volleys": pilot.get("_atk_rocket_volleys_fired"),
				"speed": craft.linear_velocity.length(), "health": craft.get("current_health"),
				"damage": target.damage_total, "gate": pilot.get("_atk_gate_last_hold"),
				"path_points": (pilot.get("_heightmap_path") as Array).size(),
				"escape_covered": pilot.get("_atk_escape_covered"),
				"exit_reason": pilot.get("_atk_tuning_exit_reason"),
				"popup": pilot.call("get_popup_diagnostic"),
				"controls": [pilot.get("_pitch_cmd"), pilot.get("_roll_cmd"), pilot.get("_yaw_cmd")]})
		if tick % 1800 == 0: print("HELI_DIAGNOSTIC_PROGRESS model=%d t=%.1f phase=%s popup=%s damage=%.1f" % [model, elapsed, phase, (pilot.call("get_popup_diagnostic") as Dictionary).phase, target.damage_total])
		tick += 1
	result.status = "COMPLETE"
	result["elapsed_s"] = elapsed
	result["alive"] = is_instance_valid(craft) and float(craft.get("current_health")) > 0
	result["damage"] = target.damage_total
	result["evasion_episodes"] = pilot.get("_air_awareness").episodes if is_instance_valid(pilot) else -1
	var output := "user://heli_attack_%s_%d.json" % [label, model]
	var file := FileAccess.open(output, FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "\t"))
	file.close()
	print("HELI_DIAGNOSTIC_COMPLETE model=%d alive=%s first_damage=%.1f damage=%.1f output=%s" % [model, result.alive, result.first_damage_s, result.damage, output])
	quit(0)

func _add_box(body: CollisionObject3D, size: Vector3) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)
