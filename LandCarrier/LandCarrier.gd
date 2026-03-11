extends CharacterBody3D
class_name LandCarrier

# --- Waypoints ---
@export var waypoints: Array[NodePath] = []
@export var loop_waypoints: bool = false
@export var waypoint_reach_distance: float = 50.0

# --- Movement ---
@export var max_speed: float = 8.0
@export var acceleration: float = 1.5
@export var turn_speed: float = 0.25

# --- Height ---
@export var height_smoothing: float = 0.6  # slow, stable height following

# --- Obstacle avoidance (short-range reactive) ---
@export var obstacle_lookahead_m: float = 300.0
@export var obstacle_width_m: float = 120.0
@export var obstacle_height_threshold_m: float = 20.0

# --- Pathfinding ---
@export var path_max_slope_m: float = 28.0    # max passable height rise per cell (carrier-specific)
@export var path_max_segment_m: float = 800.0 # replan distance; long routes are split into segments

const BODY_RIDE_HEIGHT: float = 40.0  # Root floats 40m above terrain: tread node at terrain+8, tread bottom at terrain+0
const TREAD_GROUND_OFFSET: float = 8.0  # Tread node is 8m above its bottom surface (node at -32 local, bottom at -40 local)
const MAX_TREAD_STEER: float = 0.4    # ~23 deg max tread pivot angle

# --- State ---
var _raw_waypoints: Array[Vector3] = []            # user-given destinations
var _raw_waypoint_index: int = 0
var _waypoint_positions: Array[Vector3] = []       # A*-computed path for current segment
var _waypoint_index: int = 0
var _tread_nodes: Array[Node3D] = []
var _tread_local_xz: Array[Vector2] = []           # initial local XZ from editor placement
var _tread_initial_rot_y: Array[float] = []        # initial local rotation.y from editor placement
var _current_steer: float = 0.0
var _tread_steer: float = 0.0   # smoothed tread pivot angle
var treads: Array[CarrierTread] = []
var elevator: Node3D

func _ready():
	add_to_group("carrier")
	visible = false
	_resolve_waypoints()
	_collect_tread_nodes()
	find_treads()
	elevator = find_child("Elevator")
	if elevator and elevator.has_method("setup"):
		elevator.setup(self)
	if _raw_waypoints.is_empty():
		call_deferred("_set_north_heading")
	else:
		call_deferred("_compute_next_path_segment")

func _resolve_waypoints() -> void:
	_raw_waypoints.clear()
	for path in waypoints:
		var node = get_node_or_null(path)
		if node is Node3D:
			_raw_waypoints.append((node as Node3D).global_position)

func set_patrol_waypoints(positions: Array[Vector3]) -> void:
	_raw_waypoints = positions.duplicate()
	_raw_waypoint_index = 0
	_waypoint_positions.clear()
	_waypoint_index = 0
	_compute_next_path_segment()

func _set_north_heading() -> void:
	# Wait for the nav grid to bake, then pick a random start and head for the far edge.
	if TerrainNavGrid.is_ready():
		_start_random_patrol()
	else:
		TerrainNavGrid.bake_complete.connect(_start_random_patrol, CONNECT_ONE_SHOT)

func _start_random_patrol() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()

	# Place carrier at a random flat, passable point on the terrain
	var start: Vector3 = TerrainNavGrid.get_random_passable_position(rng, path_max_slope_m)
	if start != Vector3.ZERO:
		global_position = Vector3(start.x, start.y + BODY_RIDE_HEIGHT, start.z)

	visible = true

	# Aim for the passable perimeter point furthest from here
	var destination: Vector3 = TerrainNavGrid.get_furthest_edge_position(global_position)
	_raw_waypoints = [destination]
	_raw_waypoint_index = 0
	_compute_next_path_segment()
	print("[LandCarrier] Random patrol: start=", global_position, " dest=", destination)

func _compute_next_path_segment() -> void:
	visible = true
	if _raw_waypoints.is_empty():
		return
	if _raw_waypoint_index >= _raw_waypoints.size():
		if loop_waypoints:
			_raw_waypoint_index = 0
		else:
			return
	var target := _raw_waypoints[_raw_waypoint_index]
	TerrainNavGrid.request_path(global_position, target,
		path_max_slope_m, path_max_segment_m,
		func(path: Array): _on_path_ready(path))

func _on_path_ready(path: Array) -> void:
	_waypoint_positions.clear()
	for p in path:
		_waypoint_positions.append(p as Vector3)
	_waypoint_index = 0
	print("[LandCarrier] Path ready: ", _waypoint_positions.size(), " waypoints")

