extends Node
class_name SimpleAero

const AIRFLOW_FEEDBACK_SCRIPT := preload("res://Aircraft/AirflowFeedback.gd")

@export var rb_path: NodePath
var rb: RigidBody3D = null

# Simple parameters
@export var pitch_power: float = 6.0         # Elevator strength
@export var roll_power: float = 12.0         # Aileron strength
@export var yaw_power: float = 3.0           # Rudder strength
@export var min_control_speed: float = 55.0  # (legacy) kept for compatibility; authority now scales off stall speed
@export var control_authority_full_stall_margin: float = 1.35  # Full low-speed airflow authority above this stall multiple, until high-speed stiffening begins
@export var control_authority_taper_stall_margin: float = 1.05  # Authority starts tapering below this multiple of stall speed (i.e. only right near the stall)
@export var control_authority_stall_floor: float = 0.35  # Minimum authority retained at the stall so it can still be flown out
@export var control_authority_curve: float = 1.0  # Shape of the taper between the two margins (1 = linear)
@export var control_slip_speed_blend: float = 0.55  # Arcade assist: let some total airspeed count for controls while slipping/skidding
@export var stall_control_loss_strength: float = 0.70  # Elevator authority lost at full stall/high AoA
@export var roll_stall_control_loss_strength: float = 0.90  # Ailerons become nearly ineffective in a deep departure
@export var yaw_stall_control_loss_strength: float = 0.45  # Rudder deliberately remains the strongest recovery control
@export var speed_stall_control_curve: float = 1.0  # Higher = control loss comes in less abruptly near stall speed
@export_group("Control Envelope")
@export var roll_control_stall_floor: float = 0.25  # Ailerons lose more authority than the rudder near the stall
@export var yaw_control_stall_floor: float = 0.50  # Rudder remains the most useful control in slow/departed flight
@export var control_stiffening_start_speed_mps: float = 135.0
@export var never_exceed_speed_mps: float = 180.0
@export var control_stiffening_full_speed_mps: float = 225.0
@export var pitch_control_limit_at_vne: float = 0.50
@export var roll_control_limit_at_vne: float = 0.68
@export var yaw_control_limit_at_vne: float = 0.40
@export var pitch_control_limit_full_stiffening: float = 0.25
@export var roll_control_limit_full_stiffening: float = 0.48
@export var yaw_control_limit_full_stiffening: float = 0.20
@export var pitch_surface_rate_per_s: float = 4.0
@export var roll_surface_rate_per_s: float = 6.0
@export var yaw_surface_rate_per_s: float = 3.5
@export var pitch_surface_rate_stiffened_per_s: float = 0.9
@export var roll_surface_rate_stiffened_per_s: float = 2.0
@export var yaw_surface_rate_stiffened_per_s: float = 0.7
@export_group("")
@export var ground_rudder_assist_enabled: bool = true
@export var ground_rudder_assist_power: float = 1.0
@export var ground_rudder_assist_start_speed_mps: float = 8.0
@export var ground_rudder_assist_full_speed_mps: float = 35.0
@export var ground_rudder_ground_compression_threshold_m: float = 0.02
@export var alignment_strength: float = 2.5   # High-speed horizontal sideslip damping in 1/s (mass-scaled below)
@export var alignment_low_speed_strength: float = 1.2   # Moderate low-speed horizontal alignment for tighter slip damping
@export var alignment_max_lateral_accel_mps2: float = 6.0  # Cap sideways slip-cleanup so it helps coordination without becoming a hidden thruster
@export var alignment_max_vertical_accel_mps2: float = 5.0  # Cap vertical flight-path alignment for the same reason
@export_group("Directional Stability")
@export var directional_stability_strength: float = 0.0  # Advanced-only passive weathervane moment per radian of sideslip; zero preserves existing airframes
@export var directional_stability_yaw_rate_damping: float = 0.8  # Damps the restoring yaw rate without turning this into an active rudder controller
@export var directional_stability_start_speed_mps: float = 12.0  # No useful weathercock authority without forward airflow
@export var directional_stability_full_speed_mps: float = 60.0  # Cap the response by normal flight speed instead of growing indefinitely with v^2
@export var directional_stability_max_torque_per_mass: float = 1.25  # Bounded yaw moment in torque units per kg
@export_group("")
@export var angular_damping_strength: float = 16.0  # How quickly rotations stop
@export var drag_base_multiplier: float = 0.8  # Base multiplier on combined forward+lateral drag
# Fixed-wing speed is limited by the explicit quadratic forces below, never by
# RigidBody3D's project-wide linear damping. 2.20 gives the reference
# Aircraft_5 a clean, zero-AoA full-power ceiling of about 127 m/s with the
# half-thrust baseline used by the fixed-wing fleet.
@export var forward_drag_scale: float = 2.20
@export_group("Simplified Flight Model")
@export var simplified_forward_drag_scale: float = 0.40
@export var simplified_aoa_stall_start_deg: float = 22.0
@export var simplified_aoa_stall_full_deg: float = 48.0
@export var simplified_aoa_stall_lift_loss: float = 0.42
@export var simplified_aoa_stall_control_loss: float = 0.30
@export var simplified_stall_control_loss_strength: float = 0.60
@export var simplified_stall_lift_loss: float = 0.20
@export var simplified_stall_nose_drop_force: float = 5.0
@export var simplified_stall_shake_intensity: float = 0.45
@export var simplified_pitch_power_override: float = -1.0  # Negative follows pitch_power; compatibility value can preserve an airframe's former response
@export_group("")
@export var stability_strength: float = 2.0  # How strongly it wants to return to level
@export var roll_stability_factor: float = 1.0  # Per-axis multiplier for roll self-righting
@export var pitch_stability_factor: float = 0.7  # Per-axis multiplier for pitch self-righting
@export var roll_stability_input_release: float = 0.85  # How much roll self-leveling backs off under deliberate roll input
@export var roll_stability_bank_release_start_deg: float = 55.0  # Start backing off roll self-leveling at aerobatic bank angles
@export var roll_stability_bank_release_full_deg: float = 100.0  # Roll self-leveling reaches its minimum strength here
@export var roll_stability_bank_min_factor: float = 0.18  # Keep a little roll damping so the aircraft does not tumble forever
@export var pitch_stability_input_release_start: float = 0.05  # Small corrections retain the hands-off leveling tendency
@export var pitch_stability_input_release_full: float = 0.35  # Deliberate elevator input releases pitch self-leveling for aerobatics
@export var pitch_stability_input_min_factor: float = 0.04  # Keep only a trace of stability during a committed pull/push
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
## Raised from 10 -- this, combined with aoa_lift_bonus_factor below, was the REAL ceiling on turn
## g, not max_lift_ratio (see that constant's own comment for the full history of chasing this).
## aoa_lift_scale = 1.0 + positive_alpha_t * aoa_lift_bonus_factor, and positive_alpha_t caps at
## 1.0 once AoA reaches aoa_lift_full_deg -- so lift topped out at 1.6g (1.0 base + 0.6 bonus)
## REGARDLESS of how much further AoA/pitch_input was commanded beyond 10deg, independent of
## max_lift_ratio's much higher headroom. User watched the AI pull hard and measured exactly 1.6g
## in-game, confirming this is the actual binding constraint. Set below aoa_stall_start_deg
## so full lift bonus is reached before the stall penalty starts biting, not after.
@export var aoa_lift_full_deg: float = 18.0  # Positive AoA needed to unlock the full slow-flight lift bonus
## Raised from 0.6 -- see aoa_lift_full_deg's comment. At full AoA this now gives ~1.0+2.4=3.4g,
## leaving max_lift_ratio (4.5g) as a real, higher ceiling instead of this factor binding first.
@export var aoa_lift_bonus_factor: float = 2.4  # Extra lift multiplier from positive AoA in slow flight
@export var aoa_negative_lift_penalty_factor: float = 0.35  # Reduce lift when the nose sits below the flight path
## Raised from 1.35 to give real headroom above the aoa_lift_bonus_factor ceiling above (~3.4g), so
## a fully-committed hard pull isn't double-capped by two independent mechanisms.
@export var max_lift_ratio: float = 4.5  # Prevent extreme pitch-up from generating unrealistic excess lift
@export var aoa_stall_start_deg: float = 20.0  # Buffet/lift loss begins before the deep-departure gate
@export var aoa_stall_full_deg: float = 38.0   # Full high-AoA loss arrives early enough to produce a decisive break
@export var aoa_stall_lift_loss: float = 0.65  # Deep high-AoA stall retains only 35% of commanded lift
@export var aoa_stall_control_loss: float = 1.0  # Per-axis loss strengths below determine retained recovery authority
@export var aoa_stall_drag_strength: float = 0.14  # Extra drag from high AoA; applied along the airflow vector
@export var induced_drag_strength: float = 0.20   # Energy bleed from maneuvering (induced drag ~ load_factor^2); higher = harder to sustain hard turns/climbs. Raised from 0.09: at 0.09 full-throttle thrust cancelled it and specific energy stayed FLAT through a dogfight (planes turned for free), so nobody ever fell behind and rounds stalemated. Must exceed thrust in a hard turn.
@export var induced_drag_turn_rate_scale: float = 1.2  # Modest fallback when body-rate changes precede measured aerodynamic load
@export var induced_drag_pull_scale: float = 0.35  # Small control-effort fallback; actual lift ratio is the primary load factor

