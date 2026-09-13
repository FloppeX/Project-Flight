extends "res://Tests/VehicleTransitionPerformance.gd"
## Forward+ real Main_Scene carrier/interior and generated terrain. Only the
## three camera targets have flight/AI suspended. No saved settings are changed.
## Required: -- --test-scenario=0 --label=scenario_trace

var phase_details: Dictionary = {}
var ground_wheel_audit: Dictionary = {}
var busy_battle: Dictionary = {}

func _run() -> void:
	root.get_node("SaveGameManager").set("autosave_enabled", false)
	# Abort even if a script error interrupts the coroutine later in the run.
	create_timer(300.0).timeout.connect(func():
		push_error("Scenario transition probe watchdog timeout")
		quit(1))
	if not "--test-scenario=0" in OS.get_cmdline_user_args():
		push_error("ScenarioTransitionPerformance requires --test-scenario=0")
		quit(1)
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--label="): label = arg.get_slice("=", 1).validate_filename()
	render_trace.attach(self)
	root.get_node("GameSession").call("configure_new_game", "Transition Benchmark", Color.WHITE, Color.BLACK, 0, 0, "open_canyons")
	var loading := root.get_node("LoadingScreen")
	loading.call("begin_scenario_load")
	var scene := (load("res://Main_Scene.tscn") as PackedScene).instantiate() as Node3D
	scene.set("randomize_play_area_each_run", false)
	root.add_child(scene)
	current_scene = scene
	var deadline := Time.get_ticks_msec() + 240000
	while bool(loading.get("_active")) and Time.get_ticks_msec() < deadline:
		await process_frame
	if bool(loading.get("_active")):
		push_error("Scenario transition probe: loading timed out")
		quit(1)
		return
	terrain = scene.get_node("LowPolyTerrainPrototype")
	director = root.get_node("FlightDirector")
	var carrier := scene.get_node("LandCarrier") as Node3D
	var provider: Node = director.call("_get_bridge_camera_provider")
	var bridge := provider.call("get_camera_for_mode", 0) as Camera3D if provider != null else null
	if bridge == null:
		push_error("Scenario transition probe: real carrier camera missing")
		quit(1)
		return
	if "--battle-only" in OS.get_cmdline_user_args():
		Engine.max_fps = 60
		FrameProfiler.set_report_capture_enabled(true, "battle_probe")
		FrameProfiler.configure_scope_event_capture(0.1, 8192)
		await _finish_capture(scene, carrier, loading)
		return
	# Avoid a test-spawn changing the camera during deferred aircraft startup.
	director.set_process(false)
	var craft_list: Array[RigidBody3D] = []
	var positions: Array[Vector3] = []
	for i in range(3):
		var model: int = [1, 5, 11][i]
		var offset: Vector3 = [Vector3(300, 0, 180), Vector3(8000, 0, 4000), Vector3(-500, 0, 300)][i]
		var pos := carrier.global_position + offset
		pos.y = float(terrain.call("get_height", pos)) + 650.0
		var craft := (load("res://Aircraft/Aircraft_%d.tscn" % model) as PackedScene).instantiate() as RigidBody3D
		craft.name = "TransitionAircraft%d" % model
		craft.freeze = true
		craft.position = pos
		root.get_node("EnemyVisualBudget").call("prepare_ai_aircraft_for_tree_entry", craft)
		scene.add_child(craft)
		craft.set("team", 1)
		_suspend_flight(craft)
		craft_list.append(craft)
		positions.append(pos)
	await create_timer(4.0).timeout
	for i in range(craft_list.size()):
		_suspend_flight(craft_list[i])
		craft_list[i].global_position = positions[i]
		craft_list[i].reset_physics_interpolation()
	director.call("_activate_bridge_view_now", bridge)
	director.set_process(true)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	DisplayServer.window_set_title("Scenario Transition Performance - " + label)
	Engine.max_fps = 60
	await create_timer(5.0).timeout
	FrameProfiler.set_report_capture_enabled(true, "scenario_transition_probe")
	FrameProfiler.configure_scope_event_capture(0.1, 8192)
	_start_phase("bridge_idle")
	await create_timer(3.0).timeout
	_end_phase()
	for pass_index in range(2):
		for i in range(craft_list.size()):
			_start_phase("%s_to_%d" % ["first" if pass_index == 0 else "repeat", [1, 5, 11][i]])
			director.call("_view_aircraft", craft_list[i])
			await _await_arrival()
			await create_timer(3.0).timeout
			var mount := craft_list[i].find_child("InstrumentPanel", true, false)
			if mount == null or mount.call("get_live_panel") == null: failures.append(phase + ":panel_missing")
			if director.get("current_viewed_aircraft") != craft_list[i]: failures.append(phase + ":wrong_target")
			_end_phase()
			await _capture()
		_start_phase("return_bridge_%d" % pass_index)
		director.call("_begin_bridge_camera_transition", bridge)
		await _await_arrival()
		await create_timer(3.0).timeout
		if root.get_camera_3d() != bridge: failures.append(phase + ":wrong_camera")
		_end_phase()
		await _capture()
	_start_phase("rapid_retarget")
	director.call("_view_aircraft", craft_list[1])
	await create_timer(0.5).timeout
	director.call("_view_aircraft", craft_list[0])
	await _await_arrival()
	await create_timer(3.0).timeout
	if director.get("current_viewed_aircraft") != craft_list[0]: failures.append(phase + ":wrong_target")
	_end_phase()
	_start_phase("player_takeover")
	director.call("toggle_player_control")
	# Control ownership is live, but fixture motion remains disabled.
	_suspend_flight(craft_list[0])
	await _await_arrival()
	await create_timer(2.0).timeout
	if not bool(director.get("is_player_controlling")): failures.append(phase + ":control_not_acquired")
	_end_phase()
	director.call("toggle_player_control")
	_suspend_flight(craft_list[0])
	director.call("_begin_bridge_camera_transition", bridge)
	await _await_arrival()
	await create_timer(2.0).timeout
	await _finish_capture(scene, carrier, loading)