func _advance_waypoint_or_replan() -> void:
	# Called when the last waypoint in the current A* segment is reached.
	# Check if we've actually arrived at the raw destination, or just finished a segment.
	if _raw_waypoints.is_empty():
		return
	var raw_target := _raw_waypoints[_raw_waypoint_index]
	var flat_dist := Vector2(global_position.x - raw_target.x, global_position.z - raw_target.z).length()
	if flat_dist < waypoint_reach_distance:
		# Arrived at the raw waypoint — advance to the next one
		_raw_waypoint_index += 1
		if _raw_waypoint_index >= _raw_waypoints.size():
			if loop_waypoints:
				_raw_waypoint_index = 0
			else:
				_waypoint_positions.clear()
				return
	# Replan from current position toward the (possibly new) raw waypoint
	_compute_next_path_segment()

func _collect_tread_nodes() -> void:
	_tread_nodes.clear()
	_tread_local_xz.clear()
	_tread_initial_rot_y.clear()
	for child in get_children():
		if child is CarrierTread:
			_tread_nodes.append(child)
			_tread_local_xz.append(Vector2(child.position.x, child.position.z))
			_tread_initial_rot_y.append(child.rotation.y)

func find_treads() -> void:
	treads.clear()
	for child in get_children():
		if child is CarrierTread:
			treads.append(child)

func _physics_process(delta: float) -> void:
	var transform_before := global_transform
	_drive_to_waypoint(delta)       # sets _current_steer
	_update_tread_visuals(delta)    # uses _current_steer
	if elevator and elevator.has_method("update"):
		elevator.update(delta)
	_carry_deck_passengers(global_transform, transform_before)

func _carry_deck_passengers(current_transform: Transform3D, old_transform: Transform3D) -> void:
	if current_transform.is_equal_approx(old_transform):
		return
	var transform_delta: Transform3D = current_transform * old_transform.affine_inverse()
	for group in ["aircraft", "ai_aircraft", "tractor_bot"]:
		for node in get_tree().get_nodes_in_group(group):
			if not is_instance_valid(node) or not node is Node3D:
				continue
			var n := node as Node
			var has_brake := n.has_meta("parking_brake") and bool(n.get_meta("parking_brake"))
			var has_transport := n.has_meta("carrier_transport_mode") and bool(n.get_meta("carrier_transport_mode"))
			var on_carrier := has_brake or has_transport
			# On catapult: controls_disabled is set (but not parking_brake/transport) until the moment of release
			var on_catapult := n.has_meta("controls_disabled") and bool(n.get_meta("controls_disabled")) and not has_brake and not has_transport
			if on_carrier or on_catapult:
				(node as Node3D).global_transform = transform_delta * (node as Node3D).global_transform
			if (on_carrier or on_catapult) and Engine.get_process_frames() % 120 == 0:
				var plane_z = snappedf((node as Node3D).global_position.z, 0.1)
				var carrier_z = snappedf(global_position.z, 0.1)
				print("[Deck] ", node.name, " z=", plane_z, "  carrier z=", carrier_z, "  gap=", snappedf(plane_z - carrier_z, 0.1))
	# Move catapult wheel-latch joints with the carrier so they do not anchor the aircraft in world-space
	for joint in get_tree().get_nodes_in_group("carrier_pin_joint"):
		if is_instance_valid(joint) and joint is Node3D:
			(joint as Node3D).global_transform = transform_delta * (joint as Node3D).global_transform

# --- Terrain following via 6 tread raycasts ---

func _update_tread_visuals(delta: float) -> void:
	_tread_steer = lerp(_tread_steer, _current_steer, delta * 1.5)
	var space = get_world_3d().direct_space_state
	var params = PhysicsRayQueryParameters3D.new()

	# Exclude the carrier body AND all tread bodies — treads have big collision boxes
	# that would otherwise be hit by the raycasts, creating a runaway feedback loop.
	var exclude: Array[RID] = [get_rid()]
	for t in _tread_nodes:
		exclude.append((t as CollisionObject3D).get_rid())
	params.exclude = exclude

	var world_heights: Array[float] = []

	for i in _tread_nodes.size():
		var xz: Vector2 = _tread_local_xz[i]
		var world_xz := to_global(Vector3(xz.x, 0.0, xz.y))
		params.from = to_global(Vector3(xz.x,  20.0, xz.y))
		params.to   = to_global(Vector3(xz.x, -300.0, xz.y))
		var hit = space.intersect_ray(params)
		var terrain_y: float
		if hit:
			terrain_y = (hit.position as Vector3).y
		else:
			terrain_y = global_position.y - BODY_RIDE_HEIGHT  # maintain current height

		world_heights.append(terrain_y)

		var tread := _tread_nodes[i] as Node3D
		tread.global_position = Vector3(world_xz.x, terrain_y + TREAD_GROUND_OFFSET, world_xz.z)
		# Apply steering pivot on top of editor rotation, based on initial local Z
		var steer_offset: float = 0.0
		if xz.y > 20.0:
			steer_offset = _tread_steer * MAX_TREAD_STEER
		elif xz.y < -20.0:
			steer_offset = -_tread_steer * MAX_TREAD_STEER
		tread.rotation.y = _tread_initial_rot_y[i] + steer_offset

	# Smooth carrier root Y to sit BODY_RIDE_HEIGHT above average terrain
	if not world_heights.is_empty():
		var avg_y: float = 0.0
		for h in world_heights:
			avg_y += h
		avg_y /= world_heights.size()
		var desired_y: float = avg_y + BODY_RIDE_HEIGHT
		global_position.y = lerp(global_position.y, desired_y, height_smoothing * delta)