# Keep a tiny support near knife-edge (optional safety net)
@export var min_vertical_lift_frac: float = 0.0

# Simplified stall parameters
@export_group("Stall Departure")
@export var stall_nose_drop_torque: float = 10.0  # Local pitch-down torque per unit mass at full departure
@export var stall_wing_drop_torque: float = 4.5  # Persistent asymmetric roll moment per unit mass
@export var stall_autorotation_yaw_torque: float = 5.0  # Deep-stall yaw coupling that allows a real spin to develop
@export var stall_departure_entry_severity: float = 0.22
@export var stall_departure_full_severity: float = 0.85
@export var stall_departure_exit_severity: float = 0.10
@export var stall_departure_build_rate_per_s: float = 3.0
@export var stall_departure_recovery_rate_per_s: float = 2.0
@export var deep_stall_control_loss_start: float = 0.12  # Begin making inputs mushy once a real departure is developing
@export var deep_stall_control_loss_full: float = 0.50  # Recorded player stalls around this severity should have fully separated controls
@export var deep_stall_pitch_authority_cap: float = 0.12
@export var deep_stall_roll_authority_cap: float = 0.05
@export var deep_stall_yaw_authority_cap: float = 0.20  # Rudder remains the strongest surface, but cannot fly the aircraft out by itself
@export var stall_alignment_min_factor: float = 0.12
@export var stall_stability_min_factor: float = 0.05
@export var stall_pitch_damping_min_factor: float = 0.35
@export var stall_roll_damping_min_factor: float = 0.15
@export var stall_yaw_damping_min_factor: float = 0.25
@export var stall_lift_loss: float = 0.45  # Deep speed stall retains 55% of commanded lift
@export var stall_shake_intensity: float = 0.65  # Physical buffet; player-facing feedback is handled separately by AirflowFeedback
@export var deep_stall_body_drag_strength: float = 7.0  # Bluff-body drag used after induced drag stops treating tumbling as useful wing load
@export_group("")

@export_group("Airflow Feedback")
@export var airflow_feedback_enabled: bool = true
@export var airflow_feedback_only_player: bool = true
@export_group("")

# Drag tuning
@export var forward_drag_strength: float = 0.22
@export var lateral_drag_strength: float = 1.2
@export var gear_drag_multiplier: float = 1.5
@export var flaps_drag_multiplier: float = 1.4   # When flaps deployed (approach config: gear+flaps together)
@export var flaps_stall_speed_factor: float = 0.78  # Stall speed multiplier when flaps deployed (0.78 = 22% lower -> slower approach)
@export var flaps_lift_bonus: float = 0.25       # Extra lift ratio when flaps deployed (more lift per speed -> slower, higher-AoA approach)

# Low-rate fixed-wing flight recorder. This intentionally lives in SimpleAero so
# it records what the aircraft physics model actually sees/applies, not just what
# a pilot/AI intended to command.
@export_group("Aero Report")
@export var aero_report_enabled: bool = true
@export var aero_report_interval_s: float = 0.10  # 10 Hz catches short control and departure anomalies without frame-sized logs
@export var aero_report_flush_interval_s: float = 1.0  # Batch disk writes so the recorder does not create the hitch it is measuring
@export var aero_report_max_buffered_rows: int = 30
@export var aero_report_mark_action: StringName = &"flight_log_mark"
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
var actual_pitch_control: float = 0.0
var actual_roll_control: float = 0.0
var actual_yaw_control: float = 0.0
var current_pitch_authority: float = 0.0
var current_roll_authority: float = 0.0
var current_yaw_authority: float = 0.0
var current_high_speed_stiffening: float = 0.0
var current_control_stress: float = 0.0
var current_sideslip_ratio: float = 0.0
var current_directional_sideslip_deg: float = 0.0
var current_directional_stability_torque_nm: float = 0.0
var current_departure_severity: float = 0.0
var current_stall_drop_direction: float = 0.0
var current_departure_drag_n: float = 0.0
# Runtime contributions from the localized structural-damage model. These are
# kept separate from authored aero tuning so a lost wing can drive measured
# drag/buffet feedback without permanently rewriting the aircraft profile.
var structural_damage_drag_accel_mps2: float = 0.0
var structural_damage_buffet_intensity: float = 0.0

var _flight_model_override: int = -1  # Tests only: -1 follows Gameplay, 0 simplified, 1 advanced
var _simplified_linear_damp_mode: RigidBody3D.DampMode = RigidBody3D.DAMP_MODE_COMBINE
var _simplified_linear_damp: float = 0.0
var _body_uses_advanced_damping := false

@onready var _landing_gear_node: Node = null
@onready var _gear_controller: Node = null
@onready var _flaps_module: Node = null
var _engine_modules: Array = []
var _airflow_feedback: Node = null
var _aero_report_timer_s: float = 0.0
var _aero_report_flush_timer_s: float = 0.0
var _aero_report_prepared: bool = false
var _aero_report_pending_lines: Array[String] = []
var _aero_report_previous_velocity: Vector3 = Vector3.ZERO
var _aero_report_has_previous_velocity: bool = false
var _aero_report_motion_valid: bool = false
var _aero_report_local_acceleration: Vector3 = Vector3.ZERO
var _aero_report_local_specific_g: Vector3 = Vector3.ZERO
var _aero_report_speed_rate_mps2: float = 0.0
var _aero_report_energy_rate_mps: float = 0.0
var _aero_report_mark_action_was_pressed: bool = false
var _aero_report_pending_mark: String = ""
var _control_steering_node: Node = null
var _stall_departure_active: bool = false
var _stall_departure_bias: float = 1.0
var _stall_entry_count: int = 0

static var _aero_report_reset_done: bool = false
static var _aero_report_session_id: String = ""
static var _aero_report_session_start_ticks_msec: int = 0
static var _aero_report_mark_counter: int = 0

func _ready() -> void:
	rb = get_parent() as RigidBody3D
	if rb:
		rb.gravity_scale = 1.0
		_simplified_linear_damp_mode = rb.linear_damp_mode
		_simplified_linear_damp = rb.linear_damp
		_apply_flight_model_body_damping(is_advanced_flight_model())
		_landing_gear_node = rb.get_node_or_null("LandingGear")
		_gear_controller = rb.get_node_or_null("ControlLandingGear")
		_control_steering_node = rb.get_node_or_null("ControlSteering")
		# Flaps: find AircraftModule_Flaps (gear+flaps deployed together on approach)
		if rb.has_method("find_modules_by_type"):
			var found = rb.find_modules_by_type("flaps")
			if not found.is_empty():
				_flaps_module = found[0]
			_engine_modules = rb.find_modules_by_type("engine")
	_setup_airflow_feedback()


func _exit_tree() -> void:
	_flush_aero_report_lines()

