extends Node3D
class_name ChaseCamera

@export var chase_distance: float = 20.0
@export var chase_height: float = 8.0
@export var chase_smoothing: float = 5.0
@export var look_sensitivity: float = 2.0
@export var orbit_distance: float = 8.0
@export var rotation_smoothing: float = 8.0
@export var lookahead_factor: float = 0.2 # Predicts aircraft's future position to stay centered

var look_offset: Vector2 = Vector2.ZERO
var aircraft: RigidBody3D

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
	
	# Update look offset
	look_offset.x += look_x * look_sensitivity * delta
	look_offset.y += look_y * look_sensitivity * delta
	
	# Clamp vertical look
	look_offset.y = clamp(look_offset.y, -PI/3, PI/3)

func update_position(delta):
	# Define the orbit center, compensating for smoothing lag by looking ahead
	var predicted_position = aircraft.global_position + (aircraft.linear_velocity * lookahead_factor)
	var orbit_center = aircraft.global_position.lerp(predicted_position, 0.5) # Smooth the prediction
	var aircraft_transform = aircraft.global_transform

	# Calculate the desired offset from the center based on look input.
	# Start with a base offset (behind and above) and then apply the look rotation.
	var base_offset = Vector3(0, chase_height, chase_distance)
	
	# Create a rotation transform from the look_offset angles (yaw and pitch)
	var look_rotation = Basis()
	look_rotation = look_rotation.rotated(Vector3.UP, look_offset.x)
	look_rotation = look_rotation.rotated(Vector3.RIGHT, look_offset.y)

	# Apply this rotation to our base offset
	var rotated_offset = look_rotation * base_offset

	# Rotate the offset to match the aircraft's orientation.
	# This ensures "behind" is always relative to the aircraft's tail.
	var final_offset = aircraft_transform.basis * rotated_offset
	var target_position = orbit_center + final_offset

	# Apply framerate-independent smoothing for position
	var pos_smoothing_factor = 1.0 - exp(-chase_smoothing * delta)
	global_position = global_position.lerp(target_position, pos_smoothing_factor)

	# Smoothly rotate the camera to look at a point slightly above the aircraft's center.
	# Using slerp on the basis is more stable than lerping euler angles.
	var look_at_target = orbit_center + Vector3.UP * 2.0
	var target_transform = transform.looking_at(look_at_target, Vector3.UP)
	
	var rot_smoothing_factor = 1.0 - exp(-rotation_smoothing * delta)
	global_transform.basis = global_transform.basis.slerp(target_transform.basis, rot_smoothing_factor)

func reset_look():
	look_offset = Vector2.ZERO
