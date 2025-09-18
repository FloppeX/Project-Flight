extends Node3D
class_name ChaseCamera

@export var chase_distance: float = 10.0
@export var chase_height: float = 2.0
@export var chase_smoothing: float = 5.0
@export var rotation_smoothing: float = 8.0
@export var look_sensitivity: float = 2.0
@export var max_horizontal_angle: float = 45.0  # Maximum degrees for yaw look
@export var max_vertical_angle: float = 45.0    # Maximum degrees for pitch look
@export var return_speed: float = 5.0           # How fast camera returns to center

var aircraft: RigidBody3D
var current_look: Vector2 = Vector2.ZERO  # Current look offset (X = yaw, Y = pitch)

func _ready():
	# Make this node ignore parent transforms so it doesn't move with the aircraft
	top_level = true

func setup_aircraft(aircraft_node: RigidBody3D):
	aircraft = aircraft_node

func _process(delta):
	if not aircraft:
		return
	handle_input(delta)

func _physics_process(delta: float) -> void:
	if not aircraft:
		return
	update_position(delta)

func handle_input(delta):
	# Get look input
	var look_x = Input.get_action_strength("look_left") - Input.get_action_strength("look_right")
	var look_y = Input.get_action_strength("look_down") - Input.get_action_strength("look_up")
	
	# Calculate target look angles based on input
	var target_look = Vector2(
		deg_to_rad(look_x * max_horizontal_angle),  # Yaw
		deg_to_rad(-look_y * max_vertical_angle)    # Pitch (negative for correct direction)
	)
	
	# Smoothly move current look towards target (returns to center when no input)
	current_look = current_look.lerp(target_look, return_speed * delta)

func update_position(delta):
	# Get aircraft position and orientation
	var aircraft_transform = aircraft.global_transform
	var aircraft_position = aircraft.global_position
	
	# Calculate position 20m behind and 2m above the aircraft
	# Use aircraft's basis to get the "behind" direction relative to aircraft orientation
	var behind_offset = aircraft_transform.basis * Vector3(0, chase_height, -chase_distance)
	var target_position = aircraft_position + behind_offset
	
	# Apply framerate-independent smoothing for position
	var pos_smoothing_factor = 1.0 - exp(-chase_smoothing * delta)
	global_position = global_position.lerp(target_position, pos_smoothing_factor)
	
	# Make camera look along the aircraft's flight direction with look offset
	# Start with aircraft basis flipped to look forward
	var base_basis = Basis(-aircraft_transform.basis.x, aircraft_transform.basis.y, -aircraft_transform.basis.z)
	
	# Apply look offset rotations relative to aircraft orientation
	# Yaw around aircraft's local Y-axis, pitch around aircraft's local X-axis
	var look_basis = base_basis.rotated(base_basis.y, current_look.x)
	look_basis = look_basis.rotated(base_basis.x, current_look.y)
	
	var rot_smoothing_factor = 1.0 - exp(-rotation_smoothing * delta)
	global_transform.basis = global_transform.basis.slerp(look_basis, rot_smoothing_factor)

func reset_look():
	current_look = Vector2.ZERO