func _physics_process(delta: float) -> void:
	if rb == null:
		return
	var advanced_flight_model := is_advanced_flight_model()
	_apply_flight_model_body_damping(advanced_flight_model)

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
	var alignment_force: Vector3 = Vector3.ZERO
	var lift_force: Vector3 = Vector3.ZERO
	var departure_drag_force: Vector3 = Vector3.ZERO
	var lateral_drag_feedback_n: float = 0.0
	var high_aoa_drag_feedback_n: float = 0.0
	var induced_drag_feedback_n: float = 0.0
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
		var active_forward_drag_scale := forward_drag_scale if advanced_flight_model else simplified_forward_drag_scale
		forward_drag_force = -fwd * forward_drag_strength * active_forward_drag_scale * signed_forward_speed * absf(signed_forward_speed)
		# Lateral (velocity minus forward component)
		var lat_dir: Vector3 = (-lateral_vel / lateral_speed) if lateral_speed > 0.001 else Vector3.ZERO
		lateral_drag_force = lat_dir * lateral_drag_strength * lateral_speed * lateral_speed
		# Combine and scale (gear+flaps multiply drag when deployed)
		total_drag_force = (forward_drag_force + lateral_drag_force) * drag_base_multiplier * approach_mult
		lateral_drag_feedback_n = lateral_drag_force.length() * drag_base_multiplier * approach_mult
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
	aoa_stall_severity = _get_aoa_stall_severity_for_model(alpha_deg, advanced_flight_model)
	var positive_alpha_t: float = clampf(alpha_deg / maxf(aoa_lift_full_deg, 0.1), 0.0, 1.0)
	var negative_alpha_t: float = clampf(-alpha_deg / maxf(aoa_lift_full_deg, 0.1), 0.0, 1.0)
	var aoa_lift_scale: float = 1.0 + positive_alpha_t * aoa_lift_bonus_factor - negative_alpha_t * aoa_negative_lift_penalty_factor
	# Flaps: extra lift coefficient when deployed -> more lift at a given speed, so the aircraft can fly a
	# slower approach at higher AoA. Raise the lift ceiling too so the bonus isn't immediately clamped.
	var flap_lift_scale: float = (1.0 + flaps_lift_bonus) if _is_flaps_deployed() else 1.0
	var lift_ceiling: float = maxf(max_lift_ratio, 0.1) * flap_lift_scale
	commanded_lift_ratio = clampf(
		zero_aoa_lift_ratio * maxf(aoa_lift_scale, 0.0) * flap_lift_scale,
		0.0,
		lift_ceiling
	)
	var gravity_mag: float = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	var base_lift_mag: float = rb.mass * gravity_mag * maxf(rb.gravity_scale, 0.0) * commanded_lift_ratio

	# Calculate stall effects
	var speed_stall_severity: float = 0.0
	if forward_speed < effective_stall_speed and speed > 5.0:
		speed_stall_severity = 1.0 - (forward_speed / effective_stall_speed)
	var stall_severity: float = maxf(speed_stall_severity, aoa_stall_severity)
	var airborne_for_stall_effects: bool = _is_airborne_for_stall_effects()
	var feedback_stall_severity: float = stall_severity if airborne_for_stall_effects else 0.0
	current_stall_severity = feedback_stall_severity
	if advanced_flight_model:
		_update_stall_departure(
			delta,
			feedback_stall_severity,
			local_vel,
			speed
		)
	else:
		_reset_stall_departure_state()
	var active_aoa_stall_control_loss := aoa_stall_control_loss \
		if advanced_flight_model else simplified_aoa_stall_control_loss
	var stall_control_loss: float = maxf(
		pow(speed_stall_severity, maxf(speed_stall_control_curve, 0.01)),
		aoa_stall_severity * active_aoa_stall_control_loss
	)
	if advanced_flight_model:
		var deep_stall_control_loss := get_deep_stall_control_loss(
			feedback_stall_severity,
			current_departure_severity
		)
		# Advanced controls combine the low-speed airflow envelope with surface
		# travel/rate limits under high dynamic pressure.
		var control_speed := get_control_airflow_speed(
			forward_speed,
			speed,
			deep_stall_control_loss
		)
		_update_control_envelope(
			delta,
			control_speed,
			speed,
			effective_stall_speed,
			stall_control_loss,
			local_vel,
			deep_stall_control_loss
		)
	else:
		# The simplified model retains the former direct-input response: one
		# authority value, no surface lag, and no high-speed stiffening.
		var control_speed := lerpf(
			forward_speed,
			speed,
			clampf(control_slip_speed_blend, 0.0, 1.0)
		)
		var simplified_authority := get_simplified_control_authority(
			control_speed,
			effective_stall_speed,
			stall_control_loss
		)
		current_pitch_authority = simplified_authority
		current_roll_authority = simplified_authority
		current_yaw_authority = simplified_authority
		current_high_speed_stiffening = 0.0
		current_control_stress = 0.0
		current_sideslip_ratio = absf(local_vel.x) / maxf(speed, 1.0)
		actual_pitch_control = pitch_input
		actual_roll_control = roll_input
		actual_yaw_control = clampf(yaw_input + roll_input * auto_rudder_strength, -1.0, 1.0)
	# Retain the legacy single value for damping, stability, existing telemetry,
	# and callers that have not yet adopted the per-axis values.
	control_authority = current_pitch_authority

	if airborne_for_stall_effects and aoa_stall_severity > 0.0 and speed > 5.0:
		var high_aoa_drag_force: Vector3 = -v_dir * aoa_stall_drag_strength * aoa_stall_severity * speed * speed
		high_aoa_drag_feedback_n = high_aoa_drag_force.length()
		rb.apply_central_force(high_aoa_drag_force)
		total_drag_force += high_aoa_drag_force
		
	# Reduce lift in stall
	var active_stall_lift_loss := stall_lift_loss if advanced_flight_model else simplified_stall_lift_loss
	var active_aoa_stall_lift_loss := aoa_stall_lift_loss if advanced_flight_model else simplified_aoa_stall_lift_loss
	var speed_lift_loss: float = active_stall_lift_loss * speed_stall_severity
	var aoa_lift_loss: float = active_aoa_stall_lift_loss * aoa_stall_severity
	var actual_lift_mag: float = base_lift_mag * (1.0 - clampf(maxf(speed_lift_loss, aoa_lift_loss), 0.0, 0.95))
	lift_force = lift_dir * actual_lift_mag
	actual_lift_ratio = actual_lift_mag / maxf(rb.mass * gravity_mag * maxf(rb.gravity_scale, 0.0), 0.001)

	# Optional: tiny vertical safety net near knife-edge
	var bank_vertical: float = abs(up.dot(Vector3.UP))
	if bank_vertical < 0.2 and min_vertical_lift_frac > 0.0:
		lift_force += Vector3.UP * (base_lift_mag * min_vertical_lift_frac * (0.2 - bank_vertical) * 5.0)

	# Apply lift at center of mass
	rb.apply_central_force(lift_force)

	# --- Induced drag (energy bleed from maneuvering / pulling G) ---
	# In this arcade model the velocity vector tracks the nose, so angle of attack stays near zero
	# even in a hard turn -- an AoA-based induced drag never fires and the aircraft can turn/climb for
	# free (it was ending up higher and higher). Instead model the energy cost of MANEUVERING directly
	# from the load factor: how hard the aircraft is turning its velocity vector plus how hard it's
	# being commanded to pull. A high turn rate (tight turn or a hard pull-up) generates a lot of lift,
	# which costs induced drag ~ (load factor)^2. This is what forces honest energy management.
	if airborne_for_stall_effects and speed > 8.0:
		# Turn rate of the velocity vector: |a_perp| / v, where a_perp is the change in velocity
		# direction. Approximate via angular velocity magnitude perpendicular to the flight path.
		var body_right: Vector3 = right
		var body_up: Vector3 = up
		var pitch_rate: float = absf(rb.angular_velocity.dot(body_right))   # pull/push rate
		var yaw_rate: float = absf(rb.angular_velocity.dot(body_up))        # flat-turn rate
		var maneuver_rate: float = sqrt(pitch_rate * pitch_rate + yaw_rate * yaw_rate)
		# Small transient proxy lets drag begin as the maneuver develops, before lift fully responds.
		var pull_effort: float = absf(actual_pitch_control) * current_pitch_authority
		# Actual wing load is authoritative. The old formula ADDED large body-rate and raw-control
		# terms, then squared them, so even a measured ~1g turn could be charged as a 3-5g maneuver
		# and lose tens of m/s in seconds. Use the transient proxy only when it exceeds measured load.
		# In a deep advanced-model departure, body rotation is no longer evidence
		# of useful wing load. The old proxy interpreted a tumble as a 3g turn and
		# applied enough upward drag to create a 10 m/s parachute descent.
		var rate_proxy_factor := get_induced_drag_rate_proxy_factor(
			advanced_flight_model,
			current_departure_severity
		)
		var transient_load_proxy: float = 1.0 \
			+ (maneuver_rate * induced_drag_turn_rate_scale \
			+ pull_effort * induced_drag_pull_scale) * rate_proxy_factor
		var load_factor: float = maxf(maxf(actual_lift_ratio, 1.0), transient_load_proxy)
		var induced_mag: float = induced_drag_strength * (load_factor * load_factor - 1.0) * rb.mass * gravity_mag
		# Scale mildly with dynamic pressure so it's bounded and doesn't explode at high speed. Floor kept
		# high (0.7) so a SLOW hard turn -- the low-speed scissors where a plane should bleed energy fastest
		# -- still costs; otherwise low-speed turning was nearly free and fed the stalemate.
		induced_mag *= clampf(speed / 90.0, 0.7, 1.7)
		if induced_mag > 0.0:
			induced_drag_feedback_n = induced_mag
			rb.apply_central_force(-v_dir * induced_mag)
			total_drag_force += -v_dir * induced_mag

	# Once the advanced wing is fully separated, use a bounded bluff-body term
	# instead of induced drag. At the default coefficient a 1300 kg aircraft
	# settles around 40-45 m/s vertically, rather than the recorded 10-11 m/s.
	current_departure_drag_n = 0.0
	if advanced_flight_model and airborne_for_stall_effects \
			and current_departure_severity > 0.0 and speed > 5.0:
		var departure_drag_mag := get_deep_stall_body_drag_magnitude(
			speed,
			current_departure_severity
		)
		departure_drag_force = -v_dir * departure_drag_mag
		current_departure_drag_n = departure_drag_mag
		rb.apply_central_force(departure_drag_force)
		total_drag_force += departure_drag_force

	# Deep departure: remove the old world-down nose force and apply moments in
	# aircraft axes. The persistent drop direction is chosen once on stall entry,
	# then sideslip can reinforce or oppose it without random per-frame jitter.
	if advanced_flight_model and airborne_for_stall_effects and current_departure_severity > 0.0 and speed > 5.0:
		var pitch_recovery_sign := 1.0 if alpha_deg >= 0.0 else -1.0
		var departure_squared := current_departure_severity * current_departure_severity
		var nose_drop_torque := right \
			* pitch_recovery_sign \
			* stall_nose_drop_torque \
			* current_departure_severity \
			* rb.mass
		var wing_drop_torque := fwd \
			* current_stall_drop_direction \
			* stall_wing_drop_torque \
			* current_departure_severity \
			* rb.mass
		var autorotation_torque := up \
			* current_stall_drop_direction \
			* stall_autorotation_yaw_torque \
			* departure_squared \
			* rb.mass
		rb.apply_torque(nose_drop_torque + wing_drop_torque + autorotation_torque)
	elif not advanced_flight_model and airborne_for_stall_effects and stall_severity > 0.1 and speed > 5.0:
		var nose_position := fwd * 2.0
		var nose_down_force := Vector3.DOWN \
			* simplified_stall_nose_drop_force \
			* stall_severity \
			* rb.mass
		rb.apply_force(nose_down_force, nose_position)
		
	# Add stall shake
	if airborne_for_stall_effects and stall_severity > 0.1:
		var active_stall_shake := stall_shake_intensity \
			if advanced_flight_model else simplified_stall_shake_intensity
		var shake_intensity = active_stall_shake * stall_severity
		rb.add_shake(shake_intensity)

	_update_airflow_feedback(
		delta,
		alpha_deg,
		maxf(feedback_stall_severity, structural_damage_buffet_intensity),
		speed,
		forward_speed,
		lateral_speed,
		effective_stall_speed,
		current_control_stress if advanced_flight_model else 0.0,
		advanced_flight_model,
		airborne_for_stall_effects,
		get_dirty_airflow_drag_accel_mps2(
			lateral_drag_feedback_n,
			high_aoa_drag_feedback_n,
			induced_drag_feedback_n,
			current_departure_drag_n,
			rb.mass
		) + maxf(structural_damage_drag_accel_mps2, 0.0)
	)
	
	# --- Flight controls ---
	if maxf(current_pitch_authority, maxf(current_roll_authority, current_yaw_authority)) > 0.0:
		var active_pitch_power := get_effective_pitch_power()
		var pitch_torque: float = actual_pitch_control * active_pitch_power * current_pitch_authority * rb.mass
		var roll_torque: float = actual_roll_control * roll_power * current_roll_authority * rb.mass
		var yaw_torque: float = actual_yaw_control * yaw_power * current_yaw_authority * rb.mass
		rb.apply_torque(-right * pitch_torque)
		rb.apply_torque(-fwd * roll_torque)
		rb.apply_torque(up * yaw_torque)
	# Passive directional stability is an aerodynamic weathervane moment, not a
	# hidden rudder command. Unlike the central alignment force below, it rotates
	# the nose toward the relative wind. Its bounded speed schedule prevents the
	# moment from growing without limit at high speed, while yaw-rate damping and
	# departure fade avoid a new limit cycle or fighting deliberate stall spins.
	current_directional_sideslip_deg = 0.0
	current_directional_stability_torque_nm = 0.0
	var directional_airborne := speed > 5.0 and not _has_grounded_gear()
	# Keep the signed-angle telemetry useful for every airframe, including the
	# zero-strength fleet baseline used in comparisons.
	if directional_airborne:
		current_directional_sideslip_deg = rad_to_deg(get_signed_sideslip_angle_rad(local_vel))
	if advanced_flight_model and directional_stability_strength > 0.0 and directional_airborne:
		var local_yaw_rate := rb.angular_velocity.dot(up)
		var directional_torque_per_mass := get_directional_stability_torque_per_mass(
			local_vel,
			local_yaw_rate,
			current_departure_severity
		)
		current_directional_stability_torque_nm = directional_torque_per_mass * rb.mass
		rb.apply_torque(up * current_directional_stability_torque_nm)
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
		var stall_alignment_factor := lerpf(
			1.0,
			clampf(stall_alignment_min_factor, 0.0, 1.0),
			current_departure_severity
		) if advanced_flight_model else 1.0
		horizontal_alignment_strength *= stall_alignment_factor
		vertical_alignment_strength *= stall_alignment_factor
		var slip_velocity_local := Vector3(
			local_vel.x * horizontal_alignment_strength,
			local_vel.y * vertical_alignment_strength,
			0.0
		)
		# Scale by mass so the response time is consistent across aircraft weights.
		var alignment_accel_local: Vector3 = -slip_velocity_local
		if alignment_max_lateral_accel_mps2 > 0.0:
			alignment_accel_local.x = clampf(
				alignment_accel_local.x,
				-alignment_max_lateral_accel_mps2,
				alignment_max_lateral_accel_mps2
			)
		if alignment_max_vertical_accel_mps2 > 0.0:
			alignment_accel_local.y = clampf(
				alignment_accel_local.y,
				-alignment_max_vertical_accel_mps2,
				alignment_max_vertical_accel_mps2
			)
		alignment_force = rb.global_transform.basis * (alignment_accel_local * rb.mass)
		rb.apply_central_force(alignment_force)

	# --- Angular damping ---
	# The normal scalar damping is preserved outside a stall. During a departure,
	# reduce it per axis so roll/yaw autorotation can develop while pitch remains
	# damped enough for a readable recovery.
	var damping_factor: float = max(control_authority, 0.3)  # Minimum 30% damping
	var angular_damping := Vector3.ZERO
	if advanced_flight_model:
		var local_angular_velocity := rb.global_transform.basis.inverse() * rb.angular_velocity
		var pitch_damping_factor := lerpf(1.0, clampf(stall_pitch_damping_min_factor, 0.0, 1.0), current_departure_severity)
		var yaw_damping_factor := lerpf(1.0, clampf(stall_yaw_damping_min_factor, 0.0, 1.0), current_departure_severity)
		var roll_damping_factor := lerpf(1.0, clampf(stall_roll_damping_min_factor, 0.0, 1.0), current_departure_severity)
		var local_angular_damping := Vector3(
			-local_angular_velocity.x * pitch_damping_factor,
			-local_angular_velocity.y * yaw_damping_factor,
			-local_angular_velocity.z * roll_damping_factor
		) * angular_damping_strength * rb.mass * damping_factor
		angular_damping = rb.global_transform.basis * local_angular_damping
	else:
		angular_damping = rb.angular_velocity * -angular_damping_strength * rb.mass * damping_factor
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
		departure_drag_force,
		alignment_force,
		lift_force
	)


