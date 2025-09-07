extends Node
class_name SimpleAeroNew2

@export var rb_path: NodePath
var rb: RigidBody3D = null

# Simple parameters (yours)
@export var pitch_power: float = 6.0         # Elevator strength
@export var roll_power: float = 12.0         # Aileron strength
@export var yaw_power: float = 3.0           # Rudder strength
@export var min_control_speed: float = 80.0  # Speed where controls start working
@export var alignment_strength: float = 1000.0   # How fast velocity aligns with nose direction
@export var angular_damping_strength: float = 16.0  # How quickly rotations stop
@export var drag_strength: float = 0.8       # How much drag opposes motion
@export var stability_strength: float = 2.0  # How strongly it wants to return to level
@export var stall_speed: float = 40.0        # Forward speed below which aircraft stalls
@export var stall_nose_drop: float = 20.0    # Base nose-drop torque in stall
@export var auto_rudder_strength: float = 0.3  # How much auto-rudder per roll input
@export var lift_gain: float = 0.0025        # Scales lift with speed^2 (gamey)

# Keep a tiny support near knife-edge (optional safety net)
@export var min_vertical_lift_frac: float = 0.01

# Stall helpers (no air density/wing area involved)
@export var stall_lift_floor: float = 0.25       # Keep ~25% lift in deep stall
@export var stall_sink_accel: float = 12.0       # Downward accel in deep stall (mass-scaled)
@export var stall_pitch_damping: float = 600.0   # Extra pitch-rate damping in stall

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

	# --- Kinematics / basis ---
	var vel: Vector3 = rb.linear_velocity
	var speed: float = vel.length()  # total airspeed magnitude
	var fwd: Vector3 = -rb.global_transform.basis.z
	var right: Vector3 = rb.global_transform.basis.x
	var up: Vector3 = rb.global_transform.basis.y
	var v_dir: Vector3 = (vel / speed) if speed > 0.001 else fwd

	# Forward speed (nose-aligned component); negative becomes 0 for authority/stall logic
	var forward_speed: float = max(vel.dot(fwd), 0.0)

	# --- Drag (use total speed) ---
	if speed > 0.1:
		var drag_force: Vector3 = -v_dir * drag_strength * speed * speed
		rb.apply_central_force(drag_force)

	# --- Lift (tilts with airflow so bank naturally loses vertical) ---
	# Project aircraft "up" onto plane perpendicular to airflow → lift direction that banks properly
	var lift_dir: Vector3 = (up - v_dir * up.dot(v_dir)).normalized()

	var lift_mag: float = lift_gain * speed * speed * rb.mass
	var lift_force: Vector3 = lift_dir * lift_mag

	# OPTIONAL: tiny vertical safety-net near knife-edge so turns don’t insta-sink
	var bank_vertical: float = abs(up.dot(Vector3.UP)) # 1 at wings-level, 0 at knife-edge
	if bank_vertical < 0.2 and min_vertical_lift_frac > 0.0:
		lift_force += Vector3.UP * (lift_mag * min_vertical_lift_frac * (0.2 - bank_vertical) * 5.0)

	# We'll apply lift now; stall block may trim it further with a counter-force.
	rb.apply_central_force(lift_force)

	# --- Control effectiveness based on forward speed ---
	var control_authority: float = clamp(forward_speed / min_control_speed, 0.0, 1.0)

	# --- Controls ---
	if control_authority > 0.0:
		var pitch_force: float = pitch_input * pitch_power * control_authority * rb.mass
		var roll_force: float = roll_input * roll_power * control_authority * rb.mass
		var coordinated_yaw: float = yaw_input + (roll_input * auto_rudder_strength)
		var yaw_force: float = coordinated_yaw * yaw_power * control_authority * rb.mass

		rb.apply_torque(right * pitch_force)                           # Pitch
		rb.apply_torque(rb.global_transform.basis.z * roll_force)      # Roll
		rb.apply_torque(rb.global_transform.basis.y * yaw_force)       # Yaw

	# --- Velocity alignment (gate by forward speed, use total speed for magnitude) ---
	if forward_speed > stall_speed:
		var nose_direction: Vector3 = fwd
		var current_velocity: Vector3 = vel
		var target_velocity: Vector3 = nose_direction * speed
		var alignment_force: Vector3 = (target_velocity - current_velocity) * alignment_strength
		rb.apply_central_force(alignment_force)

	# --- Global angular damping (make sure it never goes to zero) ---
	var damping_floor: float = 0.8  # 0..1 — strong base damping at low speed
	var damping_gain: float = max(control_authority, damping_floor)
	var angular_damping: Vector3 = rb.angular_velocity * -angular_damping_strength * rb.mass * damping_gain
	rb.apply_torque(angular_damping)
	
	# --- Low-speed pitch arrestor: stop backwards flip on spawn/taxi ---
	if speed < 8.0:
		var pitch_rate: float = rb.angular_velocity.dot(right)
		# Big extra damping on the pitch axis only when slow
		var extra_pitch_damp: float = angular_damping_strength * 8.0
		rb.apply_torque(-right * pitch_rate * rb.mass * extra_pitch_damp)

	# --- Roll/Pitch stability toward level (fade by forward speed; weaken in stall) ---
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
				stability_gain *= 0.02   # very weak while stalled so nose-drop controller wins
			var stability_torque: Vector3 = correction_axis * tilt_angle * stability_gain
			rb.apply_torque(stability_torque)

	# --- Stall behaviour (based on forward speed) ---
	if forward_speed < stall_speed and speed > 5:
		var stall_severity: float = 1.0 - (forward_speed / stall_speed)

		# 1) Trim lift toward a floor so wings "lose bite"
		var lift_reduce: float = (1.0 - stall_lift_floor) * stall_severity
		if lift_reduce > 0.0:
			rb.apply_central_force(-lift_dir * lift_mag * lift_reduce)

		# 2) Mass-scaled downward acceleration so stall actually sinks regardless of mass
		rb.apply_central_force(Vector3.DOWN * stall_sink_accel * rb.mass * stall_severity)

		# --- Nose-drop: always pitch toward WORLD DOWN; never runs when basically stopped ---
		# Guard: only run if we have some airflow (total speed), not just sitting/taxiing
		if speed > 5.0:
			var pitch_rate: float = rb.angular_velocity.dot(right)

			# Strengthen the push if airflow is coming from behind (falling backward / tail-first)
			var backflow: float = max(-rb.linear_velocity.dot(fwd), 0.0)      # m/s of backward flow
			var back_ratio: float = (backflow / speed) if speed > 0.001 else 0.0  # 0..1

			# Base nose-down torque (ALWAYS negative about right axis)
			var base_mag: float = stall_nose_drop * rb.mass * stall_severity

			# Always nose-down; add a boost if moving backwards so it flips nose-forward quickly
			var nose_ctrl_torque: Vector3 = -right * (base_mag * (0.6 + 0.8 * back_ratio))

			# Pitch-rate damping to prevent pogo after break
			var pitch_damp_torque: Vector3 = -right * (pitch_rate * stall_pitch_damping * rb.mass * stall_severity)

			rb.apply_torque(nose_ctrl_torque + pitch_damp_torque)

		# 4) Controls get mushy in stall (kept for feel)
		control_authority *= (1.0 - 0.7 * stall_severity)

# --- Small utility: signed angle from a to b around axis (kept for reference) ---
func _signed_angle(a: Vector3, b: Vector3, axis: Vector3) -> float:
	var c: Vector3 = a.cross(b)
	var ang: float = atan2(c.length(), a.dot(b))
	return ang * sign(c.dot(axis))
