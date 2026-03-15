extends Node3D

@export var spawn_altitude: float = 600.0
@export var spawn_speed: float = 60.0
@export var respawn_delay: float = 3.0
@export var patrol_side_length: float = 2000.0
@export var max_ai_planes: int = 10
@export var duel_range_from_carrier_m: float = 1000.0
@export var duel_altitude_m: float = 600.0
@export var strike_flight_range_from_carrier_m: float = 5000.0
@export var strike_flight_altitude_m: float = 600.0
@export var cap_flight_altitude_m: float = 600.0
@export var cap_orbit_radius_m: float = 1200.0
@export var debug_ground_vehicle_spawns: bool = true

var _aircraft_scene: PackedScene
var _enemy_aircraft_scene: PackedScene
var _active_ai_planes: Array[RigidBody3D] = []
var _enemy_vehicle_scene: PackedScene
var _friendly_vehicle_scene: PackedScene
var _ground_platoon_counter: int = 0

func _ready():
	_aircraft_scene = load("res://Aircraft/Aircraft_1.tscn")
	if not _aircraft_scene:
		push_error("[EnemyAircraftSpawner] Failed to load Aircraft_1.tscn")
	_enemy_aircraft_scene = load("res://Enemies/EnemyFighter.tscn")
	if not _enemy_aircraft_scene:
		push_error("[EnemyAircraftSpawner] Failed to load Enemies/EnemyFighter.tscn")
	_enemy_vehicle_scene = load("res://GroundVehicle/GroundVehicle.tscn")
	_friendly_vehicle_scene = load("res://GroundVehicle/vehicle_friendly_light.tscn")

func _input(event):
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_P:
			_spawn_enemy()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_O:
			_toggle_ai_attack_mode()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_L:
			_command_land()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_U:
			_spawn_on_approach()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_D:
			_spawn_dogfight_duel()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_E:
			_spawn_ground_vehicles(_enemy_vehicle_scene, 5)
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_F:
			_spawn_ground_vehicles(_friendly_vehicle_scene, 5)
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_R:
			_spawn_enemy_strike_flight()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_G:
			_spawn_friendly_cap_flight()
			get_viewport().set_input_as_handled()

func _spawn_ground_vehicles(scene: PackedScene, count: int) -> void:
	if not scene:
		return
	var carrier_pos: Vector3 = _get_carrier_position()
	var carrier_node := get_tree().get_first_node_in_group("carrier") as CollisionObject3D
	var base_pos: Vector3 = carrier_pos
	if scene == _enemy_vehicle_scene:
		base_pos = _find_enemy_vehicle_staging_position(carrier_pos)
	else:
		base_pos = _find_friendly_vehicle_staging_position(carrier_pos, carrier_node)
	if debug_ground_vehicle_spawns:
		print("[GroundSpawn] team=%d carrier=%s base=%s" % [
			1 if scene == _friendly_vehicle_scene else 2,
			str(carrier_pos),
			str(base_pos)
		])

	var space_state := get_world_3d().direct_space_state

	# Generate shared patrol waypoints around the spawn cluster (4 points, 150-300m out)
	var patrol_positions: Array[Vector3] = []
	for w in range(4):
		var angle := w * TAU / 4.0 + randf_range(-0.3, 0.3)
		var dist := randf_range(150.0, 300.0)
		var wp := Vector3(base_pos.x + cos(angle) * dist, 0.0, base_pos.z + sin(angle) * dist)
		var wp_params := PhysicsRayQueryParameters3D.create(wp + Vector3.UP * 2000.0, wp - Vector3.UP * 200.0)
		if scene == _friendly_vehicle_scene and carrier_node and is_instance_valid(carrier_node):
			wp_params.exclude = [carrier_node.get_rid()]
		var wp_hit := space_state.intersect_ray(wp_params)
		wp.y = wp_hit.position.y + 1.5 if wp_hit else 300.0
		patrol_positions.append(wp)

	var platoon := GroundVehiclePlatoon.new()
	_ground_platoon_counter += 1
	platoon.name = "GroundPlatoon_%d" % _ground_platoon_counter
	platoon.platoon_id = platoon.name
	platoon.team = 1 if scene == _friendly_vehicle_scene else 2
	platoon.global_position = base_pos
	get_tree().current_scene.add_child(platoon)
	if platoon.team == 1:
		var carrier := get_tree().get_first_node_in_group("carrier") as Node3D
		if carrier:
			platoon.set_protect_node(carrier, 450.0)
		elif not patrol_positions.is_empty():
			platoon.set_move_objective(patrol_positions[0])
	else:
		var attack_carrier := get_tree().get_first_node_in_group("carrier") as Node3D
		if attack_carrier:
			platoon.set_attack_node(attack_carrier, 500.0)
		else:
			platoon.set_pursue_enemies(1800.0)

	var offsets: Array = [
		Vector3(-35, 0, 0),
		Vector3(0, 0, 35),
		Vector3(35, 0, -15),
		Vector3(-15, 0, -35),
		Vector3(20, 0, 18),
	]
	for i in range(count):
		var off: Vector3 = offsets[i] if i < offsets.size() else Vector3(randf_range(-30, 30), 0, randf_range(-30, 30))
		var spawn_pos := Vector3(base_pos.x + off.x, 0.0, base_pos.z + off.z)
		var spawn_params := PhysicsRayQueryParameters3D.create(spawn_pos + Vector3.UP * 2000.0, spawn_pos - Vector3.UP * 200.0)
		if scene == _friendly_vehicle_scene and carrier_node and is_instance_valid(carrier_node):
			spawn_params.exclude = [carrier_node.get_rid()]
		var hit := space_state.intersect_ray(spawn_params)
		spawn_pos.y = hit.position.y + 2.0 if hit else 300.0

		var vehicle := scene.instantiate() as Node3D
		get_tree().current_scene.add_child(vehicle)
		vehicle.global_position = spawn_pos
		if debug_ground_vehicle_spawns:
			_log_ground_vehicle_spawn(scene, i, base_pos, spawn_pos, vehicle, carrier_node)

		# Stagger starting waypoint so vehicles don't all drive to the same point at once
		if vehicle.has_method("set_patrol_waypoints"):
			var staggered := patrol_positions.duplicate()
			staggered = staggered.slice(i % staggered.size()) + staggered.slice(0, i % staggered.size())
			vehicle.set_patrol_waypoints(staggered)
		if vehicle.has_method("assign_platoon"):
			vehicle.assign_platoon(platoon)

