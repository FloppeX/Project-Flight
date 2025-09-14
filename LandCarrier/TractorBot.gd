extends Node3D
class_name TractorBot

@export var debug_enabled: bool = false

# Optional navigation agent. If not provided, we will steer directly.
@export var nav_agent: NavigationAgent3D

@export var staging_marker: Node3D
@export var approach_distance_m: float = 1.5
@export var cruise_speed_mps: float = 7.0
@export var tow_speed_mps: float = 3.5
@export var accel_mps2: float = 10.0
@export var turn_speed_deg_s: float = 200.0

# Towing connection tuning
@export var towing_force_gain: float = 1.0  # legacy scalar multiplier
@export var tow_kv: float = 2.5             # velocity error gain
@export var tow_kp: float = 3.0             # position error gain
@export var tow_force_limit: float = 300000.0 # max force (N)
@export var hitch_offset_m: float = 1.0     # desired nose gear distance ahead of tractor origin
@export var stand_off_m: float = 2.0        # tractor target stays this far behind the elevator marker
@export var stop_tolerance_m: float = 0.5   # stop when nose gear is within this of destination

enum BotState {
	IDLE,
	MOVING_TO_AIRCRAFT,
	COUPLING,
	TOWING_TO_DESTINATION,
	UNCOUPLING,
	RETURNING_TO_STAGING
}

var _state: BotState = BotState.IDLE
var _job_aircraft: RigidBody3D
var _job_destination: Node3D
var _nose_gear: Node3D

# Internal kinematics
var _current_speed: float = 0.0

func _ready():
	add_to_group("tractor_bot")
	if not nav_agent:
		nav_agent = get_node_or_null("NavAgent") as NavigationAgent3D
	set_physics_process(true)
	if debug_enabled:
		print("[TractorBot] Ready. nav_agent=", nav_agent != null)

func _physics_process(delta: float) -> void:
	match _state:
		BotState.IDLE:
			_tick_idle(delta)
		BotState.MOVING_TO_AIRCRAFT:
			_tick_move_to_aircraft(delta)
		BotState.COUPLING:
			_tick_coupling(delta)
		BotState.TOWING_TO_DESTINATION:
			_tick_towing(delta)
		BotState.UNCOUPLING:
			_tick_uncoupling(delta)
		BotState.RETURNING_TO_STAGING:
			_tick_returning(delta)

func accept_recover_job(aircraft: RigidBody3D, destination_marker: Node3D) -> void:
	if debug_enabled:
		print("[TractorBot] accept_recover_job -> ", aircraft, " -> ", destination_marker)
	_job_aircraft = aircraft
	_job_destination = destination_marker
	if not is_instance_valid(_job_aircraft) or not is_instance_valid(_job_destination):
		if debug_enabled:
			print("[TractorBot] Invalid job parameters.")
		_clear_job()
		return
	_nose_gear = _find_nose_gear_collider(_job_aircraft)
	_state = BotState.MOVING_TO_AIRCRAFT
	_plan_move_to(_get_couple_target())

func _tick_idle(_delta: float) -> void:
	pass

func _tick_move_to_aircraft(delta: float) -> void:
	if not is_instance_valid(_job_aircraft):
		_abort_job("Aircraft invalid while moving to aircraft")
		return
	# Refresh the goal every tick to follow any drift after arrest
	var goal = _get_couple_target()
	_set_nav_target(goal)
	var done = _follow_plan(goal, cruise_speed_mps, delta)
	_face_toward(goal, delta)
	if global_position.distance_to(goal) <= approach_distance_m:
		_state = BotState.COUPLING

func _tick_coupling(_delta: float) -> void:
	if not is_instance_valid(_job_aircraft):
		_abort_job("Aircraft invalid while coupling")
		return
	# Take control of the aircraft and ensure engine is at 0; clear parking brake
	_job_aircraft.set_meta("controls_disabled", true)
	if _job_aircraft.has_meta("parking_brake"):
		_job_aircraft.remove_meta("parking_brake")
	var engine_controller = _find_engine_controller(_job_aircraft)
	if is_instance_valid(engine_controller):
		engine_controller.set("target_power", 0.0)
	var engine = _find_engine(_job_aircraft)
	if is_instance_valid(engine) and engine.has_method("set_throttle_input"):
		engine.set_throttle_input(0.0)
	_state = BotState.TOWING_TO_DESTINATION
	# Start path to destination (tractor target sits stand_off_m behind marker)
	_set_nav_target(_get_tow_tractor_target())

func _tick_towing(delta: float) -> void:
	if not is_instance_valid(_job_aircraft) or not is_instance_valid(_job_destination):
		_abort_job("Invalid towing references")
		return
	# Tractor target each tick so we place the aircraft nose at the elevator marker
	var tractor_goal = _get_tow_tractor_target()
	_set_nav_target(tractor_goal)
	var done = _follow_plan(tractor_goal, tow_speed_mps, delta)
	_face_toward(tractor_goal, delta)
	# Strong towing connection
	_apply_towing_force(delta)
	# Stop condition: nose gear reaches destination marker
	var nose = _find_nose_gear_collider(_job_aircraft)
	if is_instance_valid(nose):
		var nose_to_dest = nose.global_position.distance_to(_job_destination.global_position)
		if nose_to_dest <= stop_tolerance_m:
			_state = BotState.UNCOUPLING

