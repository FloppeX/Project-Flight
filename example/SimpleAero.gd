extends Node
class_name SimpleAero

@export var rb_path: NodePath
var rb: RigidBody3D = null

# Simple parameters
@export var pitch_power: float = 6.0         # Elevator strength
@export var roll_power: float = 12.0         # Aileron strength
@export var yaw_power: float = 3.0           # Rudder strength
@export var min_control_speed: float = 80.0  # Speed where controls start working
@export var alignment_strength: float = 1000.0   # How fast velocity aligns with nose direction
@export var angular_damping_strength: float = 16.0  # How quickly rotations stop
@export var drag_base_multiplier: float = 0.8  # Base multiplier on combined forward+lateral drag
@export var stability_strength: float = 2.0  # How strongly it wants to return to level
@export var stall_speed: float = 40.0        # Forward speed below which aircraft stalls
@export var auto_rudder_strength: float = 0.3  # How much auto-rudder per roll input
@export var lift_gain: float = 0.0025        # Scales lift with speed^2

# Keep a tiny support near knife-edge (optional safety net)
@export var min_vertical_lift_frac: float = 0.01

# Simplified stall parameters
@export var stall_nose_drop_force: float = 5.0  # Downward force strength at nose
@export var stall_lift_loss: float = 0.2      # Fraction of lift lost at full stall (0.0 to 1.0)
@export var stall_shake_intensity: float = 3.0  # How intense stall shake is

# Drag tuning
@export var forward_drag_strength: float = 0.4
@export var lateral_drag_strength: float = 1.2
@export var gear_drag_multiplier: float = 1.5
@export var flaps_drag_multiplier: float = 1.25  # When flaps deployed (approach config: gear+flaps together)
@export var flaps_stall_speed_factor: float = 0.85  # Stall speed multiplier when flaps deployed (0.85 = 15% lower)

# Control inputs
var pitch_input: float = 0.0
var roll_input: float = 0.0
var yaw_input: float = 0.0

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

	# Forward speed (nose-aligned component)
	var forward_speed: float = max(vel.dot(fwd), 0.0)

	# --- Drag (split longitudinal vs lateral; gear+flaps increase drag on approach) ---
	if speed > 0.1:
		var gear_mult: float = gear_drag_multiplier if _is_gear_deployed() else 1.0
		var flaps_mult: float = flaps_drag_multiplier if _is_flaps_deployed() else 1.0
		var approach_mult: float = gear_mult * flaps_mult
		# Longitudinal
		var f_drag: Vector3 = -fwd * forward_drag_strength * forward_speed * abs(forward_speed)
		# Lateral (velocity minus forward component)
		var lateral_vel: Vector3 = vel - fwd * forward_speed
		var lateral_speed: float = lateral_vel.length()
		var lat_dir: Vector3 = (-lateral_vel / lateral_speed) if lateral_speed > 0.001 else Vector3.ZERO
		var l_drag: Vector3 = lat_dir * lateral_drag_strength * lateral_speed * lateral_speed
		# Combine and scale (gear+flaps multiply drag when deployed)
		var drag_force: Vector3 = (f_drag + l_drag) * drag_base_multiplier
		rb.apply_central_force(drag_force * approach_mult)

	# --- Lift calculation ---
	# Project aircraft "up" onto plane perpendicular to airflow for realistic banking
	var lift_dir: Vector3 = (up - v_dir * up.dot(v_dir)).normalized()
	var base_lift_mag: float = lift_gain * speed * speed * rb.mass

	# Effective stall speed: lower when flaps deployed (more lift at low speed)
	var effective_stall_speed: float = stall_speed * (flaps_stall_speed_factor if _is_flaps_deployed() else 1.0)

	# Calculate stall effects
	var stall_severity: float = 0.0
	if forward_speed < effective_stall_speed and speed > 5.0:
		stall_severity = 1.0 - (forward_speed / effective_stall_speed)
		
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

	# --- Velocity alignment (the "on rails" effect) ---
	# Only when not stalled and moving forward
	if forward_speed > effective_stall_speed and speed > 1.0:
		var target_velocity: Vector3 = fwd * speed
		var alignment_force: Vector3 = (target_velocity - vel) * alignment_strength
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

	# --- Stability (return to level flight) ---
	# Only when moving and not stalled
	if speed > 5.0 and forward_speed > effective_stall_speed:
		var world_up: Vector3 = Vector3.UP
		var tilt_angle: float = up.angle_to(world_up)

		if tilt_angle > 0.1:
			var correction_axis: Vector3 = up.cross(world_up).normalized()
			var stability_gain: float = stability_strength * rb.mass * control_authority
			var stability_torque: Vector3 = correction_axis * tilt_angle * stability_gain
			rb.apply_torque(stability_torque)

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