func _finish_capture(scene: Node3D, carrier: Node3D, loading: Node) -> void:
	var sources := {}
	for path in ["res://Weapons/Turrets/turret.gd", "res://Weapons/Turrets/bullet_weapon.gd", "res://Weapons/Turrets/vehicle_lmg_turret.tscn", "res://Weapons/Turrets/vehicle_heavy_gun_turret.tscn", "res://Weapons/Turrets/helicopter_side_gun_turret.tscn", "res://Weapons/Turrets/ModularTurret.gd"]:
		sources[path] = FileAccess.get_sha256(path)
	if "--ground-wheel-audit" in OS.get_cmdline_user_args():
		await _measure_ground_wheels(scene, carrier)
	if "--busy-battle" in OS.get_cmdline_user_args():
		await _measure_busy_battle(scene, carrier)
	for path in ["res://Camera/CameraController.gd", "res://Environment/NavigationGridCache.gd", "res://Environment/TerrainNavGrid.gd", "res://Enemies/EnemyVirtualPlatoon.gd", "res://Operations/WorldUnitIndex.gd", "res://AirOps/AirOpsManager.gd"]:
		sources[path] = FileAccess.get_sha256(path)
	for path in ["res://GroundVehicle/WheelSupport.gd", "res://GroundVehicle/vehicle_friendly_light.gd", "res://GroundVehicle/vehicle_enemy_light.gd", "res://Effects/VehicleMeshLOD.gd"]:
		sources[path] = FileAccess.get_sha256(path)
	for path in ["res://UI/TerrainMapCache.gd", "res://UI/WorldMapOverlay.gd", "res://AI/NavPathScheduler.gd", "res://AI/AIPilot.gd", "res://LandCarrier/LandCarrier.gd", "res://project.godot"]:
		sources[path] = FileAccess.get_sha256(path)
	for path in ["res://Tests/ScenarioTransitionPerformance.gd", "res://Tests/VehicleTransitionPerformance.gd", "res://Tests/Fixtures/TransitionRenderTrace.gd", "res://HUD/InstrumentPanelPool.gd", "res://HUD/instrument_panel.gd", "res://HUD/heads_up_display.gd", "res://AirOps/FlightDirector.gd", "res://Environment/LowPolyTerrain.gd", "res://Main_Scene.tscn", "res://LandCarrier/LandCarrier2.tscn", "res://UI/WorldMapTextureBuilder.gd", "res://HUD/RadarCanvas.gd", "res://AI/NavGraph.gd", "res://Environment/FloatingOrigin.gd", "res://Environment/RockStream.gd", "res://Environment/Plants/PlantPatchStreamer.gd"]:
		sources[path] = FileAccess.get_sha256(path)
	var result := {"status": "COMPLETE" if failures.is_empty() else "FAILED", "failures": failures,
		"label": label, "renderer": RenderingServer.get_current_rendering_method(), "rows": rows,
		"sources": sources, "phase_scopes": phase_scopes, "phase_details": phase_details,
		"pool": root.get_node("InstrumentPanelPool").call("get_pool_stats"),
		"terrain": terrain.call("get_streaming_timing_stats"), "startup": loading.call("get_load_timing_stats"),
		"map_cache": root.get_node("TerrainMapCache").call("get_debug_snapshot")}
	result["rocks"] = scene.get_node("RockStream").call("get_streaming_diagnostics")
	result["ground_wheel_audit"] = ground_wheel_audit
	result["busy_battle"] = busy_battle
	result["sensors"] = root.get_node("AirOpsManager").get("sensor_diagnostics")
	var file := FileAccess.open("user://transition_%s.json" % label, FileAccess.WRITE)
	file.store_string(JSON.stringify(result))
	file.close()
	print("SCENARIO_TRANSITION_COMPLETE ", label, " failures=", failures)
	# Tear down the actual scene before autoload resources are released at exit.
	for manager_name in ["AirOpsManager", "EnemyOpsManager", "GroundOpsManager", "OperationsCoordinator", "FlightDirector"]:
		root.get_node(manager_name).process_mode = Node.PROCESS_MODE_DISABLED
	current_scene = null
	scene.queue_free()
	for _frame in range(3): await process_frame
	quit(0 if failures.is_empty() else 1)