func _find_enemy_vehicle_staging_position(carrier_pos: Vector3) -> Vector3:
	var carrier_ground_y: float = _sample_ground_height(carrier_pos)
	var best_pos: Vector3 = Vector3(carrier_pos.x + 5000.0, carrier_ground_y + 2.0, carrier_pos.z)
	var best_height_delta: float = INF
	for _attempt in range(32):
		var angle: float = randf() * TAU
		var dist: float = randf_range(4500.0, 5500.0)
		var candidate := Vector3(
			carrier_pos.x + cos(angle) * dist,
			0.0,
			carrier_pos.z + sin(angle) * dist
		)
		candidate.y = _sample_ground_height(candidate) + 2.0
		var height_delta: float = absf(candidate.y - (carrier_ground_y + 2.0))
		if height_delta < best_height_delta:
			best_height_delta = height_delta
			best_pos = candidate
		if height_delta <= 35.0:
			break
	return best_pos

func _find_friendly_vehicle_staging_position(carrier_pos: Vector3, carrier_node: CollisionObject3D = null) -> Vector3:
	var carrier_ground_y: float = _sample_ground_height(carrier_pos, carrier_node)
	var best_pos: Vector3 = Vector3(carrier_pos.x + 220.0, carrier_ground_y + 2.0, carrier_pos.z)
	var best_score: float = INF
	for _attempt in range(28):
		var angle: float = randf() * TAU
		var dist: float = randf_range(150.0, 300.0)
		var candidate := Vector3(
			carrier_pos.x + cos(angle) * dist,
			0.0,
			carrier_pos.z + sin(angle) * dist
		)
		candidate.y = _sample_ground_height(candidate, carrier_node) + 2.0
		var height_delta: float = absf(candidate.y - (carrier_ground_y + 2.0))
		var score: float = height_delta
		if score < best_score:
			best_score = score
			best_pos = candidate
		if height_delta <= 12.0:
			break
	return best_pos

func _sample_ground_height(world_pos: Vector3, exclude_body: CollisionObject3D = null) -> float:
	var space_state := get_world_3d().direct_space_state
	var params := PhysicsRayQueryParameters3D.create(world_pos + Vector3.UP * 2000.0, world_pos - Vector3.UP * 300.0)
	if exclude_body and is_instance_valid(exclude_body):
		params.exclude = [exclude_body.get_rid()]
	var hit := space_state.intersect_ray(params)
	if hit:
		return hit.position.y
	return world_pos.y

