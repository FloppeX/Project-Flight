extends Node
class_name SimpleAero

@export var rb_path: NodePath
var rb: RigidBody3D = null

# Simple parameters
@export var pitch_power: float = 6.0         # Elevator strength
@export var roll_power: float = 12.0          # Aileron strength  
@export var yaw_power: float = 3.0           # Rudder strength (usually weaker)
@export var min_control_speed: float = 80.0   # Speed where controls start working
@export var alignment_strength: float = 1000.0   # How fast velocity aligns with nose direction
@export var angular_damping_strength: float = 16.0  # How quickly rotations stop
@export var drag_strength: float = 0.8  # How much drag opposes motion
@export var stability_strength: float = 2.0  # How strongly it wants to return to level
@export var stall_speed: float = 40.0      # Speed below which aircraft stalls
@export var stall_nose_drop: float = 20.0   # How strongly nose drops in stall
@export var auto_rudder_strength: float = 0.3  # How much auto-rudder per roll input
#@export var landing_gear_spring_strength: float = 5000.0
#@export var landing_gear_height: float = 2.0  # Normal height above ground
@export var lift_gain: float = 0.0025      # scales lift with speed^2
@export var min_vertical_lift_frac: float = 0.01  # keep a little support at steep bank


# Control inputs
var pitch_input: float = 0.0
var roll_input: float = 0.0
var yaw_input: float = 0.0

func _ready():
	# Find RigidBody and let gravity work normally
	rb = get_parent() as RigidBody3D
	rb.gravity_scale = 1.0

#func apply_landing_gear_springs():
#	var height_above_ground = rb.global_position.y  # Assuming flat ground at Y=0
#	
#	if height_above_ground < landing_gear_height:
#		# "Compressed" - apply spring force
#		var compression = landing_gear_height - height_above_ground
#		var spring_force = compression * landing_gear_spring_strength
#		rb.apply_central_force(Vector3.UP * spring_force)
#		
#		# Add some damping to prevent bouncing
#		var vertical_velocity = rb.linear_velocity.y
#		var damping_force = -vertical_velocity * 1000.0
#		rb.apply_central_force(Vector3.UP * damping_force)

func _physics_process(delta: float):
	var speed = rb.linear_velocity.length()
	
	if speed > 0.1:  # Avoid division by zero
		var drag_force = -rb.linear_velocity.normalized() * drag_strength * speed * speed
		rb.apply_central_force(drag_force)
		
	
		# --- simple lift that weakens with bank ---
	if speed > 1.0:
		var body_up := rb.global_transform.basis.y
		# 1.0 when wings level, 0.0 when knife-edge
		var bank_factor = abs(body_up.dot(Vector3.UP))
		# keep some vertical support so turns don’t insta-sink (tune to taste)
		bank_factor = max(bank_factor, min_vertical_lift_frac)

		# Lift magnitude ~ speed^2 (arcade-friendly)
		var lift_mag = lift_gain * speed * speed * rb.mass
		rb.apply_central_force(body_up * lift_mag * bank_factor)
	
	# Control effectiveness based on speed
	var control_authority = clamp(speed / min_control_speed, 0.0, 1.0)
	
	# Apply controls (only if moving)
	if control_authority > 0.0:
		var pitch_force = pitch_input * pitch_power * control_authority * rb.mass
		var roll_force = roll_input * roll_power * control_authority * rb.mass
		# Automatic rudder coordination - add some rudder when rolling
		var coordinated_yaw = yaw_input + (roll_input * auto_rudder_strength)
		var yaw_force = coordinated_yaw * yaw_power * control_authority * rb.mass
		
		rb.apply_torque(rb.global_transform.basis.x * pitch_force)  # Pitch
		rb.apply_torque(rb.global_transform.basis.z * roll_force)   # Roll
		rb.apply_torque(rb.global_transform.basis.y * yaw_force)    # Yaw
	
	# Gradually align velocity with nose direction
	if speed > stall_speed:
		var nose_direction = -rb.global_transform.basis.z
		var current_velocity = rb.linear_velocity
		var target_velocity = nose_direction * speed
		
		var alignment_force = (target_velocity - current_velocity) * alignment_strength
		rb.apply_central_force(alignment_force)
		
	var angular_damping = rb.angular_velocity * -angular_damping_strength * rb.mass * control_authority
	rb.apply_torque(angular_damping)
	
	# Roll/Pitch Stability - wants to return to level flight
	if speed > 0:  # Only when moving
		var aircraft_up = rb.global_transform.basis.y
		var world_up = Vector3.UP
		
		# How far are we tilted from level?
		var tilt_angle = aircraft_up.angle_to(world_up)
		
		if tilt_angle > 0.1:  # Only if significantly tilted
			# Which way to rotate to get back to level?
			var correction_axis = aircraft_up.cross(world_up).normalized()
			# NEW: fade stability with airspeed; kill most of it in stall
			var speed_frac = clamp(speed / max(min_control_speed, 0.001), 0.0, 1.0)
			var stalled = speed < stall_speed
			var stability_gain = stability_strength * rb.mass * speed_frac
			if stalled:
				stability_gain *= 0.1   # 10% of normal while stalled

			var stability_torque = correction_axis * tilt_angle * stability_gain
			rb.apply_torque(stability_torque)

	# Stall behavior - nose drops and loses lift at low speed
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
		
		
		var nose_drop_torque = -rb.global_transform.basis.x * stall_nose_drop * stall_severity * rb.mass
		rb.apply_torque(nose_drop_torque)
		
		# Lose lift/sink faster
		var stall_sink = Vector3.DOWN * stall_severity * 2000.0  # Adjust sink rate
		rb.apply_central_force(stall_sink)
		
		# Reduce control authority in stall (make it feel mushy)
		control_authority *= (1.0 - stall_severity * 0.7)  # Lose 70% control in full stall
		
