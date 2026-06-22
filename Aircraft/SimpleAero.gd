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
@export var forward_drag_scale: float = 0.40  # Global fixed-wing forward drag reduction; top speed scales roughly with sqrt(1 / drag).
@export var stability_strength: float = 2.0  # How strongly it wants to return to level
@export var roll_stability_factor: float = 1.0  # Per-axis multiplier for roll self-righting
@export var pitch_stability_factor: float = 0.7  # Per-axis multiplier for pitch self-righting
@export var roll_stability_input_release: float = 0.85  # How much roll self-leveling backs off under deliberate roll input
@export var roll_stability_bank_release_start_deg: float = 55.0  # Start backing off roll self-leveling at aerobatic bank angles
@export var roll_stability_bank_release_full_deg: float = 100.0  # Roll self-leveling reaches its minimum strength here
@export var roll_stability_bank_min_factor: float = 0.18  # Keep a little roll damping so the aircraft does not tumble forever
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
@export var vertical_alignment_low_speed_strength: float = 0.08  # Light low-speed vertical path alignment
@export var vertical_alignment_high_speed_strength: float = 0.95  # Vertical path alignment at speed so fast flight feels planted without becoming sticky
@export var aoa_lift_full_deg: float = 10.0  # Positive AoA needed to unlock the full slow-flight lift bonus
@export var aoa_lift_bonus_factor: float = 0.6  # Extra lift multiplier from positive AoA in slow flight
@export var aoa_negative_lift_penalty_factor: float = 0.35  # Reduce lift when the nose sits below the flight path
@export var max_lift_ratio: float = 1.35  # Prevent extreme pitch-up from generating unrealistic excess lift
@export var aoa_stall_start_deg: float = 16.0  # Start bleeding lift/control when the wing is asked for a silly angle of attack
@export var aoa_stall_full_deg: float = 32.0   # High-AoA stall penalty reaches full strength here
@export var aoa_stall_lift_loss: float = 0.45  # Extra lift loss at full high-AoA stall
@export var aoa_stall_control_loss: float = 0.45  # Extra control loss at full high-AoA stall
@export var aoa_stall_drag_strength: float = 0.25  # Extra drag from high AoA; applied along the airflow vector

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

# Low-rate fixed-wing flight recorder. This intentionally lives in SimpleAero so
# it records what the aircraft physics model actually sees/applies, not just what
# a pilot/AI intended to command.
@export_group("Aero Report")
@export var aero_report_enabled: bool = true
@export var aero_report_interval_s: float = 0.5
@export var aero_report_path: String = "user://airplane_aero_report.log"
@export var aero_report_project_mirror_enabled: bool = true
@export var aero_report_project_mirror_path: String = "res://airplane_aero_report.log"
@export var aero_report_reset_on_first_aircraft: bool = true
@export_group("")

# Control inputs
var pitch_input: float = 0.0
var roll_input: float = 0.0
var yaw_input: float = 0.0
var current_stall_severity: float = 0.0

@onready var _landing_gear_node: Node = null
@onready var _gear_controller: Node = null
@onready var _flaps_module: Node = null
var _engine_modules: Array = []
var _aero_report_timer_s: float = 0.0
var _aero_report_prepared: bool = false