func _tick_uncoupling(_delta: float) -> void:
	if is_instance_valid(_job_aircraft):
		_job_aircraft.remove_meta("controls_disabled")
	_state = BotState.RETURNING_TO_STAGING
	if is_instance_valid(staging_marker):
		_plan_move_to(staging_marker.global_position)
	else:
		_state = BotState.IDLE
		_clear_job()

func _tick_returning(delta: float) -> void:
	if not is_instance_valid(staging_marker):
		_state = BotState.IDLE
		_clear_job()
		return
	var done = _follow_plan(staging_marker.global_position, cruise_speed_mps, delta)
	_face_toward(staging_marker.global_position, delta)
	if global_position.distance_to(staging_marker.global_position) <= 0.5:
		_state = BotState.IDLE
		_clear_job()

func _get_couple_target() -> Vector3:
	if is_instance_valid(_nose_gear):
		var target = _nose_gear.global_position
		target.y = global_position.y
		return target
	if is_instance_valid(_job_aircraft):
		var t = _job_aircraft.global_transform.origin
		t.y = global_position.y
		return t
	return global_position

func _get_tow_tractor_target() -> Vector3:
	var dest = _job_destination.global_position if is_instance_valid(_job_destination) else global_position
	var back = -global_transform.basis.z.normalized()
	var target = dest + back * stand_off_m
	target.y = global_position.y
	return target

func _plan_move_to(target: Vector3) -> void:
	if nav_agent:
		nav_agent.set_target_position(target)

func _set_nav_target(target: Vector3) -> void:
	if nav_agent:
		nav_agent.set_target_position(target)

func _follow_plan(target: Vector3, max_speed: float, delta: float) -> bool:
	var desired_dir: Vector3
	if nav_agent:
		var next_pos = nav_agent.get_next_path_position()
		if (next_pos - global_position).length() < 0.05:
			next_pos = nav_agent.get_target_position()
		desired_dir = (next_pos - global_position)
	else:
		desired_dir = (target - global_position)
	desired_dir.y = 0.0
	var dist = desired_dir.length()
	if dist < 0.01:
		_current_speed = 0.0
		return true
	desired_dir = desired_dir.normalized()
	# Basic accel/decel
	var target_speed = clamp(max_speed, 0.0, max_speed)
	_current_speed = clamp(_current_speed + accel_mps2 * delta, 0.0, target_speed)
	global_position += desired_dir * _current_speed * delta
	return false

func _face_toward(target: Vector3, delta: float) -> void:
	var dir = target - global_position
	dir.y = 0.0
	if dir.length() < 0.001:
		return
	dir = dir.normalized()
	var basis = global_transform.basis
	var forward = basis.z
	var angle_to = forward.signed_angle_to(dir, Vector3.UP)
	var max_turn = deg_to_rad(turn_speed_deg_s) * delta
	angle_to = clamp(angle_to, -max_turn, max_turn)
	rotate_y(angle_to)

func _apply_towing_force(_delta: float) -> void:
	if not is_instance_valid(_job_aircraft):
		return
	var dt = max(get_physics_process_delta_time(), 0.001)
	var desired_velocity = (global_transform.basis.z) * _current_speed
	var current_velocity = _job_aircraft.linear_velocity
	var velocity_error = desired_velocity - current_velocity
	var nose = _find_nose_gear_collider(_job_aircraft)
	var pos_error = Vector3.ZERO
	if is_instance_valid(nose):
		var hitch_target = global_transform.origin + global_transform.basis.z * hitch_offset_m
		pos_error = hitch_target - nose.global_position
	# PD acceleration
	var accel_vec = tow_kv * velocity_error + tow_kp * pos_error
	# Convert to force and clamp
	var force = _job_aircraft.mass * accel_vec / dt
	force *= towing_force_gain
	if force.length() > tow_force_limit:
		force = force.normalized() * tow_force_limit
	var force_position = (nose.global_position - _job_aircraft.global_position) if is_instance_valid(nose) else Vector3.ZERO
	if is_instance_valid(nose):
		_job_aircraft.apply_force(force, force_position)
	else:
		_job_aircraft.apply_central_force(force)

func _clear_job() -> void:
	_job_aircraft = null
	_job_destination = null
	_nose_gear = null

# --- Helpers (reused patterns from catapult) ---
func _find_engine_controller(root: Node) -> Node:
	for child in root.get_children():
		if child.get_script() and child.get_script().resource_path.ends_with("ControlEngine.gd"):
			return child
		var found = _find_engine_controller(child)
		if found:
			return found
	return null

func _find_engine(root: Node) -> Node:
	for child in root.get_children():
		if child.get_script() and child.get_script().resource_path.ends_with("Engine.gd"):
			return child
		var found = _find_engine(child)
		if found:
			return found
	return null

func _find_nose_gear_collider(root: Node) -> Node3D:
	var nodes_in_group = root.get_tree().get_nodes_in_group("nose_gear_latch_point")
	for node in nodes_in_group:
		if node.get_owner() == root:
			return node
	var found = root.find_child("CenterGearCollider", true, false)
	if is_instance_valid(found):
		return found
	found = root.find_child("*NoseGear*", true, false)
	if is_instance_valid(found):
		return found
	return null

func _abort_job(reason: String) -> void:
	if debug_enabled:
		print("[TractorBot] Aborting job: ", reason)
	_state = BotState.IDLE
	_clear_job()
