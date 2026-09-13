extends RefCounted
## Trailer-only battle staging. Ordinary campaign loading never uses this.
var friendly: GroundVehiclePlatoon
var enemy: GroundVehiclePlatoon
var strike: Flight
var friendly_start := Vector3.ZERO
var enemy_start := Vector3.ZERO
var ground_span := 0.0
var route_length := 0.0
var cleaned_count := 0
var error := ""
var aircraft_launched := 0

static func isolate_baseline(state: Dictionary) -> void:
	var campaign: Dictionary = state.get("campaign", {})
	campaign["friendly_air_ops"] = {"flights": []}
	campaign["friendly_ground_ops"] = {"platoons": []}
	campaign["enemy_bases"] = {"bases": [], "emplacements": []}
	campaign["enemy_ops"] = {"base_entries": [], "known_contacts": [], "pending_loss_incidents": [], "ops_clock_s": 0.0}
	# Wind farms are hostile targetable installations, not neutral scenery.
	campaign["scenario"] = {"wind_turbines": [], "wind_farm_guards": []}

func setup(director: Node, config: Dictionary) -> bool:
	var tree := director.get_tree()
	var carrier := tree.get_first_node_in_group("carrier") as Node3D
	var terrain := TerrainReference.get_terrain_node()
	if carrier == null or terrain == null: return _fail("Carrier/terrain unavailable")
	# Remove authored/live leftovers without invoking damage/KIA callbacks.
	var old_actors := {}
	for group in ["aircraft", "ai_aircraft", "ground_vehicles", "enemies", "friendlies", "downed_pilots"]:
		for node in tree.get_nodes_in_group(group):
			if not node is Node3D or node == carrier or carrier.is_ancestor_of(node): continue
			old_actors[node.get_instance_id()] = node
	for node in old_actors.values():
		if is_instance_valid(node) and not node.is_queued_for_deletion():
			node.queue_free()
			cleaned_count += 1
	await tree.process_frame
	if not is_instance_valid(director): return false
	friendly_start = carrier.global_position + _direction(float(config.friendly_bearing_deg)) * float(config.friendly_distance_m)
	enemy_start = friendly_start + _direction(float(config.enemy_bearing_deg)) * float(config.separation_m)
	friendly_start.y = float(terrain.call("get_height", friendly_start))
	enemy_start.y = float(terrain.call("get_height", enemy_start))
	if not _validate_plain(terrain): return false
	var route := NavGraph.find_path(friendly_start, enemy_start, 4.0)
	if route.size() < 2 or Vector2(route.back().x - enemy_start.x, route.back().z - enemy_start.z).length() > 150.0:
		return _fail("No ground route between the staged forces")
	for i in range(1, route.size()): route_length += route[i-1].distance_to(route[i])
	if route_length > 2800.0: return _fail("Ground route detours off the intended plain")
	friendly = GroundOpsManager.get_platoon("Ember")
	if friendly == null: return _fail("Friendly platoon unavailable")
	friendly.global_position = friendly_start
	enemy = GroundVehiclePlatoon.new()
	enemy.name = "Trailer_EnemyPlatoon"
	enemy.platoon_id = "Trailer enemies"
	enemy.team = 2
	tree.current_scene.add_child(enemy)
	enemy.global_position = enemy_start
	var direction := (enemy_start - friendly_start).normalized()
	direction.y = 0.0
	direction = direction.normalized()
	if not _spawn_members(director, friendly, config.friendly_vehicles, friendly_start, direction, "friendly"): return false
	if not _spawn_members(director, enemy, config.enemy_vehicles, enemy_start, -direction, "enemy"): return false
	friendly.set_attack_node(enemy, 350.0)
	enemy.set_attack_node(friendly, 350.0)
	strike = AirOpsManager.get_flight("Archer")
	if strike == null: return _fail("Strike flight unavailable")
	strike.set_cas(enemy_start, 2400.0, 600.0)
	for target in enemy.get_members(): AirOpsManager.report_contact(carrier, target)
	print("[TrailerBattle] READY friendly=%d enemy=%d friendly_start=%s enemy_start=%s bearing=%.1f range=%.1f separation=%.1f ground_span=%.2f route=%.1f cleaned=%d" % [friendly.get_members().size(), enemy.get_members().size(), friendly_start, enemy_start, float(config.friendly_bearing_deg), _flat_distance(carrier.global_position, friendly_start), _flat_distance(friendly_start, enemy_start), ground_span, route_length, cleaned_count])
	return true