func get_effective_pitch_power() -> float:
	if not is_advanced_flight_model() and simplified_pitch_power_override >= 0.0:
		return simplified_pitch_power_override
	return pitch_power


func _smoothstep(edge0: float, edge1: float, x: float) -> float:
	if is_equal_approx(edge0, edge1):
		return 1.0 if x >= edge1 else 0.0
	var t: float = clampf((x - edge0) / (edge1 - edge0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


func is_advanced_flight_model() -> bool:
	if _flight_model_override >= 0:
		return _flight_model_override == 1
	var pause_menu := get_node_or_null("/root/PauseMenu")
	if pause_menu != null and pause_menu.has_method("is_advanced_flight_model"):
		return bool(pause_menu.call("is_advanced_flight_model"))
	# Advanced is the authored/default model for scenes and isolated tests.
	return true


func set_flight_model_override_for_testing(mode: int) -> void:
	_flight_model_override = clampi(mode, -1, 1)
	if rb != null:
		_apply_flight_model_body_damping(is_advanced_flight_model())


func _apply_flight_model_body_damping(advanced: bool) -> void:
	if rb == null or advanced == _body_uses_advanced_damping:
		return
	if advanced:
		# Advanced uses only authored aerodynamic drag. Project-default linear
		# damping was the hidden energy sink that suppressed dive acceleration.
		rb.linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
		rb.linear_damp = 0.0
	else:
		rb.linear_damp_mode = _simplified_linear_damp_mode
		rb.linear_damp = _simplified_linear_damp
	_body_uses_advanced_damping = advanced


func _reset_stall_departure_state() -> void:
	_stall_departure_active = false
	current_departure_severity = 0.0
	current_stall_drop_direction = 0.0


func get_simplified_control_authority(
		control_speed_mps: float,
		effective_stall_speed_mps: float,
		stall_control_loss: float
) -> float:
	var effective_stall := maxf(effective_stall_speed_mps, 1.0)
	var full_speed := effective_stall * maxf(control_authority_full_stall_margin, 1.05)
	var taper_speed := effective_stall * clampf(
		control_authority_taper_stall_margin,
		1.0,
		control_authority_full_stall_margin - 0.01
	)
	var authority_t := clampf(
		(control_speed_mps - taper_speed) / maxf(full_speed - taper_speed, 0.1),
		0.0,
		1.0
	)
	var authority := lerpf(
		clampf(control_authority_stall_floor, 0.0, 1.0),
		1.0,
		pow(authority_t, maxf(control_authority_curve, 0.1))
	)
	return authority * (
		1.0 - clampf(simplified_stall_control_loss_strength, 0.0, 1.0)
		* clampf(stall_control_loss, 0.0, 1.0)
	)


func get_induced_drag_rate_proxy_factor(advanced: bool, departure_severity: float) -> float:
	return 1.0 - clampf(departure_severity, 0.0, 1.0) if advanced else 1.0


func get_dirty_airflow_drag_accel_mps2(
		lateral_drag_n: float,
		high_aoa_drag_n: float,
		induced_drag_n: float,
		departure_drag_n: float,
		mass_kg: float
) -> float:
	# This deliberately excludes ordinary nose-aligned parasite drag. Clean speed
	# has its own wind layer; this signal is the energy cost of flying sideways,
	# pulling load, separating the wing, or entering a developed departure.
	var dirty_drag_n := maxf(lateral_drag_n, 0.0) \
		+ maxf(high_aoa_drag_n, 0.0) \
		+ maxf(induced_drag_n, 0.0) \
		+ maxf(departure_drag_n, 0.0)
	return dirty_drag_n / maxf(mass_kg, 1.0)


func get_deep_stall_body_drag_magnitude(speed_mps: float, departure_severity: float) -> float:
	var departure_t := clampf(departure_severity, 0.0, 1.0)
	return maxf(deep_stall_body_drag_strength, 0.0) \
		* departure_t * departure_t \
		* maxf(speed_mps, 0.0) * maxf(speed_mps, 0.0)


func _update_stall_departure(
		delta: float,
		raw_stall_severity: float,
		local_velocity: Vector3,
		total_speed_mps: float
) -> void:
	var entry := clampf(stall_departure_entry_severity, 0.0, 1.0)
	var exit := clampf(stall_departure_exit_severity, 0.0, entry)
	if not _stall_departure_active and raw_stall_severity >= entry:
		_stall_departure_active = true
		_stall_entry_count += 1
		var entry_slip_ratio := local_velocity.x / maxf(total_speed_mps, 1.0)
		if absf(entry_slip_ratio) > 0.008:
			_stall_departure_bias = signf(entry_slip_ratio)
		else:
			var name_length := rb.name.length() if rb != null else 0
			_stall_departure_bias = -1.0 if (name_length + _stall_entry_count) % 2 == 0 else 1.0
	elif _stall_departure_active and raw_stall_severity <= exit:
		_stall_departure_active = false

	var target_departure := get_stall_departure_target(
		raw_stall_severity,
		_stall_departure_active
	)
	var response_rate := stall_departure_build_rate_per_s \
		if target_departure > current_departure_severity \
		else stall_departure_recovery_rate_per_s
	current_departure_severity = move_toward(
		current_departure_severity,
		target_departure,
		maxf(response_rate, 0.0) * maxf(delta, 0.0)
	)

	if current_departure_severity <= 0.001:
		current_stall_drop_direction = 0.0
		return
	var normalized_slip := clampf(
		local_velocity.x / maxf(total_speed_mps * 0.12, 1.0),
		-1.0,
		1.0
	)
	var slip_along_bias := normalized_slip * _stall_departure_bias
	var drop_magnitude := clampf(0.65 + slip_along_bias * 0.35, 0.25, 1.0)
	current_stall_drop_direction = _stall_departure_bias * drop_magnitude


func get_stall_departure_target(raw_stall_severity: float, departure_active: bool) -> float:
	if not departure_active:
		return 0.0
	var exit := clampf(
		stall_departure_exit_severity,
		0.0,
		clampf(stall_departure_entry_severity, 0.0, 1.0)
	)
	var full := maxf(stall_departure_full_severity, exit + 0.01)
	return _smoothstep(exit, full, raw_stall_severity)


func get_deep_stall_control_loss(stall_severity: float, departure_severity: float) -> float:
	var combined_severity := maxf(
		clampf(stall_severity, 0.0, 1.0),
		clampf(departure_severity, 0.0, 1.0)
	)
	return _smoothstep(
		clampf(deep_stall_control_loss_start, 0.0, 1.0),
		maxf(deep_stall_control_loss_full, deep_stall_control_loss_start + 0.01),
		combined_severity
	)


func get_control_airflow_speed(
	forward_speed_mps: float,
	total_speed_mps: float,
	deep_stall_control_loss: float
) -> float:
	var effective_slip_blend := clampf(control_slip_speed_blend, 0.0, 1.0) \
		* (1.0 - clampf(deep_stall_control_loss, 0.0, 1.0))
	return lerpf(forward_speed_mps, total_speed_mps, effective_slip_blend)


func _update_control_envelope(
		delta: float,
		control_speed_mps: float,
		total_speed_mps: float,
	effective_stall_speed_mps: float,
	stall_control_loss: float,
	local_velocity: Vector3,
	deep_stall_control_loss: float = 0.0
) -> void:
	var clamped_stall_loss := clampf(stall_control_loss, 0.0, 1.0)
	var pitch_stall_multiplier := 1.0 \
		- clampf(stall_control_loss_strength, 0.0, 1.0) * clamped_stall_loss
	var roll_stall_multiplier := 1.0 \
		- clampf(roll_stall_control_loss_strength, 0.0, 1.0) * clamped_stall_loss
	var yaw_stall_multiplier := 1.0 \
		- clampf(yaw_stall_control_loss_strength, 0.0, 1.0) * clamped_stall_loss
	current_pitch_authority = _get_low_speed_axis_authority(
		control_speed_mps,
		effective_stall_speed_mps,
		&"pitch"
	) * pitch_stall_multiplier
	current_roll_authority = _get_low_speed_axis_authority(
		control_speed_mps,
		effective_stall_speed_mps,
		&"roll"
	) * roll_stall_multiplier
	current_yaw_authority = _get_low_speed_axis_authority(
		control_speed_mps,
		effective_stall_speed_mps,
		&"yaw"
	) * yaw_stall_multiplier
	var departure_control_t := clampf(deep_stall_control_loss, 0.0, 1.0)
	current_pitch_authority = minf(
		current_pitch_authority,
		lerpf(1.0, clampf(deep_stall_pitch_authority_cap, 0.0, 1.0), departure_control_t)
	)
	current_roll_authority = minf(
		current_roll_authority,
		lerpf(1.0, clampf(deep_stall_roll_authority_cap, 0.0, 1.0), departure_control_t)
	)
	current_yaw_authority = minf(
		current_yaw_authority,
		lerpf(1.0, clampf(deep_stall_yaw_authority_cap, 0.0, 1.0), departure_control_t)
	)

	var rate_stiffening := _smoothstep(
		control_stiffening_start_speed_mps,
		maxf(never_exceed_speed_mps, control_stiffening_start_speed_mps + 0.1),
		total_speed_mps
	)
	current_high_speed_stiffening = rate_stiffening
	var pitch_limit := get_high_speed_control_limit(total_speed_mps, &"pitch")
	var roll_limit := get_high_speed_control_limit(total_speed_mps, &"roll")
	var yaw_limit := get_high_speed_control_limit(total_speed_mps, &"yaw")
	actual_pitch_control = _advance_control_surface(
		actual_pitch_control,
		pitch_input,
		pitch_limit,
		pitch_surface_rate_per_s,
		pitch_surface_rate_stiffened_per_s,
		rate_stiffening,
		delta
	)
	actual_roll_control = _advance_control_surface(
		actual_roll_control,
		roll_input,
		roll_limit,
		roll_surface_rate_per_s,
		roll_surface_rate_stiffened_per_s,
		rate_stiffening,
		delta
	)
	# Automatic coordination follows the aileron's physical position, not the raw
	# stick command. This removes the phase mismatch that previously reversed the
	# rudder while a rate-limited aileron was still travelling the other way.
	var coordinated_yaw_command := clampf(
		yaw_input + actual_roll_control * auto_rudder_strength,
		-1.0,
		1.0
	)
	actual_yaw_control = _advance_control_surface(
		actual_yaw_control,
		coordinated_yaw_command,
		yaw_limit,
		yaw_surface_rate_per_s,
		yaw_surface_rate_stiffened_per_s,
		rate_stiffening,
		delta
	)

	current_sideslip_ratio = absf(local_velocity.x) / maxf(total_speed_mps, 1.0)
	current_control_stress = get_control_stress_for_state(
		total_speed_mps,
		current_sideslip_ratio,
		pitch_input,
		roll_input,
		coordinated_yaw_command
	)


func _advance_control_surface(
		current_position: float,
		command: float,
		position_limit: float,
		normal_rate_per_s: float,
		stiffened_rate_per_s: float,
		stiffening: float,
		delta: float
) -> float:
	var safe_limit := clampf(position_limit, 0.0, 1.0)
	var desired_position := clampf(command, -1.0, 1.0) * safe_limit
	var movement_rate := lerpf(
		maxf(normal_rate_per_s, 0.0),
		maxf(stiffened_rate_per_s, 0.0),
		clampf(stiffening, 0.0, 1.0)
	)
	return move_toward(current_position, desired_position, movement_rate * maxf(delta, 0.0))


func get_signed_sideslip_angle_rad(local_velocity: Vector3) -> float:
	if local_velocity.z <= 0.1:
		return 0.0
	return atan2(local_velocity.x, local_velocity.z)


func get_directional_stability_torque_per_mass(
		local_velocity: Vector3,
		local_yaw_rate: float,
		departure_severity: float = 0.0
) -> float:
	var strength := maxf(directional_stability_strength, 0.0)
	var max_torque_per_mass := maxf(directional_stability_max_torque_per_mass, 0.0)
	if strength <= 0.0 or max_torque_per_mass <= 0.0 or local_velocity.z <= 0.1:
		return 0.0
	var beta := get_signed_sideslip_angle_rad(local_velocity)
	# In this +Z-forward convention, positive local X airflow requires a
	# positive yaw moment: rotating +Z toward +X points the nose into the wind.
	var restoring_torque_per_mass := beta * strength \
		- local_yaw_rate * maxf(directional_stability_yaw_rate_damping, 0.0)
	restoring_torque_per_mass = clampf(
		restoring_torque_per_mass,
		-max_torque_per_mass,
		max_torque_per_mass
	)
	var airflow_t := _smoothstep(
		maxf(directional_stability_start_speed_mps, 0.0),
		maxf(directional_stability_full_speed_mps, directional_stability_start_speed_mps + 0.1),
		local_velocity.z
	)
	var departure_factor := lerpf(
		1.0,
		clampf(stall_stability_min_factor, 0.0, 1.0),
		clampf(departure_severity, 0.0, 1.0)
	)
	return restoring_torque_per_mass * airflow_t * departure_factor


func get_axis_control_authority_at_speed(
		speed_mps: float,
		axis: StringName,
		effective_stall_speed_mps: float = -1.0,
		stall_control_loss: float = 0.0
) -> float:
	var effective_stall := effective_stall_speed_mps
	if effective_stall <= 0.0:
		effective_stall = get_effective_stall_speed_mps()
	var low_speed_authority := _get_low_speed_axis_authority(speed_mps, effective_stall, axis)
	var loss_strength := stall_control_loss_strength
	match axis:
		&"roll":
			loss_strength = roll_stall_control_loss_strength
		&"yaw":
			loss_strength = yaw_stall_control_loss_strength
	low_speed_authority *= 1.0 \
		- clampf(loss_strength, 0.0, 1.0) * clampf(stall_control_loss, 0.0, 1.0)
	return low_speed_authority * get_high_speed_control_limit(speed_mps, axis)


func _get_low_speed_axis_authority(
		control_speed_mps: float,
		effective_stall_speed_mps: float,
		axis: StringName
) -> float:
	var effective_stall := maxf(effective_stall_speed_mps, 1.0)
	var full_speed := effective_stall * maxf(control_authority_full_stall_margin, 1.05)
	var taper_speed := effective_stall * clampf(
		control_authority_taper_stall_margin,
		1.0,
		control_authority_full_stall_margin - 0.01
	)
	var authority_t := clampf(
		(control_speed_mps - taper_speed) / maxf(full_speed - taper_speed, 0.1),
		0.0,
		1.0
	)
	var stall_floor := control_authority_stall_floor
	match axis:
		&"roll":
			stall_floor = roll_control_stall_floor
		&"yaw":
			stall_floor = yaw_control_stall_floor
	return lerpf(
		clampf(stall_floor, 0.0, 1.0),
		1.0,
		pow(authority_t, maxf(control_authority_curve, 0.1))
	)


func get_high_speed_control_limit(speed_mps: float, axis: StringName) -> float:
	var stiffening_start := maxf(control_stiffening_start_speed_mps, 0.0)
	var vne := maxf(never_exceed_speed_mps, stiffening_start + 0.1)
	var full_stiffening_speed := maxf(control_stiffening_full_speed_mps, vne + 0.1)
	var limit_at_vne := pitch_control_limit_at_vne
	var full_limit := pitch_control_limit_full_stiffening
	match axis:
		&"roll":
			limit_at_vne = roll_control_limit_at_vne
			full_limit = roll_control_limit_full_stiffening
		&"yaw":
			limit_at_vne = yaw_control_limit_at_vne
			full_limit = yaw_control_limit_full_stiffening
	limit_at_vne = clampf(limit_at_vne, 0.0, 1.0)
	full_limit = clampf(full_limit, 0.0, limit_at_vne)
	if speed_mps <= vne:
		return lerpf(1.0, limit_at_vne, _smoothstep(stiffening_start, vne, speed_mps))
	return lerpf(
		limit_at_vne,
		full_limit,
		_smoothstep(vne, full_stiffening_speed, speed_mps)
	)


func get_control_stress_for_state(
		speed_mps: float,
		sideslip_ratio: float,
		pitch_command: float,
		roll_command: float,
		yaw_command: float
) -> float:
	var stiffening_start := maxf(control_stiffening_start_speed_mps, 0.0)
	var vne := maxf(never_exceed_speed_mps, stiffening_start + 0.1)
	var full_stiffening_speed := maxf(control_stiffening_full_speed_mps, vne + 0.1)
	# Squared speed is a useful normalized dynamic-pressure proxy. This keeps a
	# hard input quiet in normal flight but makes the same input load the airframe
	# progressively as the aircraft approaches Vne.
	var start_pressure_ratio := pow(stiffening_start / vne, 2.0)
	var speed_pressure_ratio := pow(maxf(speed_mps, 0.0) / vne, 2.0)
	var pressure_t := clampf(
		(speed_pressure_ratio - start_pressure_ratio) \
			/ maxf(1.0 - start_pressure_ratio, 0.01),
		0.0,
		1.0
	)
	var control_demand := maxf(
		absf(pitch_command),
		maxf(absf(roll_command) * 0.75, absf(yaw_command) * 1.10)
	)
	var input_stress := pressure_t * clampf(control_demand, 0.0, 1.0)
	var slip_stress := pressure_t * _smoothstep(0.04, 0.18, absf(sideslip_ratio))
	var overspeed_stress := _smoothstep(vne, full_stiffening_speed, speed_mps)
	return clampf(maxf(input_stress, maxf(slip_stress, overspeed_stress)), 0.0, 1.0)


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
	stability_authority *= lerpf(
		1.0,
		clampf(stall_stability_min_factor, 0.0, 1.0),
		current_departure_severity
	)
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
	var roll_input_release: float = 1.0 - clampf(absf(actual_roll_control) * roll_stability_input_release, 0.0, 0.95)
	var pitch_input_release: float = _get_pitch_stability_input_release_factor()
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
	var pitch_self_level_factor: float = pitch_factor * pitch_input_release
	var pitch_rate_damping_factor: float = pitch_factor * pitch_input_release

	var roll_torque: Vector3 = fwd_dir * limited_roll_error * stability_strength * roll_self_level_factor * rb.mass * stability_authority * stability_torque_scale
	var pitch_torque: Vector3 = -right_dir * limited_pitch_error * stability_strength * pitch_self_level_factor * rb.mass * stability_authority * stability_torque_scale
	var roll_rate_damping_torque: Vector3 = -fwd_dir * roll_rate * roll_rate_damping_factor * rb.mass * stability_authority * roll_stability_rate_damping
	var pitch_rate_damping_torque: Vector3 = -right_dir * pitch_rate * pitch_rate_damping_factor * rb.mass * stability_authority * pitch_stability_rate_damping
	rb.apply_torque(roll_torque + pitch_torque + roll_rate_damping_torque + pitch_rate_damping_torque)


func _get_pitch_stability_input_release_factor() -> float:
	var release_start := clampf(pitch_stability_input_release_start, 0.0, 1.0)
	var release_full := clampf(
		maxf(pitch_stability_input_release_full, release_start + 0.001),
		release_start + 0.001,
		1.0
	)
	var release_t := _smoothstep(release_start, release_full, absf(actual_pitch_control))
	return lerpf(1.0, clampf(pitch_stability_input_min_factor, 0.0, 1.0), release_t)

func get_estimated_angle_of_attack_deg() -> float:
	if rb == null:
		return 0.0
	var local_vel: Vector3 = rb.global_transform.basis.inverse() * rb.linear_velocity
	return rad_to_deg(atan2(-local_vel.y, maxf(local_vel.z, 0.1)))

func _get_aoa_stall_severity(alpha_deg: float) -> float:
	return _get_aoa_stall_severity_for_model(alpha_deg, true)


func _get_aoa_stall_severity_for_model(alpha_deg: float, advanced: bool) -> float:
	var configured_start := aoa_stall_start_deg if advanced else simplified_aoa_stall_start_deg
	var configured_full := aoa_stall_full_deg if advanced else simplified_aoa_stall_full_deg
	var start_deg: float = maxf(configured_start, 0.1)
	var full_deg: float = maxf(configured_full, start_deg + 0.1)
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
	var advanced := is_advanced_flight_model()
	var aoa_stall_severity: float = _get_aoa_stall_severity_for_model(alpha_deg, advanced)
	var active_aoa_lift_loss := aoa_stall_lift_loss if advanced else simplified_aoa_stall_lift_loss
	return commanded_ratio * (1.0 - clampf(active_aoa_lift_loss * aoa_stall_severity, 0.0, 0.95))

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
	if _aero_report_session_id.is_empty():
		_aero_report_session_id = str(int(Time.get_unix_time_from_system()))
		_aero_report_session_start_ticks_msec = Time.get_ticks_msec()
		_aero_report_mark_counter = 0
	if aero_report_reset_on_first_aircraft and not _aero_report_reset_done:
		_aero_report_reset_done = true
		_overwrite_aero_report(aero_report_path)
		if aero_report_project_mirror_enabled:
			_overwrite_aero_report(aero_report_project_mirror_path)
	else:
		_ensure_aero_report_header(aero_report_path)
		if aero_report_project_mirror_enabled:
			_ensure_aero_report_header(aero_report_project_mirror_path)
	_aero_report_flush_timer_s = maxf(aero_report_flush_interval_s, 0.1)


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
		departure_drag_force: Vector3,
		alignment_force: Vector3,
		lift_force: Vector3
) -> void:
	if not aero_report_enabled or rb == null:
		return
	if not _should_write_aero_report():
		# A handoff can otherwise leave up to one second of the previous player
		# aircraft buffered, and its next control session would derive acceleration
		# across the entire unattended interval.
		_flush_aero_report_lines()
		_aero_report_has_previous_velocity = false
		_aero_report_motion_valid = false
		_aero_report_mark_action_was_pressed = false
		return
	_prepare_aero_report()
	_update_aero_report_motion(delta, rb.linear_velocity)
	_update_aero_report_mark_input()
	_aero_report_flush_timer_s -= delta
	if _aero_report_flush_timer_s <= 0.0 and not _aero_report_pending_lines.is_empty():
		_flush_aero_report_lines()
		_aero_report_flush_timer_s = maxf(aero_report_flush_interval_s, 0.1)
	_aero_report_timer_s -= delta
	if _aero_report_timer_s > 0.0:
		return
	_aero_report_timer_s = maxf(aero_report_interval_s, 0.05)
	var pilot_mark := _aero_report_pending_mark
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
		departure_drag_force,
		alignment_force,
		lift_force,
		pilot_mark
	)
	_aero_report_pending_mark = ""
	_aero_report_pending_lines.append(line)
	var force_flush := not pilot_mark.is_empty() \
		or _aero_report_pending_lines.size() >= maxi(aero_report_max_buffered_rows, 1)
	if force_flush:
		_flush_aero_report_lines()
		_aero_report_flush_timer_s = maxf(aero_report_flush_interval_s, 0.1)


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
		departure_drag_force: Vector3,
		alignment_force: Vector3,
		lift_force: Vector3,
		pilot_mark: String = ""
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
	var local_alignment_force: Vector3 = basis.inverse() * alignment_force
	var local_angular_velocity: Vector3 = basis.inverse() * rb.angular_velocity
	var gravity_mag := maxf(float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.80665)), 0.001)
	var specific_energy_m := pos.y + speed * speed / (2.0 * gravity_mag)
	var reported_local_g := NAN
	var reported_load_factor := NAN
	var current_health := NAN
	var maximum_health := NAN
	if rb is Aircraft:
		var aircraft_body := rb as Aircraft
		reported_local_g = aircraft_body.local_g_force
		reported_load_factor = aircraft_body.local_load_factor
		current_health = aircraft_body.current_health
		maximum_health = aircraft_body.max_health
	var ai_toggle := rb.get_node_or_null("AIToggle")
	var ai_active := bool(ai_toggle.get("ai_active")) if ai_toggle != null and "ai_active" in ai_toggle else false
	var grounded := _has_grounded_gear()
	var controls_disabled := bool(rb.get_meta("controls_disabled", false))
	var arresting_engaged := bool(rb.get_meta("arresting_engaged", false)) or rb.has_meta("arresting_cable")
	var carrier_transport := bool(rb.get_meta("carrier_transport_mode", false))
	var parking_brake := bool(rb.get_meta("parking_brake", false))
	var control_mode := "ai_overlap" if ai_active else "player"
	var raw_roll := _get_control_telemetry_float(&"telemetry_raw_roll")
	var raw_pitch := _get_control_telemetry_float(&"telemetry_raw_pitch")
	var raw_yaw := _get_control_telemetry_float(&"telemetry_raw_yaw")
	var shaped_roll := _get_control_telemetry_float(&"telemetry_shaped_roll")
	var shaped_pitch := _get_control_telemetry_float(&"telemetry_shaped_pitch")
	var shaped_yaw := _get_control_telemetry_float(&"telemetry_shaped_yaw")
	var rudder_assist_component := _get_control_telemetry_float(&"telemetry_rudder_assist_component")
	var rudder_slip_error := _get_control_telemetry_float(&"telemetry_rudder_slip_error")
	var rudder_target_assist := _get_control_telemetry_float(&"telemetry_rudder_target_assist")
	var rudder_filtered_assist := _get_control_telemetry_float(&"telemetry_rudder_filtered_assist")
	var rudder_assist_strength := _get_control_telemetry_float(&"telemetry_rudder_assist_strength")
	var rudder_assist_limit := _get_control_telemetry_float(&"telemetry_rudder_assist_limit")
	var event_flags := _get_aero_report_event_flags(
		pilot_mark,
		speed,
		grounded,
		ai_active,
		controls_disabled,
		arresting_engaged
	)
	return ",".join([
		_aero_report_session_id,
		_fmt_float(Time.get_unix_time_from_system(), 3),
		_fmt_float((Time.get_ticks_msec() - _aero_report_session_start_ticks_msec) / 1000.0, 3),
		_fmt_float(Time.get_ticks_msec() / 1000.0, 3),
		str(Engine.get_physics_frames()),
		str(Engine.get_frames_per_second()),
		_csv_name(pilot_mark),
		_csv_name(event_flags),
		control_mode,
		"advanced" if is_advanced_flight_model() else "simplified",
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
		str(_aero_report_motion_valid),
		_fmt_float(_aero_report_local_acceleration.x, 3),
		_fmt_float(_aero_report_local_acceleration.y, 3),
		_fmt_float(_aero_report_local_acceleration.z, 3),
		_fmt_float(_aero_report_local_specific_g.x, 3),
		_fmt_float(_aero_report_local_specific_g.y, 3),
		_fmt_float(_aero_report_local_specific_g.z, 3),
		_fmt_float(_aero_report_speed_rate_mps2, 3),
		_fmt_float(specific_energy_m, 2),
		_fmt_float(_aero_report_energy_rate_mps, 3),
		_fmt_float(reported_local_g, 3),
		_fmt_float(reported_load_factor, 3),
		_fmt_float(pitch_deg, 2),
		_fmt_float(roll_deg, 2),
		_fmt_float(heading_deg, 2),
		_fmt_float(alpha_deg, 2),
		_fmt_float(commanded_lift_ratio, 3),
		_fmt_float(actual_lift_ratio, 3),
		_fmt_float(current_stall_severity, 3),
		_fmt_float(control_authority, 3),
		_fmt_float(current_pitch_authority, 3),
		_fmt_float(current_roll_authority, 3),
		_fmt_float(current_yaw_authority, 3),
		_fmt_float(raw_roll, 3),
		_fmt_float(raw_pitch, 3),
		_fmt_float(raw_yaw, 3),
		_fmt_float(shaped_roll, 3),
		_fmt_float(shaped_pitch, 3),
		_fmt_float(shaped_yaw, 3),
		_fmt_float(rudder_assist_component, 3),
		_fmt_float(rudder_slip_error, 3),
		_fmt_float(rudder_target_assist, 3),
		_fmt_float(rudder_filtered_assist, 3),
		_fmt_float(rudder_assist_strength, 3),
		_fmt_float(rudder_assist_limit, 3),
		_fmt_float(pitch_input, 3),
		_fmt_float(roll_input, 3),
		_fmt_float(yaw_input, 3),
		_fmt_float(actual_pitch_control, 3),
		_fmt_float(actual_roll_control, 3),
		_fmt_float(actual_yaw_control, 3),
		_fmt_float(current_high_speed_stiffening, 3),
		_fmt_float(current_control_stress, 3),
		_fmt_float(current_sideslip_ratio, 3),
		_fmt_float(current_directional_sideslip_deg, 3),
		_fmt_float(current_directional_stability_torque_nm, 1),
		_fmt_float(current_departure_severity, 3),
		_fmt_float(current_stall_drop_direction, 3),
		_fmt_float(throttle_cmd, 3),
		_fmt_float(engine_power, 3),
		_fmt_float(thrust_n, 1),
		_fmt_float(forward_thrust_n, 1),
		str(_is_gear_deployed()),
		_fmt_float(flap_position, 3),
		str(grounded),
		str(rb.freeze),
		str(rb.sleeping),
		_fmt_float(current_health, 2),
		_fmt_float(maximum_health, 2),
		str(ai_active),
		str(controls_disabled),
		str(arresting_engaged),
		str(carrier_transport),
		str(parking_brake),
		_fmt_float(approach_mult, 3),
		_fmt_float(forward_drag_force.length(), 1),
		_fmt_float(lateral_drag_force.length(), 1),
		_fmt_float(total_drag_force.length(), 1),
		_fmt_float(departure_drag_force.length(), 1),
		_fmt_float(alignment_force.length(), 1),
		_fmt_float(local_alignment_force.x, 1),
		_fmt_float(local_alignment_force.y, 1),
		_fmt_float(lift_force.length(), 1),
		_fmt_float(rb.angular_velocity.x, 3),
		_fmt_float(rb.angular_velocity.y, 3),
		_fmt_float(rb.angular_velocity.z, 3),
		_fmt_float(local_angular_velocity.x, 3),
		_fmt_float(local_angular_velocity.y, 3),
		_fmt_float(local_angular_velocity.z, 3),
		_fmt_float(mass_safe(), 1),
	])