func _measure_busy_battle(scene: Node3D, carrier: Node3D) -> void:
	var vehicles: Array[Node3D] = []
	var guns: Array[Node] = []
	var center := carrier.global_position + Vector3(500, 0, 0)
	var model := "vehicle_friendly_light"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--battle-model="): model = argument.get_slice("=", 1).validate_filename()
	busy_battle["model"] = model
	for i in 32:
		var team_ := 1 if i < 16 else 2
		# 200 m separation remains inside the normal night-reduced gunner range.
		var point := center + Vector3(-100 if team_ == 1 else 100, 0, (i % 16 - 8) * 20)
		var h: float = terrain.call("get_height", point)
		var ray := PhysicsRayQueryParameters3D.create(Vector3(point.x, h + 300, point.z), Vector3(point.x, h - 500, point.z))
		var hit := scene.get_world_3d().direct_space_state.intersect_ray(ray)
		if hit.is_empty(): continue
		var vehicle := (load("res://GroundVehicle/%s.tscn" % model) as PackedScene).instantiate() as Node3D
		vehicle.position = scene.to_local(hit.position + Vector3.UP)
		vehicle.set("team", team_)
		vehicle.set("max_health", 100000000.0)
		vehicle.set("max_speed", 0.0)
		vehicle.set("use_waypoint_pathfinding", false)
		vehicle.rotation.y = PI * 0.5 if team_ == 1 else -PI * 0.5
		scene.add_child(vehicle)
		vehicles.append(vehicle)
		for child in vehicle.find_children("*", "Node", true, false):
			if child.get("physical_rounds_fired") != null:
				child.set("infinite_ammo", true)
				child.set("ammo_count", 1000000)
				guns.append(child)
		await process_frame
	director.set_process(false)
	var view := Camera3D.new()
	scene.add_child(view)
	center.y = float(terrain.call("get_height", center))
	view.position = scene.to_local(center + Vector3(0, 180, 520))
	view.look_at(center)
	view.make_current()
	var air_ops := root.get_node("AirOpsManager")
	var original_queries: bool = air_ops.get("spatial_sensor_queries_enabled")
	var original_budget: float = air_ops.get("sensor_batch_budget_ms")
	await create_timer(5.0).timeout
	busy_battle["vehicles"] = vehicles.size()
	busy_battle["guns"] = guns.size()
	for optimized in [false, true]:
		air_ops.set("spatial_sensor_queries_enabled", optimized)
		air_ops.set("sensor_batch_budget_ms", 1.0 if optimized else 1000.0)
		await create_timer(2.0).timeout
		var shots_before := _round_count(guns)
		var sensor_before: Dictionary = air_ops.get("sensor_diagnostics").duplicate(true)
		_start_phase("busy_battle_" + ("indexed" if optimized else "exhaustive"))
		var seconds := 15.0
		for argument in OS.get_cmdline_user_args():
			if argument.begins_with("--battle-seconds="): seconds = maxf(float(argument.get_slice("=", 1)), 1.0)
		await create_timer(seconds).timeout
		_end_phase()
		var phase_rounds := _round_count(guns) - shots_before
		if phase_rounds <= 0: failures.append(phase + ":no_sustained_fire")
		busy_battle[phase] = {"rounds": phase_rounds, "max_fps": Engine.max_fps, "sensors_before": sensor_before,
			"sensors_after": air_ops.get("sensor_diagnostics").duplicate(true)}
		await _capture()
	var damage := 0.0
	for vehicle in vehicles: damage += 100000000.0 - float(vehicle.get("current_health"))
	busy_battle["damage"] = damage
	var gun_states: Array = []
	for vehicle in vehicles:
		var controller := vehicle.find_child("TurretController", true, false)
		var weapon: Variant = controller.get("weapon_instance")
		var target: Variant = controller.get("current_target")
		var turret: Variant = controller.get("turret")
		var aim: Vector3 = controller.call("_get_target_aim_point", target) if is_instance_valid(target) else Vector3.ZERO
		gun_states.append({"team": controller.get("team"), "target": str(controller.get("current_target")),
			"state": controller.get("fire_state"), "ammo": weapon.get("ammo_count") if is_instance_valid(weapon) else -1,
			"angle": turret.get_aim_angle_to_target(), "arc": turret.is_point_within_yaw_arc(aim),
			"los": controller.call("_has_line_of_sight_to_aim_point", aim, target),
			"above": controller.call("_is_target_above_host_plane", aim),
			"range": controller.call("_get_effective_range_for_target", target),
			"distance": vehicle.global_position.distance_to(aim), "processing": controller.is_physics_processing(),
			"rounds": weapon.get("physical_rounds_fired") if is_instance_valid(weapon) else -1})
	busy_battle["gun_states"] = gun_states
	if _round_count(guns) == 0: failures.append("busy_battle:no_shots")
	if damage <= 0.0: failures.append("busy_battle:no_hits")
	air_ops.set("spatial_sensor_queries_enabled", original_queries)
	air_ops.set("sensor_batch_budget_ms", original_budget)
	for vehicle in vehicles: vehicle.queue_free()
	view.queue_free()
	await process_frame

