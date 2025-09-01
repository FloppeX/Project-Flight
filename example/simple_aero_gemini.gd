extends Node
class_name SimpleAeroGemini

@export var rb_path: NodePath
var rb: RigidBody3D = null

# Simple parameters
@export var pitch_power: float = 6.0         # Elevator strength
@export var roll_power: float = 12.0         # Aileron strength  
@export var yaw_power: float = 3.0           # Rudder strength (usually weaker)
@export var min_control_speed: float = 80.0  # Speed where controls start working
@export var alignment_strength: float = 1000.0 # How fast velocity aligns with nose direction
@export var angular_damping_strength: float = 16.0 # How quickly rotations stop
@export var drag_strength: float = 0.8 # How much drag opposes motion
@export var stability_strength: float = 2.0  # How strongly it wants to return to level
@export var stall_speed: float = 40.0        # Speed below which aircraft stalls
@export var stall_nose_drop: float = 20.0    # How strongly nose drops in stall
@export var auto_rudder_strength: float = 0.3 # How much auto-rudder per roll input
@export var lift_gain: float = 0.0025        # scales lift with speed^2
@export var min_vertical_lift_frac: float = 0.01 # keep a little support at steep bank

# Control inputs
var pitch_input: float = 0.0
var roll_input: float = 0.0
var yaw_input: float = 0.0

func _ready():
	rb = get_parent() as RigidBody3D
	rb.gravity_scale = 1.0

func _physics_process(delta: float):
	var speed = rb.linear_velocity.length()
	var is_stalled = speed < stall_speed
	
	if speed > 0.1: # Avoid division by zero
		var drag_force = -rb.linear_velocity.normalized() * drag_strength * speed * speed
		rb.apply_central_force(drag_force)
		
	# --- simple lift that weakens with bank ---
	if speed > 1.0:
		var body_up := rb.global_transform.basis.y
		var bank_factor = abs(body_up.dot(Vector3.UP))
		bank_factor = max(bank_factor, min_vertical_lift_frac)

		var current_lift_gain = lift_gain
		
		# --- TWEAK 1: Stall now directly affects lift ---
		# Instead of a separate sink force, a stall now kills the lift from the wings.
		if is_stalled:
			current_lift_gain *= 0.1 # Only 10% of normal lift when stalled

		var lift_mag = current_lift_gain * speed * speed * rb.mass
		rb.apply_central_force(body_up * lift_mag * bank_factor)

		# --- TWEAK 2: Add sideslip force to punish extreme banks ---
		# This new force pushes the plane down and sideways when banked steeply,
		# making it impossible to fly at 90 degrees indefinitely.
		var bank_angle = body_up.angle_to(Vector3.UP)
		if bank_angle > PI / 4: # Only apply when banked more than 45 degrees
			var slip_severity = remap(bank_angle, PI / 4, PI / 2, 0.0, 1.0)
			var slip_direction = -rb.global_transform.basis.y
			var slip_force = slip_direction * slip_severity * speed * 50.0 # Adjust 50.0 to taste
			rb.apply_central_force(slip_force)

	# Control effectiveness based on speed
	var control_authority = clamp(speed / min_control_speed, 0.0, 1.0)
	
	# Apply controls (only if moving)
	if control_authority > 0.0:
		var pitch_force = pitch_input * pitch_power * control_authority * rb.mass
		var roll_force = roll_input * roll_power * control_authority * rb.mass
		var coordinated_yaw = yaw_input + (roll_input * auto_rudder_strength)
		var yaw_force = coordinated_yaw * yaw_power * control_authority * rb.mass
		
		rb.apply_torque(rb.global_transform.basis.x * pitch_force) # Pitch
		rb.apply_torque(rb.global_transform.basis.z * roll_force)  # Roll
		rb.apply_torque(rb.global_transform.basis.y * yaw_force)   # Yaw
	
	# Gradually align velocity with nose direction
	if not is_stalled:
		var nose_direction = -rb.global_transform.basis.z
		var current_velocity = rb.linear_velocity
		var target_velocity = nose_direction * speed
		var alignment_force = (target_velocity - current_velocity) * alignment_strength
		rb.apply_central_force(alignment_force)
		
	var angular_damping = rb.angular_velocity * -angular_damping_strength * rb.mass * control_authority
	rb.apply_torque(angular_damping)
	
	# Roll/Pitch Stability - wants to return to level flight
	if not is_stalled: # Only when not stalled
		var aircraft_up = rb.global_transform.basis.y
		var world_up = Vector3.UP
		var tilt_angle = aircraft_up.angle_to(world_up)
		
		if tilt_angle > 0.1: # Only if significantly tilted
			var correction_axis = aircraft_up.cross(world_up).normalized()
			var speed_frac = clamp(speed / max(min_control_speed, 0.001), 0.0, 1.0)
			var stability_gain = stability_strength * rb.mass * speed_frac
			var stability_torque = correction_axis * tilt_angle * stability_gain
			rb.apply_torque(stability_torque)

	# Stall behavior - nose drops and loses lift at low speed
	if is_stalled:
		var stall_severity = 1.0 - (speed / stall_speed)
		var nose_drop_torque = -rb.global_transform.basis.x * stall_nose_drop * stall_severity * rb.mass
		rb.apply_torque(nose_drop_torque)
		
		# We removed the old stall_sink force as it's now handled by the lift reduction.
