extends AircraftModule
class_name AircraftModule_ControlSteering

@export var ControlActive: bool = true
@export var input_curve: float = 1.8   # Legacy Simplified/helicopter curve: 1.0 = linear; >1 soft near center
@export var deadzone: float = 0.05     # Legacy second-stage deadzone; Advanced fixed-wing uses the Gameplay setting only
@export_group("Advanced Fixed-Wing Input")
@export_range(0.0, 1.0, 0.01) var advanced_pitch_expo: float = 0.35
@export_range(0.0, 1.0, 0.01) var advanced_roll_expo: float = 0.25
@export_range(0.0, 1.0, 0.01) var advanced_yaw_expo: float = 0.15
@export_group("")
@export var rudder_assist_gain: float = 3.0
@export var rudder_assist_max_input: float = 0.35  # LIGHT-mode command envelope before its 45 percent strength scale
@export var rudder_assist_full_max_input: float = 1.0  # FULL may request all available rudder; SimpleAero still enforces physical limits
@export var rudder_assist_yaw_rate_damping: float = 0.40
@export var rudder_assist_response_speed: float = 4.0
@export var rudder_assist_stiffened_gain_factor: float = 0.65
@export var rudder_assist_stiffened_max_input: float = 0.18
@export var rudder_assist_stiffened_response_speed: float = 1.2
@export var rudder_assist_full_deflection_lateral_g: float = 0.35
@export var rudder_assist_velocity_slip_weight: float = 1.0
@export var rudder_assist_lateral_g_weight: float = 0.20  # Stable near-center slip-ball sensitivity
@export var rudder_assist_large_error_lateral_g_weight: float = 0.30  # Use more authority once the ball is clearly displaced
@export var rudder_assist_ball_boost_start: float = 0.25  # Normalized ball displacement where progressive sensitivity begins
@export var rudder_assist_ball_boost_full: float = 0.75  # Normalized ball displacement where the large-error weight is reached
@export var rudder_assist_lateral_g_filter_speed: float = 8.0
@export var rudder_assist_center_deadzone: float = 0.012
@export var rudder_assist_manual_override_start: float = 0.05
@export var rudder_assist_manual_override_full: float = 0.30
@export var rudder_assist_reengagement_speed: float = 5.0  # Full automatic authority returns in about 0.2 s after release
@export var rudder_assist_integral_gain: float = 0.45
@export var rudder_assist_integral_limit: float = 0.8
@export var rudder_assist_adaptive_response_enabled: bool = true
@export var rudder_assist_reference_yaw_rate: float = 0.125 # rad/s per full rudder, established Aircraft 5 tuning
@export var rudder_assist_error_rate_damping: float = 0.25
@export var rudder_assist_integral_unwind_multiplier: float = 3.0
@export_group("Simplified Fixed-Wing Assist")
@export var simplified_rudder_assist_gain: float = 2.25
@export var simplified_rudder_assist_max_input: float = 1.0
@export var simplified_rudder_assist_yaw_rate_damping: float = 0.02
@export var simplified_rudder_assist_response_speed: float = 30.0
@export var simplified_rudder_assist_velocity_slip_weight: float = 0.65
@export var simplified_rudder_assist_lateral_g_filter_speed: float = 18.0
@export var simplified_rudder_assist_center_deadzone: float = 0.055
@export_group("")
@export var helicopter_rudder_assist_gain: float = 0.55
@export var helicopter_rudder_assist_max_input: float = 0.35
@export var helicopter_rudder_assist_yaw_rate_damping: float = 0.055
@export var helicopter_rudder_assist_response_speed: float = 10.0
@export var helicopter_rudder_assist_full_deflection_lateral_g: float = 0.75
@export var helicopter_rudder_assist_velocity_slip_weight: float = 0.20
@export var helicopter_rudder_assist_lateral_g_filter_speed: float = 8.0
@export var helicopter_rudder_assist_center_deadzone: float = 0.12
@export var helicopter_rudder_assist_manual_override_start: float = 0.02
@export var helicopter_rudder_assist_manual_override_full: float = 0.16
@export var helicopter_rudder_assist_roll_feedforward: float = 0.25
@export var helicopter_rudder_assist_lateral_velocity_gain: float = 0.55
@export var helicopter_rudder_assist_min_reference_speed: float = 8.0
@export var helicopter_rudder_assist_min_forward_speed: float = 8.0
@export var helicopter_rudder_assist_full_forward_speed: float = 32.0

