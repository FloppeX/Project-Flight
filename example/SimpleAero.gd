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
@export var drag_strength: float = 0.8       # How much drag opposes motion
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

# Control inputs
var pitch_input: float = 0.0
var roll_input: float = 0.0
var yaw_input: float = 0.0

func _ready() -> void:
	rb = get_parent() as RigidBody3D
	if rb:
		rb.gravity_scale = 1.0

func _physics_process(delta: float) -> void:
	if rb == null:
		return

	# --- Basic kinematics ---
	var vel: Vector3 = rb.linear_velocity
	var speed: float = vel.length()
	var fwd: Vector3 = -rb.global_transform.basis.z
	var right: Vector3 = rb.global_transform.basis.x
	var up: Vector3 = rb.global_transform.basis.y
	var v_dir: Vector3 = (vel / speed) if speed > 0.001 else fwd

	# Forward speed (nose-aligned component)
	var forward_speed: float = max(vel.dot(fwd), 0.0)

	# --- Drag (simple quadratic, opposes velocity direction) ---
	if speed > 0.1:
		var drag_force: Vector3 = -v_dir * drag_strength * speed * speed
		rb.apply_central_force(drag_force)

	# --- Lift calculation ---
	# Project aircraft "up" onto plane perpendicular to airflow for realistic banking
	var lift_dir: Vector3 = (up - v_dir * up.dot(v_dir)).normalized()
	var base_lift_mag: float = lift_gain * speed * speed * rb.mass

	# Calculate stall effects
	var stall_severity: float = 0.0
	if forward_speed < stall_speed and speed > 5.0:
		stall_severity = 1.0 - (forward_speed / stall_speed)
		
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

		rb.apply_torque(right * pitch_torque)
		rb.apply_torque(rb.global_transform.basis.z * roll_torque)
		rb.apply_torque(rb.global_transform.basis.y * yaw_torque)

	# --- Velocity alignment (the "on rails" effect) ---
	# Only when not stalled and moving forward
	if forward_speed > stall_speed and speed > 1.0:
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
	if speed > 5.0 and forward_speed > stall_speed:
		var world_up: Vector3 = Vector3.UP
		var tilt_angle: float = up.angle_to(world_up)

		if tilt_angle > 0.1:
			var correction_axis: Vector3 = up.cross(world_up).normalized()
			var stability_gain: float = stability_strength * rb.mass * control_authority
			var stability_torque: Vector3 = correction_axis * tilt_angle * stability_gain
			rb.apply_torque(stability_torque)