func _log_ground_vehicle_spawn(scene: PackedScene, index: int, base_pos: Vector3, spawn_pos: Vector3, vehicle: Node3D, carrier_node: CollisionObject3D = null) -> void:
	var team_id: int = 1 if scene == _friendly_vehicle_scene else 2
	var terrain_y: float = _sample_ground_height(spawn_pos, carrier_node)
	print("[GroundSpawn] team=%d idx=%d base=%s spawn=%s terrain_y=%.2f vehicle=%s" % [
		team_id,
		index,
		str(base_pos),
		str(spawn_pos),
		terrain_y,
		str(vehicle.global_position)
	])
	await get_tree().process_frame
	if is_instance_valid(vehicle):
		var settled_terrain_y: float = _sample_ground_height(vehicle.global_position, carrier_node)
		print("[GroundSpawn] team=%d idx=%d after_frame vehicle=%s terrain_y=%.2f delta_y=%.2f" % [
			team_id,
			index,
			str(vehicle.global_position),
			settled_terrain_y,
			vehicle.global_position.y - settled_terrain_y
		])

func _spawn_enemy_strike_flight() -> void:
	if not _enemy_aircraft_scene:
		return
	_prune_active_ai_planes()
	if _active_ai_planes.size() + 4 > max_ai_planes:
		print("[EnemyAircraftSpawner] R: max AI planes would be exceeded")
		return

	var carrier := get_tree().get_first_node_in_group("carrier") as Node3D
	var carrier_pos: Vector3 = _get_carrier_position()
	var spawn_angle: float = randf() * TAU
	var spawn_dir := Vector3(cos(spawn_angle), 0.0, sin(spawn_angle)).normalized()
	if spawn_dir.length() < 0.01:
		spawn_dir = Vector3.FORWARD
	var spawn_center := carrier_pos + spawn_dir * strike_flight_range_from_carrier_m
	spawn_center.y = carrier_pos.y + strike_flight_altitude_m
	var formation_right := Vector3(-spawn_dir.z, 0.0, spawn_dir.x)
	var offsets := [-180.0, -60.0, 60.0, 180.0]
	var spawned: Array[RigidBody3D] = []

	for i in range(offsets.size()):
		var spawn_pos: Vector3 = spawn_center + formation_right * float(offsets[i])
		spawn_pos.y = spawn_center.y
		var aircraft := await _spawn_ai_fighter(
			_enemy_aircraft_scene,
			"EnemyStrike_%d" % (i + 1),
			2,
			"enemies",
			spawn_pos,
			-spawn_dir,
			maxf(spawn_speed, 85.0)
		)
		if is_instance_valid(aircraft):
			spawned.append(aircraft)

	await get_tree().create_timer(0.5).timeout
	for aircraft in spawned:
		_configure_enemy_strike_pilot(aircraft, carrier)

func _spawn_friendly_cap_flight() -> void:
	if not _aircraft_scene:
		return
	_prune_active_ai_planes()
	if _active_ai_planes.size() + 3 > max_ai_planes:
		print("[EnemyAircraftSpawner] G: max AI planes would be exceeded")
		return

	var carrier_pos: Vector3 = _get_carrier_position()
	var orbit_waypoints: Array[Vector3] = _build_carrier_orbit_waypoints(carrier_pos, cap_orbit_radius_m, cap_flight_altitude_m, 9)
	var spawned: Array[RigidBody3D] = []

	for i in range(3):
		var angle: float = TAU * float(i) / 3.0
		var radial: Vector3 = Vector3(cos(angle), 0.0, sin(angle))
		var spawn_pos: Vector3 = carrier_pos + radial * cap_orbit_radius_m
		spawn_pos.y = carrier_pos.y + cap_flight_altitude_m
		var tangent: Vector3 = Vector3(-radial.z, 0.0, radial.x).normalized()
		var aircraft := await _spawn_ai_fighter(
			_aircraft_scene,
			"FriendlyCAP_%d" % (i + 1),
			1,
			"friendlies",
			spawn_pos,
			tangent,
			maxf(spawn_speed, 80.0)
		)
		if is_instance_valid(aircraft):
			spawned.append(aircraft)

	await get_tree().create_timer(0.5).timeout
	for i in range(spawned.size()):
		_configure_friendly_cap_pilot(spawned[i], orbit_waypoints, i)

