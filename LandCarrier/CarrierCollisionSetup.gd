extends Node3D
class_name CarrierCollisionSetup

# =============================================================================
# CARRIER COLLISION SETUP
# =============================================================================
# Sets up proper collision shapes for the land carrier
# =============================================================================

#func _ready():
	#setup_collision_shapes()

func setup_collision_shapes():
	"""Set up collision shapes for the carrier"""
	print("Setting up carrier collision shapes...")
	
	# Set up main body collision
	setup_main_collision()
	
	# Set up tread collisions
	setup_tread_collisions()
	
	print("Collision setup complete")

func setup_main_collision():
	"""Set up the main body collision shape"""
	var main_collision = get_node("MainCollision")
	if main_collision:
		var box_shape = BoxShape3D.new()
		box_shape.size = Vector3(20, 6, 30)  # Match the transform
		main_collision.shape = box_shape
		print("Main collision shape set up")

func setup_tread_collisions():
	"""Set up collision shapes for each tread"""
	var tread_collisions = get_node("TreadCollisions")
	if not tread_collisions:
		print("No TreadCollisions node found")
		return
	
	# Create a smaller, more stable tread collision shape
	var tread_shape = BoxShape3D.new()
	tread_shape.size = Vector3(1, 0.5, 2)  # Smaller, more stable shape
	
	# Apply to all tread collision nodes
	for child in tread_collisions.get_children():
		if child is CollisionShape3D:
			child.shape = tread_shape
			print("Set up collision for tread: ", child.name)
