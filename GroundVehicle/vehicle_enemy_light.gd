extends CharacterBody3D
class_name VehicleEnemyLight

signal destroyed(vehicle)

const VISUAL_FOCUS_HELPER = preload("res://Effects/VisualFocus.gd")
const FrameProfiler: Script = preload("res://Debug/FrameProfiler.gd")

# --- Movement ---
@export var max_speed: float = 15.0
@export var acceleration: float = 4.0
@export var turn_speed: float = 0.6
@export var max_steering_angle: float = 0.5
@export var chassis_ride_height_m: float = 1.0
@export var wheel_suspension_smoothing: float = 12.0
@export var wheel_probe_down_m: float = 12.0
@export var spring_stiffness: float = 120.0
@export var spring_damping: float = 18.0
@export var spring_tilt_stiffness: float = 80.0
@export var spring_tilt_damping: float = 18.0
@export var suspension_probe_interval_frames: int = 2
@export var spacing_cache_refresh_s: float = 0.35
@export var detailed_suspension_distance_m: float = 800.0
@export var distant_suspension_height_lerp: float = 8.0

# --- Waypoints ---
@export var waypoints: Array[NodePath] = []
@export var loop_waypoints: bool = true
@export var waypoint_reach_distance: float = 25.0
@export var use_waypoint_pathfinding: bool = true
@export var path_waypoint_reach_distance: float = 18.0
@export var path_replan_interval_s: float = 1.0
@export var path_goal_repath_distance_m: float = 80.0
@export var path_stuck_timeout_s: float = 4.0
@export var path_max_segment_m: float = 600.0
@export var path_min_clearance_m: float = 60.0
@export var path_retry_cooldown_s: float = 3.0
@export var path_no_anchor_retry_cooldown_s: float = 6.0
@export var path_goal_anchor_search_radius_m: float = 180.0
@export var path_goal_anchor_search_samples: int = 12
@export var path_direct_safety_sample_step_m: float = 20.0
@export var dynamic_objective_replan_interval_s: float = 2.5

# --- Combat ---
@export var max_health: float = 50.0
@export var team: int = 2
@export var turret_range: float = 750.0
@export var burst_length: float = 1.5
@export var delay_length: float = 3.0
@export var turret_weapon: PackedScene
@export var aim_skill: float = 0.35
@export var platoon_min_neighbor_distance_m: float = 30.0
@export var platoon_rejoin_distance_m: float = 80.0
@export var preferred_vehicle_spacing_min_m: float = 30.0
@export var preferred_vehicle_spacing_max_m: float = 80.0
@export var shoot_and_scoot_enabled: bool = false
@export var fire_position_hold_s: float = 2.0
@export var scoot_move_s: float = 3.0
@export var scoot_distance_m: float = 35.0
@export var combat_hold_distance_m: float = 320.0
@export var combat_stop_distance_m: float = 220.0
@export var combat_creep_speed_mps: float = 4.0
@export var combat_track_angle_deg: float = 18.0

# State
var current_health: float
var is_dying: bool = false
var turret_controller: TurretController
var current_target: Node3D
var platoon: GroundVehiclePlatoon = null
var _combat_hold_timer_s: float = 0.0
var _combat_is_scooting: bool = false
var _combat_scoot_destination: Vector3 = Vector3.ZERO
var _had_combat_target_last_frame: bool = false

var _waypoint_positions: Array[Vector3] = []
var _waypoint_index: int = 0
var _nav_path_positions: Array[Vector3] = []
var _nav_path_index: int = 0
var _nav_path_goal: Vector3 = Vector3.ZERO
var _nav_safe_target: Vector3 = Vector3.INF
var _nav_repath_timer_s: float = 0.0
var _nav_stuck_timer_s: float = 0.0
var _nav_prev_wp_distance: float = INF
var _nav_retry_cooldown_s: float = 0.0
var _is_pathfinding: bool = false

var _front_wheels: Array[Node3D] = []
var _body_node: Node3D
var _all_wheel_nodes: Array[Node3D] = []
var _wheel_contact_nodes: Array[Node3D] = []
var _wheel_nominal_positions: Array[Vector3] = []
var _wheel_contact_local_positions: Array[Vector3] = []
var _body_rest_position: Vector3 = Vector3.ZERO
var _body_rest_rotation: Vector3 = Vector3.ZERO

# Corner probe positions (local space) — front-left, front-right, rear-left, rear-right
var _corner_probes: Array[Vector3] = []
var _corner_half_x: float = 1.66
var _corner_half_z: float = 4.68

const GRAVITY: float = 25.0
const WHEEL_RADIUS: float = 0.4
var _spring_velocity_y: float = 0.0
var _spring_pitch_velocity: float = 0.0
var _spring_roll_velocity: float = 0.0
var _spring_initialized: bool = false
var _suspension_probe_counter: int = 0
var _suspension_probe_ready: bool = false
var _suspension_has_ground: bool = false
var _cached_corner_target_ys: Array[float] = []
var _cached_wheel_target_ys: Array[float] = []
var _cached_carrier: Node3D = null
var _cached_spacing_candidates: Array[Node3D] = []
var _spacing_cache_timer_s: float = 0.0
var _cached_active_camera: Camera3D = null
var _camera_cache_timer_s: float = 0.0
func _ready() -> void:
	current_health = max_health
	floor_snap_length = 0.0
	floor_max_angle = deg_to_rad(50.0)
	add_to_group("enemies")
	add_to_group("ground_vehicles")
	add_to_group("team_" + str(team))
	add_to_group("origin_shifter")
	var livery_node: Node = get_node_or_null("/root/Livery")
	if livery_node != null and livery_node.has_method("apply"):
		livery_node.call("apply", self)
	_resolve_waypoints()
	_collect_wheel_nodes()
	_compute_corner_probes()
	_suspension_probe_counter = int(get_instance_id()) % maxi(suspension_probe_interval_frames, 1)
	_nav_repath_timer_s = randf() * maxf(path_replan_interval_s, 0.1)

	# Dust from wheels
	if not has_node("DustEffect"):
		var dust := DustEffect.new()
		dust.name = "DustEffect"
		dust.min_speed_mps = 3.0
		dust.spawn_interval_s = 0.4
		dust.puff_scale_min = 1.0
		dust.puff_scale_max = 2.5
		dust.puff_lifetime_s = 4.0
		dust.puff_rise_speed = 5.0
		dust.full_speed_mps = max_speed
		add_child(dust)

	turret_controller = _find_turret_controller()

	if not turret_controller:
		push_warning("VehicleEnemyLight: No TurretController found as child!")
	else:
		turret_controller.team = team
		turret_controller.max_range = turret_range
		turret_controller.burst_length = burst_length
		turret_controller.delay_length = minf(delay_length, 0.35)
		turret_controller.aim_skill = aim_skill
		turret_controller.fire_angle_tolerance_deg = maxf(turret_controller.fire_angle_tolerance_deg, 24.0)
		turret_controller.target_aim_height_bias_m = 1.2
		if turret_weapon and turret_controller.weapon_instance == null:
			turret_controller.mount_weapon(turret_weapon)

