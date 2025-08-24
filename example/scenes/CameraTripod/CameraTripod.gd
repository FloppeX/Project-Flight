extends Node3D

@export var horizontal_sensitivity: float = 120.0  # degrees for left/right
@export var vertical_sensitivity: float = 90.0    # degrees for up/down  
@export var return_speed: float = 5.0             # how fast it snaps back to center
@export var g_force_sensitivity: float = 0.05   # How much camera moves per G
@export var g_force_smoothing: float = 8.0      # How fast camera returns to center
@export var max_g_offset: float = 0.3           # Maximum camera displacement

var base_rotation: Vector3 = Vector3.ZERO
var current_look: Vector3 = Vector3.ZERO
var base_position: Vector3
var g_force_offset: Vector3 = Vector3.ZERO
var last_velocity: Vector3 = Vector3.ZERO

func _ready():
	base_position = position
	base_rotation = rotation

func _process(delta):
	# Get right stick input
	var look_x = Input.get_action_strength("look_left") - Input.get_action_strength("look_right")
	var look_y = Input.get_action_strength("look_down") - Input.get_action_strength("look_up") 
	
	# Target look angles in radians with separate sensitivities
	var target_look = Vector3(
		deg_to_rad(-look_y * vertical_sensitivity),
		deg_to_rad(look_x * horizontal_sensitivity), 
		0
	)
	
	# Smoothly move to target
	current_look = current_look.lerp(target_look, return_speed * delta)
	
	# Apply to camera
	rotation = base_rotation + current_look
	
func _physics_process(delta: float):
	# Get aircraft acceleration (need reference to aircraft RigidBody)
	var aircraft = get_parent()  # Adjust path to your aircraft
	var current_velocity = aircraft.linear_velocity
	
	# Calculate acceleration (change in velocity)
	var acceleration = (current_velocity - last_velocity) / delta
	last_velocity = current_velocity
	
	# Convert to G-forces (divide by earth gravity)
	var g_forces = acceleration / 9.8
	
	# Calculate camera offset from G-forces
	var target_offset = Vector3(
		g_forces.x * g_force_sensitivity,      # Side G's push camera sideways
		-g_forces.y * g_force_sensitivity,     # Vertical G's push camera down  
		g_forces.z * g_force_sensitivity       # Forward G's push camera back
	)
	
	# Clamp maximum offset
	target_offset = target_offset.limit_length(max_g_offset)
	
	# Smooth camera movement
	g_force_offset = g_force_offset.lerp(target_offset, g_force_smoothing * delta)
	
	# Apply to camera position
	position = base_position + g_force_offset
