extends Node
class_name HelicopterPilot

enum State {
	IDLE,
	TAKEOFF,
	LOW_LEVEL_TRANSIT,
	HOVER,
	LANDING,
}

@export_group("References")
@export var helicopter_flight_path: NodePath
@export var control_engine_path: NodePath
@export var target_node_path: NodePath

@export_group("Low-Level Navigation")
@export var cruise_agl_m: float = 55.0
@export var takeoff_agl_m: float = 35.0
@export var min_terrain_clearance_m: float = 24.0
@export var terrain_lookahead_m: float = 260.0
@export var terrain_sample_spacing_m: float = 45.0
@export var corridor_angle_deg: float = 35.0
@export var waypoint_accept_radius_m: float = 35.0
@export var default_patrol_distance_m: float = 700.0
@export var replan_interval_s: float = 0.35

@export_group("Flight")
@export var cruise_speed_mps: float = 30.0
@export var max_speed_mps: float = 42.0
@export var hover_speed_mps: float = 4.0
@export var max_climb_mps: float = 7.0
@export var max_descent_mps: float = 4.0
@export var collective_trim: float = 0.58
@export var collective_alt_gain: float = 0.018
@export var collective_vertical_damping: float = 0.065
@export var collective_speed_lift_bias: float = 0.08
@export var takeoff_collective_min: float = 0.82
@export var takeoff_deck_release_margin: float = 0.06

@export_group("Controls")
@export var cyclic_velocity_gain: float = 0.045
@export var cyclic_position_gain: float = 0.008
@export var cyclic_response_hz: float = 1.8
@export var yaw_gain: float = 1.45
@export var yaw_rate_damping: float = 0.018
@export var yaw_response_hz: float = 2.2

@export_group("Debug")
@export var debug_enabled: bool = false
@export var debug_interval_s: float = 1.0

var aircraft: RigidBody3D = null
var helicopter_flight: Node = null
var control_engine: Node = null
var engine: Node = null
var target_node: Node3D = null
var state: State = State.IDLE

var destination: Vector3 = Vector3.ZERO
var _has_destination: bool = false
var _nav_waypoint: Vector3 = Vector3.ZERO
var _desired_altitude_m: float = 0.0
var _pitch_cmd: float = 0.0
var _roll_cmd: float = 0.0
var _yaw_cmd: float = 0.0
var _replan_timer_s: float = 0.0
var _debug_timer_s: float = 0.0

func _ready() -> void:
	add_to_group("origin_shifter")
	set_physics_process(false)


func apply_origin_shift(offset: Vector3) -> void:
	destination -= offset
	_nav_waypoint -= offset


func initialize(aircraft_node: RigidBody3D) -> void:
	aircraft = aircraft_node
	if not is_instance_valid(aircraft):
		push_error("[HelicopterPilot] Parent aircraft is not valid.")
		return

	_find_modules()
	if helicopter_flight == null or control_engine == null:
		push_error("[HelicopterPilot] Missing HelicopterFlight or ControlEngine module.")
		set_physics_process(false)
		return

	_apply_ai_groups()
	_choose_initial_destination()
	_replan_timer_s = 0.0
	_debug_timer_s = 0.0

	var ground_height: float = _get_ground_height_at_position(aircraft.global_position)
	var agl: float = aircraft.global_position.y - ground_height if not is_nan(ground_height) else aircraft.global_position.y
	if bool(aircraft.get_meta("parking_brake", false)) or agl < takeoff_agl_m:
		change_state(State.TAKEOFF)
	else:
		change_state(State.LOW_LEVEL_TRANSIT)
	set_physics_process(true)


func deinitialize() -> void:
	_set_helicopter_input(0.0, 0.0, 0.0)
	_pitch_cmd = 0.0
	_roll_cmd = 0.0
	_yaw_cmd = 0.0
	set_physics_process(false)


func change_state(new_state: State) -> void:
	if state == new_state:
		return
	state = new_state


func set_destination(world_position: Vector3) -> void:
	destination = world_position
	_has_destination = true
	if state == State.IDLE or state == State.HOVER:
		change_state(State.LOW_LEVEL_TRANSIT)


func command_hover(world_position: Variant = null) -> void:
	if world_position is Vector3:
		var hover_position: Vector3 = world_position
		destination = hover_position
		_has_destination = true
	elif is_instance_valid(aircraft):
		destination = aircraft.global_position
		_has_destination = true
	change_state(State.HOVER)