func _find_turret_controller() -> TurretController:
	var direct: Node = find_child("TurretController", true, false)
	if direct is TurretController:
		return direct as TurretController
	for child in get_children():
		if child is TurretController:
			return child as TurretController
	return null

func _collect_wheel_nodes() -> void:
	_body_node = get_node_or_null("Body")
	if _body_node:
		_body_rest_position = _body_node.position
		_body_rest_rotation = _body_node.rotation
	for wname in ["wheel_right_1", "wheel_right_2", "wheel_right_3", "wheel_left_1", "wheel_left_2", "wheel_left_3"]:
		var w := get_node_or_null(wname) as Node3D
		if w:
			_all_wheel_nodes.append(w)
			var contact_node: Node3D = _find_wheel_contact_node(w)
			_wheel_contact_nodes.append(contact_node)
			_wheel_nominal_positions.append(w.position)
			if contact_node and is_instance_valid(contact_node):
				_wheel_contact_local_positions.append(w.position + contact_node.position)
			else:
				_wheel_contact_local_positions.append(w.position + Vector3(0.0, -WHEEL_RADIUS, 0.0))
			if wname.ends_with("_1"):
				_front_wheels.append(w)

func _compute_corner_probes() -> void:
	## Build 4 corner probe positions from the CollisionShape3D box.
	var col_shape: CollisionShape3D = null
	for child in get_children():
		if child is CollisionShape3D:
			col_shape = child as CollisionShape3D
			break
	if col_shape and col_shape.shape is BoxShape3D:
		var box: BoxShape3D = col_shape.shape as BoxShape3D
		_corner_half_x = box.size.x * 0.5
		_corner_half_z = box.size.z * 0.5
	# Probe at y=0 (vehicle root level) at the 4 XZ corners
	_corner_probes = [
		Vector3(-_corner_half_x, 0.0,  _corner_half_z),  # front-left
		Vector3( _corner_half_x, 0.0,  _corner_half_z),  # front-right
		Vector3(-_corner_half_x, 0.0, -_corner_half_z),  # rear-left
		Vector3( _corner_half_x, 0.0, -_corner_half_z),  # rear-right
	]

func _find_wheel_contact_node(wheel_node: Node3D) -> Node3D:
	if not wheel_node:
		return null
	for child in wheel_node.get_children():
		if child is Node3D and child.name.to_lower().contains("contact"):
			return child as Node3D
	return null

func _resolve_waypoints() -> void:
	_waypoint_positions.clear()
	for path in waypoints:
		var node = get_node_or_null(path)
		if node is Node3D:
			_waypoint_positions.append((node as Node3D).global_position)

func set_patrol_waypoints(positions: Array[Vector3]) -> void:
	_waypoint_positions = positions.duplicate()
	_waypoint_index = 0
	_clear_navigation_path()

func assign_platoon(new_platoon: GroundVehiclePlatoon) -> void:
	platoon = new_platoon
	if platoon and is_instance_valid(platoon):
		platoon.register_vehicle(self)
	_clear_navigation_path()
	_nav_repath_timer_s = randf() * _get_navigation_replan_interval_s()

func apply_origin_shift(offset: Vector3) -> void:
	for i in range(_waypoint_positions.size()):
		_waypoint_positions[i] -= offset
	for i in range(_nav_path_positions.size()):
		_nav_path_positions[i] -= offset
	_nav_path_goal -= offset
	if _combat_scoot_destination != Vector3.ZERO:
		_combat_scoot_destination -= offset

func _physics_process(delta: float) -> void:
	var _profiler_start: int = FrameProfiler.begin("VehicleEnemyLight.physics")
	if is_dying:
		FrameProfiler.end("VehicleEnemyLight.physics", _profiler_start)
		return

	if turret_controller:
		current_target = turret_controller.current_target
	else:
		current_target = null
	_update_shoot_and_scoot(delta)
	_update_navigation_path(delta)

	_drive_to_waypoint(delta)
	_update_wheel_visuals()
	FrameProfiler.end("VehicleEnemyLight.physics", _profiler_start)

# --- Wheel Visuals / Chassis Support ---