func _aero_report_header() -> String:
	return ",".join([
		"session_id",
		"utc_unix_s",
		"session_elapsed_s",
		"t_s",
		"physics_frame",
		"render_fps",
		"pilot_mark",
		"event_flags",
		"control_mode",
		"flight_model",
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
		"motion_sample_valid",
		"local_accel_x_mps2",
		"local_accel_y_mps2",
		"local_accel_z_mps2",
		"lateral_g",
		"normal_g",
		"longitudinal_g",
		"speed_rate_mps2",
		"specific_energy_m",
		"specific_energy_rate_mps",
		"aircraft_reported_g",
		"aircraft_load_factor",
		"pitch_deg",
		"roll_deg",
		"heading_deg",
		"aoa_deg",
		"cmd_lift_ratio",
		"actual_lift_ratio",
		"stall_severity",
		"control_authority",
		"pitch_authority",
		"roll_authority",
		"yaw_authority",
		"raw_roll_input",
		"raw_pitch_input",
		"raw_yaw_input",
		"shaped_roll_input",
		"shaped_pitch_input",
		"shaped_yaw_input",
		"rudder_assist_component",
		"rudder_slip_error",
		"rudder_target_assist",
		"rudder_filtered_assist",
		"rudder_assist_strength",
		"rudder_assist_limit",
		"pitch_input",
		"roll_input",
		"yaw_input",
		"actual_pitch_control",
		"actual_roll_control",
		"actual_yaw_control",
		"high_speed_stiffening",
		"control_stress",
		"sideslip_ratio",
		"directional_sideslip_deg",
		"directional_stability_torque_nm",
		"departure_severity",
		"stall_drop_direction",
		"throttle_cmd",
		"engine_power",
		"thrust_n",
		"forward_thrust_n",
		"gear_deployed",
		"flap_position",
		"grounded",
		"frozen",
		"sleeping",
		"health",
		"max_health",
		"ai_active",
		"controls_disabled",
		"arresting_engaged",
		"carrier_transport",
		"parking_brake",
		"gear_flap_drag_mult",
		"forward_drag_n",
		"lateral_drag_n",
		"total_drag_n",
		"departure_drag_n",
		"alignment_force_n",
		"alignment_lateral_force_n",
		"alignment_vertical_force_n",
		"lift_n",
		"ang_vel_x",
		"ang_vel_y",
		"ang_vel_z",
		"local_pitch_rate",
		"local_yaw_rate",
		"local_roll_rate",
		"mass_kg",
	])


