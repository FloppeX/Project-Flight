extends Node
class_name SimpleAero

@export var rb_path: NodePath
var rb: RigidBody3D = null

# Simple parameters
@export var pitch_power: float = 6.0         # Elevator strength
@export var roll_power: float = 12.0         # Aileron strength
@export var yaw_power: float = 3.0           # Rudder strength
@export var min_control_speed: float = 80.0  # Speed where controls start working
@export var ground_rudder_assist_enabled: bool = true
@export var ground_rudder_assist_power: float = 1.0
@export var ground_rudder_assist_start_speed_mps: float = 8.0
@export var ground_rudder_assist_full_speed_mps: float = 35.0
@export var ground_rudder_ground_compression_threshold_m: float = 0.02
@export var alignment_strength: float = 2.5   # High-speed horizontal sideslip damping in 1/s (mass-scaled below)
@export var alignment_low_speed_strength: float = 1.2   # Moderate low-speed horizontal alignment for tighter slip damping
@export var angular_damping_strength: float = 16.0  # How quickly rotations stop
@export var drag_base_multiplier: float = 0.8  # Base multiplier on combined forward+lateral drag
@export var stability_strength: float = 2.0  # How strongly it wants to return to level
@export var roll_stability_factor: float = 1.0  # Per-axis multiplier for roll self-righting
@export var pitch_stability_factor: float = 0.7  # Per-axis multiplier for pitch self-righting
@export var stability_torque_scale: float = 2.0  # Converts attitude error into a noticeable restoring torque
@export var roll_stability_rate_damping: float = 3.2  # Extra roll-rate damping while the aircraft tries to settle level
@export var pitch_stability_rate_damping: float = 2.1  # Extra pitch-rate damping while the aircraft tries to settle level
@export var stability_error_limit_deg: float = 70.0  # Cap huge aerobatic errors so the helper does not overreact
@export var stability_start_speed_mps: float = 12.0  # Start blending in attitude stability above this speed
@export var stability_full_speed_mps: float = 45.0  # Reach full attitude stability by this speed
@export var stability_grounded_factor: float = 0.2  # Keep only a small fraction of attitude stability while on gear
@export var stall_speed: float = 40.0        # Forward speed below which aircraft stalls
@export var auto_rudder_strength: float = 0.3  # How much auto-rudder per roll input
@export var lift_gain: float = 0.0025        # Scales lift with speed^2
@export var aligned_level_speed_mps: float = 60.0  # At/above this speed, zero-AoA flight should support ~1g
@export var slow_flight_alignment_start_speed_mps: float = 92.0  # Reach the full high-speed flight-path alignment only near the top of the normal envelope
@export var slow_flight_alignment_release_speed_mps: float = 60.0  # Keep the stronger alignment mostly out of medium-speed handling below this speed
@export var vertical_alignment_low_speed_strength: float = 0.06  # Light low-speed vertical path alignment
@export var vertical_alignment_high_speed_strength: float = 0.80  # Vertical path alignment at speed so fast flight feels planted without becoming sticky
@export var aoa_lift_full_deg: float = 10.0  # Positive AoA needed to unlock the full slow-flight lift bonus
@export var aoa_lift_bonus_factor: float = 0.6  # Extra lift multiplier from positive AoA in slow flight
@export var aoa_negative_lift_penalty_factor: float = 0.35  # Reduce lift when the nose sits below the flight path
@export var max_lift_ratio: float = 1.35  # Prevent extreme pitch-up from generating unrealistic excess lift

# Keep a tiny support near knife-edge (optional safety net)
@export var min_vertical_lift_frac: float = 0.01

# Simplified stall parameters
@export var stall_nose_drop_force: float = 5.0  # Downward force strength at nose
@export var stall_lift_loss: float = 0.2      # Fraction of lift lost at full stall (0.0 to 1.0)
@export var stall_shake_intensity: float = 3.0  # How intense stall shake is