func _update_wheel_visuals() -> void:
	var delta := get_physics_process_delta_time()
	if not _should_use_detailed_suspension(delta):
		_apply_distant_suspension_visuals(delta)
		return
	if _should_refresh_suspension_probes():
		_refresh_suspension_targets()

	if not _suspension_probe_ready:
		return

	if not _suspension_has_ground:
		_spring_velocity_y -= GRAVITY * delta
		for i in range(_all_wheel_nodes.size()):
			_all_wheel_nodes[i].position.y = lerpf(_all_wheel_nodes[i].position.y, _wheel_nominal_positions[i].y, 0.1)
		return

	var fast_corner_targets := _cached_corner_target_ys
	var fast_target_y: float = (fast_corner_targets[0] + fast_corner_targets[1] + fast_corner_targets[2] + fast_corner_targets[3]) / 4.0
	var fast_front_avg_y: float = (fast_corner_targets[0] + fast_corner_targets[1]) / 2.0
	var fast_rear_avg_y: float = (fast_corner_targets[2] + fast_corner_targets[3]) / 2.0
	var fast_target_pitch: float = atan2(fast_rear_avg_y - fast_front_avg_y, _corner_half_z * 2.0)
	var fast_left_avg_y: float = (fast_corner_targets[0] + fast_corner_targets[2]) / 2.0
	var fast_right_avg_y: float = (fast_corner_targets[1] + fast_corner_targets[3]) / 2.0
	var fast_target_roll: float = atan2(fast_right_avg_y - fast_left_avg_y, _corner_half_x * 2.0)

	if not _spring_initialized:
		global_position.y = fast_target_y
		_spring_velocity_y = 0.0
		_spring_pitch_velocity = 0.0
		_spring_roll_velocity = 0.0
		_spring_initialized = true
	else:
		var displacement_fast: float = global_position.y - fast_target_y
		var spring_force_fast: float = -spring_stiffness * displacement_fast - spring_damping * _spring_velocity_y
		_spring_velocity_y += spring_force_fast * delta
		_spring_velocity_y = clampf(_spring_velocity_y, -50.0, 50.0)

	var current_yaw_fast: float = atan2(global_basis.z.x, global_basis.z.z)
	var current_pitch_fast: float = asin(clampf(-global_basis.z.y, -1.0, 1.0))
	var current_roll_fast: float = atan2(global_basis.x.y, global_basis.y.y)
	var pitch_torque_fast: float = -spring_tilt_stiffness * (current_pitch_fast - fast_target_pitch) - spring_tilt_damping * _spring_pitch_velocity
	_spring_pitch_velocity += pitch_torque_fast * delta
	_spring_pitch_velocity = clampf(_spring_pitch_velocity, -5.0, 5.0)
	var roll_torque_fast: float = -spring_tilt_stiffness * (current_roll_fast - fast_target_roll) - spring_tilt_damping * _spring_roll_velocity
	_spring_roll_velocity += roll_torque_fast * delta
	_spring_roll_velocity = clampf(_spring_roll_velocity, -5.0, 5.0)
	var new_pitch_fast: float = current_pitch_fast + _spring_pitch_velocity * delta
	var new_roll_fast: float = current_roll_fast + _spring_roll_velocity * delta
	global_basis = Basis.from_euler(Vector3(new_pitch_fast, current_yaw_fast, new_roll_fast), EULER_ORDER_YXZ).orthonormalized()

	for i in range(_all_wheel_nodes.size()):
		var nominal_fast: Vector3 = _wheel_nominal_positions[i]
		var target_wheel_y_fast: float = nominal_fast.y
		if i < _cached_wheel_target_ys.size():
			target_wheel_y_fast = _cached_wheel_target_ys[i]
		var blend_fast: float = clampf(wheel_suspension_smoothing * delta, 0.0, 1.0)
		_all_wheel_nodes[i].position.y = lerpf(_all_wheel_nodes[i].position.y, target_wheel_y_fast, blend_fast)

	if _body_node:
		_body_node.position = _body_rest_position
		_body_node.rotation = _body_rest_rotation
	return
	var space_state := get_world_3d().direct_space_state
	var params := PhysicsRayQueryParameters3D.new()
	params.exclude = [get_rid()]

	# --- 1. Corner probes: determine target height & tilt ---
	var corner_target_ys: Array[float] = []
	var hit_count: int = 0
	for corner_local in _corner_probes:
		# Use only XZ from corner, probe straight down in world Y
		var corner_world: Vector3 = to_global(corner_local)
		params.from = corner_world + Vector3.UP * 5.0
		params.to = corner_world - Vector3.UP * wheel_probe_down_m
		var hit := space_state.intersect_ray(params)
		if hit:
			corner_target_ys.append(hit.position.y + chassis_ride_height_m)
			hit_count += 1
		else:
			corner_target_ys.append(-99999.0)

	if hit_count == 0:
		# No ground — free-fall
		_spring_velocity_y -= GRAVITY * delta
		# Settle wheels to nominal
		for i in range(_all_wheel_nodes.size()):
			_all_wheel_nodes[i].position.y = lerpf(_all_wheel_nodes[i].position.y, _wheel_nominal_positions[i].y, 0.1)
		return

	# Fill missing corners with average of valid ones
	var valid_sum: float = 0.0
	for y in corner_target_ys:
		if y > -90000.0:
			valid_sum += y
	var valid_avg: float = valid_sum / float(hit_count)
	for i in range(corner_target_ys.size()):
		if corner_target_ys[i] < -90000.0:
			corner_target_ys[i] = valid_avg

	# Target height = average of 4 corners
	var target_y: float = (corner_target_ys[0] + corner_target_ys[1] + corner_target_ys[2] + corner_target_ys[3]) / 4.0

	# Target pitch from front vs rear (positive pitch = nose up)
	var front_avg_y: float = (corner_target_ys[0] + corner_target_ys[1]) / 2.0
	var rear_avg_y: float = (corner_target_ys[2] + corner_target_ys[3]) / 2.0
	var target_pitch: float = atan2(rear_avg_y - front_avg_y, _corner_half_z * 2.0)

	# Target roll from right vs left (positive roll = right side up)
	var left_avg_y: float = (corner_target_ys[0] + corner_target_ys[2]) / 2.0
	var right_avg_y: float = (corner_target_ys[1] + corner_target_ys[3]) / 2.0
	var target_roll: float = atan2(right_avg_y - left_avg_y, _corner_half_x * 2.0)

	# --- 2. Height spring ---
	if not _spring_initialized:
		global_position.y = target_y
		_spring_velocity_y = 0.0
		_spring_pitch_velocity = 0.0
		_spring_roll_velocity = 0.0
		_spring_initialized = true
	else:
		var displacement: float = global_position.y - target_y
		var spring_force: float = -spring_stiffness * displacement - spring_damping * _spring_velocity_y
		_spring_velocity_y += spring_force * delta
		_spring_velocity_y = clampf(_spring_velocity_y, -50.0, 50.0)

	# --- 3. Tilt spring (pitch & roll only, never yaw) ---
	# Extract current yaw from basis
	var current_yaw: float = atan2(global_basis.z.x, global_basis.z.z)
	# Extract current pitch and roll
	var current_pitch: float = asin(clampf(-global_basis.z.y, -1.0, 1.0))
	var current_roll: float = atan2(global_basis.x.y, global_basis.y.y)

	var pitch_torque: float = -spring_tilt_stiffness * (current_pitch - target_pitch) - spring_tilt_damping * _spring_pitch_velocity
	_spring_pitch_velocity += pitch_torque * delta
	_spring_pitch_velocity = clampf(_spring_pitch_velocity, -5.0, 5.0)

	var roll_torque: float = -spring_tilt_stiffness * (current_roll - target_roll) - spring_tilt_damping * _spring_roll_velocity
	_spring_roll_velocity += roll_torque * delta
	_spring_roll_velocity = clampf(_spring_roll_velocity, -5.0, 5.0)

	var new_pitch: float = current_pitch + _spring_pitch_velocity * delta
	var new_roll: float = current_roll + _spring_roll_velocity * delta

	# Rebuild basis from yaw (preserved), new pitch, new roll
	global_basis = Basis.from_euler(Vector3(new_pitch, current_yaw, new_roll), EULER_ORDER_YXZ).orthonormalized()

	# --- 4. Position wheels visually on the ground ---
	for i in range(_all_wheel_nodes.size()):
		if i >= _wheel_contact_local_positions.size():
			continue
		var nominal: Vector3 = _wheel_nominal_positions[i]
		var contact_local: Vector3 = _wheel_contact_local_positions[i]
		var contact_world: Vector3 = to_global(contact_local)
		params.from = contact_world + Vector3.UP * 3.0
		params.to = contact_world - Vector3.UP * wheel_probe_down_m
		var hit := space_state.intersect_ray(params)
		if hit:
			var hit_local_y: float = to_local(hit.position).y
			var target_wheel_y: float = nominal.y + (hit_local_y - contact_local.y)
			var blend: float = clampf(wheel_suspension_smoothing * delta, 0.0, 1.0)
			_all_wheel_nodes[i].position.y = lerpf(_all_wheel_nodes[i].position.y, target_wheel_y, blend)
		else:
			_all_wheel_nodes[i].position.y = lerpf(_all_wheel_nodes[i].position.y, nominal.y, 0.1)

	if _body_node:
		_body_node.position = _body_rest_position
		_body_node.rotation = _body_rest_rotation