func _update_aero_report_motion(delta: float, velocity: Vector3) -> void:
	if rb == null:
		return
	if _aero_report_has_previous_velocity and delta > 0.0001:
		_aero_report_motion_valid = true
		var world_acceleration := (velocity - _aero_report_previous_velocity) / delta
		var basis := rb.global_transform.basis.orthonormalized()
		_aero_report_local_acceleration = basis.inverse() * world_acceleration
		var gravity_mag := maxf(float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.80665)), 0.001)
		var gravity := Vector3.DOWN * gravity_mag * maxf(rb.gravity_scale, 0.0)
		_aero_report_local_specific_g = basis.inverse() * (world_acceleration - gravity) / gravity_mag
		var speed := velocity.length()
		_aero_report_speed_rate_mps2 = world_acceleration.dot(velocity / speed) if speed > 0.001 else 0.0
		_aero_report_energy_rate_mps = velocity.y + speed * _aero_report_speed_rate_mps2 / gravity_mag
	else:
		_aero_report_motion_valid = false
		_aero_report_local_acceleration = Vector3.ZERO
		_aero_report_local_specific_g = Vector3.ZERO
		_aero_report_speed_rate_mps2 = 0.0
		_aero_report_energy_rate_mps = 0.0
	_aero_report_previous_velocity = velocity
	_aero_report_has_previous_velocity = true


