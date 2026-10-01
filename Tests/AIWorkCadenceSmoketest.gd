extends Node3D

class TestAircraft extends RigidBody3D:
	var team := 1
	func get_team() -> int: return team

class Pilot extends AIPilot:
	var terrain_queries := 0
	func _ready() -> void: pass
	func _get_ground_height_at_position(_point: Vector3) -> float:
		terrain_queries += 1
		return 0.0

class Vehicle extends VehicleEnemyLight:
	var searches := 0
	func _ready() -> void: pass
	func _refresh_spacing_candidates() -> void:
		searches += 1
		super._refresh_spacing_candidates()

class Platoon extends GroundVehiclePlatoon:
	var contact_updates := 0
	var route_updates := 0
	var route_elapsed := 0.0
	func _update_contact_position(delta: float) -> void:
		contact_updates += 1
		super._update_contact_position(delta)
	func _update_route_preview(delta: float) -> void:
		route_updates += 1
		route_elapsed += delta
		super._update_route_preview(delta)

var failures: Array[String] = []
func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func _ready() -> void: call_deferred("run")
func run() -> void:
	for node in get_tree().root.get_children():
		if node != self: node.process_mode = Node.PROCESS_MODE_DISABLED
	var own := TestAircraft.new()
	own.position.y = 1000
	own.linear_velocity = Vector3.BACK * 100
	add_child(own)
	var pilot := Pilot.new()
	own.add_child(pilot)
	pilot.set_physics_process(false)
	pilot.aircraft = own
	pilot.current_state = AIPilot.State.TRANSIT
	pilot.sensor_update_interval = 1
	var enemy := TestAircraft.new()
	enemy.team = 2
	enemy.position = own.position + Vector3(0, 0, 200)
	enemy.linear_velocity = Vector3.FORWARD * 100
	add_child(enemy)
	enemy.add_to_group("ai_aircraft")
	enemy.add_to_group("aircraft")
	enemy.add_to_group("enemies")
	pilot._scan_contacts()
	check(pilot.known_enemies.count(enemy) == 1, "Multi-group contacts appear once")
	check(pilot.cached_hostile_nodes.count(enemy) == 1, "Sensor cache has unique contacts")
	check(not pilot.known_friendlies.has(enemy), "Hostile team remains excluded from friendlies")
	check(pilot._check_collision_avoidance(0.1), "Head-on nearby traffic still triggers avoidance")
	pilot.terrain_queries = 0
	enemy.position.z = 2000
	check(not pilot._check_collision_avoidance(0.1) and pilot.terrain_queries == 0,
		"Distant aircraft skip terrain queries")
	enemy.position = own.position + Vector3(0, 100, 100)
	check(not pilot._check_collision_avoidance(0.1) and pilot.terrain_queries == 0,
		"Vertically separated traffic skips terrain queries")
	enemy.team = 1
	pilot._scan_contacts()
	check(pilot.known_friendlies.has(enemy) and not pilot.known_enemies.has(enemy), "Team changes remain live")
	enemy.free()
	pilot._scan_contacts()
	check(pilot.known_enemies.is_empty() and pilot.known_friendlies.is_empty(), "Freed contacts disappear")
	var vehicle := Vehicle.new()
	add_child(vehicle)
	vehicle.set_physics_process(false)
	for tick in 10: vehicle._get_spacing_candidates(0.02)
	check(vehicle.searches == 1, "Empty vehicle spacing cache respects its refresh interval")
	vehicle._get_spacing_candidates(0.36)
	check(vehicle.searches == 2, "Empty cache is refreshed after its interval")
	var neighbour := Node3D.new()
	neighbour.position.x = 5
	add_child(neighbour)
	neighbour.add_to_group("ground_vehicles")
	WorldUnitIndex.register_unit(neighbour)
	check(vehicle._get_spacing_candidates(0.36).has(neighbour), "New nearby vehicles are discovered")
	var platoons: Array[Platoon] = []
	for i in 24:
		var platoon := Platoon.new()
		add_child(platoon)
		platoon.set_physics_process(false)
		platoon.register_vehicle(vehicle)
		platoons.append(platoon)
	var distribution := []
	for tick in 60:
		var updates := 0
		for platoon in platoons:
			var previous := platoon.contact_updates
			platoon._physics_process(1.0 / 60.0)
			updates += platoon.contact_updates - previous
		distribution.append(updates)
	for platoon in platoons:
		check(platoon.contact_updates >= 8 and platoon.contact_updates <= 12, "Platoon tactical work runs near 10 Hz")
		check(platoon.contact_updates == platoon.route_updates, "Contact and route updates stay paired")
		check(absf(platoon.route_elapsed + platoon._tactical_update_elapsed_s - 1.0) < 0.00001,
			"Cadence preserves accumulated elapsed time")
	var platoon := platoons[0]
	platoon._tactical_update_timer_s = 0.1
	var previous := platoon.contact_updates
	platoon.set_move_objective(Vector3(500, 0, 500))
	platoon._physics_process(0.016)
	check(platoon.contact_updates == previous + 1, "New orders refresh on the next physics tick")
	check(not platoon.get_active_waypoints().is_empty(), "New move order exposes a route")
	previous = platoon.contact_updates
	platoon._physics_process(1.0)
	check(platoon.contact_updates == previous + 1, "Slow frames do not trigger a catch-up work burst")
	platoon.set_hold_objective()
	check(platoon._route_preview_positions.is_empty(), "Hold clears the route immediately")
	var old_contact := platoon.get_contact_position()
	platoon.apply_origin_shift(Vector3(1000, 0, 0))
	check(platoon.get_contact_position() == old_contact - Vector3(1000, 0, 0), "Origin shifts rebase cached contacts immediately")
	var maximum := 0
	for count in distribution.slice(2): maximum = maxi(maximum, count)
	check(maximum < platoons.size(), "Recurring platoon work is spread across ticks")
	print("AI_WORK_CADENCE_", "PASS" if failures.is_empty() else "FAIL", " updates_per_tick=", distribution, " failures=", failures)
	get_tree().quit(0 if failures.is_empty() else 1)