func _should_refresh_suspension_probes() -> bool:
	if not _suspension_probe_ready:
		return true
	var interval: int = maxi(suspension_probe_interval_frames, 1)
	if interval <= 1:
		return true
	_suspension_probe_counter = (_suspension_probe_counter + 1) % interval
	return _suspension_probe_counter == 0

func _refresh_suspension_targets() -> void:
	var space_state := get_world_3d().direct_space_state
	var params := PhysicsRayQueryParameters3D.new()
	params.exclude = [get_rid()]

	_cached_corner_target_ys.clear()
	_cached_wheel_target_ys.clear()
	var hit_count: int = 0
	for corner_local in _corner_probes:
		var corner_world: Vector3 = to_global(corner_local)
		params.from = corner_world + Vector3.UP * 5.0
		params.to = corner_world - Vector3.UP * wheel_probe_down_m
		var hit := space_state.intersect_ray(params)
		if hit:
			_cached_corner_target_ys.append(hit.position.y + chassis_ride_height_m)
			hit_count += 1
		else:
			var terrain_y: float = TerrainNavGrid.sample_height(corner_world.x, corner_world.z)
			if terrain_y > TerrainNavGrid.IMPASSABLE * 0.5:
				_cached_corner_target_ys.append(terrain_y + chassis_ride_height_m)
				hit_count += 1
			else:
				_cached_corner_target_ys.append(-99999.0)

	if hit_count == 0:
		_suspension_has_ground = false
		for nominal in _wheel_nominal_positions:
			_cached_wheel_target_ys.append(nominal.y)
		_suspension_probe_ready = true
		return

	var valid_sum: float = 0.0
	for y in _cached_corner_target_ys:
		if y > -90000.0:
			valid_sum += y
	var valid_avg: float = valid_sum / float(hit_count)
	for i in range(_cached_corner_target_ys.size()):
		if _cached_corner_target_ys[i] < -90000.0:
			_cached_corner_target_ys[i] = valid_avg

	for i in range(_all_wheel_nodes.size()):
		var nominal: Vector3 = _wheel_nominal_positions[i]
		var target_wheel_y: float = nominal.y
		if i < _wheel_contact_local_positions.size():
			var contact_local: Vector3 = _wheel_contact_local_positions[i]
			var contact_world: Vector3 = to_global(contact_local)
			params.from = contact_world + Vector3.UP * 3.0
			params.to = contact_world - Vector3.UP * wheel_probe_down_m
			var hit := space_state.intersect_ray(params)
			if hit:
				var hit_local_y: float = to_local(hit.position).y
				target_wheel_y = nominal.y + (hit_local_y - contact_local.y)
			else:
				var terrain_y: float = TerrainNavGrid.sample_height(contact_world.x, contact_world.z)
				if terrain_y > TerrainNavGrid.IMPASSABLE * 0.5:
					var baked_hit_local_y: float = to_local(Vector3(contact_world.x, terrain_y, contact_world.z)).y
					target_wheel_y = nominal.y + (baked_hit_local_y - contact_local.y)
		_cached_wheel_target_ys.append(target_wheel_y)

	_suspension_has_ground = true
	_suspension_probe_ready = true

func _get_active_camera(delta: float) -> Camera3D:
	_camera_cache_timer_s = maxf(_camera_cache_timer_s - delta, 0.0)
	if _cached_active_camera and is_instance_valid(_cached_active_camera) and _camera_cache_timer_s > 0.0:
		return _cached_active_camera
	_cached_active_camera = get_viewport().get_camera_3d()
	_camera_cache_timer_s = 0.25
	return _cached_active_camera

func _should_use_detailed_suspension(delta: float) -> bool:
	if VISUAL_FOCUS_HELPER.is_node_in_target_camera_focus(self, self):
		return true
	var camera := _get_active_camera(delta)
	if camera == null or not is_instance_valid(camera):
		return false
	return global_position.distance_squared_to(camera.global_position) <= detailed_suspension_distance_m * detailed_suspension_distance_m

func _apply_distant_suspension_visuals(delta: float) -> void:
	var terrain_y: float = TerrainNavGrid.sample_height(global_position.x, global_position.z)
	if terrain_y > TerrainNavGrid.IMPASSABLE * 0.5:
		global_position.y = lerpf(global_position.y, terrain_y + chassis_ride_height_m, clampf(distant_suspension_height_lerp * delta, 0.0, 1.0))
	var current_yaw: float = atan2(global_basis.z.x, global_basis.z.z)
	global_basis = Basis.from_euler(Vector3(0.0, current_yaw, 0.0), EULER_ORDER_YXZ).orthonormalized()
	_spring_pitch_velocity = 0.0
	_spring_roll_velocity = 0.0
	for i in range(_all_wheel_nodes.size()):
		_all_wheel_nodes[i].position.y = lerpf(_all_wheel_nodes[i].position.y, _wheel_nominal_positions[i].y, 0.15)
	if _body_node:
		_body_node.position = _body_rest_position
		_body_node.rotation = _body_rest_rotation

# --- Driving AI ---

func _update_navigation_path(delta: float) -> void:
	_advance_patrol_waypoint_if_reached()
	if _nav_retry_cooldown_s > 0.0:
		_nav_retry_cooldown_s = maxf(_nav_retry_cooldown_s - delta, 0.0)
	if not use_waypoint_pathfinding:
		_clear_navigation_path()
		return
	if _has_combat_target():
		_nav_repath_timer_s = 0.0
		_nav_stuck_timer_s = 0.0
		_nav_prev_wp_distance = INF
		return
	if not _has_navigation_destination():
		_clear_navigation_path()
		_nav_safe_target = Vector3.INF
		return
	if _use_platoon_shared_route_navigation():
		_clear_navigation_path()
		return
	if not NavGraph.is_ready():
		return
	var raw_target: Vector3 = _get_raw_navigation_destination()
	var safe_target: Vector3 = _get_safe_navigation_target(raw_target)
	_nav_safe_target = safe_target
	if not _is_valid_navigation_target(safe_target):
		_nav_path_positions.clear()
		_nav_path_index = 0
		_nav_path_goal = global_position
		_nav_repath_timer_s = 0.0
		_nav_stuck_timer_s = 0.0
		_nav_prev_wp_distance = INF
		_nav_retry_cooldown_s = maxf(_nav_retry_cooldown_s, path_retry_cooldown_s)
		return
	_consume_reached_nav_waypoints(safe_target)
	var dynamic_goal: bool = _has_dynamic_navigation_goal()
	var repath_interval_s: float = _get_navigation_replan_interval_s()
	var goal_shifted: bool = _flat_distance(safe_target, _nav_path_goal) > path_goal_repath_distance_m
	_nav_repath_timer_s += delta
	var needs_repath: bool = _nav_path_positions.is_empty() or _nav_path_index >= _nav_path_positions.size()
	if _nav_retry_cooldown_s > 0.0:
		return
	if goal_shifted and _nav_repath_timer_s >= repath_interval_s:
		_recompute_navigation_path(safe_target)
	elif needs_repath and _nav_repath_timer_s >= repath_interval_s:
		_recompute_navigation_path(safe_target)
	elif dynamic_goal and _nav_repath_timer_s >= repath_interval_s:
		_recompute_navigation_path(safe_target)

