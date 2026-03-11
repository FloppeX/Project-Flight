extends CharacterBody3D
class_name VehicleFriendlyLight

signal destroyed(vehicle)

# --- Movement ---
@export var max_speed: float = 15.0
@export var acceleration: float = 12.0
@export var turn_speed: float = 1.8
@export var max_steering_angle: float = 0.5

# --- Waypoints ---
@export var waypoints: Array[NodePath] = []
@export var loop_waypoints: bool = true
@export var waypoint_reach_distance: float = 8.0

# --- Combat ---
@export var max_health: float = 50.0
@export var team: int = 1
@export var turret_range: float = 400.0
@export var burst_length: float = 1.5
@export var delay_length: float = 3.0
@export var turret_weapon: PackedScene
@export var aim_skill: float = 0.75

# State
var current_health: float
var is_dying: bool = false
var turret_controller: TurretController
var current_target: Node3D

var _waypoint_positions: Array[Vector3] = []
var _waypoint_index: int = 0

var _front_wheels: Array[Node3D] = []
var _body_node: Node3D
var _all_wheel_nodes: Array[Node3D] = []
var _wheel_nominal_positions: Array[Vector3] = []

const GRAVITY: float = 25.0
const WHEEL_RADIUS: float = 0.4
const BODY_RIDE_HEIGHT: float = 1.72
const MIN_VEHICLE_SEPARATION: float = 20.0

func _ready() -> void:
	current_health = max_health
	floor_snap_length = 0.5
	floor_max_angle = deg_to_rad(50.0)
	add_to_group("friendlies")
	add_to_group("ground_vehicles")
	add_to_group("team_" + str(team))
	_resolve_waypoints()
	_collect_wheel_nodes()
	
	# Look for a turret controller child
	for child in get_children():
		if child is TurretController:
			turret_controller = child
			break
			
	if not turret_controller:
		push_warning("VehicleFriendlyLight: No TurretController found as child!")
	else:
		turret_controller.team = team
		turret_controller.max_range = turret_range
		turret_controller.burst_length = burst_length
		turret_controller.delay_length = delay_length
		turret_controller.aim_skill = aim_skill
		if turret_weapon and turret_controller.weapon_instance == null:
			turret_controller.mount_weapon(turret_weapon)

func _collect_wheel_nodes() -> void:
	_body_node = get_node_or_null("Body")
	for wname in ["wheel_right_1", "wheel_right_2", "wheel_right_3",
			"wheel_left_1", "wheel_left_2", "wheel_left_3"]:
		var w = get_node_or_null(wname)
		if w:
			_all_wheel_nodes.append(w)
			_wheel_nominal_positions.append(w.position)
			if wname.ends_with("_1"):
				_front_wheels.append(w)

func _resolve_waypoints() -> void:
	_waypoint_positions.clear()
	for path in waypoints:
		var node = get_node_or_null(path)
		if node is Node3D:
			_waypoint_positions.append((node as Node3D).global_position)

func set_patrol_waypoints(positions: Array[Vector3]) -> void:
	_waypoint_positions = positions.duplicate()
	_waypoint_index = 0

func _physics_process(delta: float) -> void:
	if is_dying:
		return
		
	if turret_controller:
		current_target = turret_controller.current_target
	else:
		current_target = null
		
	_drive_to_waypoint(delta)
	_update_wheel_visuals()

# --- Wheel Visuals ---