static var _aero_report_reset_done: bool = false

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
			_engine_modules = rb.find_modules_by_type("engine")

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
	var lateral_vel: Vector3 = vel - fwd * signed_forward_speed
	var lateral_speed: float = lateral_vel.length()
	var approach_mult: float = 1.0
	var forward_drag_force: Vector3 = Vector3.ZERO
	var lateral_drag_force: Vector3 = Vector3.ZERO
	var total_drag_force: Vector3 = Vector3.ZERO
	var lift_force: Vector3 = Vector3.ZERO
	var alpha_deg: float = 0.0
	var aoa_stall_severity: float = 0.0
	var commanded_lift_ratio: float = 0.0
	var actual_lift_ratio: float = 0.0
	var control_authority: float = 0.0

	# --- Drag (split longitudinal vs lateral; gear+flaps increase drag on approach) ---
	if speed > 0.1:
		var gear_mult: float = gear_drag_multiplier if _is_gear_deployed() else 1.0
		var flaps_mult: float = flaps_drag_multiplier if _is_flaps_deployed() else 1.0
		approach_mult = gear_mult * flaps_mult
		# Longitudinal
		forward_drag_force = -fwd * forward_drag_strength * forward_drag_scale * signed_forward_speed * absf(signed_forward_speed)
		# Lateral (velocity minus forward component)
		var lat_dir: Vector3 = (-lateral_vel / lateral_speed) if lateral_speed > 0.001 else Vector3.ZERO
		lateral_drag_force = lat_dir * lateral_drag_strength * lateral_speed * lateral_speed
		# Combine and scale (gear+flaps multiply drag when deployed)
		total_drag_force = (forward_drag_force + lateral_drag_force) * drag_base_multiplier * approach_mult
		rb.apply_central_force(total_drag_force)

	# --- Lift calculation ---
	# Project aircraft "up" onto plane perpendicular to airflow for realistic banking
	var lift_dir: Vector3 = (up - v_dir * up.dot(v_dir)).normalized()

	# Effective stall speed: lower when flaps deployed (more lift at low speed)
	var effective_stall_speed: float = stall_speed * (flaps_stall_speed_factor if _is_flaps_deployed() else 1.0)
	var aligned_level_speed: float = maxf(aligned_level_speed_mps, effective_stall_speed + 1.0)
	var zero_aoa_lift_ratio: float = minf(pow(speed / aligned_level_speed, 2.0), 1.0)
	var alpha_rad: float = atan2(-local_vel.y, maxf(local_vel.z, 0.1))
	alpha_deg = rad_to_deg(alpha_rad)
	aoa_stall_severity = _get_aoa_stall_severity(alpha_deg)
	var positive_alpha_t: float = clampf(alpha_deg / maxf(aoa_lift_full_deg, 0.1), 0.0, 1.0)
	var negative_alpha_t: float = clampf(-alpha_deg / maxf(aoa_lift_full_deg, 0.1), 0.0, 1.0)
	var aoa_lift_scale: float = 1.0 + positive_alpha_t * aoa_lift_bonus_factor - negative_alpha_t * aoa_negative_lift_penalty_factor
	commanded_lift_ratio = clampf(
		zero_aoa_lift_ratio * maxf(aoa_lift_scale, 0.0),
		0.0,
		maxf(max_lift_ratio, 0.1)
	)
	var gravity_mag: float = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	var base_lift_mag: float = rb.mass * gravity_mag * maxf(rb.gravity_scale, 0.0) * commanded_lift_ratio

	# Calculate stall effects
	var speed_stall_severity: float = 0.0
	if forward_speed < effective_stall_speed and speed > 5.0:
		speed_stall_severity = 1.0 - (forward_speed / effective_stall_speed)
	var stall_severity: float = maxf(speed_stall_severity, aoa_stall_severity)
	current_stall_severity = stall_severity

	if aoa_stall_severity > 0.0 and speed > 5.0:
		var high_aoa_drag_force: Vector3 = -v_dir * aoa_stall_drag_strength * aoa_stall_severity * speed * speed
		rb.apply_central_force(high_aoa_drag_force)
		total_drag_force += high_aoa_drag_force
		
	# Reduce lift in stall
	var speed_lift_loss: float = stall_lift_loss * speed_stall_severity
	var aoa_lift_loss: float = aoa_stall_lift_loss * aoa_stall_severity
	var actual_lift_mag: float = base_lift_mag * (1.0 - clampf(maxf(speed_lift_loss, aoa_lift_loss), 0.0, 0.95))
	lift_force = lift_dir * actual_lift_mag
	actual_lift_ratio = actual_lift_mag / maxf(rb.mass * gravity_mag * maxf(rb.gravity_scale, 0.0), 0.001)

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
	control_authority = clamp(forward_speed / min_control_speed, 0.0, 1.0)
	
	# Reduce control authority in stall
	var stall_control_loss = maxf(
		pow(speed_stall_severity, 0.3),
		aoa_stall_severity * aoa_stall_control_loss
	)
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

	_update_aero_report(
		delta,
		local_vel,
		speed,
		signed_forward_speed,
		lateral_speed,
		alpha_deg,
		commanded_lift_ratio,
		actual_lift_ratio,
		control_authority,
		approach_mult,
		forward_drag_force,
		lateral_drag_force,
		total_drag_force,
		lift_force
	)

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
	var roll_input_release: float = 1.0 - clampf(absf(roll_input) * roll_stability_input_release, 0.0, 0.95)
	var bank_release_t: float = _smoothstep(
		roll_stability_bank_release_start_deg,
		maxf(roll_stability_bank_release_full_deg, roll_stability_bank_release_start_deg + 1.0),
		absf(rad_to_deg(roll_error))
	)
	var bank_release: float = lerpf(1.0, clampf(roll_stability_bank_min_factor, 0.0, 1.0), bank_release_t)
	var roll_self_level_factor: float = roll_factor * roll_input_release * bank_release
	var roll_rate_damping_factor: float = roll_factor * maxf(
		roll_input_release * bank_release,
		clampf(roll_stability_bank_min_factor, 0.0, 1.0)
	)

	var roll_torque: Vector3 = fwd_dir * limited_roll_error * stability_strength * roll_self_level_factor * rb.mass * stability_authority * stability_torque_scale
	var pitch_torque: Vector3 = -right_dir * limited_pitch_error * stability_strength * pitch_factor * rb.mass * stability_authority * stability_torque_scale
	var roll_rate_damping_torque: Vector3 = -fwd_dir * roll_rate * roll_rate_damping_factor * rb.mass * stability_authority * roll_stability_rate_damping
	var pitch_rate_damping_torque: Vector3 = -right_dir * pitch_rate * pitch_factor * rb.mass * stability_authority * pitch_stability_rate_damping
	rb.apply_torque(roll_torque + pitch_torque + roll_rate_damping_torque + pitch_rate_damping_torque)