var steering_module: Node = null
var landing_gear: AircraftModule_LandingGear = null
var simple_aero: Node = null
var aero_has_cmds := false
var _is_helicopter_controls: bool = false
var _filtered_lateral_g: float = 0.0
var _previous_velocity: Vector3 = Vector3.ZERO
var _has_previous_velocity: bool = false
var _filtered_assist_yaw: float = 0.0
var _rudder_integral: float = 0.0
var _previous_assist_error: float = 0.0
var _filtered_assist_error_rate: float = 0.0
var _has_assist_error: bool = false
var _fixed_wing_auto_rudder_authority: float = 1.0
var _simple_aero_has_control_envelope: bool = false

# Public read-only-by-convention telemetry. SimpleAero's player flight recorder
# samples these after input shaping so a marked anomaly can distinguish the
# physical stick command from automatic rudder correction and surface lag.
var telemetry_raw_roll: float = 0.0
var telemetry_raw_pitch: float = 0.0
var telemetry_raw_yaw: float = 0.0
var telemetry_shaped_roll: float = 0.0
var telemetry_shaped_pitch: float = 0.0
var telemetry_shaped_yaw: float = 0.0
var telemetry_assisted_yaw: float = 0.0
var telemetry_rudder_assist_component: float = 0.0
var telemetry_rudder_slip_error: float = 0.0
var telemetry_rudder_target_assist: float = 0.0
var telemetry_rudder_filtered_assist: float = 0.0
var telemetry_rudder_assist_strength: float = 0.0
var telemetry_rudder_assist_limit: float = 0.0
var telemetry_rudder_assist_stiffening: float = 0.0

func setup(aircraft_node: Node) -> void:
	_reset_rudder_assist_state()
	aircraft = aircraft_node

	# Grab the steering module provided by the addon
	var list = aircraft.find_modules_by_type("steering")
	if list and list.size() > 0:
		steering_module = list.pop_front()
	pass
	simple_aero = aircraft.get_node_or_null("SimpleAero")
	if simple_aero == null:
		simple_aero = aircraft.find_child("SimpleAero", true, false)
	if simple_aero != null and not _node_has_properties(simple_aero, ["pitch_input", "roll_input", "yaw_input"]):
		simple_aero = null
	_simple_aero_has_control_envelope = simple_aero != null \
		and _node_has_properties(simple_aero, ["current_high_speed_stiffening"])
	_is_helicopter_controls = _detect_helicopter_controls()
	landing_gear = aircraft.find_child("LandingGear", true, false) as AircraftModule_LandingGear

