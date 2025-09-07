extends Node3D
class_name ChaseCamera

@export var chase_distance: float = 20.0
@export var chase_height: float = 8.0
@export var chase_smoothing: float = 5.0
@export var look_sensitivity: float = 2.0
@export var orbit_distance: float = 8.0

var look_offset: Vector2 = Vector2.ZERO
var aircraft: RigidBody3D

func setup_aircraft(aircraft_node: RigidBody3D):
	aircraft = aircraft_node

func _process(delta):
	if not aircraft:
		return
		
	handle_input(delta)
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
	var aircraft_pos = aircraft.global_position
	var aircraft_forward = -aircraft.global_transform.basis.z
	
	# Calculate base position behind and above aircraft
	var base_position = aircraft_pos - aircraft_forward * chase_distance + Vector3.UP * chase_height
	
	# Apply spherical coordinates for orbiting around base position
	var spherical_offset = Vector3(
		sin(look_offset.x) * cos(look_offset.y) * orbit_distance,
		sin(look_offset.y) * orbit_distance,
		cos(look_offset.x) * cos(look_offset.y) * orbit_distance
	)
	
	var target_position = base_position + spherical_offset
	
	# Smooth camera movement
	global_position = global_position.lerp(target_position, chase_smoothing * delta)
	
	# Always look at aircraft
	look_at(aircraft_pos, Vector3.UP)

func reset_look():
	look_offset = Vector2.ZERO