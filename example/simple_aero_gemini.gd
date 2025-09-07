# SimpleAero.gd - A basic flight model script for a Godot flight game.
# This script simulates believable flight physics without being a full simulator.

extends Node
class_name SimpleAeroGemini

@export var rb_path: NodePath
var rb: RigidBody3D = null

# Tunable Parameters: Adjust these values in the Godot inspector for different flight feels.
#
# Control Strength
@export var pitch_power: float = 6.0          # Elevator strength (affects nose up/down)
@export var roll_power: float = 12.0          # Aileron strength (affects banking)
@export var yaw_power: float = 3.0            # Rudder strength (affects turning left/right)
@export var auto_rudder_strength: float = 0.3 # How much auto-rudder per roll input (helps with coordinated turns)

# Aerodynamic Forces
@export var drag_strength: float = 0.8        # How much drag opposes motion
@export var lift_gain: float = 0.0025         # Scales lift with speed^2 (gamey)
@export var min_vertical_lift_frac: float = 0.01 # A tiny vertical lift safety net for turning

# Movement and Stability
@export var alignment_strength: float = 10.0   # How fast velocity aligns with nose direction
@export var angular_damping_strength: float = 16.0 # How quickly rotations stop
@export var stability_strength: float = 2.0   # How strongly it wants to return to level
@export var min_control_speed: float = 80.0   # Speed where controls start working

# Stall Behaviour
@export var stall_speed: float = 40.0         # Forward speed below which aircraft stalls
@export var stall_lift_floor: float = 0.8     # Minimum lift in a stall
@export var stall_sink_accel: float = 12.0    # Downward accel in deep stall (mass-scaled)
@export var stall_nose_drop: float = 40.0     # Base nose-drop torque in stall
@export var stall_pitch_damping: float = 100.0# Extra pitch-rate damping in stall

# Control inputs
var pitch_input: float = 0.0
var roll_input: float = 0.0
var yaw_input: float = 0.0

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	rb = get_parent() as RigidBody3D
	if rb:
		rb.gravity_scale = 1.0