func _physics_process(delta: float) -> void:
	if (not ControlActive) or (steering_module == null):
		if is_instance_valid(landing_gear):
			landing_gear.set_wheel_brake_input(0.0)
		_reset_rudder_assist_state()
		return

	if is_instance_valid(landing_gear) and not _is_helicopter_controls:
		# Shared trigger pressure brakes; their difference remains the rudder input.
		# Use raw pressure so braking is linear in both flight-model modes.
		var shared_pressure := minf(Input.get_action_raw_strength("yaw_left"), Input.get_action_raw_strength("yaw_right"))
		landing_gear.set_wheel_brake_input(clampf((shared_pressure - 0.05) / 0.95, 0.0, 1.0))

	var advanced_fixed_wing := not _is_helicopter_controls and _is_advanced_fixed_wing_model()
	# Pitch/roll use Godot's configured Input Map deadzone. Advanced rudder reads
	# the trigger actions before their legacy 15% deadzone so it can use the same
	# configurable deadzone as the stick without changing Simplified/helicopters.
	var roll_raw  := Input.get_action_strength("roll_right") - Input.get_action_strength("roll_left")
	var pitch_raw := Input.get_action_strength("pitch_up")   - Input.get_action_strength("pitch_down")
	var yaw_legacy := Input.get_action_strength("yaw_left") - Input.get_action_strength("yaw_right")
	var yaw_raw := Input.get_action_raw_strength("yaw_left") \
		- Input.get_action_raw_strength("yaw_right") if advanced_fixed_wing else yaw_legacy
	telemetry_raw_roll = roll_raw
	telemetry_raw_pitch = pitch_raw
	telemetry_raw_yaw = yaw_raw

	# Advanced fixed-wing input consumes the Input Map's already-deadzoned value
	# directly. A blended cubic retains a finite center slope for precise small
	# corrections while preserving full command at full stick. Simplified and
	# helicopter controls keep their former power curve and second-stage deadzone.
	var roll := shape_advanced_fixed_wing_input(roll_raw, advanced_roll_expo) \
		if advanced_fixed_wing else _shape_input(roll_raw)
	var pitch := shape_advanced_fixed_wing_input(pitch_raw, advanced_pitch_expo) \
		if advanced_fixed_wing else _shape_input(pitch_raw)
	var yaw := shape_advanced_fixed_wing_raw_input(
		yaw_raw,
		advanced_yaw_expo,
		_get_advanced_fixed_wing_deadzone()
	) if advanced_fixed_wing else _shape_input(yaw_raw)
	var assisted_yaw := _apply_rudder_assist(yaw, delta, roll)
	telemetry_shaped_roll = roll
	telemetry_shaped_pitch = pitch
	telemetry_shaped_yaw = yaw
	telemetry_assisted_yaw = assisted_yaw

	# Drive control surfaces (addon uses z=roll, x=pitch, y=yaw)
	steering_module.set_z(roll)
	steering_module.set_x(pitch)
	steering_module.set_y(assisted_yaw)

	# Feed the same to SimpleAero if present and compatible
	if simple_aero != null and is_instance_valid(simple_aero):
		simple_aero.pitch_input = pitch
		simple_aero.roll_input = -roll
		simple_aero.yaw_input = assisted_yaw

func _shape_input(v: float) -> float:
	if absf(v) < deadzone:
		return 0.0
	var s := (absf(v) - deadzone) / (1.0 - deadzone)
	if input_curve != 1.0:
		s = pow(s, input_curve)
	return s * signf(v)


func shape_advanced_fixed_wing_input(v: float, expo: float) -> float:
	var clamped_input := clampf(v, -1.0, 1.0)
	var magnitude := absf(clamped_input)
	var cubic_blend := clampf(expo, 0.0, 1.0)
	var shaped_magnitude := lerpf(magnitude, magnitude * magnitude * magnitude, cubic_blend)
	return shaped_magnitude * signf(clamped_input)


func shape_advanced_fixed_wing_raw_input(v: float, expo: float, input_deadzone: float) -> float:
	var clamped_input := clampf(v, -1.0, 1.0)
	var magnitude := absf(clamped_input)
	var safe_deadzone := clampf(input_deadzone, 0.0, 0.95)
	if magnitude <= safe_deadzone:
		return 0.0
	var normalized := (magnitude - safe_deadzone) / (1.0 - safe_deadzone)
	return shape_advanced_fixed_wing_input(normalized * signf(clamped_input), expo)


func _get_advanced_fixed_wing_deadzone() -> float:
	var pause_menu := get_node_or_null("/root/PauseMenu")
	if pause_menu != null and pause_menu.has_method("get_stick_deadzone"):
		return clampf(float(pause_menu.call("get_stick_deadzone")), 0.0, 0.95)
	if InputMap.has_action("pitch_up"):
		return clampf(InputMap.action_get_deadzone("pitch_up"), 0.0, 0.95)
	return 0.05