func _update_wheel_visuals() -> void:
	if _all_wheel_nodes.is_empty():
		return
	var space = get_world_3d().direct_space_state
	var params = PhysicsRayQueryParameters3D.new()
	params.exclude = [get_rid()]

	var ground_heights: Array[float] = []
	var ground_normals: Array[Vector3] = []

	for i in _all_wheel_nodes.size():
		var nominal: Vector3 = _wheel_nominal_positions[i]
		params.from = to_global(Vector3(nominal.x, 3.0, nominal.z))
		params.to   = to_global(Vector3(nominal.x, -2.0, nominal.z))
		var hit = space.intersect_ray(params)
		if hit:
			var local_y: float = to_local(hit.position).y
			_all_wheel_nodes[i].position.y = local_y + WHEEL_RADIUS
			ground_heights.append(local_y)
			ground_normals.append(hit.normal)
		else:
			_all_wheel_nodes[i].position.y = nominal.y
			ground_heights.append(nominal.y)
			ground_normals.append(Vector3.UP)

	if not _body_node or ground_heights.is_empty():
		return

	# Average ground height → body Y
	var avg_y: float = 0.0
	for h in ground_heights:
		avg_y += h
	avg_y /= ground_heights.size()
	_body_node.position.y = avg_y + BODY_RIDE_HEIGHT

	# Average normal → body pitch / roll
	var avg_normal := Vector3.ZERO
	for n in ground_normals:
		avg_normal += n
	avg_normal = avg_normal.normalized()

	var local_normal: Vector3 = global_transform.basis.inverse() * avg_normal
	var pitch: float = atan2(-local_normal.z, local_normal.y)
	var roll: float  = atan2( local_normal.x, local_normal.y)
	_body_node.rotation = Vector3(pitch, 0.0, -roll)

# --- Driving AI ---

func _drive_to_waypoint(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = -2.0

	var has_target := current_target != null and is_instance_valid(current_target)

	# Determine destination: combat target overrides patrol waypoint
	var dest: Vector3
	if has_target:
		dest = current_target.global_position
	elif not _waypoint_positions.is_empty():
		dest = _waypoint_positions[_waypoint_index]
		var to_wp := (dest - global_position)
		to_wp.y = 0.0
		if to_wp.length() < waypoint_reach_distance:
			if loop_waypoints:
				_waypoint_index = (_waypoint_index + 1) % _waypoint_positions.size()
			else:
				_waypoint_index = min(_waypoint_index + 1, _waypoint_positions.size() - 1)
			move_and_slide()
			return
	else:
		velocity.x = move_toward(velocity.x, 0.0, acceleration * delta * 2)
		velocity.z = move_toward(velocity.z, 0.0, acceleration * delta * 2)
		move_and_slide()
		return

	var to_dest: Vector3 = dest - global_position
	to_dest.y = 0.0
	var desired_dir: Vector3 = to_dest.normalized()
	var current_forward: Vector3 = global_transform.basis.z

	var cross_y: float = current_forward.cross(desired_dir).y
	var dot: float = current_forward.dot(desired_dir)

	var steer_target: float = clamp(cross_y * 2.0, -1.0, 1.0)
	rotate_y(steer_target * turn_speed * delta)

	var throttle: float = clamp((dot + 1.0) * 0.5, 0.0, 1.0) * (1.0 - abs(steer_target) * 0.3)
	var forward: Vector3 = global_transform.basis.z

	# Separation: push away from any ground vehicle within MIN_VEHICLE_SEPARATION
	var sep := Vector3.ZERO
	for other in get_tree().get_nodes_in_group("ground_vehicles"):
		if other == self or not is_instance_valid(other) or not other is Node3D:
			continue
		var away: Vector3 = global_position - (other as Node3D).global_position
		away.y = 0.0
		var dist: float = away.length()
		if dist < MIN_VEHICLE_SEPARATION and dist > 0.01:
			sep += away.normalized() * (MIN_VEHICLE_SEPARATION - dist) / MIN_VEHICLE_SEPARATION * max_speed

	velocity.x = move_toward(velocity.x, forward.x * throttle * max_speed + sep.x, acceleration * delta)
	velocity.z = move_toward(velocity.z, forward.z * throttle * max_speed + sep.z, acceleration * delta)

	move_and_slide()

	for w in _front_wheels:
		w.rotation.y = steer_target * max_steering_angle

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
	var explosion_res = load("res://Projectiles/Explosion/explosion.tscn")
	if explosion_res:
		var exp = explosion_res.instantiate()
		get_parent().add_child(exp)
		exp.global_position = global_position
	VehicleWreck.spawn(get_parent(), global_transform)
	queue_free()