# --- Obstacle avoidance (forward terrain raycasts) ---

func _sample_terrain_y(wx: float, wz: float) -> float:
	var h: float = TerrainNavGrid.sample_height(wx, wz)
	if h <= TerrainNavGrid.IMPASSABLE * 0.5:
		return global_position.y - BODY_RIDE_HEIGHT
	return h

func _get_avoidance_steer() -> float:
	var fwd   := global_transform.basis.z
	var right := fwd.cross(global_transform.basis.y)  # starboard direction
	var ahead := global_position + fwd * obstacle_lookahead_m

	var port_pos      := ahead - right * obstacle_width_m
	var center_pos    := ahead
	var starboard_pos := ahead + right * obstacle_width_m
	var port_h      := _sample_terrain_y(port_pos.x,      port_pos.z)
	var center_h    := _sample_terrain_y(center_pos.x,    center_pos.z)
	var starboard_h := _sample_terrain_y(starboard_pos.x, starboard_pos.z)

	var base_y := global_position.y - BODY_RIDE_HEIGHT
	var thresh := obstacle_height_threshold_m

	var left_excess   := maxf(port_h      - base_y - thresh, 0.0)
	var center_excess := maxf(center_h    - base_y - thresh, 0.0)
	var right_excess  := maxf(starboard_h - base_y - thresh, 0.0)

	if left_excess == 0.0 and center_excess == 0.0 and right_excess == 0.0:
		return 0.0

	# Steer toward whichever side has lower terrain; center excess amplifies urgency
	# Positive steer = left turn; negative = right turn (matches cross-product convention)
	var side_diff := right_excess - left_excess  # positive when right is higher → steer left
	var urgency := 1.0 + center_excess * 0.05
	return clamp(side_diff * urgency, -1.0, 1.0)

# --- Waypoint driving (same cross/dot principle as ground vehicles) ---

func _drive_to_waypoint(delta: float) -> void:
	if _waypoint_positions.is_empty() or _waypoint_index >= _waypoint_positions.size():
		var avoidance: float = _get_avoidance_steer()
		_current_steer = clamp(avoidance, -1.0, 1.0) if abs(avoidance) > 0.1 else move_toward(_current_steer, 0.0, delta * 2.0)
		return

	var wp: Vector3 = _waypoint_positions[_waypoint_index]
	var to_wp: Vector3 = wp - global_position
	to_wp.y = 0.0

	if to_wp.length() < waypoint_reach_distance:
		_waypoint_index += 1
		if _waypoint_index >= _waypoint_positions.size():
			_advance_waypoint_or_replan()
		_current_steer = move_toward(_current_steer, 0.0, delta * 2.0)
		return

	var desired_dir: Vector3 = to_wp.normalized()
	var current_forward: Vector3 = global_transform.basis.z

	var cross_y: float = current_forward.cross(desired_dir).y
	var dot: float = current_forward.dot(desired_dir)

	var wp_steer: float = clamp(cross_y * 2.0, -1.0, 1.0)
	var avoidance: float = _get_avoidance_steer()
	# Avoidance overrides waypoint steering when it's the stronger signal
	_current_steer = clamp(wp_steer + avoidance, -1.0, 1.0)
	rotate_y(_current_steer * turn_speed * delta)

	var throttle: float = clamp((dot + 1.0) * 0.5, 0.0, 1.0) * (1.0 - abs(_current_steer) * 0.3)
	var forward: Vector3 = global_transform.basis.z
	global_position.x += forward.x * throttle * max_speed * delta
	global_position.z += forward.z * throttle * max_speed * delta

# --- Speed / direction API (kept for LandCarrierInput compatibility) ---

func set_speed(speed: float) -> void:
	pass  # waypoint AI controls speed now

func set_direction(direction: float) -> void:
	pass

func increase_speed(_amount: float = 5.0) -> void:
	pass

func decrease_speed(_amount: float = 5.0) -> void:
	pass

func turn_left(_amount: float = 30.0) -> void:
	pass

func turn_right(_amount: float = 30.0) -> void:
	pass

func get_speed() -> float:
	return max_speed

func get_direction() -> float:
	return rad_to_deg(atan2(-global_transform.basis.z.x, -global_transform.basis.z.z))

func get_elevator() -> Node3D:
	if not elevator:
		elevator = find_child("Elevator")
	return elevator