func _configure_enemy_strike_pilot(aircraft: RigidBody3D, carrier: Node3D) -> void:
	if not is_instance_valid(aircraft):
		return
	var ai_toggle = aircraft.find_child("AIToggle", true, false)
	if ai_toggle and ai_toggle.has_method("enable_ai"):
		ai_toggle.enable_ai()
	var ai_pilot = aircraft.find_child("AIPilot", true, false) as AIPilot
	if not ai_pilot:
		print("[EnemyAircraftSpawner] R: missing AIPilot on strike aircraft")
		return
	ai_pilot.carrier_position = _get_carrier_position()
	ai_pilot.target_altitude = strike_flight_altitude_m
	ai_pilot.patrol_altitude_m = strike_flight_altitude_m
	ai_pilot.target_speed = maxf(spawn_speed, 90.0)
	ai_pilot.ground_attack_enabled = true
	ai_pilot.dogfight_enabled = true
	ai_pilot.waypoints.clear()
	if carrier and is_instance_valid(carrier):
		ai_pilot.set_target(carrier)
	else:
		ai_pilot.change_state(AIPilot.State.SEARCH)

func _configure_friendly_cap_pilot(aircraft: RigidBody3D, orbit_waypoints: Array[Vector3], orbit_offset: int) -> void:
	if not is_instance_valid(aircraft):
		return
	var ai_toggle = aircraft.find_child("AIToggle", true, false)
	if ai_toggle and ai_toggle.has_method("enable_ai"):
		ai_toggle.enable_ai()
	var ai_pilot = aircraft.find_child("AIPilot", true, false) as AIPilot
	if not ai_pilot:
		print("[EnemyAircraftSpawner] G: missing AIPilot on CAP aircraft")
		return
	ai_pilot.carrier_position = _get_carrier_position()
	ai_pilot.target_altitude = cap_flight_altitude_m
	ai_pilot.patrol_altitude_m = cap_flight_altitude_m
	ai_pilot.target_speed = maxf(spawn_speed, 80.0)
	ai_pilot.ground_attack_enabled = false
	ai_pilot.dogfight_enabled = true
	ai_pilot.set_waypoints(orbit_waypoints.duplicate())
	if not orbit_waypoints.is_empty():
		ai_pilot.current_waypoint_index = int((orbit_offset * orbit_waypoints.size()) / 3)
	ai_pilot.change_state(AIPilot.State.SEARCH)

func _build_carrier_orbit_waypoints(center: Vector3, radius_m: float, altitude_m: float, point_count: int) -> Array[Vector3]:
	var points: Array[Vector3] = []
	var clamped_count: int = max(point_count, 3)
	for i in range(clamped_count):
		var angle: float = TAU * float(i) / float(clamped_count)
		points.append(center + Vector3(cos(angle) * radius_m, altitude_m, sin(angle) * radius_m))
	return points

