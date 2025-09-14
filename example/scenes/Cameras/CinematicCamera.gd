extends Node3D
class_name CinematicCamera

@export var distance_range: Vector2 = Vector2(80, 200)
@export var height_range: Vector2 = Vector2(5, 100)
@export var side_range: Vector2 = Vector2(-100, 100)
@export var look_smoothing: float = 8.0

var aircraft: RigidBody3D
var current_rotation: Vector3

func _ready():
	# Make this node ignore parent transforms so it doesn't move with the aircraft
	top_level = true
	current_rotation = rotation

func setup_aircraft(aircraft_node: RigidBody3D):
	aircraft = aircraft_node

func _process(delta):
	if aircraft:
		update_look()

func setup_shot():
	if not aircraft:
		return
		
	var aircraft_pos = aircraft.global_position
	var aircraft_forward = aircraft.global_transform.basis.z
	var aircraft_right = aircraft.global_transform.basis.x
	
	# Position camera ahead of aircraft's flight path
	var ahead_distance = randf_range(distance_range.x, distance_range.y)
	var side_offset = randf_range(side_range.x * 0.5, side_range.y * 0.5)  # Less extreme side positioning
	var random_height = randf_range(height_range.x, height_range.y)
	
	# Calculate position ahead of aircraft's current direction
	var cinematic_pos = aircraft_pos + aircraft_forward * ahead_distance
	cinematic_pos += aircraft_right * side_offset
	cinematic_pos.y = random_height  # Absolute height above ground
	
	# Set position once and stay there (completely stationary)
	global_position = cinematic_pos
	print("Cinematic camera positioned at: ", cinematic_pos, " ahead of aircraft")

func update_look():
	# Calculate target rotation to look at aircraft
	var target_transform = transform.looking_at(aircraft.global_position, Vector3.UP)
	
	# Smooth rotation to reduce jerkiness
	rotation = rotation.lerp(target_transform.basis.get_euler(), look_smoothing * get_process_delta_time())