# Drag tuning
@export var forward_drag_strength: float = 0.22
@export var lateral_drag_strength: float = 1.2
@export var gear_drag_multiplier: float = 1.5
@export var flaps_drag_multiplier: float = 1.25  # When flaps deployed (approach config: gear+flaps together)
@export var flaps_stall_speed_factor: float = 0.85  # Stall speed multiplier when flaps deployed (0.85 = 15% lower)

# Control inputs
var pitch_input: float = 0.0
var roll_input: float = 0.0
var yaw_input: float = 0.0
var current_stall_severity: float = 0.0

@onready var _landing_gear_node: Node = null
@onready var _gear_controller: Node = null
@onready var _flaps_module: Node = null

func _ready() -> void:
	rb = get_parent() as RigidBody3D
	if rb:
		rb.gravity_scale = 1.0
		_landing_gear_node = rb.get_node_or_null("LandingGear")
		_gear_controller = rb.get_node_or_null("ControlLandingGear")
		# Flaps: find AircraftModule_Flaps (gear+flaps deployed together on approach)
		if rb.has_method("find_modules_by_type"):
			var found = rb.find_modules_by_type("flaps")
			if not found.is_empty():
				_flaps_module = found[0]

func _physics_process(delta: float) -> void:
	if rb == null:
		return

	# --- Basic kinematics ---
	var vel: Vector3 = rb.linear_velocity
	var speed: float = vel.length()
	var fwd: Vector3 = rb.global_transform.basis.z
	var right: Vector3 = rb.global_transform.basis.x
	var up: Vector3 = rb.global_transform.basis.y
	var v_dir: Vector3 = (vel / speed) if speed > 0.001 else fwd
	var local_vel: Vector3 = rb.global_transform.basis.inverse() * vel

	# Forward speed (nose-aligned component)
	var signed_forward_speed: float = vel.dot(fwd)
	var forward_speed: float = maxf(signed_forward_speed, 0.0)

	# --- Drag (split longitudinal vs lateral; gear+flaps increase drag on approach) ---
	if speed > 0.1:
		var gear_mult: float = gear_drag_multiplier if _is_gear_deployed() else 1.0
		var flaps_mult: float = flaps_drag_multiplier if _is_flaps_deployed() else 1.0
		var approach_mult: float = gear_mult * flaps_mult
		# Longitudinal
		var f_drag: Vector3 = -fwd * forward_drag_strength * signed_forward_speed * absf(signed_forward_speed)
		# Lateral (velocity minus forward component)
		var lateral_vel: Vector3 = vel - fwd * signed_forward_speed
		var lateral_speed: float = lateral_vel.length()
		var lat_dir: Vector3 = (-lateral_vel / lateral_speed) if lateral_speed > 0.001 else Vector3.ZERO
		var l_drag: Vector3 = lat_dir * lateral_drag_strength * lateral_speed * lateral_speed
		# Combine and scale (gear+flaps multiply drag when deployed)
		var drag_force: Vector3 = (f_drag + l_drag) * drag_base_multiplier
		rb.apply_central_force(drag_force * approach_mult)

	# --- Lift calculation ---
	# Project aircraft "up" onto plane perpendicular to airflow for realistic banking
	var lift_dir: Vector3 = (up - v_dir * up.dot(v_dir)).normalized()

	# Effective stall speed: lower when flaps deployed (more lift at low speed)
	var effective_stall_speed: float = stall_speed * (flaps_stall_speed_factor if _is_flaps_deployed() else 1.0)
	var aligned_level_speed: float = maxf(aligned_level_speed_mps, effective_stall_speed + 1.0)
	var zero_aoa_lift_ratio: float = minf(pow(speed / aligned_level_speed, 2.0), 1.0)
	var alpha_rad: float = atan2(-local_vel.y, maxf(local_vel.z, 0.1))
	var alpha_deg: float = rad_to_deg(alpha_rad)
	var positive_alpha_t: float = clampf(alpha_deg / maxf(aoa_lift_full_deg, 0.1), 0.0, 1.0)
	var negative_alpha_t: float = clampf(-alpha_deg / maxf(aoa_lift_full_deg, 0.1), 0.0, 1.0)
	var aoa_lift_scale: float = 1.0 + positive_alpha_t * aoa_lift_bonus_factor - negative_alpha_t * aoa_negative_lift_penalty_factor
	var commanded_lift_ratio: float = clampf(
		zero_aoa_lift_ratio * maxf(aoa_lift_scale, 0.0),
		0.0,
		maxf(max_lift_ratio, 0.1)
	)
	var gravity_mag: float = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	var base_lift_mag: float = rb.mass * gravity_mag * maxf(rb.gravity_scale, 0.0) * commanded_lift_ratio

	# Calculate stall effects
	var stall_severity: float = 0.0
	if forward_speed < effective_stall_speed and speed > 5.0:
		stall_severity = 1.0 - (forward_speed / effective_stall_speed)
	current_stall_severity = stall_severity
		
	# Reduce lift in stall
	var actual_lift_mag: float = base_lift_mag * (1.0 - stall_lift_loss * stall_severity)
	var lift_force: Vector3 = lift_dir * actual_lift_mag

	# Optional: tiny vertical safety net near knife-edge
	var bank_vertical: float = abs(up.dot(Vector3.UP))
	if bank_vertical < 0.2 and min_vertical_lift_frac > 0.0:
		lift_force += Vector3.UP * (base_lift_mag * min_vertical_lift_frac * (0.2 - bank_vertical) * 5.0)

	# Apply lift at center of mass
	rb.apply_central_force(lift_force)

	# Apply nose-down force when stalled
	if stall_severity > 0.1 and speed > 5.0:  # Only when flying and stalled
		var nose_position = fwd * 2.0  # 2 meters forward of center (adjust to your aircraft)
		var nose_down_force = Vector3.DOWN * stall_nose_drop_force * stall_severity * rb.mass
		rb.apply_force(nose_down_force, nose_position)
		
	# Add stall shake
	if stall_severity > 0.1:  # Start shake at 10% stall
		var shake_intensity = stall_shake_intensity * stall_severity
		rb.add_shake(shake_intensity)
	
	# --- Control effectiveness based on forward speed ---
	var control_authority: float = clamp(forward_speed / min_control_speed, 0.0, 1.0)
	
	# Reduce control authority in stall
	var stall_control_loss = pow(stall_severity, 0.3)  # Steep curve
	control_authority *= (1.0 - 0.9 * stall_control_loss)

	# --- Flight controls ---
	if control_authority > 0.0:
		var pitch_torque: float = pitch_input * pitch_power * control_authority * rb.mass
		var roll_torque: float = roll_input * roll_power * control_authority * rb.mass
		var coordinated_yaw: float = yaw_input + (roll_input * auto_rudder_strength)
		var yaw_torque: float = coordinated_yaw * yaw_power * control_authority * rb.mass

		rb.apply_torque(-right * pitch_torque)
		rb.apply_torque(-fwd * roll_torque)
		rb.apply_torque(up * yaw_torque)

	var ground_rudder_assist: float = _get_ground_rudder_assist_strength(forward_speed)
	if ground_rudder_assist > 0.0 and absf(yaw_input) > 0.001:
		var ground_yaw_torque: float = yaw_input * ground_rudder_assist_power * ground_rudder_assist * rb.mass
		rb.apply_torque(Vector3.UP * ground_yaw_torque)

	# --- Slip damping ---
	# Let flight-path alignment grow with speed: mild at slow speed so the
	# aircraft can still feel loose and maneuverable, stronger in fast flight so
	# the movement direction lines up with the nose more naturally.
	if speed > 5.0 and not _has_grounded_gear():
		var high_speed_alignment_t: float = _smoothstep(
			slow_flight_alignment_release_speed_mps,
			slow_flight_alignment_start_speed_mps,
			speed
		)
		var horizontal_alignment_strength: float = lerpf(
			alignment_low_speed_strength,
			alignment_strength,
			high_speed_alignment_t
		)
		var vertical_alignment_strength: float = lerpf(
			vertical_alignment_low_speed_strength,
			vertical_alignment_high_speed_strength,
			high_speed_alignment_t
		)
		var slip_velocity_local := Vector3(
			local_vel.x * horizontal_alignment_strength,
			local_vel.y * vertical_alignment_strength,
			0.0
		)
		# Scale by mass so the response time is consistent across aircraft weights.
		var alignment_force: Vector3 = rb.global_transform.basis * (-slip_velocity_local * rb.mass)
		rb.apply_central_force(alignment_force)

	# --- Angular damping ---
	# Always apply some damping, stronger when moving
	var damping_factor: float = max(control_authority, 0.3)  # Minimum 30% damping
	var angular_damping: Vector3 = rb.angular_velocity * -angular_damping_strength * rb.mass * damping_factor
	rb.apply_torque(angular_damping)
	
	# Extra pitch damping when slow to prevent ground loops
	if speed < 10.0:
		var pitch_rate: float = rb.angular_velocity.dot(right)
		var extra_pitch_damping: Vector3 = -right * pitch_rate * rb.mass * angular_damping_strength * 3.0
		rb.apply_torque(extra_pitch_damping)

	# --- Attitude stability (separate roll/pitch self-righting) ---
	if speed > 5.0 and stability_strength > 0.0:
		_apply_attitude_stability(fwd, right, up, speed, forward_speed, stall_control_loss)