func command_land(world_position: Variant = null) -> void:
	if world_position is Vector3:
		var landing_position: Vector3 = world_position
		destination = landing_position
		_has_destination = true
	elif is_instance_valid(aircraft):
		destination = aircraft.global_position
		_has_destination = true
	change_state(State.LANDING)


func launch() -> void:
	change_state(State.TAKEOFF)


func _physics_process(delta: float) -> void:
	if not is_instance_valid(aircraft):
		set_physics_process(false)
		return
	if aircraft.get_meta("controls_disabled", false):
		return

	_replan_timer_s -= delta
	if _replan_timer_s <= 0.0:
		_replan_timer_s = maxf(replan_interval_s, 0.05)
		_update_navigation_plan()

	match state:
		State.IDLE:
			_apply_collective(0.0)
			_set_helicopter_input(0.0, 0.0, 0.0)
		State.TAKEOFF:
			_fly_toward(_nav_waypoint, cruise_speed_mps * 0.45, delta)
			if aircraft.global_position.y >= _desired_altitude_m - 4.0:
				change_state(State.LOW_LEVEL_TRANSIT)
		State.LOW_LEVEL_TRANSIT:
			_fly_toward(_nav_waypoint, cruise_speed_mps, delta)
			if _has_destination and _flat_distance(aircraft.global_position, destination) <= waypoint_accept_radius_m:
				change_state(State.HOVER)
		State.HOVER:
			_fly_toward(destination if _has_destination else aircraft.global_position, hover_speed_mps, delta)
		State.LANDING:
			_fly_toward(destination if _has_destination else aircraft.global_position, hover_speed_mps, delta)
			_try_finish_landing()

	_emit_debug(delta)


func _find_modules() -> void:
	if helicopter_flight_path != NodePath():
		helicopter_flight = get_node_or_null(helicopter_flight_path)
	if helicopter_flight == null:
		helicopter_flight = _find_module_by_name("HelicopterFlight")
	if helicopter_flight == null:
		helicopter_flight = aircraft.find_child("HelicopterFlight", true, false)

	if control_engine_path != NodePath():
		control_engine = get_node_or_null(control_engine_path)
	if control_engine == null:
		control_engine = _find_module_by_name("ControlEngine")
	if control_engine == null:
		control_engine = aircraft.find_child("ControlEngine", true, false)

	engine = _find_module_by_name("Engine")
	if engine == null:
		engine = aircraft.find_child("Engine", true, false)

	if target_node_path != NodePath():
		target_node = get_node_or_null(target_node_path) as Node3D


func _find_module_by_name(module_name: String) -> Node:
	if not is_instance_valid(aircraft):
		return null
	if aircraft.has_method("find_modules_by_type"):
		var modules_variant: Variant = aircraft.call("find_modules_by_type", module_name)
		if not (modules_variant is Array):
			modules_variant = []
		var modules: Array = modules_variant as Array
		if not modules.is_empty():
			return modules[0] as Node
	return _find_node_by_script_name(aircraft, module_name)


func _find_node_by_script_name(root: Node, script_name: String) -> Node:
	for child in root.get_children():
		var script_obj: Script = child.get_script()
		if script_obj != null and script_obj.resource_path.ends_with(script_name + ".gd"):
			return child
		var result: Node = _find_node_by_script_name(child, script_name)
		if result != null:
			return result
	return null


func _apply_ai_groups() -> void:
	if not is_instance_valid(aircraft):
		return
	if not aircraft.is_in_group("aircraft"):
		aircraft.add_to_group("aircraft")
	if not aircraft.is_in_group("ai_aircraft"):
		aircraft.add_to_group("ai_aircraft")

	var my_team: int = aircraft.get_team() if aircraft.has_method("get_team") else 1
	if my_team == 1:
		if not aircraft.is_in_group("friendlies"):
			aircraft.add_to_group("friendlies")
		if aircraft.is_in_group("enemies"):
			aircraft.remove_from_group("enemies")
	else:
		if not aircraft.is_in_group("enemies"):
			aircraft.add_to_group("enemies")
		if aircraft.is_in_group("friendlies"):
			aircraft.remove_from_group("friendlies")