func get_estimated_angle_of_attack_deg() -> float:
	if rb == null:
		return 0.0
	var local_vel: Vector3 = rb.global_transform.basis.inverse() * rb.linear_velocity
	return rad_to_deg(atan2(-local_vel.y, maxf(local_vel.z, 0.1)))

func _get_aoa_stall_severity(alpha_deg: float) -> float:
	var start_deg: float = maxf(aoa_stall_start_deg, 0.1)
	var full_deg: float = maxf(aoa_stall_full_deg, start_deg + 0.1)
	var abs_alpha: float = absf(alpha_deg)
	if abs_alpha <= start_deg:
		return 0.0
	return clampf((abs_alpha - start_deg) / (full_deg - start_deg), 0.0, 1.0)

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
	var commanded_ratio: float = clampf(
		zero_aoa_lift_ratio * maxf(aoa_lift_scale, 0.0),
		0.0,
		maxf(max_lift_ratio, 0.1)
	)
	var aoa_stall_severity: float = _get_aoa_stall_severity(alpha_deg)
	return commanded_ratio * (1.0 - clampf(aoa_stall_lift_loss * aoa_stall_severity, 0.0, 0.95))

func get_stall_severity() -> float:
	return current_stall_severity

func get_effective_stall_speed_mps() -> float:
	return stall_speed * (flaps_stall_speed_factor if _is_flaps_deployed() else 1.0)

func _prepare_aero_report() -> void:
	if not aero_report_enabled:
		return
	if _aero_report_prepared:
		return
	_aero_report_prepared = true
	if aero_report_reset_on_first_aircraft and not _aero_report_reset_done:
		_aero_report_reset_done = true
		_overwrite_aero_report(aero_report_path)
		if aero_report_project_mirror_enabled:
			_overwrite_aero_report(aero_report_project_mirror_path)
		return
	_ensure_aero_report_header(aero_report_path)
	if aero_report_project_mirror_enabled:
		_ensure_aero_report_header(aero_report_project_mirror_path)


func _update_aero_report(
		delta: float,
		local_vel: Vector3,
		speed: float,
		signed_forward_speed: float,
		lateral_speed: float,
		alpha_deg: float,
		commanded_lift_ratio: float,
		actual_lift_ratio: float,
		control_authority: float,
		approach_mult: float,
		forward_drag_force: Vector3,
		lateral_drag_force: Vector3,
		total_drag_force: Vector3,
		lift_force: Vector3
) -> void:
	if not aero_report_enabled or rb == null:
		return
	if not _should_write_aero_report():
		return
	_prepare_aero_report()
	_aero_report_timer_s -= delta
	if _aero_report_timer_s > 0.0:
		return
	_aero_report_timer_s = maxf(aero_report_interval_s, 0.05)
	var line := _build_aero_report_line(
		local_vel,
		speed,
		signed_forward_speed,
		lateral_speed,
		alpha_deg,
		commanded_lift_ratio,
		actual_lift_ratio,
		control_authority,
		approach_mult,
		forward_drag_force,
		lateral_drag_force,
		total_drag_force,
		lift_force
	)
	_append_aero_report_line(aero_report_path, line)
	if aero_report_project_mirror_enabled:
		_append_aero_report_line(aero_report_project_mirror_path, line)