# Called every physics frame.
func _physics_process(delta: float) -> void:
	if rb == null:
		return

	# --- Kinematics / basis ---
	var vel: Vector3 = rb.linear_velocity
	var speed: float = vel.length() # total airspeed magnitude
	var fwd: Vector3 = -rb.global_transform.basis.z # The aircraft's forward vector
	var right: Vector3 = rb.global_transform.basis.x
	var up: Vector3 = rb.global_transform.basis.y
	var v_dir: Vector3 = (vel / speed) if speed > 0.001 else fwd

	# Forward speed (nose-aligned component); negative becomes 0 for authority/stall logic
	var forward_speed: float = max(vel.dot(fwd), 0.0)

	# --- Drag (use total speed) ---
	if speed > 0.1:
		# Applies a force opposite to the velocity direction.
		var drag_force: Vector3 = -v_dir * drag_strength * speed * speed
		rb.apply_central_force(drag_force)

	# --- Lift ---
	# Lift direction is perpendicular to both the aircraft's up vector and the velocity vector.
	# This ensures that banking a plane will redirect lift correctly, causing a turn.
	var lift_dir: Vector3 = (up.cross(v_dir.cross(up))).normalized()

	# Lift magnitude scales with speed squared.
	var lift_mag: float = lift_gain * speed * speed * rb.mass
	var lift_force: Vector3 = lift_dir * lift_mag

	# OPTIONAL: a tiny vertical safety-net near knife-edge so turns don’t insta-sink
	var bank_vertical: float = abs(up.dot(Vector3.UP)) # 1 at wings-level, 0 at knife-edge
	if bank_vertical < 0.2 and min_vertical_lift_frac > 0.0:
		lift_force += Vector3.UP * (lift_mag * min_vertical_lift_frac * (0.2 - bank_vertical) * 5.0)

	# Apply the calculated lift force
	rb.apply_central_force(lift_force)

	# --- Control effectiveness based on forward speed ---
	var control_authority: float = clamp(forward_speed / min_control_speed, 0.0, 1.0)

	# --- Controls ---
	if control_authority > 0.0:
		var pitch_torque: float = pitch_input * pitch_power * control_authority * rb.mass
		var roll_torque: float = roll_input * roll_power * control_authority * rb.mass
		var coordinated_yaw: float = yaw_input + (roll_input * auto_rudder_strength)
		var yaw_torque: float = coordinated_yaw * yaw_power * control_authority * rb.mass

		# Apply torques to rotate the aircraft
		rb.apply_torque(right * pitch_torque)          # Pitch
		rb.apply_torque(fwd * roll_torque)             # Roll
		rb.apply_torque(up * yaw_torque)               # Yaw

	# --- Velocity alignment ---
	if forward_speed > stall_speed:
		# This is the main change: we now only correct the sideways velocity.
		# This prevents the snappy, unnatural feel of the old alignment method.
		var sideways_velocity: Vector3 = vel - (fwd * forward_speed)
		var alignment_force: Vector3 = -sideways_velocity * alignment_strength * speed
		rb.apply_central_force(alignment_force)

	# --- Global angular damping ---
	var damping_floor: float = 0.8
	var damping_gain: float = max(control_authority, damping_floor)
	var angular_damping: Vector3 = rb.angular_velocity * -angular_damping_strength * rb.mass * damping_gain
	rb.apply_torque(angular_damping)

	# --- Low-speed pitch arrestor: stop backwards flip ---
	if speed < 8.0:
		var pitch_rate: float = rb.angular_velocity.dot(right)
		var extra_pitch_damp: float = angular_damping_strength * 8.0
		rb.apply_torque(-right * pitch_rate * rb.mass * extra_pitch_damp)

	# --- Roll/Pitch stability toward level (fades with speed, weakens in stall) ---
	if speed > 0.0:
		var aircraft_up: Vector3 = up
		var world_up: Vector3 = Vector3.UP
		var tilt_angle: float = aircraft_up.angle_to(world_up)

		if tilt_angle > 0.1:
			var correction_axis: Vector3 = aircraft_up.cross(world_up).normalized()
			var speed_frac: float = clamp(forward_speed / max(min_control_speed, 0.001), 0.0, 1.0)
			var stalled: bool = forward_speed < stall_speed
			var stability_gain: float = stability_strength * rb.mass * speed_frac
			if stalled:
				stability_gain *= 0.02
			var stability_torque: Vector3 = correction_axis * tilt_angle * stability_gain
			rb.apply_torque(stability_torque)

	# --- Stall behaviour ---
	if forward_speed < stall_speed and speed > 5:
		var stall_severity: float = 1.0 - (forward_speed / stall_speed)

		# 1) Trim lift toward a floor
		var lift_reduce: float = (1.0 - stall_lift_floor) * stall_severity
		if lift_reduce > 0.0:
			rb.apply_central_force(-lift_dir * lift_mag * lift_reduce)

		# 2) Mass-scaled downward acceleration so stall actually sinks
		rb.apply_central_force(Vector3.DOWN * stall_sink_accel * rb.mass * stall_severity)

		# 3) Nose-drop: always pitch toward WORLD DOWN
		if speed > 5.0:
			var pitch_rate: float = rb.angular_velocity.dot(right)
			var backflow: float = max(-rb.linear_velocity.dot(fwd), 0.0)
			var back_ratio: float = (backflow / speed) if speed > 0.001 else 0.0

			var base_mag: float = stall_nose_drop * rb.mass * stall_severity
			var nose_ctrl_torque: Vector3 = -right * (base_mag * (0.6 + 0.8 * back_ratio))
			var pitch_damp_torque: Vector3 = -right * (pitch_rate * stall_pitch_damping * rb.mass * stall_severity)
			rb.apply_torque(nose_ctrl_torque + pitch_damp_torque)

		# 4) Controls get mushy in stall
		control_authority *= (1.0 - 0.7 * stall_severity)

# --- Small utility: signed angle from a to b around axis (kept for reference) ---
func _signed_angle(a: Vector3, b: Vector3, axis: Vector3) -> float:
	var c: Vector3 = a.cross(b)
	var ang: float = atan2(c.length(), a.dot(b))
	return ang * sign(c.dot(axis))
