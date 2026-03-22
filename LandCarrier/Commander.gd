extends CharacterBody3D
class_name Commander

@export var eye_height_m: float = 1.8
@export var walk_speed_mps: float = 3.5
@export var look_sensitivity_deg: float = 120.0
@export var pitch_limit_deg: float = 85.0
@export var gravity_mps2: float = 9.8
@export var bridge_wall_margin_m: float = 0.55

@onready var commander_camera: Camera3D = $Camera3D
@onready var body_mesh: MeshInstance3D = $BodyMesh

var _look_yaw: float = 0.0
var _look_pitch: float = 0.0
var _anchor_local_position: Vector3 = Vector3.ZERO
var _bridge_bounds_min: Vector2 = Vector2.ZERO
var _bridge_bounds_max: Vector2 = Vector2.ZERO
var _has_bridge_bounds: bool = false

func _ready() -> void:
	physics_interpolation_mode = Node3D.PHYSICS_INTERPOLATION_MODE_INHERIT
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	if commander_camera:
		commander_camera.physics_interpolation_mode = Node3D.PHYSICS_INTERPOLATION_MODE_INHERIT
		commander_camera.top_level = false
	if body_mesh:
		body_mesh.physics_interpolation_mode = Node3D.PHYSICS_INTERPOLATION_MODE_INHERIT

	_anchor_local_position = position
	_cache_bridge_bounds()
	_anchor_local_position = _clamp_to_bridge_bounds(_anchor_local_position)
	position = _anchor_local_position
	_look_yaw = rotation.y
	if commander_camera:
		commander_camera.position.y = eye_height_m
		_look_pitch = commander_camera.rotation.x

func _process(delta: float) -> void:
	var active_view := _is_active_view()
	_update_body_visibility(active_view)

func _physics_process(delta: float) -> void:
	if not _is_active_view():
		velocity = Vector3.ZERO
		return

	_update_look(delta)

	var forward_input := Input.get_action_strength("pitch_up") - Input.get_action_strength("pitch_down")
	var strafe_input := Input.get_action_strength("roll_left") - Input.get_action_strength("roll_right")
	var move_input := Vector2(strafe_input, forward_input)
	if move_input.length_squared() > 1.0:
		move_input = move_input.normalized()

	var move_basis := basis
	var right_dir := move_basis.x
	right_dir.y = 0.0
	right_dir = right_dir.normalized()

	var forward_dir := -move_basis.z
	forward_dir.y = 0.0
	forward_dir = forward_dir.normalized()

	var move_velocity: Vector3 = ((right_dir * move_input.x) + (forward_dir * move_input.y)) * walk_speed_mps

	# When standing still, just hold the last valid local spot.
	if move_input.length_squared() < 0.001:
		velocity = Vector3.ZERO
		return

	velocity = Vector3.ZERO
	position = _clamp_to_bridge_bounds(position + move_velocity * delta)
	_anchor_local_position = position

func _update_look(delta: float) -> void:
	var look_yaw_input := Input.get_action_strength("look_right") - Input.get_action_strength("look_left")
	var look_pitch_input := Input.get_action_strength("look_up") - Input.get_action_strength("look_down")

	_look_yaw -= look_yaw_input * deg_to_rad(look_sensitivity_deg) * delta
	_look_pitch += look_pitch_input * deg_to_rad(look_sensitivity_deg) * delta
	_look_pitch = clamp(
		_look_pitch,
		deg_to_rad(-pitch_limit_deg),
		deg_to_rad(pitch_limit_deg)
	)

	rotation.y = _look_yaw
	commander_camera.rotation.x = _look_pitch

func _is_active_view() -> bool:
	return commander_camera != null and commander_camera.current

func get_camera() -> Camera3D:
	return commander_camera

func set_aircraft_reference(_aircraft_node: Node3D) -> void:
	pass

func set_tracking_enabled(_enabled: bool) -> void:
	pass

func _cache_bridge_bounds() -> void:
	var bridge_body := get_parent().get_node_or_null("BridgeWalkCollision") as Node3D
	if bridge_body == null:
		return

	var floor_shape := bridge_body.get_node_or_null("Floor") as CollisionShape3D
	if floor_shape == null:
		return

	var box_shape := floor_shape.shape as BoxShape3D
	if box_shape == null:
		return

	var local_floor_transform: Transform3D = bridge_body.transform * floor_shape.transform
	var half_extents := box_shape.size * 0.5
	var min_x := INF
	var min_z := INF
	var max_x := -INF
	var max_z := -INF

	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var corner := local_floor_transform * Vector3(half_extents.x * sx, 0.0, half_extents.z * sz)
			min_x = minf(min_x, corner.x)
			max_x = maxf(max_x, corner.x)
			min_z = minf(min_z, corner.z)
			max_z = maxf(max_z, corner.z)

	_bridge_bounds_min = Vector2(min_x + bridge_wall_margin_m, min_z + bridge_wall_margin_m)
	_bridge_bounds_max = Vector2(max_x - bridge_wall_margin_m, max_z - bridge_wall_margin_m)
	_has_bridge_bounds = _bridge_bounds_min.x < _bridge_bounds_max.x and _bridge_bounds_min.y < _bridge_bounds_max.y

func _clamp_to_bridge_bounds(local_position: Vector3) -> Vector3:
	var clamped := local_position
	clamped.y = _anchor_local_position.y
	if not _has_bridge_bounds:
		return clamped

	clamped.x = clampf(clamped.x, _bridge_bounds_min.x, _bridge_bounds_max.x)
	clamped.z = clampf(clamped.z, _bridge_bounds_min.y, _bridge_bounds_max.y)
	return clamped

func _update_body_visibility(active_view: bool) -> void:
	if body_mesh == null:
		return
	body_mesh.visible = not active_view
	body_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if active_view else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