func _spawn_enemy():
	if not _aircraft_scene:
		return
	_prune_active_ai_planes()
	if _active_ai_planes.size() >= max_ai_planes:
		print("[EnemyAircraftSpawner] Max AI planes reached: ", max_ai_planes)
		return

	var aircraft = _aircraft_scene.instantiate() as RigidBody3D
	if not aircraft:
		push_error("[EnemyAircraftSpawner] Failed to instantiate enemy aircraft")
		return

	aircraft.name = "FriendlyAI"
	get_tree().current_scene.add_child(aircraft)

	var spawn_pos = _get_carrier_position()
	spawn_pos.y += spawn_altitude
	aircraft.global_position = spawn_pos

	var forward_dir = _get_carrier_forward()
	var yaw = atan2(forward_dir.x, forward_dir.z)
	aircraft.global_rotation = Vector3(0, yaw, 0)
	aircraft.linear_velocity = forward_dir * spawn_speed

	# aircraft._ready() awaits process_frame before add_to_group("aircraft"), so we must
	# remove after it completes (next frame)
	await get_tree().process_frame
	await get_tree().process_frame  # Extra frame to ensure aircraft._ready() has finished
	aircraft.remove_from_group("aircraft")
	aircraft.add_to_group("friendlies")
	aircraft.add_to_group("ai_aircraft")

	# Friendly AI: keep ControlWeapons enabled for ground attack; disable player UI/targeting
	var disable_nodes = [
		"CameraController", "HeadsUpDisplay", "InstrumentPanel",
		"ControlTargeting"
	]
	for node_name in disable_nodes:
		var node = aircraft.find_child(node_name, true, false)
		if node:
			node.set_process(false)
			node.set_physics_process(false)
			node.set_process_input(false)
			if node is CanvasItem:
				node.visible = false
			elif node is Node3D:
				node.visible = false
	
	# Ensure camera tripods stay enabled so player can switch to view this AI plane
	for cam_name in ["CameraCockpit", "CameraChase", "CameraCinematic"]:
		var tripod = aircraft.get_node_or_null(cam_name)
		if tripod:
			tripod.set_process(true)
			tripod.set_physics_process(true)

	# AI planes spawn airborne - stow gear immediately
	var control_gear = aircraft.find_child("ControlLandingGear", true, false)
	if control_gear and control_gear.has_method("send_to_landing_gears"):
		control_gear.send_to_landing_gears("stow")
		control_gear.send_to_tailhooks("stow")
		if control_gear.has_method("send_to_tailhook_simple"):
			control_gear.send_to_tailhook_simple(false)
		if "gear_down_state" in control_gear:
			control_gear.gear_down_state = false
		if control_gear.has_method("_set_collider_disabled"):
			control_gear._set_collider_disabled(true)

	if aircraft.has_signal("crashed"):
		aircraft.crashed.connect(_on_enemy_crashed.bind(aircraft))
	if aircraft.has_signal("destroyed"):
		aircraft.destroyed.connect(_on_enemy_destroyed.bind(aircraft))

	_active_ai_planes.append(aircraft)
	pass

	await get_tree().create_timer(0.5).timeout
	_configure_ai_patrol(aircraft)

func _spawn_ai_fighter(scene: PackedScene, display_name: String, team_id: int, extra_group: String, spawn_pos: Vector3, forward_dir: Vector3, initial_speed: float) -> RigidBody3D:
	if not scene:
		return null
	var aircraft := scene.instantiate() as RigidBody3D
	if not aircraft:
		return null
	aircraft.name = display_name
	if "team" in aircraft:
		aircraft.team = team_id
	get_tree().current_scene.add_child(aircraft)

	aircraft.global_position = spawn_pos
	var flat_fwd := Vector3(forward_dir.x, 0.0, forward_dir.z).normalized()
	if flat_fwd.length() < 0.01:
		flat_fwd = Vector3.FORWARD
	var yaw := atan2(flat_fwd.x, flat_fwd.z)
	aircraft.global_rotation = Vector3(0.0, yaw, 0.0)
	aircraft.linear_velocity = flat_fwd * initial_speed

	# Wait for aircraft._ready() to finish adding default groups.
	await get_tree().process_frame
	await get_tree().process_frame
	aircraft.remove_from_group("aircraft")
	aircraft.add_to_group("ai_aircraft")
	if not extra_group.is_empty():
		aircraft.add_to_group(extra_group)

	# Disable player-only UI/camera controller/targeting.
	for node_name in ["CameraController", "HeadsUpDisplay", "InstrumentPanel", "ControlTargeting"]:
		var node = aircraft.find_child(node_name, true, false)
		if node:
			node.set_process(false)
			node.set_physics_process(false)
			node.set_process_input(false)
			if node is CanvasItem:
				node.visible = false
			elif node is Node3D:
				node.visible = false

	for cam_name in ["CameraCockpit", "CameraChase", "CameraCinematic"]:
		var tripod = aircraft.get_node_or_null(cam_name)
		if tripod:
			tripod.set_process(true)
			tripod.set_physics_process(true)

	# Spawn airborne with gear up.
	var control_gear = aircraft.find_child("ControlLandingGear", true, false)
	if control_gear and control_gear.has_method("send_to_landing_gears"):
		control_gear.send_to_landing_gears("stow")
		control_gear.send_to_tailhooks("stow")
		if control_gear.has_method("send_to_tailhook_simple"):
			control_gear.send_to_tailhook_simple(false)
		if "gear_down_state" in control_gear:
			control_gear.gear_down_state = false
		if control_gear.has_method("_set_collider_disabled"):
			control_gear._set_collider_disabled(true)

	if aircraft.has_signal("crashed"):
		aircraft.crashed.connect(_on_enemy_crashed.bind(aircraft))
	if aircraft.has_signal("destroyed"):
		aircraft.destroyed.connect(_on_enemy_destroyed.bind(aircraft))
	_active_ai_planes.append(aircraft)
	return aircraft