func _apply_rudder_assist(manual_yaw: float, delta: float, roll_command: float = 0.0) -> float:
	var assist_strength := _get_rudder_assist_strength(_is_helicopter_controls)
	telemetry_rudder_assist_strength = assist_strength
	if assist_strength <= 0.0 or aircraft == null or not is_instance_valid(aircraft) or not (aircraft is RigidBody3D):
		_reset_rudder_assist_state()
		telemetry_assisted_yaw = manual_yaw
		return manual_yaw

	var gain := helicopter_rudder_assist_gain if _is_helicopter_controls else rudder_assist_gain
	var max_input := helicopter_rudder_assist_max_input if _is_helicopter_controls else rudder_assist_max_input
	var yaw_rate_damping := helicopter_rudder_assist_yaw_rate_damping if _is_helicopter_controls else rudder_assist_yaw_rate_damping
	var response_speed := helicopter_rudder_assist_response_speed if _is_helicopter_controls else rudder_assist_response_speed
	var center_deadzone := helicopter_rudder_assist_center_deadzone if _is_helicopter_controls else rudder_assist_center_deadzone
	var manual_override_start := helicopter_rudder_assist_manual_override_start if _is_helicopter_controls else rudder_assist_manual_override_start
	var manual_override_full := helicopter_rudder_assist_manual_override_full if _is_helicopter_controls else rudder_assist_manual_override_full
	var advanced_fixed_wing := not _is_helicopter_controls and _is_advanced_fixed_wing_model()
	if not _is_helicopter_controls and not advanced_fixed_wing:
		gain = simplified_rudder_assist_gain
		max_input = simplified_rudder_assist_max_input
		yaw_rate_damping = simplified_rudder_assist_yaw_rate_damping
		response_speed = simplified_rudder_assist_response_speed
		center_deadzone = simplified_rudder_assist_center_deadzone
	var fixed_wing_stiffening := 0.0
	if advanced_fixed_wing:
		fixed_wing_stiffening = _get_fixed_wing_rudder_stiffening()
		gain *= lerpf(1.0, clampf(rudder_assist_stiffened_gain_factor, 0.0, 1.0), fixed_wing_stiffening)
		max_input = _get_advanced_fixed_wing_rudder_assist_limit(
			assist_strength,
			fixed_wing_stiffening
		)
		response_speed = lerpf(
			response_speed,
			maxf(rudder_assist_stiffened_response_speed, 0.1),
			fixed_wing_stiffening
		)
	telemetry_rudder_assist_stiffening = fixed_wing_stiffening
	telemetry_rudder_assist_limit = max_input

	var slip_error := _estimate_slip_ball_error(delta, _is_helicopter_controls)
	if absf(slip_error) < center_deadzone:
		slip_error = 0.0
	telemetry_rudder_slip_error = slip_error

	var basis := (aircraft as Node3D).global_transform.basis.orthonormalized()
	var yaw_rate := 0.0
	var helicopter_speed_factor := 1.0
	if aircraft is RigidBody3D:
		yaw_rate = (aircraft as RigidBody3D).angular_velocity.dot(basis.y)

	# Fixed-wing uses its existing slip-ball feedback below. Helicopters replace
	# this target with rotor-roll feed-forward and measured lateral airspeed.
	var slip_correction := slip_error * gain if advanced_fixed_wing else -slip_error * gain
	if advanced_fixed_wing and rudder_assist_adaptive_response_enabled:
		# Existing high-speed protection already reduces feedback and disables trim.
		# Fade out the extra gain reduction as that protection takes over.
		var response_scale := lerpf(_get_rudder_response_gain_scale(), 1.0,
			_smoothstep(0.0, 0.15, fixed_wing_stiffening))
		var error_rate := (slip_error - _previous_assist_error) / maxf(delta, 0.001) if _has_assist_error else 0.0
		_filtered_assist_error_rate = lerpf(_filtered_assist_error_rate, error_rate, 1.0 - exp(-maxf(delta, 0.0) / 0.15))
		_previous_assist_error = slip_error
		_has_assist_error = true
		# The derivative anticipates slip reaching centre; it does not oppose a
		# steady coordinated turn merely because the aircraft has a yaw rate.
		slip_correction = (slip_correction + _filtered_assist_error_rate * rudder_assist_error_rate_damping) * response_scale
	var target_assist := slip_correction - yaw_rate * yaw_rate_damping
	if _is_helicopter_controls:
		var local_velocity := basis.inverse() * _get_control_air_velocity()
		helicopter_speed_factor = _smoothstep(
			helicopter_rudder_assist_min_forward_speed,
			maxf(helicopter_rudder_assist_full_forward_speed,
				helicopter_rudder_assist_min_forward_speed + 0.1),
			absf(local_velocity.z)
		)
		var reference_speed := maxf(absf(local_velocity.z), helicopter_rudder_assist_min_reference_speed)
		var lateral_error := clampf(local_velocity.x / reference_speed, -1.0, 1.0)
		# HelicopterFlight negates the shaped roll command before tilting its rotor.
		# Feed yaw toward that lateral thrust immediately, then follow the actual
		# sideways movement as it builds. Pedals retain the existing override.
		target_assist = -roll_command * helicopter_rudder_assist_roll_feedforward \
			+ lateral_error * helicopter_rudder_assist_lateral_velocity_gain \
			- yaw_rate * yaw_rate_damping
		telemetry_rudder_slip_error = lateral_error
	if advanced_fixed_wing:
		var bank := atan2(basis.x.y, basis.y.y)
		var speed := _get_control_air_velocity().length()
		var can_accumulate: bool = assist_strength > 0.99 and fixed_wing_stiffening < 0.05 \
			and absf(manual_yaw) < 0.05 and absf(bank) > deg_to_rad(5.0) \
			and basis.y.y > 0.25 and speed > float(simple_aero.get("stall_speed")) * 1.2 \
			and simple_aero.call("_is_airborne_for_stall_effects")
		# Positive bank requires negative yaw for this aircraft's +Z forward axis.
		# Release stored turn trim on rollout/reversal or pedal takeover.
		if _rudder_integral * bank > 0.0:
			can_accumulate = false
		var ball_error := -_filtered_lateral_g / maxf(rudder_assist_full_deflection_lateral_g, 0.05)
		target_assist += _update_rudder_integral(ball_error, target_assist, max_input, can_accumulate, delta)
	else:
		_rudder_integral = 0.0
	target_assist = clampf(
		target_assist,
		-max_input,
		max_input
	) * assist_strength
	telemetry_rudder_target_assist = target_assist

	var response_t := clampf(delta * maxf(response_speed, 0.1), 0.0, 1.0)
	_filtered_assist_yaw = lerpf(_filtered_assist_yaw, target_assist, response_t)
	var available_assist := _filtered_assist_yaw * helicopter_speed_factor \
		if _is_helicopter_controls else _filtered_assist_yaw
	telemetry_rudder_filtered_assist = available_assist
	if _is_helicopter_controls:
		telemetry_rudder_assist_strength = assist_strength * helicopter_speed_factor

	var assisted_yaw := _blend_legacy_manual_rudder_override(
		manual_yaw,
		available_assist,
		manual_override_start,
		manual_override_full
	) if _is_helicopter_controls else _blend_fixed_wing_manual_rudder_priority(
		manual_yaw,
		_filtered_assist_yaw,
		delta
	)
	telemetry_rudder_assist_component = assisted_yaw - manual_yaw
	telemetry_assisted_yaw = assisted_yaw
	return assisted_yaw