func _advance_patrol_waypoint_if_reached() -> void:
	if platoon and is_instance_valid(platoon) and platoon.has_active_objective():
		return
	if _waypoint_positions.is_empty():
		return
	var current_target: Vector3 = _waypoint_positions[_waypoint_index]
	if _flat_distance(global_position, current_target) > waypoint_reach_distance:
		return
	if loop_waypoints:
		_waypoint_index = (_waypoint_index + 1) % _waypoint_positions.size()
	else:
		_waypoint_index = min(_waypoint_index + 1, _waypoint_positions.size() - 1)
	_clear_navigation_path()

func _recompute_navigation_path(raw_target: Vector3) -> void:
	if not NavGraph.is_ready():
		return
	if _is_pathfinding:
		return

	var flat := Vector2(raw_target.x - global_position.x, raw_target.z - global_position.z)
	if flat.length() <= maxf(path_waypoint_reach_distance, waypoint_reach_distance):
		_clear_navigation_path()
		_nav_path_goal = raw_target
		return

	_is_pathfinding = true
	var start_pos := global_position
	var clearance := path_min_clearance_m
	var max_seg := path_max_segment_m
	var reach_dist := maxf(path_waypoint_reach_distance, waypoint_reach_distance)
	var retry_cooldown := path_retry_cooldown_s
	var no_anchor_retry_cooldown := path_no_anchor_retry_cooldown_s

	var work: Callable = func() -> Dictionary:
		var status_code := 0 # 0 = OK, 1 = NO_ANCHOR, 2 = NO_PATH
		var best_path: Array[Vector3] = []
		
		if not NavGraph.can_anchor(start_pos, clearance):
			status_code = 1
		else:
			var base_dir := flat.normalized() if flat.length() > 1.0 else Vector2(1.0, 0.0)
			var seg_len := minf(flat.length(), max_seg)
			const ROTATIONS: Array[float] = [0.0, 30.0, -30.0, 60.0, -60.0, 90.0, -90.0, 120.0, -120.0, 150.0, -150.0, 180.0]

			for deg in ROTATIONS:
				var rad := deg_to_rad(deg)
				var c := cos(rad)
				var s := sin(rad)
				var dir := Vector2(base_dir.x * c - base_dir.y * s, base_dir.x * s + base_dir.y * c)
				var segment_goal := start_pos + Vector3(dir.x, 0.0, dir.y) * seg_len
				var terrain_y := TerrainNavGrid.sample_height(segment_goal.x, segment_goal.z)
				if terrain_y > TerrainNavGrid.IMPASSABLE * 0.5:
					segment_goal.y = terrain_y
				else:
					segment_goal.y = start_pos.y
				
				var candidate := NavGraph.find_path(start_pos, segment_goal, clearance)
				if candidate.is_empty():
					continue
				
				# Math calculations
				var candidate_len := 0.0
				for i in range(1, candidate.size()):
					candidate_len += Vector2(candidate[i].x - candidate[i - 1].x, candidate[i].z - candidate[i - 1].z).length()
				
				if candidate_len > seg_len * 3.0:
					continue
				best_path = candidate
				break
			
			if best_path.is_empty():
				status_code = 2

		return {
			"best_path": best_path,
			"target": raw_target,
			"status_code": status_code,
			"no_anchor_cooldown": no_anchor_retry_cooldown,
			"path_cooldown": retry_cooldown,
		}

	var job_id: int = NavPathScheduler.request_work(work, _on_navigation_path_job_result, 0, "EnemyVehicle.navigation")
	if job_id < 0:
		_is_pathfinding = false
		_nav_retry_cooldown_s = maxf(_nav_retry_cooldown_s, retry_cooldown)

func _on_navigation_path_job_result(result: Variant) -> void:
	if not result is Dictionary:
		_is_pathfinding = false
		_nav_retry_cooldown_s = maxf(_nav_retry_cooldown_s, path_retry_cooldown_s)
		return
	var data: Dictionary = result as Dictionary
	_on_navigation_path_computed(
		data.get("best_path", []),
		data.get("target", Vector3.INF),
		int(data.get("status_code", 2)),
		float(data.get("no_anchor_cooldown", path_no_anchor_retry_cooldown_s)),
		float(data.get("path_cooldown", path_retry_cooldown_s)))

func _on_navigation_path_computed(best_path: Array[Vector3], target_at_request_time: Vector3, status_code: int, no_anchor_cooldown: float, path_cooldown: float) -> void:
	_is_pathfinding = false
	if not is_instance_valid(self):
		return
	
	# If the target changed while queued/running, wait for the regular repath cadence.
	var current_target_dest := _get_raw_navigation_destination()
	if _flat_distance(target_at_request_time, current_target_dest) > 1.0:
		_nav_repath_timer_s = 0.0
		return

	_nav_repath_timer_s = 0.0
	_nav_stuck_timer_s = 0.0
	_nav_prev_wp_distance = INF
	_nav_retry_cooldown_s = 0.0
	_nav_path_goal = target_at_request_time

	if status_code == 1: # NO_ANCHOR
		_nav_retry_cooldown_s = maxf(_nav_retry_cooldown_s, no_anchor_cooldown)
		if _nav_path_index >= _nav_path_positions.size():
			_nav_path_positions.clear()
			_nav_path_index = 0
		return
	elif status_code == 2 or best_path.is_empty(): # NO_PATH
		_nav_retry_cooldown_s = maxf(_nav_retry_cooldown_s, path_cooldown)
		if _nav_path_index >= _nav_path_positions.size():
			_clear_navigation_path()
		return

	_nav_path_positions = best_path
	_nav_path_index = 0
	_consume_reached_nav_waypoints(target_at_request_time, false)

func _consume_reached_nav_waypoints(raw_target: Vector3, _allow_replan: bool = true) -> void:
	var reach_dist := maxf(path_waypoint_reach_distance, waypoint_reach_distance)
	while _nav_path_index < _nav_path_positions.size():
		if _flat_distance(global_position, _nav_path_positions[_nav_path_index]) > reach_dist:
			break
		_nav_path_index += 1
		_nav_stuck_timer_s = 0.0
		_nav_prev_wp_distance = INF
	if _allow_replan and _nav_path_index >= _nav_path_positions.size() and _flat_distance(global_position, raw_target) > reach_dist:
		_recompute_navigation_path(raw_target)