func _spawn_dogfight_duel() -> void:
	"""D key: spawn one friendly + one enemy in a head-on dogfight setup."""
	if not _aircraft_scene or not _enemy_aircraft_scene:
		print("[EnemyAircraftSpawner] D: missing aircraft scenes")
		return
	_prune_active_ai_planes()
	if _active_ai_planes.size() + 2 > max_ai_planes:
		print("[EnemyAircraftSpawner] D: max AI planes would be exceeded")
		return

	var carrier_pos: Vector3 = _get_carrier_position()
	var carrier_fwd: Vector3 = _get_carrier_forward()
	var forward_flat: Vector3 = Vector3(carrier_fwd.x, 0.0, carrier_fwd.z).normalized()
	if forward_flat.length() < 0.01:
		forward_flat = Vector3.FORWARD
	var altitude_y: float = carrier_pos.y + duel_altitude_m

	var friendly_pos: Vector3 = carrier_pos + forward_flat * duel_range_from_carrier_m
	friendly_pos.y = altitude_y
	var enemy_pos: Vector3 = carrier_pos - forward_flat * duel_range_from_carrier_m
	enemy_pos.y = altitude_y

	var friendly: RigidBody3D = await _spawn_ai_fighter(_aircraft_scene, "FriendlyDuelAI", 1, "friendlies", friendly_pos, -forward_flat, spawn_speed)
	var enemy: RigidBody3D = await _spawn_ai_fighter(_enemy_aircraft_scene, "EnemyDuelAI", 2, "enemies", enemy_pos, forward_flat, spawn_speed)
	if not is_instance_valid(friendly) or not is_instance_valid(enemy):
		print("[EnemyAircraftSpawner] D: failed to spawn duel aircraft")
		return

	await get_tree().create_timer(0.5).timeout
	var friendly_toggle = friendly.find_child("AIToggle", true, false)
	if friendly_toggle and friendly_toggle.has_method("enable_ai"):
		friendly_toggle.enable_ai()
	var enemy_toggle = enemy.find_child("AIToggle", true, false)
	if enemy_toggle and enemy_toggle.has_method("enable_ai"):
		enemy_toggle.enable_ai()

	var friendly_pilot = friendly.find_child("AIPilot", true, false)
	var enemy_pilot = enemy.find_child("AIPilot", true, false)
	if friendly_pilot and enemy_pilot and friendly_pilot is AIPilot and enemy_pilot is AIPilot:
		friendly_pilot.dogfight_enabled = true
		enemy_pilot.dogfight_enabled = true
		friendly_pilot.ground_attack_enabled = false
		enemy_pilot.ground_attack_enabled = false
		friendly_pilot.set_target(enemy)
		enemy_pilot.set_target(friendly)
		print("[EnemyAircraftSpawner] D: spawned dogfight duel. Separation=", snapped(friendly.global_position.distance_to(enemy.global_position), 1.0), "m Alt=", snapped(duel_altitude_m, 1.0), "m")
	else:
		print("[EnemyAircraftSpawner] D: missing AIPilot on one or both duel aircraft")

func _configure_ai_patrol(aircraft: RigidBody3D):
	if not is_instance_valid(aircraft):
		return

	var ai_toggle = aircraft.find_child("AIToggle", true, false)
	if ai_toggle and ai_toggle.has_method("enable_ai"):
		ai_toggle.enable_ai()

	var ai_pilot = aircraft.find_child("AIPilot", true, false)
	if not ai_pilot:
		push_error("[EnemyAircraftSpawner] No AIPilot found on enemy aircraft")
		return

	var center = _get_carrier_position()
	ai_pilot.carrier_position = center
	ai_pilot.target_altitude = 600.0
	ai_pilot.patrol_altitude_m = 600.0
	ai_pilot.target_speed = spawn_speed

	# Build a square patrol: 4 corners, each side = patrol_side_length, centered on carrier
	var half = patrol_side_length / 2.0
	var alt: float = 600.0
	ai_pilot.waypoints.clear()
	ai_pilot.waypoints.append(center + Vector3( half, alt,  half))
	ai_pilot.waypoints.append(center + Vector3(-half, alt,  half))
	ai_pilot.waypoints.append(center + Vector3(-half, alt, -half))
	ai_pilot.waypoints.append(center + Vector3( half, alt, -half))
	# Start at the waypoint most ahead of the aircraft (avoids flying away from first target)
	ai_pilot.current_waypoint_index = _waypoint_most_ahead(aircraft, ai_pilot.waypoints)

	ai_pilot.change_state(AIPilot.State.SEARCH)