func _build_aero_report_line(
		local_vel: Vector3,
		speed: float,
		signed_forward_speed: float,
		lateral_speed: float,
		alpha_deg: float,
		commanded_lift_ratio: float,
		actual_lift_ratio: float,
		control_authority: float,
		approach_mult: float,
		forward_drag_force: Vector3,
		lateral_drag_force: Vector3,
		total_drag_force: Vector3,
		lift_force: Vector3
) -> String:
	var pos := rb.global_position
	var basis := rb.global_transform.basis
	var fwd := basis.z.normalized()
	var up := basis.y.normalized()
	var right := basis.x.normalized()
	var ground_y := _sample_aero_report_ground_y(pos)
	var agl := pos.y - ground_y if not is_nan(ground_y) else NAN
	var pitch_deg := rad_to_deg(asin(clampf(fwd.y, -1.0, 1.0)))
	var roll_deg := rad_to_deg(atan2(right.y, up.y))
	var heading_deg := rad_to_deg(atan2(fwd.x, fwd.z))
	var throttle_cmd := _get_aero_report_throttle_command()
	var engine_power := _get_aero_report_engine_power()
	var thrust_n := _get_aero_report_thrust_n()
	var forward_thrust_n := _get_aero_report_forward_thrust_n(fwd)
	var flap_position := _get_flap_position()
	return ",".join([
		_fmt_float(Time.get_ticks_msec() / 1000.0, 3),
		_csv_name(rb.name),
		_csv_name(_get_aircraft_type_label()),
		_fmt_float(pos.x, 2),
		_fmt_float(pos.y, 2),
		_fmt_float(pos.z, 2),
		_fmt_float(ground_y, 2),
		_fmt_float(agl, 2),
		_fmt_float(speed, 2),
		_fmt_float(signed_forward_speed, 2),
		_fmt_float(lateral_speed, 2),
		_fmt_float(local_vel.x, 2),
		_fmt_float(local_vel.y, 2),
		_fmt_float(local_vel.z, 2),
		_fmt_float(rb.linear_velocity.y, 2),
		_fmt_float(pitch_deg, 2),
		_fmt_float(roll_deg, 2),
		_fmt_float(heading_deg, 2),
		_fmt_float(alpha_deg, 2),
		_fmt_float(commanded_lift_ratio, 3),
		_fmt_float(actual_lift_ratio, 3),
		_fmt_float(current_stall_severity, 3),
		_fmt_float(control_authority, 3),
		_fmt_float(pitch_input, 3),
		_fmt_float(roll_input, 3),
		_fmt_float(yaw_input, 3),
		_fmt_float(throttle_cmd, 3),
		_fmt_float(engine_power, 3),
		_fmt_float(thrust_n, 1),
		_fmt_float(forward_thrust_n, 1),
		str(_is_gear_deployed()),
		_fmt_float(flap_position, 3),
		_fmt_float(approach_mult, 3),
		_fmt_float(forward_drag_force.length(), 1),
		_fmt_float(lateral_drag_force.length(), 1),
		_fmt_float(total_drag_force.length(), 1),
		_fmt_float(lift_force.length(), 1),
		_fmt_float(rb.angular_velocity.x, 3),
		_fmt_float(rb.angular_velocity.y, 3),
		_fmt_float(rb.angular_velocity.z, 3),
		_fmt_float(mass_safe(), 1),
	])


