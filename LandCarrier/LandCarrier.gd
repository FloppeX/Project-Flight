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

const BODY_RIDE_HEIGHT: float = 32.0  # Root floats 32m above tread contact
const MAX_TREAD_STEER: float = 0.4    # ~23 deg max tread pivot angle

# Tread nominal XZ positions in local space (matches tscn layout)
# Z=+43 = front (leading), Z=-43 = rear (trailing), Z=0 = middle
const TREAD_XZ: Array = [
	Vector2(-32, -43), Vector2(-32,  0), Vector2(-32, 43),
	Vector2( 32, -43), Vector2( 32,  0), Vector2( 32, 43),
]
const FRONT_TREAD_INDICES: Array = [2, 5]  # Z = +43
const REAR_TREAD_INDICES:  Array = [0, 3]  # Z = -43

# --- State ---
var _waypoint_positions: Array[Vector3] = []
var _waypoint_index: int = 0
var _tread_nodes: Array[Node3D] = []
var _current_steer: float = 0.0
var treads: Array[CarrierTread] = []
var elevator: Node3D

func _ready():
	add_to_group("carrier")
	_resolve_waypoints()
	_collect_tread_nodes()
	find_treads()
	elevator = find_child("Elevator")
	if elevator and elevator.has_method("setup"):
		elevator.setup(self)
	# Generate a simple patrol loop if no waypoints were configured
	if _waypoint_positions.is_empty():
		call_deferred("_set_north_heading")

func _resolve_waypoints() -> void:
	_waypoint_positions.clear()
	for path in waypoints:
		var node = get_node_or_null(path)
		if node is Node3D:
			_waypoint_positions.append((node as Node3D).global_position)

func set_patrol_waypoints(positions: Array[Vector3]) -> void:
	_waypoint_positions = positions.duplicate()
	_waypoint_index = 0

func _set_north_heading() -> void:
	# Head north (-Z world direction) toward the map edge
	_waypoint_positions = [Vector3(global_position.x, global_position.y, global_position.z - 100000.0)]
	_waypoint_index = 0

func _collect_tread_nodes() -> void:
	_tread_nodes.clear()
	for child in get_children():
		if child is CarrierTread:
			_tread_nodes.append(child)

func find_treads() -> void:
	treads.clear()
	for child in get_children():
		if child is CarrierTread:
			treads.append(child)

func _physics_process(delta: float) -> void:
	var pos_before := global_position
	_drive_to_waypoint(delta)       # sets _current_steer
	_update_tread_visuals(delta)    # uses _current_steer
	if elevator and elevator.has_method("update"):
		elevator.update(delta)
	_carry_deck_passengers(global_position - pos_before)

func _carry_deck_passengers(pos_delta: Vector3) -> void:
	if pos_delta.length_squared() < 0.00001:
		return
	for group in ["aircraft", "ai_aircraft"]:
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
				(node as Node3D).global_position += pos_delta
			if (on_carrier or on_catapult) and Engine.get_process_frames() % 120 == 0:
				var plane_z = snappedf((node as Node3D).global_position.z, 0.1)
				var carrier_z = snappedf(global_position.z, 0.1)
				print("[Deck] ", node.name, " z=", plane_z, "  carrier z=", carrier_z, "  gap=", snappedf(plane_z - carrier_z, 0.1))
	# Move catapult wheel-latch joints with the carrier so they do not anchor the aircraft in world-space
	for joint in get_tree().get_nodes_in_group("carrier_pin_joint"):
		if is_instance_valid(joint) and joint is Node3D:
			(joint as Node3D).global_position += pos_delta

# --- Terrain following via 6 tread raycasts ---

func _update_tread_visuals(delta: float) -> void:
	var space = get_world_3d().direct_space_state
	var params = PhysicsRayQueryParameters3D.new()

	# Exclude the carrier body AND all tread bodies — treads have big collision boxes
	# that would otherwise be hit by the raycasts, creating a runaway feedback loop.
	var exclude: Array[RID] = [get_rid()]
	for t in _tread_nodes:
		exclude.append((t as CollisionObject3D).get_rid())
	params.exclude = exclude

	var world_heights: Array[float] = []

	for i in TREAD_XZ.size():
		var xz: Vector2 = TREAD_XZ[i]
		var world_xz := to_global(Vector3(xz.x, 0.0, xz.y))
		params.from = to_global(Vector3(xz.x,  20.0, xz.y))
		params.to   = to_global(Vector3(xz.x, -80.0, xz.y))
		var hit = space.intersect_ray(params)
		var terrain_y: float
		if hit:
			terrain_y = (hit.position as Vector3).y
		else:
			terrain_y = global_position.y - BODY_RIDE_HEIGHT  # maintain current height

		world_heights.append(terrain_y)

		# Drop tread to terrain contact
		if i < _tread_nodes.size():
			var tread := _tread_nodes[i] as Node3D
			tread.global_position = Vector3(world_xz.x, terrain_y, world_xz.z)
			# Apply steering pivot: front and rear steer in opposite directions
			if i in FRONT_TREAD_INDICES:
				tread.rotation.y = _current_steer * MAX_TREAD_STEER
			elif i in REAR_TREAD_INDICES:
				tread.rotation.y = -_current_steer * MAX_TREAD_STEER
			else:
				tread.rotation.y = 0.0

	# Smooth carrier root Y to sit BODY_RIDE_HEIGHT above average terrain
	if not world_heights.is_empty():
		var avg_y: float = 0.0
		for h in world_heights:
			avg_y += h
		avg_y /= world_heights.size()
		var desired_y: float = avg_y + BODY_RIDE_HEIGHT
		global_position.y = lerp(global_position.y, desired_y, height_smoothing * delta)

# --- Waypoint driving (same cross/dot principle as ground vehicles) ---

func _drive_to_waypoint(delta: float) -> void:
	if _waypoint_positions.is_empty():
		_current_steer = move_toward(_current_steer, 0.0, delta * 2.0)
		return

	var wp: Vector3 = _waypoint_positions[_waypoint_index]
	var to_wp: Vector3 = wp - global_position
	to_wp.y = 0.0

	if to_wp.length() < waypoint_reach_distance:
		if loop_waypoints:
			_waypoint_index = (_waypoint_index + 1) % _waypoint_positions.size()
		else:
			_waypoint_index = min(_waypoint_index + 1, _waypoint_positions.size() - 1)
		_current_steer = move_toward(_current_steer, 0.0, delta * 2.0)
		return

	var desired_dir: Vector3 = to_wp.normalized()
	var current_forward: Vector3 = global_transform.basis.z

	var cross_y: float = current_forward.cross(desired_dir).y
	var dot: float = current_forward.dot(desired_dir)

	_current_steer = clamp(cross_y * 2.0, -1.0, 1.0)
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
