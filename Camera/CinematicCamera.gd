extends Node3D
class_name CinematicCamera

@export var distance_range: Vector2 = Vector2(100, 200)  # Distance in front of aircraft
@export var height_offset_range: Vector2 = Vector2(0, 30)  # Random height offset from aircraft
@export var side_offset_range: Vector2 = Vector2(-30, 30)  # Random horizontal offset
@export var look_smoothing: float = 8.0

var aircraft: RigidBody3D
var focus_target: Node3D
var current_rotation: Vector3

func _ready():
	# Make this node ignore parent transforms so it doesn't move with the aircraft
	top_level = true
	current_rotation = rotation

func setup_aircraft(aircraft_node: RigidBody3D):
	setup_follow_target(aircraft_node, null)

func setup_follow_target(aircraft_node: RigidBody3D, target_node: Node3D = null) -> void:
	aircraft = aircraft_node
	focus_target = target_node

func _get_focus_position() -> Vector3:
	if focus_target != null and is_instance_valid(focus_target):
		return focus_target.global_position
	if aircraft != null and is_instance_valid(aircraft):
		return aircraft.global_position
	return global_position

func _process(delta):
	if aircraft and is_instance_valid(aircraft):
		update_look()

func setup_shot():
	if not aircraft:
		return
		
	var aircraft_pos = _get_focus_position()
	var aircraft_forward = aircraft.global_transform.basis.z
	var aircraft_right = aircraft.global_transform.basis.x
	var aircraft_up = aircraft.global_transform.basis.y
	
	# Position camera ahead of aircraft with random offsets
	var ahead_distance = randf_range(distance_range.x, distance_range.y)
	var side_offset = randf_range(side_offset_range.x, side_offset_range.y)
	var height_offset = randf_range(height_offset_range.x, height_offset_range.y)
	
	# Calculate position ahead of aircraft's current direction
	var cinematic_pos = aircraft_pos + aircraft_forward * ahead_distance
	cinematic_pos += aircraft_right * side_offset
	cinematic_pos += aircraft_up * height_offset  # Height relative to aircraft, not ground
	
	# Set position once and stay there (completely stationary)
	global_position = cinematic_pos

func update_look():
	var focus_position := _get_focus_position()
	if focus_position.is_equal_approx(global_position):
		return
	look_at(focus_position, Vector3.UP)