func _clear_navigation_path() -> void:
	_nav_path_positions.clear()
	_nav_path_index = 0
	_nav_safe_target = Vector3.INF
	_nav_repath_timer_s = path_replan_interval_s
	_nav_stuck_timer_s = 0.0
	_nav_prev_wp_distance = INF
	_nav_retry_cooldown_s = 0.0

func _get_raw_navigation_destination() -> Vector3:
	if platoon and is_instance_valid(platoon) and platoon.has_active_objective():
		var platoon_destination: Vector3 = platoon.get_destination_for(self)
		if _use_platoon_shared_route_navigation():
			return platoon.get_shared_route_destination_for(self, platoon_destination)
		if not platoon.has_any_member_in_combat():
			return platoon.get_formation_destination_for(self, platoon_destination)
		return platoon_destination
	if not _waypoint_positions.is_empty():
		return _waypoint_positions[_waypoint_index]
	return global_position

func _get_follow_navigation_destination() -> Vector3:
	var raw_target := _get_raw_navigation_destination()
	if _use_platoon_shared_route_navigation():
		return raw_target
	if not use_waypoint_pathfinding or not NavGraph.is_ready():
		return raw_target
	if _nav_path_index < _nav_path_positions.size():
		return _nav_path_positions[_nav_path_index]
	if _is_valid_navigation_target(_nav_safe_target) and _is_direct_navigation_segment_safe(global_position, _nav_safe_target):
		return _nav_safe_target
	return global_position

func _use_platoon_shared_route_navigation() -> bool:
	return platoon != null \
		and is_instance_valid(platoon) \
		and platoon.should_vehicle_use_shared_route(self)

func _has_dynamic_navigation_goal() -> bool:
	if platoon == null or not is_instance_valid(platoon) or not platoon.has_active_objective():
		return false
	match platoon.objective_type:
		GroundVehiclePlatoon.ObjectiveType.PURSUE_ENEMIES, GroundVehiclePlatoon.ObjectiveType.PROTECT_NODE, GroundVehiclePlatoon.ObjectiveType.ATTACK_NODE, GroundVehiclePlatoon.ObjectiveType.PROTECT_POSITION, GroundVehiclePlatoon.ObjectiveType.ATTACK_POSITION, GroundVehiclePlatoon.ObjectiveType.ESCORT_CARRIER:
			return true
		_:
			return false

func _get_navigation_replan_interval_s() -> float:
	if _has_dynamic_navigation_goal():
		return maxf(dynamic_objective_replan_interval_s, path_replan_interval_s)
	return maxf(path_replan_interval_s, 0.1)

func _update_path_stuck_state(delta: float, follow_destination: Vector3) -> void:
	if _use_platoon_shared_route_navigation():
		_nav_stuck_timer_s = 0.0
		_nav_prev_wp_distance = INF
		return
	if not use_waypoint_pathfinding or _nav_path_index >= _nav_path_positions.size():
		_nav_stuck_timer_s = 0.0
		_nav_prev_wp_distance = INF
		return
	var wp_dist := _flat_distance(global_position, follow_destination)
	if wp_dist > _nav_prev_wp_distance + 0.5:
		_nav_stuck_timer_s += delta
		if _nav_stuck_timer_s >= path_stuck_timeout_s and _nav_retry_cooldown_s <= 0.0:
			_recompute_navigation_path(_get_raw_navigation_destination())
			_nav_stuck_timer_s = 0.0
			_nav_prev_wp_distance = INF
			return
	else:
		_nav_stuck_timer_s = 0.0
	_nav_prev_wp_distance = wp_dist

func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func _path_length(path: Array[Vector3]) -> float:
	var total := 0.0
	for i in range(1, path.size()):
		total += _flat_distance(path[i], path[i - 1])
	return total

func _get_safe_navigation_target(raw_target: Vector3) -> Vector3:
	var projected_target: Vector3 = _project_destination_to_baked_ground(raw_target)
	if not use_waypoint_pathfinding or not NavGraph.is_ready():
		return projected_target
	if _can_anchor_navigation_target(projected_target):
		return projected_target

	var search_radius: float = maxf(path_goal_anchor_search_radius_m, path_waypoint_reach_distance)
	var sample_count: int = maxi(path_goal_anchor_search_samples, 4)
	var base_vec := Vector2(projected_target.x - global_position.x, projected_target.z - global_position.z)
	var base_angle: float = atan2(base_vec.y, base_vec.x) if base_vec.length_squared() > 1.0 else 0.0
	var best_target: Vector3 = Vector3.INF
	var best_score: float = INF
	var ring_count: int = 3
	for ring_idx in range(1, ring_count + 1):
		var radius: float = search_radius * float(ring_idx) / float(ring_count)
		for sample_idx in range(sample_count):
			var angle: float = base_angle + TAU * float(sample_idx) / float(sample_count)
			var candidate := projected_target + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
			candidate = _project_destination_to_baked_ground(candidate)
			if not _can_anchor_navigation_target(candidate):
				continue
			var score: float = _flat_distance(candidate, projected_target) + _flat_distance(candidate, global_position) * 0.1
			if score < best_score:
				best_score = score
				best_target = candidate
	if _is_valid_navigation_target(best_target):
		return best_target
	return Vector3.INF

func _can_anchor_navigation_target(target_world: Vector3) -> bool:
	if not _is_valid_navigation_target(target_world):
		return false
	return NavGraph.can_anchor(target_world, path_min_clearance_m, path_goal_anchor_search_radius_m)

func _is_direct_navigation_segment_safe(from_world: Vector3, to_world: Vector3) -> bool:
	if not TerrainNavGrid.is_ready():
		return true
	var from_pos := _project_destination_to_baked_ground(from_world)
	var to_pos := _project_destination_to_baked_ground(to_world)
	if not _is_valid_navigation_target(from_pos) or not _is_valid_navigation_target(to_pos):
		return false
	var planar: Vector2 = Vector2(to_pos.x - from_pos.x, to_pos.z - from_pos.z)
	var distance_m: float = planar.length()
	if distance_m <= maxf(path_waypoint_reach_distance, waypoint_reach_distance):
		return true
	var dir: Vector2 = planar / maxf(distance_m, 0.001)
	var sample_step_m: float = maxf(path_direct_safety_sample_step_m, 5.0)
	var prev_height: float = from_pos.y
	var max_slope_m: float = NavGraph.max_slope_m if NavGraph != null else 18.0
	var d: float = sample_step_m
	while d < distance_m:
		var sample := Vector3(from_pos.x + dir.x * d, 0.0, from_pos.z + dir.y * d)
		var sample_height: float = TerrainNavGrid.sample_height(sample.x, sample.z)
		if sample_height <= TerrainNavGrid.IMPASSABLE * 0.5:
			return false
		var gx: int = int((sample.x - TerrainNavGrid._origin_x) / TerrainNavGrid.cell_size_m)
		var gz: int = int((sample.z - TerrainNavGrid._origin_z) / TerrainNavGrid.cell_size_m)
		if TerrainNavGrid.is_cell_near_steep_slope(gx, gz, max_slope_m):
			return false
		if absf(sample_height - prev_height) > max_slope_m:
			return false
		prev_height = sample_height
		d += sample_step_m
	return true

