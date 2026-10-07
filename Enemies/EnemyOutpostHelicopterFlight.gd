extends EnemyVirtualFlight
## Outpost-owned Aircraft 13 section. Uses the shared physical helicopter pilot.

const CRUISE_SPEED := 30.0
const CRUISE_CLEARANCE := 140.0
const CONTACT_RANGE := 4000.0

func _carrier_report_delay_s() -> float:
	return 15.0

func capture_save_state() -> Dictionary:
	var state := super.capture_save_state()
	state["flight_kind"] = "outpost_helicopter"
	return state

func _generate_patrol_waypoints(start_angle: float) -> void:
	super._generate_patrol_waypoints(start_angle)
	for i in _patrol_waypoints.size():
		_patrol_waypoints[i] = _above_terrain(_patrol_waypoints[i])

func _above_terrain(point: Vector3) -> Vector3:
	var height := EnemyOutpost.sample_terrain_height(point.x, point.z)
	point.y = maxf(home_position.y, height) + CRUISE_CLEARANCE if is_finite(height) and height > TerrainNavGrid.IMPASSABLE * 0.5 else home_position.y + CRUISE_CLEARANCE
	return point

func _tick_patrol(delta: float) -> void:
	if _patrol_waypoints.is_empty(): _generate_patrol_waypoints(0.0)
	var target := _patrol_waypoints[_patrol_wp_idx]
	if position.distance_to(target) < 200.0:
		_patrol_wp_idx = (_patrol_wp_idx + 1) % _patrol_waypoints.size()
		return
	_move_virtual_toward(target, CRUISE_SPEED, delta)

func _move_virtual_toward(target: Vector3, _speed_mps: float, delta: float) -> void:
	var direction := (target - position).normalized()
	position = _above_terrain(position.move_toward(target, CRUISE_SPEED * delta))
	heading = Vector3(direction.x, 0, direction.z).normalized()

func _build_investigation_route(slot_offset: int = 0) -> Array[Vector3]:
	var route := super._build_investigation_route(slot_offset)
	for i in route.size(): route[i] = _above_terrain(route[i])
	return route

func _configure_materialized_enemy_aircraft(ac: Node3D, loadout: String = "rockets", slot_idx: int = 0) -> void:
	var pilot := ac.get_node("HelicopterPilot") as HelicopterPilot
	pilot.set_outpost_patrol_route(_route_for_slot(slot_idx))
	pilot.cruise_agl_m = CRUISE_CLEARANCE
	pilot.cruise_speed_mps = CRUISE_SPEED
	pilot.heightmap_path_target_agl_m = CRUISE_CLEARANCE
	super._configure_materialized_enemy_aircraft(ac, loadout, slot_idx)
	# This aircraft was already flying in the virtual simulation. Resume with
	# lift available immediately, rather than cold-starting during free fall.
	var trim := pilot._get_collective_trim()
	if pilot.engine != null:
		pilot.engine.set("is_engine_working", true)
		pilot.engine.set("current_power", trim)
		pilot.engine.set("target_power", trim)
	ac.get_node("SimpleAero").prime_airborne_rotor()
	pilot._collective_cmd = trim
	if pilot.control_engine != null:
		pilot.control_engine.set_target_power(trim)
	if ac is RigidBody3D:
		ac.linear_velocity = heading * CRUISE_SPEED
	# The authored helicopter faces local +Z, as does its flight controller.
	ac.rotation.y = atan2(heading.x, heading.z)

func _route_for_slot(slot: int) -> Array[Vector3]:
	var route: Array[Vector3] = []
	var source := _build_investigation_route() if mission == Mission.INVESTIGATE else _patrol_waypoints
	for i in source.size():
		var point := source[(i + _patrol_wp_idx) % source.size()]
		# Nearby parallel tracks keep the section together without a shared point.
		point += Vector3(float(slot) * 90.0, float(slot) * 15.0, float(slot) * -60.0)
		route.append(point)
	return route

func _apply_investigation_routes_to_active_aircraft() -> void:
	_apply_patrol_routes_to_active_aircraft()

func _apply_patrol_routes_to_active_aircraft() -> void:
	for i in active_aircraft.size():
		var ac := active_aircraft[i]
		if is_instance_valid(ac):
			var pilot := ac.get_node("HelicopterPilot") as HelicopterPilot
			pilot.set_outpost_patrol_route(_route_for_slot(i))

func _scan_for_contacts(immediate: bool) -> void:
	var seen: Dictionary = {}
	for group in ["carrier", "ground_vehicles"]:
		for target in get_tree().get_nodes_in_group(group):
			if not is_instance_valid(target) or not target is Node3D or target.is_in_group("enemies"): continue
			if target.has_method("get_team") and target.get_team() != 1: continue
			if seen.has(target.get_instance_id()): continue
			# Not all surface units expose this optional flag; bool(null) errors.
			var destroyed: Variant = target.get("is_destroyed")
			if destroyed is bool and destroyed: continue
			seen[target.get_instance_id()] = true
			if position.distance_to(target.global_position) > CONTACT_RANGE: continue
			var visible := true
			var end: Vector3 = target.global_position + Vector3.UP * 3.0
			var steps := maxi(1, int(ceil(position.distance_to(end) / 40.0)))
			for step in range(1, steps):
				var point := position.lerp(end, float(step) / steps)
				var height := EnemyOutpost.sample_terrain_height(point.x, point.z)
				if not is_finite(height) or height <= TerrainNavGrid.IMPASSABLE * 0.5 or height > point.y:
					visible = false
					break
			if visible:
				_queue_report("carrier" if group == "carrier" else "ground", target.global_position, 1, 0.0 if immediate else 15.0)