func _smoothstep(edge0: float, edge1: float, x: float) -> float:
	if is_equal_approx(edge0, edge1):
		return 1.0 if x >= edge1 else 0.0
	var t: float = clampf((x - edge0) / (edge1 - edge0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)

func _apply_attitude_stability(fwd: Vector3, right: Vector3, up: Vector3, speed: float, forward_speed: float, stall_control_loss: float) -> void:
	if rb == null:
		return
	var flat_forward: Vector3 = Vector3(fwd.x, 0.0, fwd.z)
	if flat_forward.length_squared() < 0.0001:
		return
	flat_forward = flat_forward.normalized()

	var desired_right: Vector3 = Vector3.UP.cross(flat_forward).normalized()
	var desired_up: Vector3 = flat_forward.cross(desired_right).normalized()
	var fwd_dir: Vector3 = fwd.normalized()
	var right_dir: Vector3 = right.normalized()
	var up_dir: Vector3 = up.normalized()

	var roll_error: float = atan2(fwd_dir.dot(up_dir.cross(desired_up)), clampf(up_dir.dot(desired_up), -1.0, 1.0))
	var pitch_error: float = atan2(right_dir.dot(flat_forward.cross(fwd_dir)), clampf(flat_forward.dot(fwd_dir), -1.0, 1.0))

	var stability_authority: float = _smoothstep(
		stability_start_speed_mps,
		maxf(stability_full_speed_mps, stability_start_speed_mps + 0.01),
		maxf(forward_speed, 0.0)
	)
	stability_authority *= (1.0 - 0.65 * stall_control_loss)
	if _has_grounded_gear():
		stability_authority *= stability_grounded_factor
	if stability_authority <= 0.0:
		return

	var roll_factor: float = maxf(roll_stability_factor, 0.0)
	var pitch_factor: float = maxf(pitch_stability_factor, 0.0)
	var error_limit_rad: float = deg_to_rad(maxf(stability_error_limit_deg, 1.0))
	var limited_roll_error: float = clampf(roll_error, -error_limit_rad, error_limit_rad)
	var limited_pitch_error: float = clampf(pitch_error, -error_limit_rad, error_limit_rad)
	var roll_rate: float = rb.angular_velocity.dot(fwd_dir)
	var pitch_rate: float = rb.angular_velocity.dot(right_dir)

	var roll_torque: Vector3 = fwd_dir * limited_roll_error * stability_strength * roll_factor * rb.mass * stability_authority * stability_torque_scale
	var pitch_torque: Vector3 = -right_dir * limited_pitch_error * stability_strength * pitch_factor * rb.mass * stability_authority * stability_torque_scale
	var roll_rate_damping_torque: Vector3 = -fwd_dir * roll_rate * roll_factor * rb.mass * stability_authority * roll_stability_rate_damping
	var pitch_rate_damping_torque: Vector3 = -right_dir * pitch_rate * pitch_factor * rb.mass * stability_authority * pitch_stability_rate_damping
	rb.apply_torque(roll_torque + pitch_torque + roll_rate_damping_torque + pitch_rate_damping_torque)

func get_estimated_angle_of_attack_deg() -> float:
	if rb == null:
		return 0.0
	var local_vel: Vector3 = rb.global_transform.basis.inverse() * rb.linear_velocity
	return rad_to_deg(atan2(-local_vel.y, maxf(local_vel.z, 0.1)))

func get_estimated_lift_ratio() -> float:
	if rb == null:
		return 0.0
	var speed: float = rb.linear_velocity.length()
	var effective_stall_speed: float = stall_speed * (flaps_stall_speed_factor if _is_flaps_deployed() else 1.0)
	var aligned_level_speed: float = maxf(aligned_level_speed_mps, effective_stall_speed + 1.0)
	var zero_aoa_lift_ratio: float = minf(pow(speed / aligned_level_speed, 2.0), 1.0)
	var alpha_deg: float = get_estimated_angle_of_attack_deg()
	var positive_alpha_t: float = clampf(alpha_deg / maxf(aoa_lift_full_deg, 0.1), 0.0, 1.0)
	var negative_alpha_t: float = clampf(-alpha_deg / maxf(aoa_lift_full_deg, 0.1), 0.0, 1.0)
	var aoa_lift_scale: float = 1.0 + positive_alpha_t * aoa_lift_bonus_factor - negative_alpha_t * aoa_negative_lift_penalty_factor
	return clampf(
		zero_aoa_lift_ratio * maxf(aoa_lift_scale, 0.0),
		0.0,
		maxf(max_lift_ratio, 0.1)
	)

func get_stall_severity() -> float:
	return current_stall_severity

func get_effective_stall_speed_mps() -> float:
	return stall_speed * (flaps_stall_speed_factor if _is_flaps_deployed() else 1.0)

func _is_gear_deployed() -> bool:
	# Prefer LandingGear module state
	if _landing_gear_node != null:
		var val = _landing_gear_node.get("is_deployed") if _landing_gear_node.has_method("get") else null
		if val != null:
			return bool(val)
	# Fallback: ControlLandingGear controller
	if _gear_controller != null:
		var v2 = _gear_controller.get("gear_down_state") if _gear_controller.has_method("get") else null
		if v2 != null:
			return bool(v2)
	return false

func _is_flaps_deployed() -> bool:
	"""True when flaps are extended (flap_position > 0.5). Gear+flaps deployed together on approach."""
	if _flaps_module == null:
		return false
	if "flap_position" in _flaps_module:
		return float(_flaps_module.flap_position) > 0.5
	return false

func _get_ground_rudder_assist_strength(forward_speed: float) -> float:
	if not ground_rudder_assist_enabled or not _is_gear_deployed() or _landing_gear_node == null:
		return 0.0
	var compressions = _landing_gear_node.get("gear_compressions") if _landing_gear_node.has_method("get") else null
	if typeof(compressions) != TYPE_ARRAY:
		return 0.0
	var grounded_wheels: int = 0
	for compression_value in compressions:
		var compression: float = float(compression_value)
		if compression > ground_rudder_ground_compression_threshold_m:
			grounded_wheels += 1
	if grounded_wheels < 2:
		return 0.0
	var speed_factor: float = _smoothstep(
		ground_rudder_assist_start_speed_mps,
		maxf(ground_rudder_assist_full_speed_mps, ground_rudder_assist_start_speed_mps + 0.01),
		absf(forward_speed)
	)
	var grounded_factor: float = clampf(float(grounded_wheels - 1) / 2.0, 0.0, 1.0)
	return speed_factor * grounded_factor

func _has_grounded_gear() -> bool:
	if not _is_gear_deployed() or _landing_gear_node == null:
		return false
	var compressions = _landing_gear_node.get("gear_compressions") if _landing_gear_node.has_method("get") else null
	if typeof(compressions) != TYPE_ARRAY:
		return false
	var grounded_wheels: int = 0
	for compression_value in compressions:
		if float(compression_value) > ground_rudder_ground_compression_threshold_m:
			grounded_wheels += 1
	if grounded_wheels >= 2:
		return true
	return false