func _choose_initial_destination() -> void:
	if target_node != null and is_instance_valid(target_node):
		set_destination(target_node.global_position)
		return
	if _has_destination:
		return
	var forward: Vector3 = aircraft.global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.001:
		forward = Vector3.FORWARD
	forward = forward.normalized()
	destination = aircraft.global_position + forward * default_patrol_distance_m
	_has_destination = true


func _update_navigation_plan() -> void:
	if not _has_destination:
		_choose_initial_destination()

	var current_pos: Vector3 = aircraft.global_position
	var goal: Vector3 = destination
	if state == State.TAKEOFF:
		goal = current_pos
	elif state == State.HOVER:
		goal = destination if _has_destination else current_pos
	elif state == State.LANDING:
		goal = destination if _has_destination else current_pos

	var ground_height: float = _get_ground_height_at_position(current_pos)
	var base_ground: float = ground_height if not is_nan(ground_height) else current_pos.y - cruise_agl_m
	var requested_agl: float = cruise_agl_m
	if state == State.TAKEOFF:
		requested_agl = takeoff_agl_m
	elif state == State.LANDING:
		requested_agl = 4.0
	_desired_altitude_m = base_ground + requested_agl

	if state == State.LANDING:
		_nav_waypoint = Vector3(goal.x, _desired_altitude_m, goal.z)
		return

	var selected_dir: Vector3 = _choose_low_level_corridor(current_pos, goal)
	var lookahead_distance: float = minf(terrain_lookahead_m, maxf(_flat_distance(current_pos, goal), 80.0))
	var candidate: Vector3 = current_pos + selected_dir * lookahead_distance
	if _flat_distance(current_pos, goal) <= lookahead_distance:
		candidate = goal

	var corridor_height: float = _sample_max_terrain_height_along_path(current_pos, candidate)
	if not is_nan(corridor_height):
		_desired_altitude_m = maxf(_desired_altitude_m, corridor_height + min_terrain_clearance_m)
	_nav_waypoint = Vector3(candidate.x, _desired_altitude_m, candidate.z)


func _choose_low_level_corridor(current_pos: Vector3, goal: Vector3) -> Vector3:
	var direct: Vector3 = goal - current_pos
	direct.y = 0.0
	if direct.length_squared() < 1.0:
		direct = aircraft.linear_velocity
		direct.y = 0.0
	if direct.length_squared() < 1.0:
		direct = aircraft.global_transform.basis.z
		direct.y = 0.0
	if direct.length_squared() < 0.001:
		return Vector3.FORWARD
	direct = direct.normalized()

	var angles: PackedFloat32Array = PackedFloat32Array([
		0.0,
		deg_to_rad(corridor_angle_deg),
		-deg_to_rad(corridor_angle_deg),
		deg_to_rad(corridor_angle_deg * 2.0),
		-deg_to_rad(corridor_angle_deg * 2.0),
	])
	var best_dir: Vector3 = direct
	var best_score: float = INF
	for angle in angles:
		var dir: Vector3 = direct.rotated(Vector3.UP, angle).normalized()
		var sample_end: Vector3 = current_pos + dir * terrain_lookahead_m
		var terrain_h: float = _sample_max_terrain_height_along_path(current_pos, sample_end)
		var destination_bias: float = _flat_distance(sample_end, goal) * 0.035
		var turn_bias: float = absf(angle) * 12.0
		var height_score: float = terrain_h if not is_nan(terrain_h) else current_pos.y
		var score: float = height_score + destination_bias + turn_bias
		if score < best_score:
			best_score = score
			best_dir = dir
	return best_dir


