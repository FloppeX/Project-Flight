extends Node3D
class_name ChaseCamera

@export var chase_distance: float = 10.0
@export var chase_height: float = 2.0
@export var chase_smoothing: float = 5.0
@export var rotation_smoothing: float = 8.0
@export var look_sensitivity: float = 2.0
@export var orbit_yaw_speed_deg: float = 120.0
@export var orbit_pitch_deg: float = 0.0

var aircraft: RigidBody3D
var orbit_yaw: float = 0.0
var current_offset: Vector3 = Vector3.ZERO

func _get_horizontal_forward() -> Vector3:
	var forward_flat: Vector3 = aircraft.global_transform.basis.z
	forward_flat.y = 0.0
	if forward_flat.length_squared() > 0.001:
		return forward_flat.normalized()

	var velocity_flat: Vector3 = aircraft.linear_velocity
	velocity_flat.y = 0.0
	if velocity_flat.length_squared() > 0.001:
		return velocity_flat.normalized()

	return Vector3.FORWARD

func _get_orbit_center() -> Vector3:
	return aircraft.global_position

func _ready():
	# Make this node ignore parent transforms so it doesn't move with the aircraft
	top_level = true

func setup_aircraft(aircraft_node: RigidBody3D):
	aircraft = aircraft_node
	if aircraft:
		var forward_flat: Vector3 = _get_horizontal_forward()
		orbit_yaw = atan2(-forward_flat.x, -forward_flat.z)
		current_offset = Vector3(sin(orbit_yaw), 0.0, cos(orbit_yaw)) * chase_distance + Vector3.UP * chase_height

func _process(delta):
	if not aircraft:
		return
	handle_input(delta)

func _physics_process(delta: float) -> void:
	if not aircraft:
		return
	update_position(delta)

func handle_input(delta):
	var look_x = Input.get_action_strength("look_left") - Input.get_action_strength("look_right")
	orbit_yaw = wrapf(orbit_yaw + deg_to_rad(look_x * orbit_yaw_speed_deg * look_sensitivity * delta), -PI, PI)

func update_position(delta):
	var orbit_center: Vector3 = _get_orbit_center()

	# Orbit around the aircraft on the horizontal plane, keeping the aircraft centered.
	var orbit_dir: Vector3 = Vector3(sin(orbit_yaw), 0.0, cos(orbit_yaw))
	var desired_offset: Vector3 = orbit_dir * chase_distance + Vector3.UP * chase_height
	
	# Smooth the orbit offset, not the world position, so the camera truly stays centered on the aircraft.
	var pos_smoothing_factor = 1.0 - exp(-chase_smoothing * delta)
	current_offset = current_offset.lerp(desired_offset, pos_smoothing_factor)
	global_position = orbit_center + current_offset
	
	# Keep the chase camera level relative to the world and only orbit around global Y.
	var look_target: Vector3 = orbit_center
	var look_basis: Basis = Transform3D(Basis.IDENTITY, global_position).looking_at(look_target, Vector3.UP).basis
	if not is_zero_approx(orbit_pitch_deg):
		look_basis = look_basis.rotated(look_basis.x, deg_to_rad(orbit_pitch_deg))
	
	var rot_smoothing_factor = 1.0 - exp(-rotation_smoothing * delta)
	global_transform.basis = global_transform.basis.slerp(look_basis, rot_smoothing_factor)

func reset_look():
	if aircraft:
		var forward_flat: Vector3 = _get_horizontal_forward()
		orbit_yaw = atan2(-forward_flat.x, -forward_flat.z)
		current_offset = Vector3(sin(orbit_yaw), 0.0, cos(orbit_yaw)) * chase_distance + Vector3.UP * chase_height
	else:
		orbit_yaw = 0.0
		current_offset = Vector3(0.0, chase_height, chase_distance)
