extends Node3D
class_name CockpitCamera

@export var horizontal_sensitivity: float = 120.0  # degrees for left/right
@export var vertical_sensitivity: float = 90.0    # degrees for up/down  
@export var return_speed: float = 5.0             # how fast it snaps back to center
@export var g_force_sensitivity: float = 0.08   # How much camera moves per G
@export var g_force_vertical_scale: float = 0.35 # Scale vertical G camera motion without affecting horizontal response
@export var g_force_smoothing_horizontal: float = 12.0  # How fast camera returns to center side-to-side/front-back
@export var g_force_smoothing_vertical: float = 35.0    # How fast camera returns to center up-down
@export var max_g_offset: float = 0.2           # Maximum camera displacement in any direction
@export var max_backward_offset: float = 0.04   # Rearward travel limit so launch G does not push the view into the seat
@export var g_deadzone: float = 0.5             # Minimum G-force to trigger effect
@export var airflow_buffet_position_strength: float = 0.026
@export var airflow_buffet_rotation_strength_deg: float = 0.75
@export var airflow_buffet_frequency: float = 22.0
@export var cockpit_interact_action: StringName = &"flaps_down"
@export var cockpit_interact_range_m: float = 2.5

var base_rotation: Vector3 = Vector3.ZERO
var current_look: Vector3 = Vector3.ZERO
var base_position: Vector3
var g_force_offset: Vector3 = Vector3.ZERO
var airflow_buffet_offset: Vector3 = Vector3.ZERO
var airflow_buffet_rotation: Vector3 = Vector3.ZERO
var airflow_buffet_intensity: float = 0.0
var last_velocity: Vector3 = Vector3.ZERO
var _pause_menu_settings: Node = null

func _ready():
	base_position = position
	base_rotation = rotation
	var aircraft := get_parent() as RigidBody3D
	if aircraft != null:
		# Do not interpret the aircraft's existing world velocity as a one-frame
		# acceleration impulse when the cockpit script first becomes active.
		last_velocity = aircraft.linear_velocity

func _process(delta):
	# Get right stick input
	var look_x = Input.get_action_strength("look_left") - Input.get_action_strength("look_right")
	var look_y = Input.get_action_strength("look_down") - Input.get_action_strength("look_up") 
	var sensitivity_scale := _user_look_sensitivity_multiplier()
	if _user_invert_look_y():
		look_y = -look_y
	
	# Target look angles in radians with separate sensitivities
	var target_look = Vector3(
		deg_to_rad(-look_y * vertical_sensitivity * sensitivity_scale),
		deg_to_rad(look_x * horizontal_sensitivity * sensitivity_scale),
		0
	)
	
	# Smoothly move to target
	current_look = current_look.lerp(target_look, return_speed * delta)
	
	# Apply to camera
	rotation = base_rotation + current_look + airflow_buffet_rotation


func _input(event: InputEvent) -> void:
	if InputMap.has_action(cockpit_interact_action) and event.is_action_pressed(cockpit_interact_action, false, true):
		_try_cockpit_interaction()


func _physics_process(delta: float):
	# Get aircraft acceleration (need reference to aircraft RigidBody)
	var aircraft = get_parent() as RigidBody3D
	if not aircraft:
		return
	var current_velocity = aircraft.linear_velocity

	# Calculate acceleration (change in velocity)
	var acceleration = (current_velocity - last_velocity) / delta
	last_velocity = current_velocity

	# Convert to G-forces relative to aircraft's local coordinate system
	var local_acceleration = aircraft.global_transform.basis.inverse() * acceleration
	var g_forces = local_acceleration / 9.8

	# Apply deadzone to reduce jitter from small movements
	if g_forces.length() < g_deadzone:
		g_forces = Vector3.ZERO

	var motion_scale := _user_camera_motion_scale()
	# Calculate camera offset from G-forces with improved mapping
	var target_offset = Vector3(
		-g_forces.x * g_force_sensitivity,     # Side G's push camera opposite direction
		-g_forces.y * g_force_sensitivity * g_force_vertical_scale,     # Positive G pushes down, negative G lifts up
		-g_forces.z * g_force_sensitivity      # Forward G's push camera back
	) * motion_scale

	# Clamp maximum offset
	target_offset = target_offset.limit_length(max_g_offset)

	# Exponential response is frame-rate stable and cannot overshoot when a launch
	# or effect-spawn hitch produces a large delta.
	var horizontal_blend: float = 1.0 - exp(-maxf(g_force_smoothing_horizontal, 0.0) * delta)
	var vertical_blend: float = 1.0 - exp(-maxf(g_force_smoothing_vertical, 0.0) * delta)
	g_force_offset.x = lerpf(g_force_offset.x, target_offset.x, horizontal_blend)
	g_force_offset.y = lerpf(g_force_offset.y, target_offset.y, vertical_blend)
	g_force_offset.z = lerpf(g_force_offset.z, target_offset.z, horizontal_blend)

	_update_airflow_buffet(delta, motion_scale)

	# Apply the general travel cap, then a tighter rearward limit. Aircraft use +Z
	# as forward, so negative local Z is movement back into the seat.
	var total_offset := _limit_camera_offset(g_force_offset + airflow_buffet_offset)
	position = base_position + total_offset