func _update_rudder_integral(error: float, proportional: float, limit: float, enabled: bool, delta: float) -> float:
	if not enabled or rudder_assist_integral_gain <= 0.0:
		_rudder_integral = move_toward(_rudder_integral, 0.0, 2.0 * delta)
		return _rudder_integral
	# Conditional integration prevents accumulating against a saturated command.
	# Opposite error can always unwind the stored correction.
	var total := proportional + _rudder_integral
	if absf(error) > 0.025 and (absf(total) < limit or error * total < 0.0):
		var integral_step := error * rudder_assist_integral_gain * delta
		if rudder_assist_adaptive_response_enabled and error * _rudder_integral < 0.0:
			# Remove stale trim faster, without jumping through zero and creating
			# a new opposite trim demand in the same step.
			integral_step = signf(integral_step) * minf(absf(_rudder_integral),
				absf(integral_step) * maxf(rudder_assist_integral_unwind_multiplier, 1.0))
		_rudder_integral = clampf(_rudder_integral + integral_step,
			-minf(limit, rudder_assist_integral_limit), minf(limit, rudder_assist_integral_limit))
	return _rudder_integral


func _get_rudder_response_gain_scale() -> float:
	if not is_instance_valid(simple_aero) or not simple_aero.has_method("get_rate_damping_factor_at_speed"):
		return 1.0
	var speed := _get_control_air_velocity().length()
	var authority := float(simple_aero.get_axis_control_authority_at_speed(speed, &"yaw"))
	var damping := float(simple_aero.get_rate_damping_factor_at_speed(speed))
	var maximum_rate := absf(float(simple_aero.yaw_power)) * authority \
		/ maxf(float(simple_aero.angular_damping_strength) * damping, 0.001)
	# Reduce feedback gain on more responsive aircraft, without increasing gain
	# on a weak/stalled rudder or changing the available manual surface travel.
	return clampf(rudder_assist_reference_yaw_rate / maxf(maximum_rate, 0.001), 0.2, 1.0)


