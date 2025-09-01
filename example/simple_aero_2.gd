extends Node
class_name SimpleAero2

@export var rb_path: NodePath
var rb: RigidBody3D = null

# Simple parameters
@export var pitch_power: float = 5.0         # Elevator strength
@export var roll_power: float = 5.0          # Aileron strength  
@export var yaw_power: float = 3.0           # Rudder strength (usually weaker)
@export var min_control_speed: float = 10.0   # Speed where controls start working
@export var angular_damping_strength: float = 5.0  # How quickly rotations stop
@export var drag_strength: float = 0.5  # How much drag opposes motion
@export var stability_strength: float = 2.0  # How strongly it wants to return to level
@export var stall_speed: float = 15.0      # Speed below which aircraft stalls
@export var stall_nose_drop: float = 3.0   # How strongly nose drops in stall
@export var auto_rudder_strength: float = 0.3  # How much auto-rudder per roll input
@export var lift_gain: float = 0.0025      # scales lift with speed^2
@export var min_vertical_lift_frac: float = 0.1  # keep a little support at steep bank

# Control inputs
var pitch_input: float = 0.0
var roll_input: float = 0.0
var yaw_input: float = 0.0

func _ready():
	# Find RigidBody and let gravity work normally
	rb = get_parent() as RigidBody3D
	rb.gravity_scale = 1.0

func _physics_process(delta: float):
	var speed = rb.linear_velocity.length()
	
	# === DRAG ===
	if speed > 0.1:  # Avoid division by zero
		var drag_force = -rb.linear_velocity.normalized() * drag_strength * speed * speed
		rb.apply_central_force(drag_force)
	
	# === LIFT (reduced when banking) ===
	if speed > 1.0:
		var body_up = rb.global_transform.basis.y
		# 1.0 when wings level, 0.0 when knife-edge
		var bank_factor = abs(body_up.dot(Vector3.UP))
		# Keep some vertical support so turns don't insta-sink
		bank_factor = max(bank_factor, min_vertical_lift_frac)

		var lift_mag = lift_gain * speed * speed * rb.mass
		rb.apply_central_force(Vector3.UP * lift_mag * bank_factor) 
	
	# Control effectiveness based on speed
	var control_authority = clamp(speed / min_control_speed, 0.0, 1.0)
	
	# === CONTROLS ===
	if control_authority > 0.0:
		var pitch_force = pitch_input * pitch_power * control_authority * rb.mass
		var roll_force = roll_input * roll_power * control_authority * rb.mass
		# Automatic rudder coordination - add some rudder when rolling
		var coordinated_yaw = yaw_input + (roll_input * auto_rudder_strength)
		var yaw_force = coordinated_yaw * yaw_power * control_authority * rb.mass
		
		rb.apply_torque(rb.global_transform.basis.x * pitch_force)  # Pitch
		rb.apply_torque(rb.global_transform.basis.z * roll_force)   # Roll
		rb.apply_torque(rb.global_transform.basis.y * yaw_force)    # Yaw
	
	# === ANGULAR DAMPING ===
	var angular_damping = rb.angular_velocity * -angular_damping_strength * rb.mass * control_authority
	rb.apply_torque(angular_damping)
	
	# === STABILITY - wants to return to level flight ===
	if speed > 1.0:  # Only when moving
		var aircraft_up = rb.global_transform.basis.y
		var world_up = Vector3.UP
		
		# How far are we tilted from level?
		var tilt_angle = aircraft_up.angle_to(world_up)
		
		if tilt_angle > 0.1:  # Only if significantly tilted
			# Which way to rotate to get back to level?
			var correction_axis = aircraft_up.cross(world_up).normalized()
			# Fade stability with airspeed; kill most of it in stall
			var speed_frac = clamp(speed / max(min_control_speed, 0.001), 0.0, 1.0)
			var stalled = speed < stall_speed
			var stability_gain = stability_strength * rb.mass * speed_frac
			if stalled:
				stability_gain *= 0.1   # 10% of normal while stalled

			var stability_torque = correction_axis * tilt_angle * stability_gain
			rb.apply_torque(stability_torque)

	# === STALL - nose drops and loses lift at low speed ===
	if speed < stall_speed:
		var stall_severity = 1.0 - (speed / stall_speed)
		
		# Nose drops toward GROUND, not aircraft-relative down
		var gravity_direction = Vector3.DOWN
		var aircraft_forward = -rb.global_transform.basis.z
		var aircraft_right = rb.global_transform.basis.x
		
		# Create torque that pitches nose toward ground
		var ground_drop_axis = aircraft_right
		if aircraft_forward.dot(gravity_direction) < 0:  # If nose is pointing up
			ground_drop_axis = -aircraft_right  # Reverse direction
		
		var nose_drop_torque = ground_drop_axis * stall_nose_drop * stall_severity * rb.mass
		rb.apply_torque(nose_drop_torque)
		
		# Lose lift/sink faster
		var stall_sink = Vector3.DOWN * stall_severity * 2000.0  # Adjust sink rate
		rb.apply_central_force(stall_sink)
		
		# Reduce control authority in stall (make it feel mushy)
		control_authority *= (1.0 - stall_severity * 0.7)  # Lose 70% control in full stall

# Helper functions for external control
func set_elevator(value: float):
	pitch_input = clamp(value, -1.0, 1.0)

func set_ailerons(value: float):
	roll_input = clamp(value, -1.0, 1.0)

func set_rudder(value: float):
	yaw_input = clamp(value, -1.0, 1.0)
