extends SceneTree

class Terrain extends Node3D:
	func get_height(_point: Vector3) -> float:
		return 0.0

class Carrier extends StaticBody3D:
	var team := 1
	var is_destroyed := false
	func get_team() -> int:
		return team

var failures: Array[String] = []
var deployments: Array[Dictionary] = []

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, reason: String) -> void:
	if not ok:
		failures.append(reason)
		push_error(reason)

func run() -> void:
	await process_frame
	for singleton in root.get_children():
		singleton.process_mode = Node.PROCESS_MODE_DISABLED
	root.get_node("FloatingOrigin").enabled = false
	var world := Node3D.new()
	world.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(world)
	current_scene = world
	var terrain := Terrain.new()
	world.add_child(terrain)
	terrain.add_to_group("terrain_provider")
	root.get_node("TerrainReference").terrain_node = terrain
	var carrier := Carrier.new()
	world.add_child(carrier)
	carrier.add_to_group("carrier")
	var vehicle := Carrier.new()
	world.add_child(vehicle)
	vehicle.add_to_group("ground_vehicles")
	vehicle.position = Vector3(80, 0, 40)
	var allied_vehicle := Carrier.new()
	world.add_child(allied_vehicle)
	allied_vehicle.team = 2
	allied_vehicle.add_to_group("ground_vehicles")
	var distant_vehicle := Carrier.new()
	world.add_child(distant_vehicle)
	distant_vehicle.position = Vector3(20000, 0, 20000)
	distant_vehicle.add_to_group("ground_vehicles")
	var air_target := Carrier.new()
	world.add_child(air_target)
	air_target.add_to_group("aircraft")
	var spawner := load("res://Enemies/EnemyAircraftSpawner.gd").new() as Node3D
	spawner.max_ai_planes = 8
	world.add_child(spawner)
	var menu := load("res://UI/VehicleSpawnMenu.gd").new() as CanvasLayer
	world.add_child(menu)
	menu.enemy_force_spawned.connect(func(_force: Node, entry: Dictionary, count: int):
		deployments.append({"role": entry.role, "count": count}))
	menu.spawn_failed.connect(func(reason: String): check(false, "menu spawn failed: " + reason))
	var presets := [
		{"role": "scout_helicopter", "model": 13},
		{"role": "attack_helicopter", "model": 15},
	]
	for preset in presets:
		menu.set_open(true)
		var choice: Button
		for button: Button in menu._buttons:
			if button.text == "HELICOPTER FLIGHT // AIRCRAFT %d" % preset.model:
				choice = button
		check(choice != null, "button exists for Aircraft %d" % preset.model)
		if choice == null:
			continue
		var deployment_count := deployments.size()
		choice.pressed.emit()
		check(not paused and not menu.is_open(), "selection closes menu and resumes simulation")
		var deadline := Time.get_ticks_msec() + 15000
		while deployments.size() == deployment_count and Time.get_ticks_msec() < deadline and failures.is_empty():
			await process_frame
		check(deployments.size() == deployment_count + 1, "menu reports deployed helicopter flight")
		var members: Array[Node3D] = []
		for aircraft in get_nodes_in_group("enemies"):
			if aircraft.get_meta("spawned_enemy_role", "") == preset.role:
				members.append(aircraft as Node3D)
		check(members.size() == 4, "four Aircraft %d helicopters deployed" % preset.model)
		for aircraft in members:
			check(aircraft.scene_file_path == "res://Aircraft/Aircraft_%d.tscn" % preset.model
				and aircraft.get_team() == 2 and aircraft.is_in_group("ai_aircraft")
				and not aircraft.is_in_group("friendlies"), "correct model and hostile ownership")
			var pilot: Node = aircraft.get_node("HelicopterPilot")
			check(pilot.is_physics_processing() and not aircraft.get_node("AIPilot").is_physics_processing(),
				"helicopter controller owns flight")
			check(pilot._commanded_attack_target == null and pilot.flight_patrol_engagement == "ground"
				and pilot.combat_enabled and pilot.atk_enabled, "flight has autonomous ground attack orders")
			check(pilot._can_start_combat_attack(), "spawned helicopter is ready for combat selection")
			var targets: Array = pilot._get_combat_target_candidates()
			check(targets.has(carrier) and targets.has(vehicle), "carrier and nearby opposing vehicle are both selectable")
			check(not targets.has(allied_vehicle) and not targets.has(distant_vehicle) and not targets.has(air_target),
				"allied, distant and air contacts are excluded")
			vehicle.is_destroyed = true
			targets = pilot._get_combat_target_candidates()
			check(not targets.has(vehicle) and targets.has(carrier), "destroyed vehicle is dropped while carrier remains available")
			vehicle.is_destroyed = false
			check(pilot.outpost_patrol_mode and pilot._outpost_route.size() == 4, "surface patrol is available")
			var route: Array[Vector3] = pilot._outpost_route.duplicate()
			pilot.command_attack_target(vehicle)
			targets = pilot._get_combat_target_candidates()
			check(targets.size() == 1 and targets[0] == vehicle, "explicit individual attack still takes precedence")
			pilot.command_flight_patrol(route, "ground")
			check(pilot.engine.is_engine_working and pilot.engine.current_power > 0.3, "airborne helicopters have rotor lift")
			check(aircraft.linear_velocity.length() <= pilot.max_speed_mps
				and aircraft.linear_velocity.dot(aircraft.global_basis.z) > 29.0, "helicopter forward speed stays within limits")
			check(not pilot._get_combat_weapon_options().is_empty(), "authored weapons are available")
			check(aircraft.global_position.y >= 140.0, "spawn clears the terrain")
		for i in members.size():
			for j in range(i + 1, members.size()):
				check(members[i].global_position.distance_to(members[j].global_position) >= 179.0, "flight slots have safe spacing")
	# A repeated click at the limit must fail without deploying part of a flight.
	var before: int = spawner._active_ai_planes.size()
	var blocked: Array = await spawner.spawn_enemy_flight_by_role("scout_helicopter", 4)
	check(blocked.is_empty() and spawner._active_ai_planes.size() == before, "capacity limit refuses partial helicopter flights")
	# Autoload processing is disabled in this fixture, so release detached cockpit
	# nodes explicitly instead of waiting for the presentation cache's prune pass.
	var visual_budget := root.get_node("EnemyVisualBudget")
	for aircraft in spawner._active_ai_planes:
		visual_budget.release_aircraft_cache(aircraft)
	world.queue_free()
	await process_frame
	await process_frame
	print("ENEMY_HELICOPTER_SPAWN_MENU_%s deployments=%s failures=%s" % ["PASS" if failures.is_empty() else "FAIL", deployments, failures])
	quit(0 if failures.is_empty() else 1)
