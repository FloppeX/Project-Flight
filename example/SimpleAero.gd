extends Node
class_name SimpleAero

@export var rb_path: NodePath
var rb: RigidBody3D = null

# Simple parameters
@export var pitch_power: float = 5.0         # Elevator strength
@export var roll_power: float = 5.0          # Aileron strength  
@export var yaw_power: float = 3.0           # Rudder strength (usually weaker)
@export var min_control_speed: float = 10.0   # Speed where controls start working
@export var alignment_strength: float = 2.0   # How fast velocity aligns with nose direction
@export var angular_damping_strength: float = 5.0  # How quickly rotations stop
@export var drag_strength: float = 0.5  # How much drag opposes motion
@export var stability_strength: float = 2.0  # How strongly it wants to return to level
@export var stall_speed: float = 15.0      # Speed below which aircraft stalls
@export var stall_nose_drop: float = 3.0   # How strongly nose drops in stall
@export var auto_rudder_strength: float = 0.3  # How much auto-rudder per roll input
#@export var landing_gear_spring_strength: float = 5000.0
#@export var landing_gear_height: float = 2.0  # Normal height above ground

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
		
	# Control effectiveness based on speed
	var control_authority = clamp(speed / min_control_speed, 0.0, 1.0)
	
	# In the control section, add this debug:
	if abs(yaw_input) > 0.1:
		print("Yaw Input: ", yaw_input, " Yaw Force: ", yaw_power, " Applied Torque: ", rb.global_transform.basis.y * yaw_power)
	
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
	if speed > 1.0:
		var nose_direction = -rb.global_transform.basis.z
		var current_velocity = rb.linear_velocity
		var target_velocity = nose_direction * speed
		
		var alignment_force = (target_velocity - current_velocity) * alignment_strength
		rb.apply_central_force(alignment_force)
		
	var angular_damping = rb.angular_velocity * -angular_damping_strength * rb.mass * control_authority
	rb.apply_torque(angular_damping)
	
	# Roll/Pitch Stability - wants to return to level flight
	if speed > 2.0:  # Only when moving
		var aircraft_up = rb.global_transform.basis.y
		var world_up = Vector3.UP
		
		# How far are we tilted from level?
		var tilt_angle = aircraft_up.angle_to(world_up)
		
		if tilt_angle > 0.1:  # Only if significantly tilted
			# Which way to rotate to get back to level?
			var correction_axis = aircraft_up.cross(world_up).normalized()
			var stability_torque = correction_axis * tilt_angle * stability_strength * rb.mass
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
		
		var nose_drop_torque = ground_drop_axis * stall_nose_drop * stall_severity * rb.mass
		rb.apply_torque(nose_drop_torque)
		
		# Lose lift/sink faster
		var stall_sink = Vector3.DOWN * stall_severity * 2000.0  # Adjust sink rate
		rb.apply_central_force(stall_sink)
		
		# Reduce control authority in stall (make it feel mushy)
		control_authority *= (1.0 - stall_severity * 0.7)  # Lose 70% control in full stall
