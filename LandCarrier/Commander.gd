extends CharacterBody3D
class_name Commander

@export var eye_height_m: float = 1.8
@export var walk_speed_mps: float = 3.5
@export var look_sensitivity_deg: float = 120.0
@export var pitch_limit_deg: float = 85.0
@export var gravity_mps2: float = 9.8

@onready var commander_camera: Camera3D = $Camera3D
@onready var body_mesh: MeshInstance3D = $BodyMesh

var _look_yaw: float = 0.0
var _look_pitch: float = 0.0

func _ready() -> void:
	_look_yaw = rotation.y
	if commander_camera:
		commander_camera.position.y = eye_height_m
		_look_pitch = commander_camera.rotation.x

func _process(delta: float) -> void:
	var active_view := _is_active_view()
	_update_body_visibility(active_view)
	if not active_view:
		return
	_update_look(delta)

func _physics_process(delta: float) -> void:
	# When not the active view, skip physics entirely to avoid jitter.
	# The commander is a child of the carrier so it moves with it automatically.
	if not _is_active_view():
		velocity = Vector3.ZERO
		return

	var forward_input := Input.get_action_strength("pitch_up") - Input.get_action_strength("pitch_down")
	var strafe_input := Input.get_action_strength("roll_left") - Input.get_action_strength("roll_right")
	var move_input := Vector2(strafe_input, forward_input)
	if move_input.length_squared() > 1.0:
		move_input = move_input.normalized()

	var move_basis := global_basis
	var right_dir := move_basis.x
	right_dir.y = 0.0
	right_dir = right_dir.normalized()

	var forward_dir := -move_basis.z
	forward_dir.y = 0.0
	forward_dir = forward_dir.normalized()

	var move_velocity: Vector3 = ((right_dir * move_input.x) + (forward_dir * move_input.y)) * walk_speed_mps

	# If on floor with no movement input, skip move_and_slide to prevent
	# physics jitter from gravity fighting the moving platform floor.
	if is_on_floor() and move_input.length_squared() < 0.001:
		velocity = Vector3.ZERO
		return

	velocity.x = move_velocity.x
	velocity.z = move_velocity.z

	if is_on_floor():
		if velocity.y < 0.0:
			velocity.y = 0.0
	else:
		velocity.y -= gravity_mps2 * delta

	move_and_slide()

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

func _update_body_visibility(active_view: bool) -> void:
	if body_mesh == null:
		return
	body_mesh.visible = not active_view
	body_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if active_view else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
