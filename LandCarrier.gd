extends CharacterBody3D
class_name LandCarrier

# Simplified Land Carrier with floating system
# No complex suspension - just floats at 32m above ground

@export var target_height: float = 41.0  # Height above ground to maintain
@export var height_smoothing: float = 5.0  # How quickly to adjust height
@export var max_speed: float = 20.0  # Maximum speed in m/s
@export var acceleration: float = 5.0  # Acceleration in m/s²
@export var turn_speed: float = 30.0  # Turn speed in degrees/second

var current_speed: float = 0.0
var current_direction: float = 0.0  # Direction in degrees
var treads: Array[CarrierTread] = []
var elevator: Node3D # Reference to the elevator system

# Ground detection
var ground_ray: RayCast3D
var ground_height: float = 0.0

func _ready():
	# Set up ground detection
	setup_ground_detection()
	# Make carrier discoverable to systems (e.g., radar)
	add_to_group("carrier")
	
	# Find all treads
	find_treads()
	
	# Set up collision
	#setup_collision()
	
	# Initialize elevator
	elevator = find_child("Elevator")
	if elevator:
		print("Elevator system found and ready")
		# Setup the elevator system
		if elevator.has_method("setup"):
			elevator.setup(self)
	else:
		print("No elevator system found")

func setup_ground_detection():
	"""Set up raycast for ground detection"""
	ground_ray = RayCast3D.new()
	ground_ray.collision_mask = 1  # Ground layer
	ground_ray.collide_with_areas = false
	ground_ray.collide_with_bodies = true
	add_child(ground_ray)
	
	# Position ray at carrier center, pointing down
	ground_ray.position = Vector3.ZERO
	ground_ray.target_position = Vector3(0, -100, 0)  # Cast 100m down

func find_treads():
	"""Find all tread elements"""
	treads.clear()
	for child in get_children():
		if child is CarrierTread:
			treads.append(child)

func setup_collision():
	"""Set up collision shape for the carrier"""
	#var collision_shape = CollisionShape3D.new()
	#var box_shape = BoxShape3D.new()
	#box_shape.size = Vector3(30, 8, 60)  # Carrier dimensions
	#collision_shape.shape = box_shape
	#collision_shape.position = Vector3(0, 0, 0)
	#add_child(collision_shape)

func _physics_process(delta):
	# Update ground detection
	update_ground_height()
	
	# Maintain floating height
	maintain_floating_height(delta)
	
	# Update tread positions
	update_tread_positions()
	
	# Apply movement
	apply_movement(delta)
	
	# Update elevator
	if elevator and elevator.has_method("update"):
		elevator.update(delta)

func update_ground_height():
	"""Update the detected ground height"""
	ground_ray.force_raycast_update()
	if ground_ray.is_colliding():
		ground_height = ground_ray.get_collision_point().y
	else:
		# If no ground detected, use current height as fallback
		ground_height = global_position.y - target_height

func maintain_floating_height(delta):
	"""Maintain the target height above ground"""
	var target_y = ground_height + target_height
	var current_y = global_position.y
	var height_difference = target_y - current_y
	
	# Smooth height adjustment
	var height_adjustment = height_difference * height_smoothing * delta
	
	# Apply height adjustment
	global_position.y += height_adjustment
	
	# Update tread positions to be 32m below the carrier
	update_tread_positions()

func update_tread_positions():
	"""Update all tread positions to follow the carrier"""
	for tread in treads:
		if tread.has_method("update_position"):
			tread.update_position()

func apply_movement(delta):
	"""Apply movement based on current speed and direction"""
	if current_speed > 0:
		# Calculate movement vector - 0 degrees = forward (positive Z)
		var direction_rad = deg_to_rad(current_direction)
		var movement = Vector3(
			sin(direction_rad) * current_speed * delta,   # X movement
			0,
			-cos(direction_rad) * current_speed * delta   # Z movement (negative for forward)
		)
		
		# Apply movement directly to position
		global_position += movement

func set_speed(speed: float):
	"""Set the carrier speed"""
	current_speed = clamp(speed, 0, max_speed)

func set_direction(direction: float):
	"""Set the carrier direction in degrees"""
	current_direction = direction

func increase_speed(amount: float = 5.0):
	"""Increase speed by the specified amount"""
	current_speed = clamp(current_speed + amount, 0, max_speed)

func decrease_speed(amount: float = 5.0):
	"""Decrease speed by the specified amount"""
	current_speed = clamp(current_speed - amount, 0, max_speed)

func turn_left(amount: float = 30.0):
	"""Turn left by the specified amount in degrees"""
	current_direction -= amount

func turn_right(amount: float = 30.0):
	"""Turn right by the specified amount in degrees"""
	current_direction += amount

func get_speed() -> float:
	"""Get current speed"""
	return current_speed

func get_direction() -> float:
	"""Get current direction"""
	return current_direction

func get_elevator() -> Node3D:
	"""Return the elevator node"""
	if not elevator:
		elevator = find_child("Elevator")
	return elevator