func _fly_toward(target: Vector3, desired_speed: float, delta: float) -> void:
	var current_pos: Vector3 = aircraft.global_position
	var to_target: Vector3 = target - current_pos
	var horizontal_to_target: Vector3 = Vector3(to_target.x, 0.0, to_target.z)
	var target_dir: Vector3 = Vector3.ZERO
	if horizontal_to_target.length_squared() > 1.0:
		target_dir = horizontal_to_target.normalized()

	var speed_limit: float = clampf(desired_speed, 0.0, max_speed_mps)
	var distance_t: float = clampf(horizontal_to_target.length() / maxf(waypoint_accept_radius_m * 2.0, 1.0), 0.25, 1.0)
	if state == State.HOVER or state == State.LANDING:
		speed_limit = minf(speed_limit, lerpf(1.5, hover_speed_mps, distance_t))
	var desired_velocity: Vector3 = target_dir * speed_limit
	var velocity_error: Vector3 = desired_velocity - aircraft.linear_velocity
	velocity_error.y = 0.0

	var basis: Basis = aircraft.global_transform.basis
	var forward: Vector3 = basis.z
	forward.y = 0.0
	forward = forward.normalized() if forward.length_squared() > 0.001 else Vector3.FORWARD
	var right: Vector3 = basis.x
	right.y = 0.0
	right = right.normalized() if right.length_squared() > 0.001 else Vector3.RIGHT

	var pos_forward_error: float = horizontal_to_target.dot(forward) * cyclic_position_gain
	var pos_right_error: float = horizontal_to_target.dot(right) * cyclic_position_gain
	var vel_forward_error: float = velocity_error.dot(forward) * cyclic_velocity_gain
	var vel_right_error: float = velocity_error.dot(right) * cyclic_velocity_gain

	var target_pitch: float = clampf(-(vel_forward_error + pos_forward_error), -1.0, 1.0)
	var target_roll: float = clampf(vel_right_error + pos_right_error, -1.0, 1.0)
	var cyclic_t: float = clampf(cyclic_response_hz * delta, 0.0, 1.0)
	_pitch_cmd = lerpf(_pitch_cmd, target_pitch, cyclic_t)
	_roll_cmd = lerpf(_roll_cmd, target_roll, cyclic_t)

	var desired_heading: Vector3 = target_dir
	if desired_heading.length_squared() < 0.001:
		desired_heading = forward
	var yaw_error: float = forward.signed_angle_to(desired_heading, Vector3.UP)
	var yaw_rate: float = aircraft.angular_velocity.y
	var target_yaw: float = clampf(yaw_error * yaw_gain - yaw_rate * yaw_rate_damping, -1.0, 1.0)
	var yaw_t: float = clampf(yaw_response_hz * delta, 0.0, 1.0)
	_yaw_cmd = lerpf(_yaw_cmd, target_yaw, yaw_t)

	_set_helicopter_input(_pitch_cmd, _roll_cmd, _yaw_cmd)
	_apply_collective(_calculate_collective(target.y))


func _calculate_collective(target_altitude_m: float) -> float:
	var altitude_error: float = target_altitude_m - aircraft.global_position.y
	var vertical_velocity: float = aircraft.linear_velocity.y
	var climb_command: float = clampf(altitude_error * 0.35, -max_descent_mps, max_climb_mps)
	var collective: float = collective_trim
	collective += climb_command * collective_alt_gain
	collective -= vertical_velocity * collective_vertical_damping
	var horizontal_speed: float = Vector2(aircraft.linear_velocity.x, aircraft.linear_velocity.z).length()
	collective += clampf(horizontal_speed / maxf(max_speed_mps, 1.0), 0.0, 1.0) * collective_speed_lift_bias
	if state == State.TAKEOFF:
		collective = maxf(collective, _get_takeoff_collective_floor())
	if state == State.LANDING:
		collective = minf(collective, 0.48)
	return clampf(collective, 0.0, 1.0)


func _get_takeoff_collective_floor() -> float:
	var floor_value: float = clampf(takeoff_collective_min, 0.0, 1.0)
	if aircraft == null or not bool(aircraft.get_meta("helicopter_deck_takeoff_ready", false)):
		return floor_value
	if helicopter_flight != null:
		var release_variant: Variant = helicopter_flight.get("deck_takeoff_brake_release_collective")
		if release_variant != null:
			floor_value = maxf(floor_value, float(release_variant) + maxf(takeoff_deck_release_margin, 0.0))
	return clampf(floor_value, 0.0, 1.0)


func _apply_collective(value: float) -> void:
	var clamped_value: float = clampf(value, 0.0, 1.0)
	if control_engine != null and control_engine.has_method("set_target_power"):
		control_engine.call("set_target_power", clamped_value)
		return
	if engine != null and engine.has_method("engine_set_power"):
		engine.call("engine_set_power", clamped_value)


func _set_helicopter_input(pitch: float, roll: float, yaw: float) -> void:
	if helicopter_flight == null:
		return
	helicopter_flight.set("pitch_input", clampf(pitch, -1.0, 1.0))
	helicopter_flight.set("roll_input", clampf(roll, -1.0, 1.0))
	helicopter_flight.set("yaw_input", clampf(yaw, -1.0, 1.0))