func tick() -> void:
	# Vehicles are world siblings, so moving the platoon marker does not move them.
	if is_instance_valid(friendly) and friendly.has_members(): friendly.global_position = friendly.get_center_position()
	if is_instance_valid(enemy) and enemy.has_members(): enemy.global_position = enemy.get_center_position()

func on_launched(pilot: Node) -> void:
	var aircraft: RigidBody3D = pilot.get("aircraft") as RigidBody3D
	if aircraft == null or not is_instance_valid(strike): return
	strike.register(aircraft)
	AirOpsManager._assign_pilot_identity(aircraft, strike)
	aircraft_launched += 1
	# Refresh authored target reports at launch; normal sensors and Flight CAS
	# handle subsequent tracking and attack passes.
	var carrier := pilot.get_tree().get_first_node_in_group("carrier") as Node3D
	if carrier != null and is_instance_valid(enemy):
		for target in enemy.get_members(): AirOpsManager.report_contact(carrier, target)
	print("[TrailerBattle] STRIKE_JOIN craft=%s scene=%s mission=CAS strength=%d" % [aircraft.name, aircraft.scene_file_path, strike.strength()])

func _spawn_members(director: Node, platoon: GroundVehiclePlatoon, scenes: Array, center: Vector3, forward: Vector3, prefix: String) -> bool:
	var right := Vector3.UP.cross(forward)
	var terrain := TerrainReference.get_terrain_node()
	for i in scenes.size():
		var packed := load(str(scenes[i])) as PackedScene
		if packed == null: return _fail("Missing vehicle scene %s" % scenes[i])
		var vehicle := packed.instantiate() as Node3D
		if vehicle == null: return _fail("Not a vehicle: %s" % scenes[i])
		vehicle.name = "Trailer_%s_%02d" % [prefix, i + 1]
		vehicle.set("team", platoon.team)
		vehicle.set_meta("trailer_battle_unit", true)
		vehicle.set_meta("source_scene_path", scenes[i])
		var rank := floorf(float(i) / 2.0) - (ceilf(scenes.size() / 2.0) - 1.0) * 0.5
		var position := center + right * (-25.0 if i % 2 == 0 else 25.0) - forward * rank * 50.0
		position.y = float(terrain.call("get_height", position)) + 0.15
		director.get_tree().current_scene.add_child(vehicle)
		vehicle.global_position = position
		vehicle.global_rotation.y = atan2(forward.x, forward.z)
		vehicle.remove_from_group("enemies" if platoon.team == 1 else "friendlies")
		vehicle.add_to_group("friendlies" if platoon.team == 1 else "enemies")
		if "deploy_mode" in vehicle: vehicle.set("deploy_mode", false)
		if "use_waypoint_pathfinding" in vehicle: vehicle.set("use_waypoint_pathfinding", true)
		if vehicle.has_method("assign_platoon"): vehicle.call("assign_platoon", platoon)
		else: return _fail("Vehicle cannot join platoon: %s" % scenes[i])
		vehicle.reset_physics_interpolation()
	return true

func _validate_plain(terrain: Node) -> bool:
	var low := INF
	var high := -INF
	var right := (enemy_start - friendly_start).normalized().cross(Vector3.UP)
	for step in 81:
		for across in [-150.0, -75.0, 0.0, 75.0, 150.0]:
			var point: Vector3 = friendly_start.lerp(enemy_start, step / 80.0) + right * float(across)
			var height := float(terrain.call("get_height", point))
			if not is_finite(height): return _fail("Staging plain has invalid terrain")
			low = minf(low, height)
			high = maxf(high, height)
	ground_span = high - low
	if ground_span > 8.0: return _fail("Staging corridor is no longer a common plain (%.1f m relief)" % ground_span)
	return true

func _direction(bearing: float) -> Vector3:
	return Vector3(sin(deg_to_rad(bearing)), 0, -cos(deg_to_rad(bearing)))

func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x-b.x, a.z-b.z).length()

func _fail(message: String) -> bool:
	error = message
	return false