func _estimate_slip_ball_error(delta: float, use_helicopter_tuning: bool) -> float:
	var rb := aircraft as RigidBody3D
	if rb == null:
		return 0.0
	var velocity: Vector3 = rb.linear_velocity
	var basis := rb.global_transform.basis.orthonormalized()
	var local_velocity: Vector3 = basis.inverse() * _get_control_air_velocity()
	var reference_speed := maxf(absf(local_velocity.z), 20.0)
	var velocity_slip := clampf(local_velocity.x / reference_speed, -1.0, 1.0)

	var lateral_g := 0.0
	if _has_previous_velocity and delta > 0.0001:
		var acceleration := (velocity - _previous_velocity) / delta
		var gravity_mps2 := float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.80665))
		var gravity := Vector3.DOWN * gravity_mps2
		var specific_force := acceleration - gravity
		var local_specific_force := basis.inverse() * specific_force
		lateral_g = local_specific_force.x / maxf(gravity_mps2, 0.001)
	_previous_velocity = velocity
	_has_previous_velocity = true

	var advanced_fixed_wing := not use_helicopter_tuning and _is_advanced_fixed_wing_model()
	var lateral_filter_speed := helicopter_rudder_assist_lateral_g_filter_speed if use_helicopter_tuning else rudder_assist_lateral_g_filter_speed
	var full_deflection_lateral_g := helicopter_rudder_assist_full_deflection_lateral_g if use_helicopter_tuning else rudder_assist_full_deflection_lateral_g
	var velocity_slip_weight := helicopter_rudder_assist_velocity_slip_weight if use_helicopter_tuning else rudder_assist_velocity_slip_weight
	if not use_helicopter_tuning and not advanced_fixed_wing:
		lateral_filter_speed = simplified_rudder_assist_lateral_g_filter_speed
		velocity_slip_weight = simplified_rudder_assist_velocity_slip_weight
	var lateral_filter_t := clampf(delta * maxf(lateral_filter_speed, 0.1), 0.0, 1.0)
	_filtered_lateral_g = lerpf(_filtered_lateral_g, lateral_g, lateral_filter_t)

	var force_slip := _filtered_lateral_g / maxf(full_deflection_lateral_g, 0.05)
	if use_helicopter_tuning or not advanced_fixed_wing:
		return clampf(force_slip + velocity_slip * maxf(velocity_slip_weight, 0.0), -1.0, 1.0)
	# Keep geometric sideslip as the primary signal and blend in a bounded
	# physical slip-ball term. The two measurements have opposite control signs:
	# the nose turns into geometric sideslip, while rudder opposes lateral
	# specific force. Keeping that legacy sign distinction makes the force loop
	# stabilizing negative feedback.
	# Fade the force term as surface travel/rate stiffens near Vne; delayed force
	# feedback can otherwise form a limit cycle there. Geometric correction stays.
	return _combine_fixed_wing_slip_error(
		velocity_slip,
		force_slip * _get_fixed_wing_slip_ball_scale()
	)