func _project_destination_to_baked_ground(candidate: Vector3) -> Vector3:
	var projected := candidate
	var terrain_y: float = TerrainNavGrid.sample_height(candidate.x, candidate.z)
	if terrain_y > TerrainNavGrid.IMPASSABLE * 0.5:
		projected.y = terrain_y
		return projected
	return _project_destination_to_ground(candidate)

func _is_valid_navigation_target(target_world: Vector3) -> bool:
	return is_finite(target_world.x) and is_finite(target_world.y) and is_finite(target_world.z)

func _get_cached_carrier() -> Node3D:
	if _cached_carrier and is_instance_valid(_cached_carrier):
		return _cached_carrier
	_cached_carrier = get_tree().get_first_node_in_group("carrier") as Node3D
	return _cached_carrier

func _refresh_spacing_candidates() -> void:
	_cached_spacing_candidates.clear()
	for node in get_tree().get_nodes_in_group("ground_vehicles"):
		if node is Node3D and is_instance_valid(node):
			_cached_spacing_candidates.append(node as Node3D)
	_spacing_cache_timer_s = spacing_cache_refresh_s

func _get_spacing_candidates(delta: float) -> Array[Node3D]:
	if platoon and is_instance_valid(platoon):
		return platoon.get_members()
	_spacing_cache_timer_s = maxf(_spacing_cache_timer_s - delta, 0.0)
	if _cached_spacing_candidates.is_empty() or _spacing_cache_timer_s <= 0.0:
		_refresh_spacing_candidates()
	return _cached_spacing_candidates

func _drive_to_waypoint(delta: float) -> void:
	velocity.y = _spring_velocity_y

	var hold_in_combat: bool = _has_combat_target()

	if not _has_navigation_destination():
		var stop_accel: float = acceleration * delta * 2.5
		velocity.x = move_toward(velocity.x, 0.0, stop_accel)
		velocity.z = move_toward(velocity.z, 0.0, stop_accel)
		move_and_slide()
		return

	var nav_dest: Vector3 = _get_follow_navigation_destination()
	var dest: Vector3 = _apply_combat_mobility(nav_dest)
	dest = _apply_platoon_cohesion(dest)
	_update_path_stuck_state(delta, nav_dest)

	var current_forward: Vector3 = global_basis.z
	current_forward.y = 0.0
	current_forward = current_forward.normalized() if current_forward.length_squared() > 0.0001 else Vector3.FORWARD
	var desired_dir: Vector3 = current_forward
	if hold_in_combat and current_target and is_instance_valid(current_target):
		desired_dir = current_target.global_position - global_position
		desired_dir.y = 0.0
	else:
		var to_dest: Vector3 = dest - global_position
		to_dest.y = 0.0
		if to_dest.length_squared() <= 0.01:
			var stop_accel_idle: float = acceleration * delta * 2.5
			velocity.x = move_toward(velocity.x, 0.0, stop_accel_idle)
			velocity.z = move_toward(velocity.z, 0.0, stop_accel_idle)
			move_and_slide()
			return
		desired_dir = to_dest
	if desired_dir.length_squared() <= 0.0001:
		desired_dir = current_forward
	else:
		desired_dir = desired_dir.normalized()

	# Compute avoidance nudge BEFORE steering so it influences direction, not just velocity
	var nudge := Vector3.ZERO
	if not hold_in_combat:
		for other in _get_spacing_candidates(delta):
			if other == self or not is_instance_valid(other) or not other is Node3D:
				continue
			var away: Vector3 = global_position - (other as Node3D).global_position
			away.y = 0.0
			var dist: float = away.length()
			var min_spacing: float = maxf(preferred_vehicle_spacing_min_m, 5.0)
			if dist < min_spacing and dist > 0.01:
				var strength: float = (min_spacing - dist) / min_spacing
				nudge += away.normalized() * strength

	# Elliptical carrier avoidance — gentle flow around
	var carrier := _get_cached_carrier()
	if carrier and is_instance_valid(carrier):
		var local_pos: Vector3 = carrier.to_local(global_position)
		var rx: float = 70.0
		var rz: float = 90.0
		var nx: float = local_pos.x / rx
		var nz: float = local_pos.z / rz
		var ellipse_dist: float = sqrt(nx * nx + nz * nz)
		if ellipse_dist < 1.4 and ellipse_dist > 0.01:
			var radial_local := Vector3(local_pos.x / (rx * rx), 0.0, local_pos.z / (rz * rz))
			if radial_local.length_squared() > 0.0001:
				radial_local = radial_local.normalized()
			var tangent_local := Vector3(-radial_local.z, 0.0, radial_local.x)
			var desired_local: Vector3 = carrier.global_basis.inverse() * desired_dir
			if tangent_local.dot(Vector3(desired_local.x, 0.0, desired_local.z)) < 0.0:
				tangent_local = -tangent_local
			var strength: float = clampf((1.4 - ellipse_dist) / 0.4, 0.0, 1.0)
			if ellipse_dist < 1.0:
				strength = 1.0
			var push_local := (radial_local * 0.4 + tangent_local * 0.6).normalized()
			var push_world: Vector3 = carrier.global_basis * push_local
			push_world.y = 0.0
			nudge += push_world * strength * 3.0

	# Track whether avoidance is active
	var nudge_active: bool = nudge.length_squared() > 0.001

	# Blend avoidance into desired direction so vehicles steer around obstacles
	if nudge_active:
		var nudge_weight: float = clampf(nudge.length(), 1.0, 6.0)
		desired_dir = (desired_dir + nudge.normalized() * nudge_weight).normalized()

	var cross_y: float = current_forward.cross(desired_dir).y
	var dot: float = clampf(current_forward.dot(desired_dir), -1.0, 1.0)
	var turn_angle_deg: float = rad_to_deg(acos(dot))
	var planar_speed: float = Vector2(velocity.x, velocity.z).length()

	var steer_target: float = clamp(cross_y, -1.0, 1.0)
	if hold_in_combat:
		steer_target = clamp(cross_y * 0.7, -0.65, 0.65)
	var turn_rate_scale: float = lerpf(0.2, 1.0, clampf(planar_speed / maxf(max_speed, 0.1), 0.0, 1.0))
	if nudge_active:
		turn_rate_scale = maxf(turn_rate_scale, 0.5)  # Don't let avoidance kill turn rate
	if hold_in_combat:
		turn_rate_scale = maxf(turn_rate_scale, 0.35)
	global_rotate(Vector3.UP, steer_target * turn_speed * delta * turn_rate_scale)

	var throttle: float = 1.0
	if hold_in_combat and current_target and is_instance_valid(current_target):
		var target_distance: float = global_position.distance_to(current_target.global_position)
		if target_distance <= combat_stop_distance_m and turn_angle_deg <= combat_track_angle_deg:
			throttle = 0.0
		elif target_distance <= combat_stop_distance_m:
			throttle = combat_creep_speed_mps / maxf(max_speed, 0.1)
		else:
			var closing_speed: float = clampf((target_distance - combat_stop_distance_m) / maxf(combat_hold_distance_m - combat_stop_distance_m, 1.0), 0.25, 0.7)
			throttle = maxf(closing_speed, combat_creep_speed_mps / maxf(max_speed, 0.1))
	var forward: Vector3 = global_basis.z
	forward.y = 0.0
	forward = forward.normalized() if forward.length_squared() > 0.0001 else Vector3.FORWARD

	# Kill lateral velocity — vehicles only move along their forward axis
	var current_planar := Vector3(velocity.x, 0.0, velocity.z)
	var forward_speed: float = current_planar.dot(forward)
	var cruise_speed_limit: float = _get_platoon_speed_limit()
	var target_speed: float = throttle * minf(max_speed, cruise_speed_limit)
	if hold_in_combat:
		forward_speed = move_toward(forward_speed, target_speed, acceleration * delta * (4.0 if forward_speed > target_speed else 1.8))
	else:
		forward_speed = move_toward(forward_speed, target_speed, acceleration * delta * (4.0 if forward_speed > target_speed else 1.0))
	velocity.x = forward.x * forward_speed
	velocity.z = forward.z * forward_speed

	move_and_slide()

	for w in _front_wheels:
		w.rotation.y = steer_target * max_steering_angle