func _on_enemy_crashed(_impact_velocity: float, aircraft: RigidBody3D):
	_schedule_respawn(aircraft)

func _on_enemy_destroyed(aircraft: RigidBody3D):
	_schedule_respawn(aircraft)

func _schedule_respawn(aircraft: RigidBody3D):
	if is_instance_valid(aircraft):
		if aircraft.crashed.is_connected(_on_enemy_crashed):
			aircraft.crashed.disconnect(_on_enemy_crashed)
		if aircraft.destroyed.is_connected(_on_enemy_destroyed):
			aircraft.destroyed.disconnect(_on_enemy_destroyed)

	await get_tree().create_timer(respawn_delay).timeout

	if is_instance_valid(aircraft):
		aircraft.queue_free()
	_active_ai_planes.erase(aircraft)
	_prune_active_ai_planes()

	# No automatic respawn — planes are only spawned manually via key press.

func _prune_active_ai_planes():
	_active_ai_planes = _active_ai_planes.filter(func(p): return is_instance_valid(p))

func _spawn_on_approach():
	"""U key: spawn an AI plane at approach_0 (alt 450 m), pointed at approach_1, already in landing mode."""
	var root := get_tree().current_scene
	var wp0 := root.find_child("approach_0", true, false) as Node3D
	var wp1 := root.find_child("approach_1", true, false) as Node3D
	if not wp0 or not wp1:
		print("[EnemyAircraftSpawner] U: approach_0/1 nodes not found in scene")
		return

	if not _aircraft_scene:
		return
	_prune_active_ai_planes()
	if _active_ai_planes.size() >= max_ai_planes:
		print("[EnemyAircraftSpawner] U: max AI planes reached")
		return

	var aircraft = _aircraft_scene.instantiate() as RigidBody3D
	if not aircraft:
		return

	aircraft.name = "FriendlyAI"
	get_tree().current_scene.add_child(aircraft)

	# Place at approach_0 XZ, altitude 450 m, pointed toward approach_1
	var spawn_pos := Vector3(wp0.global_position.x, 450.0, wp0.global_position.z)
	aircraft.global_position = spawn_pos
	var to_wp1 := Vector3(wp1.global_position.x - spawn_pos.x, 0.0, wp1.global_position.z - spawn_pos.z).normalized()
	var yaw := atan2(to_wp1.x, to_wp1.z)
	aircraft.global_rotation = Vector3(0.0, yaw, 0.0)
	aircraft.linear_velocity = to_wp1 * 80.0

	await get_tree().process_frame
	await get_tree().process_frame
	aircraft.remove_from_group("aircraft")
	aircraft.add_to_group("friendlies")
	aircraft.add_to_group("ai_aircraft")

	var disable_nodes = ["CameraController", "HeadsUpDisplay", "InstrumentPanel", "ControlTargeting"]
	for node_name in disable_nodes:
		var node = aircraft.find_child(node_name, true, false)
		if node:
			node.set_process(false)
			node.set_physics_process(false)
			node.set_process_input(false)
			if node is CanvasItem:
				node.visible = false
			elif node is Node3D:
				node.visible = false

	for cam_name in ["CameraCockpit", "CameraChase", "CameraCinematic"]:
		var tripod = aircraft.get_node_or_null(cam_name)
		if tripod:
			tripod.set_process(true)
			tripod.set_physics_process(true)

	# Gear stowed — will be deployed by AIPilot at approach_2
	var control_gear = aircraft.find_child("ControlLandingGear", true, false)
	if control_gear and control_gear.has_method("send_to_landing_gears"):
		control_gear.send_to_landing_gears("stow")
		control_gear.send_to_tailhooks("stow")
		if control_gear.has_method("send_to_tailhook_simple"):
			control_gear.send_to_tailhook_simple(false)
		if "gear_down_state" in control_gear:
			control_gear.gear_down_state = false
		if control_gear.has_method("_set_collider_disabled"):
			control_gear._set_collider_disabled(true)

	if aircraft.has_signal("crashed"):
		aircraft.crashed.connect(_on_enemy_crashed.bind(aircraft))
	if aircraft.has_signal("destroyed"):
		aircraft.destroyed.connect(_on_enemy_destroyed.bind(aircraft))

	_active_ai_planes.append(aircraft)

	await get_tree().create_timer(0.5).timeout
	if not is_instance_valid(aircraft):
		return

	var ai_toggle = aircraft.find_child("AIToggle", true, false)
	if ai_toggle and ai_toggle.has_method("enable_ai"):
		ai_toggle.enable_ai()

	var ai_pilot = aircraft.find_child("AIPilot", true, false)
	if not ai_pilot or not ai_pilot.has_method("start_landing"):
		push_error("[EnemyAircraftSpawner] U: no AIPilot on spawned aircraft")
		return

	# start_landing() finds all waypoints, sets phase 0, enters APPROACH state.
	# Override phase to 1 so it heads straight to approach_1 (we spawned at approach_0).
	var ok: bool = ai_pilot.start_landing()
	if ok:
		ai_pilot._landing_phase = 1
		print("[EnemyAircraftSpawner] U: spawned on approach at approach_0, heading to approach_1")
	else:
		print("[EnemyAircraftSpawner] U: approach waypoints not found — place approach_0..4 in scene")