func _combine_fixed_wing_slip_error(velocity_slip: float, force_slip: float) -> float:
	var lateral_g_weight := _get_fixed_wing_lateral_g_weight(force_slip)
	return clampf(
		velocity_slip * maxf(rudder_assist_velocity_slip_weight, 0.0)
			- force_slip * lateral_g_weight,
		-1.0,
		1.0
	)


func _get_fixed_wing_lateral_g_weight(force_slip: float) -> float:
	var near_center_weight := maxf(rudder_assist_lateral_g_weight, 0.0)
	var large_error_weight := maxf(
		rudder_assist_large_error_lateral_g_weight,
		near_center_weight
	)
	var boost := _smoothstep(
		maxf(rudder_assist_ball_boost_start, 0.0),
		maxf(rudder_assist_ball_boost_full, rudder_assist_ball_boost_start + 0.01),
		absf(force_slip)
	)
	return lerpf(near_center_weight, large_error_weight, boost)


func _get_fixed_wing_rudder_stiffening() -> float:
	if not _simple_aero_has_control_envelope \
			or simple_aero == null \
			or not is_instance_valid(simple_aero):
		return 0.0
	var stiffening := clampf(float(simple_aero.get("current_high_speed_stiffening")), 0.0, 1.0)
	# ControlSteering can run before SimpleAero on the first physics tick. Derive
	# the same schedule from current speed so the slip-ball loop never gets one
	# unrestricted frame at high speed and leaves a slow-decaying rudder command.
	if aircraft != null \
			and is_instance_valid(aircraft) \
			and aircraft is RigidBody3D \
			and _node_has_properties(simple_aero, [
				"control_stiffening_start_speed_mps",
				"never_exceed_speed_mps",
			]):
		var start_speed := maxf(float(simple_aero.get("control_stiffening_start_speed_mps")), 0.0)
		var vne := maxf(float(simple_aero.get("never_exceed_speed_mps")), start_speed + 0.1)
		var speed := _get_control_air_velocity().length()
		stiffening = maxf(stiffening, _smoothstep(start_speed, vne, speed))
	return stiffening


func _get_control_air_velocity() -> Vector3:
	if aircraft.has_method("get_air_relative_velocity"):
		return aircraft.call("get_air_relative_velocity")
	return (aircraft as RigidBody3D).linear_velocity

func _get_fixed_wing_slip_ball_scale() -> float:
	return 1.0 - _get_fixed_wing_rudder_stiffening()


func _get_advanced_fixed_wing_rudder_assist_limit(
		assist_strength: float,
		stiffening: float) -> float:
	# FULL means full requested input. The aerodynamic model remains responsible
	# for the actual surface position/rate and its high-speed travel restriction.
	# Lower assist levels retain the conservative secondary command envelope.
	if assist_strength >= 0.99:
		return clampf(rudder_assist_full_max_input, 0.0, 1.0)
	var normal_limit := clampf(rudder_assist_max_input, 0.0, 1.0)
	return lerpf(
		normal_limit,
		clampf(rudder_assist_stiffened_max_input, 0.0, normal_limit),
		clampf(stiffening, 0.0, 1.0)
	)