func _limit_camera_offset(offset: Vector3) -> Vector3:
	var limited_offset := offset.limit_length(maxf(max_g_offset, 0.0))
	limited_offset.z = maxf(limited_offset.z, -maxf(max_backward_offset, 0.0))
	return limited_offset


func set_airflow_buffet_intensity(intensity: float) -> void:
	airflow_buffet_intensity = clampf(intensity, 0.0, 1.0)


func _update_airflow_buffet(delta: float, motion_scale: float) -> void:
	var target_offset := Vector3.ZERO
	var target_rotation := Vector3.ZERO
	if airflow_buffet_intensity > 0.001:
		var t := Time.get_ticks_msec() * 0.001 * airflow_buffet_frequency
		var intensity := airflow_buffet_intensity * airflow_buffet_intensity
		target_offset = Vector3(
			sin(t * 1.07 + 0.3),
			sin(t * 1.31 + 1.9) * 0.65,
			sin(t * 0.89 + 3.7) * 0.7
		) * airflow_buffet_position_strength * intensity * motion_scale
		target_rotation = Vector3(
			sin(t * 1.19 + 2.4),
			sin(t * 0.93 + 4.1) * 0.45,
			sin(t * 1.47 + 0.8) * 0.7
		) * deg_to_rad(airflow_buffet_rotation_strength_deg) * intensity * motion_scale
	var blend := clampf(delta * 18.0, 0.0, 1.0)
	airflow_buffet_offset = airflow_buffet_offset.lerp(target_offset, blend)
	airflow_buffet_rotation = airflow_buffet_rotation.lerp(target_rotation, blend)


func _user_look_sensitivity_multiplier() -> float:
	var settings := _user_settings_node()
	if settings != null and settings.has_method("get_look_sensitivity_multiplier"):
		return float(settings.call("get_look_sensitivity_multiplier"))
	return 1.0


func _user_invert_look_y() -> bool:
	var settings := _user_settings_node()
	return settings != null \
			and settings.has_method("get_invert_look_y") \
			and bool(settings.call("get_invert_look_y"))


func _user_camera_motion_scale() -> float:
	var settings := _user_settings_node()
	if settings != null and settings.has_method("get_camera_motion_scale"):
		return float(settings.call("get_camera_motion_scale"))
	return 1.0


func _user_settings_node() -> Node:
	if not is_instance_valid(_pause_menu_settings):
		_pause_menu_settings = get_node_or_null("/root/PauseMenu")
	return _pause_menu_settings


func _try_cockpit_interaction() -> bool:
	var camera := find_child("Camera3D", true, false) as Camera3D
	if camera == null or not is_instance_valid(camera) or not camera.current:
		return false
	var aircraft := get_parent()
	if aircraft == null or not is_instance_valid(aircraft):
		return false
	var panel := aircraft.find_child("InstrumentPanel", true, false)
	if panel == null or not is_instance_valid(panel) or not panel.has_method("interact_from_camera"):
		return false
	var interacted := bool(panel.call("interact_from_camera", camera, cockpit_interact_range_m))
	if interacted:
		aircraft.set_meta("cockpit_interaction_consumed_physics_frame", Engine.get_physics_frames())
		aircraft.set_meta("cockpit_interaction_consumed_process_frame", Engine.get_process_frames())
	return interacted
