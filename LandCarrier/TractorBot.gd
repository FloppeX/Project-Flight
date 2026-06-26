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
@export var turn_in_place_deg: float = 25.0

# Towing connection tuning
@export var towing_force_gain: float = 1.0	# legacy scalar multiplier
@export var tow_kv: float = 2.5				# velocity error gain
@export var tow_kp: float = 3.0				# position error gain
@export var tow_force_limit: float = 300000.0	# max force (N)
@export var tow_force_smoothing_s: float = 0.2	# low-pass filter time (s)
@export var hitch_offset_m: float = 1.0		# desired nose gear distance ahead of tractor origin
@export var stand_off_m: float = 2.0			# tractor target stays this far behind the elevator marker
@export var stop_tolerance_m: float = 0.5		# stop when nose gear is within this of destination

# Arm (optional)
@export var arm_node_path: NodePath = "TowArm"
@export var arm_extended_z: float = 1.3
@export var arm_retracted_z: float = 0.3
@export var arm_extend_distance_m: float = 3.0
@export var arm_length_m: float = 1.0
@export var hitch_separation_m: float = 0.15

# Rope mode
@export var use_rope_mode: bool = true
@export var rope_length_m: float = 2.0
@export var rope_anchor_path: NodePath = "RopeAnchor"
@export var approach_a_marker: Node3D
@export var approach_b_marker: Node3D
@export var elevator_marker: Node3D
@export var disconnect_distance_m: float = 1.0

@export var center_stop_tolerance_m: float = 1.0
@export var arm_extend_time_s: float = 0.4
@export var min_tow_time_s: float = 1.0

var _arm_extending: bool = false
var _arm_extended_flag: bool = false
var _arm_extend_elapsed: float = 0.0
var _reverse_mode: bool = false
var _arm_node: Node3D
var _arm_tip: Node3D
var _prev_force: Vector3 = Vector3.ZERO
var _tow_elapsed: float = 0.0
var _hitch_body: Node3D
var _joint: PinJoint3D
var _rope_anchor: Node3D
var _rope_active: bool = true
var _tow_phase: int = 0	# 0: to A, 1: to B
var _latched: bool = false
var _carrier_node: Node3D = null
var _aircraft_carrier_local_basis: Basis = Basis.IDENTITY
var _has_aircraft_carrier_local_basis: bool = false