func _get_navigation_destination() -> Vector3:
	return _get_follow_navigation_destination()

func _has_navigation_destination() -> bool:
	return (platoon and is_instance_valid(platoon) and platoon.has_active_objective()) or not _waypoint_positions.is_empty()

func _get_platoon_speed_limit() -> float:
	if not platoon or not is_instance_valid(platoon):
		return max_speed
	if platoon.has_any_member_in_combat():
		return max_speed
	return platoon.get_platoon_speed_limit(max_speed)

func _apply_platoon_cohesion(base_destination: Vector3) -> Vector3:
	if _has_combat_target():
		return global_position
	if not platoon or not is_instance_valid(platoon):
		return base_destination
	if _use_platoon_shared_route_navigation():
		return base_destination
	if platoon.has_any_member_in_combat():
		return base_destination
	return platoon.get_formation_destination_for(self, base_destination)

func _update_shoot_and_scoot(delta: float) -> void:
	if not shoot_and_scoot_enabled or not _has_combat_target():
		_combat_hold_timer_s = 0.0
		_combat_is_scooting = false
		_combat_scoot_destination = Vector3.ZERO
		_had_combat_target_last_frame = false
		return
	var engage_distance: float = maxf(combat_hold_distance_m, 25.0)
	if global_position.distance_to(current_target.global_position) > engage_distance:
		_combat_hold_timer_s = 0.0
		_combat_is_scooting = false
		_combat_scoot_destination = Vector3.ZERO
		_had_combat_target_last_frame = false
		return
	if not _had_combat_target_last_frame:
		_combat_is_scooting = false
		_combat_hold_timer_s = maxf(fire_position_hold_s, 0.2)
		_combat_scoot_destination = Vector3.ZERO
		_had_combat_target_last_frame = true
		return
	if _combat_hold_timer_s > 0.0:
		_combat_hold_timer_s -= delta
		return
	if _combat_is_scooting:
		_combat_is_scooting = false
		_combat_hold_timer_s = maxf(fire_position_hold_s, 0.2)
		_combat_scoot_destination = Vector3.ZERO
		return
	_combat_is_scooting = true
	_combat_hold_timer_s = maxf(scoot_move_s, 0.2)
	_combat_scoot_destination = _choose_scoot_destination()

func _apply_combat_mobility(base_destination: Vector3) -> Vector3:
	if not _has_combat_target():
		return base_destination
	return global_position

func _has_combat_target() -> bool:
	return current_target != null and is_instance_valid(current_target) and not _is_air_target(current_target)

func _should_hold_combat_position() -> bool:
	return _has_combat_target()

func _is_air_target(target: Node3D) -> bool:
	return target != null and (target.is_in_group("aircraft") or target.is_in_group("ai_aircraft"))

func _choose_scoot_destination() -> Vector3:
	if not current_target or not is_instance_valid(current_target):
		return global_position
	var to_target: Vector3 = current_target.global_position - global_position
	to_target.y = 0.0
	if to_target.length_squared() < 0.01:
		return global_position
	var forward_from_target: Vector3 = to_target.normalized()
	var lateral: Vector3 = Vector3(-forward_from_target.z, 0.0, forward_from_target.x)
	if randf() < 0.5:
		lateral = -lateral
	var scoot_offset: Vector3 = lateral * scoot_distance_m + forward_from_target * randf_range(-0.4, 0.3) * scoot_distance_m
	var candidate: Vector3 = global_position + scoot_offset
	return _project_destination_to_ground(candidate)

func _project_destination_to_ground(candidate: Vector3) -> Vector3:
	var space_state := get_world_3d().direct_space_state
	var hit := space_state.intersect_ray(
		PhysicsRayQueryParameters3D.create(candidate + Vector3.UP * 2000.0, candidate - Vector3.UP * 200.0)
	)
	if hit:
		candidate.y = hit.position.y + 2.0
	return candidate

# --- Combat ---

func get_team() -> int:
	return team

func take_damage(damage_amount: float) -> void:
	if is_dying or current_health <= 0:
		return
	current_health -= damage_amount
	current_health = max(current_health, 0.0)
	if current_health <= 0:
		is_dying = true
		var death_timer = Timer.new()
		death_timer.wait_time = randf_range(0.0, 0.6)
		death_timer.one_shot = true
		death_timer.timeout.connect(explode)
		death_timer.timeout.connect(death_timer.queue_free)
		add_child(death_timer)
		death_timer.start()

func explode() -> void:
	emit_signal("destroyed", self)
	if platoon and is_instance_valid(platoon):
		platoon.unregister_vehicle(self)
	var explosion_res = load("res://Projectiles/Explosion/explosion.tscn")
	if explosion_res:
		var exp = explosion_res.instantiate()
		get_parent().add_child(exp)
		exp.global_position = global_position
	VehicleWreck.spawn(get_parent(), global_transform, velocity)
	queue_free()