func _command_land():
	"""L key: tell the currently watched AI plane to begin its carrier landing approach."""
	var switcher = get_tree().get_first_node_in_group("standalone_camera_switcher")
	if not switcher or not switcher.has_method("get_watched_aircraft"):
		print("[EnemyAircraftSpawner] L: camera switcher not found")
		return
	var aircraft: RigidBody3D = switcher.get_watched_aircraft()
	if not aircraft or not is_instance_valid(aircraft):
		print("[EnemyAircraftSpawner] L: no aircraft currently being watched")
		return
	var ai_pilot = aircraft.find_child("AIPilot", true, false)
	if not ai_pilot or not ai_pilot.has_method("start_landing"):
		print("[EnemyAircraftSpawner] L: no AIPilot on watched aircraft")
		return
	var ok: bool = ai_pilot.start_landing()
	if ok:
		print("[EnemyAircraftSpawner] L: landing commanded for ", aircraft.name)
	else:
		print("[EnemyAircraftSpawner] L: approach_0/1/2/3/4 waypoints not found in scene — place them first")

func _toggle_ai_attack_mode():
	"""Toggle all AI planes between patrol mode and attack mode (O key)."""
	var ai_planes = get_tree().get_nodes_in_group("ai_aircraft")
	var pilots: Array[AIPilot] = []
	for node in ai_planes:
		if not is_instance_valid(node):
			continue
		var pilot = node.find_child("AIPilot", true, false)
		if pilot and pilot is AIPilot:
			pilots.append(pilot)
	if pilots.is_empty():
		return
	var new_mode: bool = not pilots[0].ground_attack_enabled
	for pilot in pilots:
		pilot.ground_attack_enabled = new_mode
	var mode_str: String = "ATTACK" if new_mode else "PATROL"
	print("[EnemyAircraftSpawner] AI mode: ", mode_str, " (", pilots.size(), " plane(s))")

func _waypoint_most_ahead(aircraft: Node3D, waypoints: Array) -> int:
	"""Return index of waypoint that is most ahead of aircraft (largest forward dot product)."""
	if waypoints.is_empty():
		return 0
	var fwd := aircraft.global_transform.basis.z
	var best_idx := 0
	var best_dot := -INF
	for i in range(waypoints.size()):
		var wp: Vector3 = waypoints[i]
		var to_wp := (wp - aircraft.global_position).normalized()
		var dot_val := to_wp.dot(fwd)
		if dot_val > best_dot:
			best_dot = dot_val
			best_idx = i
	return best_idx

func _get_carrier_position() -> Vector3:
	var carriers = get_tree().get_nodes_in_group("carrier")
	if carriers.size() > 0 and carriers[0] is Node3D:
		return (carriers[0] as Node3D).global_position
	return Vector3.ZERO

func _get_carrier_forward() -> Vector3:
	var carriers = get_tree().get_nodes_in_group("carrier")
	if carriers.size() > 0 and carriers[0] is Node3D:
		return (carriers[0] as Node3D).global_transform.basis.z.normalized()
	return Vector3(0, 0, 1)