func _round_count(guns: Array[Node]) -> int:
	var count := 0
	for gun in guns:
		if is_instance_valid(gun): count += int(gun.get("physical_rounds_fired")) + int(gun.get("virtual_rounds_fired"))
	return count

func _measure_ground_wheels(scene: Node3D, carrier: Node3D) -> void:
	var vehicles: Array[CharacterBody3D] = []
	var names := ["GroundVehicle", "vehicle_enemy_buggy", "vehicle_enemy_pickup", "vehicle_enemy_battle_bus", "vehicle_friendly_light"]
	for i in range(30):
		var point := carrier.global_position + Vector3(180 + (i % 6) * 18, 0, (i / 6) * 20)
		var h: float = terrain.call("get_height", point)
		var ray := PhysicsRayQueryParameters3D.create(Vector3(point.x, h + 300, point.z), Vector3(point.x, h - 500, point.z))
		var hit := scene.get_world_3d().direct_space_state.intersect_ray(ray)
		if hit.is_empty(): continue
		var vehicle := (load("res://GroundVehicle/%s.tscn" % names[i % names.size()]) as PackedScene).instantiate() as CharacterBody3D
		vehicle.position = hit.position + Vector3.UP
		vehicle.set("team", 1)
		vehicle.set("max_speed", 0.0)
		vehicle.set("use_waypoint_pathfinding", false)
		scene.add_child(vehicle)
		for turret in vehicle.find_children("*", "TurretController", true, false): turret.process_mode = Node.PROCESS_MODE_DISABLED
		vehicles.append(vehicle)
		await process_frame
	ground_wheel_audit["spawned"] = vehicles.size()
	if vehicles.is_empty():
		failures.append("ground_wheels:no_collision_spawn_sites")
		return
	director.set_process(false)
	var view := Camera3D.new()
	scene.add_child(view)
	view.far = 5000
	for mode in ["near", "distant", "zoom"]:
		var point := vehicles[0].global_position
		view.global_position = point + (Vector3(13, 8, 18) if mode == "near" else Vector3(0, 100, 600))
		view.look_at(point + Vector3.UP)
		view.fov = 12.0 if mode == "zoom" else 70.0
		view.make_current()
		await create_timer(2).timeout
		_start_phase("ground_wheels_" + mode)
		await create_timer(4).timeout
		_end_phase()
		await _capture()
	var caps: Array = []
	for vehicle in vehicles:
		caps.append({"model": vehicle.scene_file_path, "position": str(vehicle.global_position),
			"ground": vehicle.get("_suspension_has_ground"), "wheel_range": vehicle.get("wheel_mesh_visibility_distance_m")})
	ground_wheel_audit["vehicles"] = caps
	view.queue_free()
	for vehicle in vehicles: vehicle.queue_free()