func _try_finish_landing() -> void:
	var ground_height: float = _get_ground_height_at_position(aircraft.global_position)
	if is_nan(ground_height):
		return
	var agl: float = aircraft.global_position.y - ground_height
	if agl <= 2.0 and aircraft.linear_velocity.length() < 3.0:
		_apply_collective(0.0)
		change_state(State.IDLE)


func _get_ground_height_at_position(world_pos: Vector3) -> float:
	var nav_grid: Node = get_node_or_null("/root/TerrainNavGrid")
	if nav_grid != null and nav_grid.has_method("sample_query_height"):
		var query_h_variant: Variant = nav_grid.call("sample_query_height", world_pos.x, world_pos.z)
		var query_h: float = float(query_h_variant)
		if query_h > -500000.0:
			return query_h
	if nav_grid != null and nav_grid.has_method("sample_height"):
		var grid_h_variant: Variant = nav_grid.call("sample_height", world_pos.x, world_pos.z)
		var grid_h: float = float(grid_h_variant)
		if grid_h > -500000.0:
			return grid_h

	var terrain: Node = TerrainReference.get_terrain_node()
	if terrain != null and is_instance_valid(terrain):
		if terrain.has_method("get_height"):
			var h_variant: Variant = terrain.call("get_height", world_pos)
			return float(h_variant)
		if "data" in terrain:
			var data_variant: Variant = terrain.get("data")
			if data_variant is Object:
				var data_object: Object = data_variant as Object
				if data_object.has_method("get_height"):
					var data_h_variant: Variant = data_object.call("get_height", world_pos)
					return float(data_h_variant)

	var space_state: PhysicsDirectSpaceState3D = aircraft.get_world_3d().direct_space_state
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		world_pos + Vector3.UP * 2000.0,
		world_pos + Vector3.DOWN * 6000.0
	)
	query.exclude = [aircraft.get_rid()]
	var result: Dictionary = space_state.intersect_ray(query)
	if result.has("position"):
		var hit_position: Vector3 = result["position"]
		return hit_position.y
	return NAN


func _sample_max_terrain_height_along_path(from_pos: Vector3, to_pos: Vector3) -> float:
	var distance: float = _flat_distance(from_pos, to_pos)
	var sample_count: int = maxi(int(ceil(distance / maxf(terrain_sample_spacing_m, 1.0))), 1)
	var max_height: float = -INF
	var found_height: bool = false
	for i in range(sample_count + 1):
		var t: float = float(i) / float(sample_count)
		var sample_pos: Vector3 = from_pos.lerp(to_pos, t)
		var h: float = _get_ground_height_at_position(sample_pos)
		if is_nan(h):
			continue
		max_height = maxf(max_height, h)
		found_height = true
	return max_height if found_height else NAN


func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _emit_debug(delta: float) -> void:
	if not debug_enabled:
		return
	_debug_timer_s -= delta
	if _debug_timer_s > 0.0:
		return
	_debug_timer_s = maxf(debug_interval_s, 0.1)
	var ground_height: float = _get_ground_height_at_position(aircraft.global_position)
	var agl: float = aircraft.global_position.y - ground_height if not is_nan(ground_height) else NAN
	print(
		"HELI_AI state=", _state_name(),
		" pos=", aircraft.global_position.snapped(Vector3.ONE * 0.1),
		" dest=", destination.snapped(Vector3.ONE * 0.1),
		" wp=", _nav_waypoint.snapped(Vector3.ONE * 0.1),
		" agl=", snapped(agl, 0.1),
		" target_alt=", snapped(_desired_altitude_m, 0.1),
		" speed=", snapped(aircraft.linear_velocity.length(), 0.1),
		" pitch=", snapped(_pitch_cmd, 0.01),
		" roll=", snapped(_roll_cmd, 0.01),
		" yaw=", snapped(_yaw_cmd, 0.01)
	)


func _state_name() -> String:
	match state:
		State.IDLE:
			return "IDLE"
		State.TAKEOFF:
			return "TAKEOFF"
		State.LOW_LEVEL_TRANSIT:
			return "LOW_LEVEL_TRANSIT"
		State.HOVER:
			return "HOVER"
		State.LANDING:
			return "LANDING"
	return "UNKNOWN"