func _aero_report_header() -> String:
	return ",".join([
		"t_s",
		"aircraft",
		"aircraft_type",
		"pos_x",
		"pos_y",
		"pos_z",
		"ground_y",
		"agl_m",
		"speed_mps",
		"forward_speed_mps",
		"lateral_speed_mps",
		"local_vel_x_mps",
		"local_vel_y_mps",
		"local_vel_z_mps",
		"vertical_speed_mps",
		"pitch_deg",
		"roll_deg",
		"heading_deg",
		"aoa_deg",
		"cmd_lift_ratio",
		"actual_lift_ratio",
		"stall_severity",
		"control_authority",
		"pitch_input",
		"roll_input",
		"yaw_input",
		"throttle_cmd",
		"engine_power",
		"thrust_n",
		"forward_thrust_n",
		"gear_deployed",
		"flap_position",
		"gear_flap_drag_mult",
		"forward_drag_n",
		"lateral_drag_n",
		"total_drag_n",
		"lift_n",
		"ang_vel_x",
		"ang_vel_y",
		"ang_vel_z",
		"mass_kg",
	])


func _overwrite_aero_report(path: String) -> void:
	if path.is_empty():
		return
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("[SimpleAero] Could not reset aero report: %s" % path)
		return
	file.store_line(_aero_report_header())
	file.close()


func _ensure_aero_report_header(path: String) -> void:
	if path.is_empty() or FileAccess.file_exists(path):
		return
	_overwrite_aero_report(path)