func _blend_fixed_wing_manual_rudder_priority(
		manual_yaw: float,
		automatic_yaw: float,
		delta: float) -> float:
	# Reserve a fraction of the normalized command range equal to the player's
	# input magnitude. Taking authority is immediate; automatic authority returns
	# smoothly when the player releases the control. At steady state this is:
	# player + automatic * (1 - abs(player)).
	var desired_auto_authority := 1.0 - clampf(absf(manual_yaw), 0.0, 1.0)
	if desired_auto_authority <= _fixed_wing_auto_rudder_authority:
		_fixed_wing_auto_rudder_authority = desired_auto_authority
	else:
		_fixed_wing_auto_rudder_authority = move_toward(
			_fixed_wing_auto_rudder_authority,
			desired_auto_authority,
			maxf(rudder_assist_reengagement_speed, 0.1) * maxf(delta, 0.0)
		)
	return clampf(
		manual_yaw + automatic_yaw * _fixed_wing_auto_rudder_authority,
		-1.0,
		1.0
	)


func _blend_legacy_manual_rudder_override(
		manual_yaw: float,
		automatic_yaw: float,
		override_start: float,
		override_full: float) -> float:
	# Small inputs blend naturally; a deliberate input at/above override_full
	# removes the automatic command completely and gives the player authority.
	var manual_fade := 1.0 - _smoothstep(
		override_start,
		maxf(override_full, override_start + 0.01),
		absf(manual_yaw)
	)
	return clampf(manual_yaw + automatic_yaw * manual_fade, -1.0, 1.0)


func _is_advanced_fixed_wing_model() -> bool:
	if simple_aero != null and is_instance_valid(simple_aero) \
			and simple_aero.has_method("is_advanced_flight_model"):
		return bool(simple_aero.call("is_advanced_flight_model"))
	return true


func _get_rudder_assist_strength(use_helicopter_setting: bool) -> float:
	var pause_menu := get_node_or_null("/root/PauseMenu")
	if use_helicopter_setting and pause_menu != null and pause_menu.has_method("get_helicopter_rudder_assist_strength"):
		return clampf(float(pause_menu.call("get_helicopter_rudder_assist_strength")), 0.0, 1.0)
	if pause_menu != null and pause_menu.has_method("get_rudder_assist_strength"):
		return clampf(float(pause_menu.call("get_rudder_assist_strength")), 0.0, 1.0)
	return 0.0


func _reset_rudder_assist_state() -> void:
	_has_assist_error = false
	_previous_assist_error = 0.0
	_filtered_assist_error_rate = 0.0
	_rudder_integral = 0.0
	_filtered_lateral_g = 0.0
	_filtered_assist_yaw = 0.0
	_fixed_wing_auto_rudder_authority = 1.0
	_has_previous_velocity = false
	telemetry_rudder_assist_component = 0.0
	telemetry_rudder_slip_error = 0.0
	telemetry_rudder_target_assist = 0.0
	telemetry_rudder_filtered_assist = 0.0
	telemetry_rudder_assist_limit = 0.0
	telemetry_rudder_assist_stiffening = 0.0


func _smoothstep(edge0: float, edge1: float, x: float) -> float:
	var t := clampf((x - edge0) / maxf(edge1 - edge0, 0.0001), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


func _detect_helicopter_controls() -> bool:
	if simple_aero == null:
		return false
	var script := simple_aero.get_script() as Script
	if script != null and script.resource_path.ends_with("HelicopterFlight.gd"):
		return true
	return simple_aero.get_class() == "HelicopterFlight"


func _node_has_properties(n: Object, names: Array) -> bool:
	var plist := n.get_property_list()
	var have := {}
	for p in plist:
		have[p.name] = true
	for name in names:
		if not have.has(name):
			return false
	return true