func _update_aero_report_mark_input() -> void:
	var mark_pressed := InputMap.has_action(aero_report_mark_action) \
		and Input.is_action_pressed(aero_report_mark_action)
	if mark_pressed and not _aero_report_mark_action_was_pressed:
		add_player_flight_log_mark("L3")
	_aero_report_mark_action_was_pressed = mark_pressed


func add_player_flight_log_mark(label: String = "MARK") -> String:
	if rb == null or not _should_write_aero_report():
		return ""
	_prepare_aero_report()
	_aero_report_mark_counter += 1
	var safe_label := label.strip_edges().to_upper().replace(" ", "_")
	if safe_label.is_empty():
		safe_label = "MARK"
	_aero_report_pending_mark = "%s_%03d" % [safe_label, _aero_report_mark_counter]
	# Force a sample on this physics tick. The resulting row is flushed
	# immediately, so a later crash or forced quit does not lose the marker.
	_aero_report_timer_s = 0.0
	print("[PlayerFlightRecorder] %s aircraft=%s speed=%.1f aoa=%.1f departure=%.2f" % [
		_aero_report_pending_mark,
		rb.name,
		rb.linear_velocity.length(),
		get_estimated_angle_of_attack_deg(),
		current_departure_severity,
	])
	return _aero_report_pending_mark


