extends Node3D
class_name CockpitCamera

@export var horizontal_sensitivity: float = 120.0  # degrees for left/right
@export var vertical_sensitivity: float = 90.0    # degrees for up/down  
@export var return_speed: float = 5.0             # how fast it snaps back to center
@export var g_force_sensitivity: float = 0.08   # How much camera moves per G
@export var g_force_smoothing: float = 12.0     # How fast camera returns to center
@export var max_g_offset: float = 0.4           # Maximum camera displacement
@export var g_deadzone: float = 0.5             # Minimum G-force to trigger effect

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
	
	# Convert to G-forces relative to aircraft's local coordinate system
	var local_acceleration = aircraft.global_transform.basis.inverse() * acceleration
	var g_forces = local_acceleration / 9.8
	
	# Apply deadzone to reduce jitter from small movements
	if g_forces.length() < g_deadzone:
		g_forces = Vector3.ZERO
	
	# Calculate camera offset from G-forces with improved mapping
	var target_offset = Vector3(
		-g_forces.x * g_force_sensitivity,     # Side G's push camera opposite direction
		-g_forces.y * g_force_sensitivity,     # Positive G pushes down, negative G lifts up
		-g_forces.z * g_force_sensitivity      # Forward G's push camera back
	)
	
	# Clamp maximum offset
	target_offset = target_offset.limit_length(max_g_offset)
	
	# Smooth camera movement
	g_force_offset = g_force_offset.lerp(target_offset, g_force_smoothing * delta)
	
	# Apply to camera position
	position = base_position + g_force_offset