func _suspend_flight(craft: RigidBody3D) -> void:
	for node_name in ["AIPilot", "HelicopterPilot", "AIToggle", "SimpleAero", "HelicopterFlight"]:
		var node := craft.find_child(node_name, true, false)
		if node: node.process_mode = Node.PROCESS_MODE_DISABLED
	craft.set_physics_process(false)
	craft.freeze = true
	craft.linear_velocity = Vector3.ZERO
	craft.angular_velocity = Vector3.ZERO

func _start_phase(name_: String) -> void:
	phase = name_
	last_us = Time.get_ticks_usec()
	phase_details[phase] = {"start_us": last_us, "terrain_start": terrain.call("get_streaming_stats")}
	recording = true
	print("SCENARIO_TRANSITION_BEGIN ", phase)

func _end_phase() -> void:
	recording = false
	phase_details[phase]["end_us"] = Time.get_ticks_usec()
	phase_details[phase]["terrain_end"] = terrain.call("get_streaming_stats")
	phase_scopes[phase] = FrameProfiler.summarize_scope_events(phase_details[phase].start_us, Time.get_ticks_usec(), 40)
	print("SCENARIO_TRANSITION_END ", phase)

func _await_arrival() -> void:
	var deadline := Time.get_ticks_msec() + 20000
	while bool(director.call("is_aircraft_view_transition_active")) and Time.get_ticks_msec() < deadline:
		await process_frame
	if bool(director.call("is_aircraft_view_transition_active")): failures.append(phase + ":timeout")

func _capture() -> void:
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("user://transition_%s_%s.png" % [label, phase])
	for _frame in range(3): await process_frame