enum BotState {
	IDLE,
	MOVING_TO_AIRCRAFT,
	COUPLING,
	TOWING_TO_DESTINATION,
	DISCONNECTING,
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
	physics_interpolation_mode = Node3D.PHYSICS_INTERPOLATION_MODE_ON
	if not nav_agent:
		nav_agent = get_node_or_null("NavAgent") as NavigationAgent3D
	_arm_node = get_node_or_null(arm_node_path) as Node3D
	_arm_tip = _arm_node.get_node_or_null("Tip") as Node3D if is_instance_valid(_arm_node) else null
	_hitch_body = get_node_or_null("TowArm/HitchBody") as Node3D
	_rope_anchor = get_node_or_null(rope_anchor_path) as Node3D
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
		BotState.DISCONNECTING:
			_tick_disconnecting(delta)
		BotState.UNCOUPLING:
			_tick_uncoupling(delta)
		BotState.RETURNING_TO_STAGING:
			_tick_returning(delta)

func accept_recover_job(aircraft: RigidBody3D, destination_marker: Node3D) -> void:
	if debug_enabled:
		print("[TractorBot] accept_recover_job -> ", aircraft, " -> ", destination_marker)
	_job_aircraft = aircraft
	_job_destination = destination_marker
	if elevator_marker == null:
		elevator_marker = destination_marker
	if not is_instance_valid(_job_aircraft) or not is_instance_valid(_job_destination):
		if debug_enabled:
			print("[TractorBot] Invalid job parameters.")
		_clear_job()
		return
	_nose_gear = _find_nose_gear_collider(_job_aircraft)
	_reverse_mode = false
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
	# Face toward aircraft while approaching
	_face_toward(_get_nose_pos_or(goal), delta)
	if not use_rope_mode:
		_update_arm_extension(goal)
	if global_position.distance_to(goal) <= approach_distance_m:
		# Enter coupling only if not already latched
		if not _latched:
			_state = BotState.COUPLING

func _tick_coupling(_delta: float) -> void:
	if not is_instance_valid(_job_aircraft):
		_abort_job("Aircraft invalid while coupling")
		return
	# Stop movement and prepare connector (rope or arm)
	_current_speed = 0.0
	var nose = _find_nose_gear_collider(_job_aircraft)
	if not use_rope_mode:
		if is_instance_valid(_arm_node) and is_instance_valid(nose):
			var nose_pos = nose.global_position
			nose_pos.y = _arm_node.global_transform.origin.y
			_arm_node.look_at(nose_pos, Vector3.UP)
		if not _arm_extending and not _arm_extended_flag:
			_arm_extending = true
			_arm_extend_elapsed = 0.0
		if _arm_extending and is_instance_valid(_arm_node):
			_arm_extend_elapsed += _delta
			var t = clamp(_arm_extend_elapsed / max(arm_extend_time_s, 0.001), 0.0, 1.0)
			var tr = _arm_node.transform
			tr.origin.z = lerp(arm_retracted_z, arm_extended_z, t)
			_arm_node.transform = tr
			if t >= 1.0:
				_arm_extending = false
				_arm_extended_flag = true
	# Latch and start towing
	if (not use_rope_mode and _arm_extended_flag) or (use_rope_mode and is_instance_valid(nose)):
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
		if not use_rope_mode:
			_create_hitch_joint()
		_latched = true
		_capture_aircraft_carrier_rotation()
	_state = BotState.TOWING_TO_DESTINATION
	_reverse_mode = true
	_tow_elapsed = 0.0
	_rope_active = true
	_tow_phase = 0
	# Start path to destination (tractor target sits stand_off_m behind marker)
	_set_nav_target(_get_tow_tractor_target())

func _tick_towing(delta: float) -> void:
	if not is_instance_valid(_job_aircraft) or not is_instance_valid(_job_destination):
		_abort_job("Invalid towing references")
		return
	_sync_aircraft_rotation_to_carrier()
	# Tractor target each tick per phase
	var tractor_goal = _get_tow_tractor_target()
	_set_nav_target(tractor_goal)
	# Slow down gently as the aircraft nears destination
	var local_tow_speed = tow_speed_mps
	var ac_center = _job_aircraft.global_transform.origin
	var dist_center = _horizontal_distance(ac_center, (elevator_marker.global_position if is_instance_valid(elevator_marker) else _job_destination.global_position))
	if _tow_phase == 1:
		# approach B slowly
		local_tow_speed = max(1.0, tow_speed_mps * 0.5)
	elif dist_center < 3.0:
		local_tow_speed = max(1.0, tow_speed_mps * 0.7)
	var done = _follow_plan(tractor_goal, local_tow_speed, delta, false)
	# Face the aircraft while reversing to maintain alignment and avoid spinning around goal
	_face_toward(_get_nose_pos_or(tractor_goal), delta)
	# Keep arm fully extended while towing (arm mode only)
	if not use_rope_mode and is_instance_valid(_arm_node):
		var tr = _arm_node.transform
		tr.origin.z = arm_extended_z
		_arm_node.transform = tr
	# If no joint in arm mode, apply force; in rope mode apply force only when rope is active
	if use_rope_mode:
		_apply_towing_force(delta)
	else:
		if _joint == null or not is_instance_valid(_joint):
			_apply_towing_force(delta)
	_tow_elapsed += delta
	# Stop condition: aircraft center near marker
	if is_instance_valid(_job_aircraft):
		var center_to_dest = _horizontal_distance(_job_aircraft.global_transform.origin, (elevator_marker.global_position if is_instance_valid(elevator_marker) else _job_destination.global_position))
		# Drop rope when within 1m of elevator marker
		if use_rope_mode and _rope_active and center_to_dest <= disconnect_distance_m:
			_state = BotState.DISCONNECTING
			return
		# Phase advance: when near A, switch to B
		if _tow_phase == 0 and is_instance_valid(approach_a_marker):
			if global_position.distance_to(approach_a_marker.global_position) <= 0.75:
				_tow_phase = 1
		var ac_vel = _job_aircraft.linear_velocity.length()
		if _tow_phase == 1 and center_to_dest <= center_stop_tolerance_m and _tow_elapsed >= min_tow_time_s and ac_vel < 0.3:
			_state = BotState.UNCOUPLING

func _tick_disconnecting(delta: float) -> void:
	_sync_aircraft_rotation_to_carrier()
	# Smoothly come to a stop, disconnect, then resume towing toward phase B
	_current_speed = max(0.0, _current_speed - accel_mps2 * delta)
	# Face approach B for clean egress
	if is_instance_valid(approach_b_marker):
		_face_toward(approach_b_marker.global_position, delta)
	# When both bot and aircraft are nearly still, drop rope/joint
	var ac_speed = 0.0
	if is_instance_valid(_job_aircraft):
		ac_speed = _job_aircraft.linear_velocity.length()
	if _current_speed <= 0.05 and ac_speed < 0.3:
		# Disconnect
		if use_rope_mode:
			_rope_active = false
		else:
			if _joint and is_instance_valid(_joint):
				_joint.queue_free()
			_joint = null
		# Engage aircraft parking brake after disconnect
		if is_instance_valid(_job_aircraft):
			_job_aircraft.set_meta("parking_brake", true)
		# Proceed to phase B
		_tow_phase = 1
		_state = BotState.TOWING_TO_DESTINATION
		_set_nav_target(_get_tow_tractor_target())

func _tick_uncoupling(_delta: float) -> void:
	_sync_aircraft_rotation_to_carrier()
	if is_instance_valid(_job_aircraft):
		_job_aircraft.remove_meta("controls_disabled")
	_reverse_mode = false
	# Remove joint (arm mode)
	if _joint and is_instance_valid(_joint):
		_joint.queue_free()
	_joint = null
	# Retract arm if we were using it
	if not use_rope_mode:
		if is_instance_valid(_arm_node):
			var tr = _arm_node.transform
			tr.origin.z = arm_retracted_z
			_arm_node.transform = tr
		_arm_extending = false
		_arm_extended_flag = false
	_latched = false
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
	if is_instance_valid(elevator_marker):
		dest = elevator_marker.global_position
	# Choose intermediate waypoint
	var phase_target = dest
	if _tow_phase == 0 and is_instance_valid(approach_a_marker):
		# Go directly to A (no standoff) to avoid circling
		return Vector3(approach_a_marker.global_position.x, global_position.y, approach_a_marker.global_position.z)
	elif _tow_phase == 1 and is_instance_valid(approach_b_marker):
		phase_target = approach_b_marker.global_position
	var nose = _find_nose_gear_collider(_job_aircraft) if is_instance_valid(_job_aircraft) else null
	var back_dir: Vector3
	if is_instance_valid(nose):
		back_dir = (phase_target - nose.global_position)
	else:
		back_dir = -global_transform.basis.z
	if back_dir.length() < 0.001:
		back_dir = -global_transform.basis.z
	back_dir = back_dir.normalized()
	var target = phase_target + back_dir * stand_off_m
	target.y = global_position.y
	return target

func _horizontal_distance(a: Vector3, b: Vector3) -> float:
	var da = Vector3(a.x, 0.0, a.z)
	var db = Vector3(b.x, 0.0, b.z)
	return da.distance_to(db)

func _plan_move_to(target: Vector3) -> void:
	if nav_agent:
		nav_agent.set_target_position(target)

func _set_nav_target(target: Vector3) -> void:
	if nav_agent:
		nav_agent.set_target_position(target)

func _follow_plan(target: Vector3, max_speed: float, delta: float, allow_turn_in_place: bool = true) -> bool:
	var desired_dir: Vector3
	if nav_agent:
		var next_pos = nav_agent.get_next_path_position()
		if (next_pos - global_position).length() < 0.05:
			next_pos = nav_agent.get_target_position()
		var vec = next_pos - global_position
		if vec.length() < 0.05:
			desired_dir = (target - global_position)
		else:
			desired_dir = vec
	else:
		desired_dir = (target - global_position)
	desired_dir.y = 0.0
	var dist = desired_dir.length()
	if dist < 0.01:
		_current_speed = 0.0
		return true
	var move_dir = desired_dir.normalized()
	# If facing error is large, rotate in place (zero-radius turn) when allowed
	if allow_turn_in_place:
		var forward = global_transform.basis.z
		var angle_to = forward.signed_angle_to(move_dir, Vector3.UP)
		if abs(angle_to) > deg_to_rad(turn_in_place_deg):
			# Decelerate while rotating; no translation this tick
			_current_speed = max(0.0, _current_speed - accel_mps2 * delta)
			return false
	# Basic accel/decel
	var target_speed = clamp(max_speed, 0.0, max_speed)
	_current_speed = clamp(_current_speed + accel_mps2 * delta, 0.0, target_speed)
	global_position += move_dir * _current_speed * delta
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
	# If in reverse mode, keep the tractor roughly facing the plane (avoid spinning 180)
	if _reverse_mode:
		angle_to = clamp(angle_to, -max_turn * 0.5, max_turn * 0.5)
	else:
		angle_to = clamp(angle_to, -max_turn, max_turn)
	rotate_y(angle_to)

func _get_nose_pos_or(fallback: Vector3) -> Vector3:
	var nose = _find_nose_gear_collider(_job_aircraft) if is_instance_valid(_job_aircraft) else null
	if is_instance_valid(nose):
		return nose.global_position
	return fallback

func _update_arm_extension(goal: Vector3) -> void:
	if not is_instance_valid(_arm_node):
		return
	# Do not change arm extension while coupling/towing; keep it extended until uncoupling
	if _state == BotState.TOWING_TO_DESTINATION or _state == BotState.COUPLING:
		return
	var d = global_position.distance_to(goal)
	var tz = arm_extended_z if d <= arm_extend_distance_m else arm_retracted_z
	var t = _arm_node.transform
	t.origin.z = tz
	_arm_node.transform = t

func _apply_towing_force(_delta: float) -> void:
	if not is_instance_valid(_job_aircraft):
		return
	var dt = max(get_physics_process_delta_time(), 0.001)
	# Reverse towing: move backward while pulling aircraft toward the marker
	var desired_velocity = -(global_transform.basis.z) * _current_speed
	var current_velocity = _job_aircraft.linear_velocity
	var velocity_error = desired_velocity - current_velocity
	var nose = _find_nose_gear_collider(_job_aircraft)
	var pos_error = Vector3.ZERO
	if use_rope_mode:
		if is_instance_valid(nose) and is_instance_valid(_rope_anchor) and _rope_active:
			# Rope constraint: only pull when stretched beyond rope_length
			var anchor_pos = _rope_anchor.global_transform.origin
			var nose_pos = nose.global_position
			var vec = nose_pos - anchor_pos
			var dist = vec.length()
			if dist > rope_length_m and dist > 0.001:
				var target_on_rope = anchor_pos + vec.normalized() * rope_length_m
				pos_error = target_on_rope - nose_pos
	else:
		# Hitch at explicit arm tip marker with a slight separation to avoid overlap
		var tip_pos = _arm_tip.global_transform.origin if is_instance_valid(_arm_tip) else (_arm_node.global_transform.origin + _arm_node.global_transform.basis.z * arm_length_m)
		var dir_to_nose = (nose.global_position - tip_pos).normalized()
		var hitch_target = tip_pos + dir_to_nose * hitch_separation_m
		pos_error = hitch_target - nose.global_position
	# PD acceleration
	var accel_vec = tow_kv * velocity_error + tow_kp * pos_error
	# Convert to force and clamp
	var force = _job_aircraft.mass * accel_vec / dt
	force *= towing_force_gain
	if force.length() > tow_force_limit:
		force = force.normalized() * tow_force_limit
	# Smooth the force to reduce jerks
	var alpha = clamp(dt / max(tow_force_smoothing_s, 0.001), 0.0, 1.0)
	force = _prev_force.lerp(force, alpha)
	_prev_force = force
	var force_position = (nose.global_position - _job_aircraft.global_position) if is_instance_valid(nose) else Vector3.ZERO
	if is_instance_valid(nose):
		_job_aircraft.apply_force(force, force_position)
	else:
		_job_aircraft.apply_central_force(force)

func _create_hitch_joint() -> void:
	if not is_instance_valid(_job_aircraft) or not is_instance_valid(_hitch_body):
		return
	# Create a PinJoint3D at the tip position and attach A=aircraft, B=hitch body
	var joint := PinJoint3D.new()
	var tip_pos = _arm_tip.global_transform.origin if is_instance_valid(_arm_tip) else _hitch_body.global_transform.origin
	joint.global_position = tip_pos
	get_tree().current_scene.add_child(joint)
	joint.set_node_a(_job_aircraft.get_path())
	joint.set_node_b(_hitch_body.get_path())
	_joint = joint

func _clear_job() -> void:
	_job_aircraft = null
	_job_destination = null
	_nose_gear = null
	_carrier_node = null
	_has_aircraft_carrier_local_basis = false

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


func _capture_aircraft_carrier_rotation() -> void:
	if not is_instance_valid(_job_aircraft):
		return
	_carrier_node = _find_carrier_node()
	if not is_instance_valid(_carrier_node):
		_has_aircraft_carrier_local_basis = false
		return
	_aircraft_carrier_local_basis = _carrier_node.global_transform.basis.inverse() * _job_aircraft.global_transform.basis
	_has_aircraft_carrier_local_basis = true


func _sync_aircraft_rotation_to_carrier() -> void:
	if not _has_aircraft_carrier_local_basis or not is_instance_valid(_job_aircraft) or not is_instance_valid(_carrier_node):
		return
	var transform := _job_aircraft.global_transform
	transform.basis = (_carrier_node.global_transform.basis * _aircraft_carrier_local_basis).orthonormalized()
	_job_aircraft.global_transform = transform
	PhysicsServer3D.body_set_state(_job_aircraft.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, _job_aircraft.global_transform)
	# Deck towing owns the aircraft attitude; avoid residual physics torque
	# slowly winding it out of carrier-relative alignment.
	_job_aircraft.angular_velocity = Vector3.ZERO


func _find_carrier_node() -> Node3D:
	var node: Node = self
	while node != null:
		if node is Node3D and (node.is_in_group("carrier") or node.name.to_lower().find("landcarrier") != -1):
			return node as Node3D
		node = node.get_parent()
	var carrier := get_tree().get_first_node_in_group("carrier")
	return carrier as Node3D
