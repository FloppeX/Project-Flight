extends StaticBody3D

signal damaged(amount: float, health: float)
signal destroyed

@export var team: int = 2
@export var max_health: float = 500.0
@export var infinite_health: bool = false

# Movement: when path_points has >= 2 entries the target patrols the loop like an enemy vehicle,
# so the AI must lead a moving aim point. Exposes `velocity` so the pilots' CCIP lead logic
# (AIPilot._get_target_linear_velocity) automatically accounts for the motion.
@export var move_speed_mps: float = 0.0            # 0 = stationary (backward compatible)
@export var path_points: PackedVector3Array = PackedVector3Array()
@export var path_loops: bool = true                # loop the circuit vs ping-pong
@export var stick_to_ground: bool = true           # follow terrain height like a ground vehicle

var health: float = 500.0
var velocity: Vector3 = Vector3.ZERO

var _path_index: int = 0
var _path_dir: int = 1                              # for ping-pong mode
var _terrain_provider: Node = null

func _ready() -> void:
	health = max_health
	add_to_group("enemies")
	add_to_group("buildings")
	add_to_group("enemy_bases")
	add_to_group("team_%d" % team)
	if stick_to_ground:
		var providers: Array = get_tree().get_nodes_in_group("terrain_provider")
		if not providers.is_empty():
			_terrain_provider = providers[0]

func _physics_process(delta: float) -> void:
	if move_speed_mps <= 0.0 or path_points.size() < 2:
		velocity = Vector3.ZERO
		return
	var target_point: Vector3 = path_points[_path_index]
	var pos: Vector3 = global_position
	var to_point: Vector3 = Vector3(target_point.x - pos.x, 0.0, target_point.z - pos.z)
	var dist: float = to_point.length()
	var step: float = move_speed_mps * delta
	if dist <= maxf(step, 1.0):
		# Reached the waypoint; advance to the next one.
		_advance_path_index()
		velocity = Vector3.ZERO
		global_position = _grounded(Vector3(target_point.x, pos.y, target_point.z))
		return
	var move_dir: Vector3 = to_point / dist
	velocity = move_dir * move_speed_mps
	var new_pos: Vector3 = pos + velocity * delta
	global_position = _grounded(new_pos)

func _advance_path_index() -> void:
	if path_loops:
		_path_index = (_path_index + 1) % path_points.size()
		return
	# Ping-pong: reverse direction at the ends.
	if _path_index + _path_dir < 0 or _path_index + _path_dir >= path_points.size():
		_path_dir = -_path_dir
	_path_index = clampi(_path_index + _path_dir, 0, path_points.size() - 1)

func _grounded(pos: Vector3) -> Vector3:
	if not stick_to_ground or _terrain_provider == null:
		return pos
	if _terrain_provider.has_method("get_height"):
		var h: float = _terrain_provider.call("get_height", pos)
		if not is_nan(h):
			pos.y = h
	return pos

func get_velocity_vector() -> Vector3:
	return velocity

func get_team() -> int:
	return team

func take_damage(amount: float) -> void:
	if infinite_health:
		damaged.emit(amount, health)
		return
	health = maxf(health - maxf(amount, 0.0), 0.0)
	damaged.emit(amount, health)
	if health <= 0.0:
		destroyed.emit()
