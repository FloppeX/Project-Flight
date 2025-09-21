# Wheel.gd
# Individual wheel RigidBody3D with mesh and collision

extends RigidBody3D
class_name Wheel

@export var wheel_radius: float = 0.3
@export var wheel_width: float = 0.2

func _ready():
	# Set up physics properties
	mass = 5.0
	gravity_scale = 0.0  # Wheels don't fall due to gravity
	linear_damp = 0.0
	angular_damp = 0.0
	contact_monitor = true
	max_contacts_reported = 1
	
	# Lock rotation and freeze initially
	lock_rotation = true
	freeze = true
	
	# Create collision shape
	var collision_shape = CollisionShape3D.new()
	add_child(collision_shape)
	
	# Create cylinder shape for wheel
	var cylinder_shape = CylinderShape3D.new()
	cylinder_shape.height = wheel_width
	cylinder_shape.top_radius = wheel_radius
	cylinder_shape.bottom_radius = wheel_radius
	collision_shape.shape = cylinder_shape
	
	# Create visual mesh
	var mesh_instance = MeshInstance3D.new()
	add_child(mesh_instance)
	
	# Create cylinder mesh for visual
	var cylinder_mesh = CylinderMesh.new()
	cylinder_mesh.height = wheel_width
	cylinder_mesh.top_radius = wheel_radius
	cylinder_mesh.bottom_radius = wheel_radius
	cylinder_mesh.radial_segments = 8
	mesh_instance.mesh = cylinder_mesh
	
	# Rotate mesh to align with wheel orientation
	mesh_instance.rotation_degrees = Vector3(0, 0, 90)