func _append_aero_report_line(path: String, line: String) -> void:
	if path.is_empty():
		return
	var file := FileAccess.open(path, FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
	if file == null:
		push_warning("[SimpleAero] Could not open aero report: %s" % path)
		return
	if file.get_length() <= 0:
		file.store_line(_aero_report_header())
	file.seek_end()
	file.store_line(line)
	file.close()


func _sample_aero_report_ground_y(world_pos: Vector3) -> float:
	var nav_grid := get_node_or_null("/root/TerrainNavGrid")
	if nav_grid != null and nav_grid.has_method("sample_query_height"):
		var query_h := float(nav_grid.call("sample_query_height", world_pos.x, world_pos.z))
		if query_h > -500000.0:
			return query_h
	if nav_grid != null and nav_grid.has_method("sample_height"):
		var grid_h := float(nav_grid.call("sample_height", world_pos.x, world_pos.z))
		if grid_h > -500000.0:
			return grid_h
	var terrain: Node = TerrainReference.get_terrain_node()
	if terrain != null and is_instance_valid(terrain):
		if terrain.has_method("get_height"):
			return float(terrain.call("get_height", world_pos))
		if "data" in terrain:
			var data_variant: Variant = terrain.get("data")
			if data_variant is Object:
				var data_object := data_variant as Object
				if data_object.has_method("get_height"):
					return float(data_object.call("get_height", world_pos))
	return NAN


func _should_write_aero_report() -> bool:
	if rb == null:
		return false
	var director := get_node_or_null("/root/FlightDirector")
	if director != null:
		var player_controlled = director.get("player_controlled_plane")
		if bool(director.get("is_player_controlling")):
			return player_controlled == rb
		return false
	# Fallback for isolated scene tests without FlightDirector: only record aircraft
	# whose AI toggle is explicitly off and that are not tagged as AI/enemy.
	if rb.is_in_group("ai_aircraft") or rb.is_in_group("enemies"):
		return false
	var ai_toggle := rb.get_node_or_null("AIToggle")
	if ai_toggle != null and "ai_active" in ai_toggle:
		return not bool(ai_toggle.get("ai_active"))
	return false


func _get_aero_report_throttle_command() -> float:
	var control_engine := rb.get_node_or_null("ControlEngine") if rb != null else null
	if control_engine != null and "target_power" in control_engine:
		return float(control_engine.get("target_power"))
	var engine_modules := _get_engine_modules_for_report()
	if not engine_modules.is_empty():
		var total := 0.0
		var count := 0
		for engine in engine_modules:
			if engine == null:
				continue
			if "target_power" in engine:
				total += float(engine.get("target_power"))
				count += 1
		if count > 0:
			return total / float(count)
	return NAN


func _get_aero_report_engine_power() -> float:
	var engine_modules := _get_engine_modules_for_report()
	if engine_modules.is_empty():
		return NAN
	var total := 0.0
	var count := 0
	for engine in engine_modules:
		if engine == null:
			continue
		if engine.has_method("get_throttle_ratio"):
			total += float(engine.call("get_throttle_ratio"))
			count += 1
		elif "current_power" in engine:
			total += float(engine.get("current_power"))
			count += 1
	return total / float(maxi(count, 1)) if count > 0 else NAN


func _get_aero_report_thrust_n() -> float:
	var engine_modules := _get_engine_modules_for_report()
	if engine_modules.is_empty():
		return NAN
	var total := 0.0
	var count := 0
	for engine in engine_modules:
		if engine == null or not is_instance_valid(engine):
			continue
		var power_factor := _get_engine_power_factor(engine)
		var power := _get_engine_current_power(engine)
		if is_nan(power_factor) or is_nan(power):
			continue
		total += absf(power_factor * power)
		count += 1
	return total if count > 0 else NAN


func _get_aero_report_forward_thrust_n(aircraft_forward: Vector3) -> float:
	var engine_modules := _get_engine_modules_for_report()
	if engine_modules.is_empty():
		return NAN
	var total := 0.0
	var count := 0
	for engine in engine_modules:
		if engine == null or not is_instance_valid(engine):
			continue
		var power_factor := _get_engine_power_factor(engine)
		var power := _get_engine_current_power(engine)
		if is_nan(power_factor) or is_nan(power):
			continue
		var engine_spatial := engine as Node3D
		if engine_spatial == null:
			continue
		var thrust_vec: Vector3 = -engine_spatial.global_transform.basis.z.normalized() * power_factor * power
		total += thrust_vec.dot(aircraft_forward.normalized())
		count += 1
	return total if count > 0 else NAN


func _get_engine_power_factor(engine: Node) -> float:
	if engine != null and "PowerFactor" in engine:
		return float(engine.get("PowerFactor"))
	return NAN


func _get_engine_current_power(engine: Node) -> float:
	if engine == null:
		return NAN
	if engine.has_method("get_throttle_ratio"):
		return float(engine.call("get_throttle_ratio"))
	if "current_power" in engine:
		return float(engine.get("current_power"))
	return NAN


func _get_engine_modules_for_report() -> Array:
	if rb == null:
		return []
	var needs_refresh := _engine_modules.is_empty()
	if not needs_refresh:
		for engine in _engine_modules:
			if engine == null or not is_instance_valid(engine):
				needs_refresh = true
				break
	if needs_refresh:
		_engine_modules.clear()
		if rb.has_method("find_modules_by_type"):
			_engine_modules = rb.find_modules_by_type("engine")
		if _engine_modules.is_empty():
			var control_engine := rb.get_node_or_null("ControlEngine")
			if control_engine != null and "engine_modules" in control_engine:
				for engine in control_engine.get("engine_modules"):
					if engine != null and is_instance_valid(engine):
						_engine_modules.append(engine)
		if _engine_modules.is_empty():
			_collect_engine_modules_recursive(rb, _engine_modules)
	return _engine_modules


func _collect_engine_modules_recursive(node: Node, result: Array) -> void:
	for child in node.get_children():
		if child == null:
			continue
		var module_type := ""
		if "ModuleType" in child:
			module_type = str(child.get("ModuleType"))
		var looks_like_engine := child.has_method("get_throttle_ratio") and "PowerFactor" in child
		if module_type == "engine" or looks_like_engine:
			result.append(child)
		_collect_engine_modules_recursive(child, result)


func _get_flap_position() -> float:
	if _flaps_module != null and "flap_position" in _flaps_module:
		return float(_flaps_module.get("flap_position"))
	return 0.0


func _get_aircraft_type_label() -> String:
	if rb == null:
		return "unknown"
	var scene_path: String = rb.scene_file_path
	if not scene_path.is_empty():
		var base := scene_path.get_file().get_basename()
		if not base.is_empty():
			return base
	var name_label := String(rb.name)
	var aircraft_pattern := RegEx.new()
	if aircraft_pattern.compile("(?i)^(aircraft[_ -]?\\d+)") == OK:
		var match := aircraft_pattern.search(name_label)
		if match != null:
			return match.get_string(1).replace(" ", "_").replace("-", "_")
	return name_label


func _fmt_float(value: float, decimals: int = 2) -> String:
	if is_nan(value):
		return "nan"
	if not is_finite(value):
		return "inf" if value > 0.0 else "-inf"
	return String.num(value, decimals)


func _csv_name(value: String) -> String:
	return value.replace(",", "_").replace("\n", " ").replace("\r", " ")


func mass_safe() -> float:
	return rb.mass if rb != null else 0.0


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