func _get_control_telemetry_float(property_name: StringName) -> float:
	if _control_steering_node == null or not is_instance_valid(_control_steering_node):
		_control_steering_node = rb.get_node_or_null("ControlSteering") if rb != null else null
	if _control_steering_node == null:
		return NAN
	for property in _control_steering_node.get_property_list():
		if StringName(property.name) == property_name:
			return float(_control_steering_node.get(property_name))
	return NAN


func _get_aero_report_event_flags(
	pilot_mark: String,
	speed_mps: float,
	grounded: bool,
	ai_active: bool,
	controls_disabled: bool,
	arresting_engaged: bool
) -> String:
	var flags: Array[String] = []
	if not pilot_mark.is_empty():
		flags.append("pilot_mark")
	if current_stall_severity >= 0.10:
		flags.append("stall")
	if current_departure_severity >= 0.05:
		flags.append("departure")
	if speed_mps >= never_exceed_speed_mps:
		flags.append("overspeed")
	if current_control_stress >= 0.75:
		flags.append("control_stress")
	if current_sideslip_ratio >= 0.08:
		flags.append("high_sideslip")
	if absf(_aero_report_local_specific_g.y) >= 4.0:
		flags.append("high_g")
	if grounded:
		flags.append("grounded")
	if ai_active:
		flags.append("ai_overlap")
	if controls_disabled:
		flags.append("controls_disabled")
	if arresting_engaged:
		flags.append("arresting")
	return "|".join(flags)


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


func _flush_aero_report_lines() -> void:
	if _aero_report_pending_lines.is_empty():
		return
	var payload := "\n".join(_aero_report_pending_lines) + "\n"
	_append_aero_report_payload(aero_report_path, payload)
	if aero_report_project_mirror_enabled:
		_append_aero_report_payload(aero_report_project_mirror_path, payload)
	_aero_report_pending_lines.clear()


func _append_aero_report_payload(path: String, payload: String) -> void:
	if path.is_empty():
		return
	var file := FileAccess.open(path, FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
	if file == null:
		push_warning("[SimpleAero] Could not open aero report: %s" % path)
		return
	if file.get_length() <= 0:
		file.store_line(_aero_report_header())
	file.seek_end()
	file.store_string(payload)
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


func _setup_airflow_feedback() -> void:
	if not airflow_feedback_enabled or rb == null:
		return
	_airflow_feedback = AIRFLOW_FEEDBACK_SCRIPT.new()
	_airflow_feedback.name = "AirflowFeedback"
	add_child(_airflow_feedback)
	_airflow_feedback.setup(rb)


func _update_airflow_feedback(
		delta: float,
		alpha_deg: float,
		stall_severity: float,
		total_speed: float,
		forward_speed: float,
		lateral_speed: float,
		effective_stall_speed: float,
		control_stress: float,
		advanced_flight_model: bool,
		airborne_for_stall_effects: bool,
		dirty_drag_accel_mps2: float
) -> void:
	if _airflow_feedback == null:
		return
	var active := true
	if airflow_feedback_only_player:
		active = _should_write_aero_report()
	active = active and airborne_for_stall_effects
	_airflow_feedback.update_airflow_feedback(
		delta,
		active,
		alpha_deg,
		stall_severity,
		total_speed,
		forward_speed,
		lateral_speed,
		effective_stall_speed,
		never_exceed_speed_mps,
		control_stress,
		advanced_flight_model,
		dirty_drag_accel_mps2,
		current_departure_severity
	)


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
	if engine != null and engine.has_method("get_effective_power_factor"):
		return float(engine.call("get_effective_power_factor"))
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

func _is_airborne_for_stall_effects() -> bool:
	if rb == null:
		return false
	if _has_grounded_gear():
		return false
	if rb.has_meta("parking_brake") and bool(rb.get_meta("parking_brake")):
		return false
	if rb.has_meta("carrier_transport_mode") and bool(rb.get_meta("carrier_transport_mode")):
		return false
	if rb.has_meta("controls_disabled") and bool(rb.get_meta("controls_disabled")):
		return false
	if rb.has_meta("arresting_engaged") and bool(rb.get_meta("arresting_engaged")):
		return false
	if rb.has_meta("helicopter_deck_takeoff_ready") and bool(rb.get_meta("helicopter_deck_takeoff_ready")):
		return false
	return true

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
