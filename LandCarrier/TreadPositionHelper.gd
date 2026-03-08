extends Node3D
class_name TreadPositionHelper

# =============================================================================
# TREAD POSITION HELPER
# =============================================================================
# This script helps you visually configure tread positions in the editor
# =============================================================================

@export var tread_positions: Array[Vector3] = []
@export var show_debug_spheres: bool = false
@export var sphere_radius: float = 1.0
@export var sphere_color: Color = Color.RED

var debug_spheres: Array[Node3D] = []

func _ready():
	if show_debug_spheres:
		create_debug_spheres()

func create_debug_spheres():
	"""Create visual spheres to show tread positions"""
	clear_debug_spheres()
	
	for i in range(tread_positions.size()):
		var pos = tread_positions[i]
		var sphere = create_debug_sphere(pos, "Tread_" + str(i))
		debug_spheres.append(sphere)

func create_debug_sphere(position: Vector3, name: String) -> Node3D:
	"""Create a debug sphere at the specified position"""
	var sphere = MeshInstance3D.new()
	sphere.name = name
	
	# Create a sphere mesh
	var sphere_mesh = SphereMesh.new()
	sphere_mesh.radius = sphere_radius
	sphere_mesh.height = sphere_radius * 2
	sphere.mesh = sphere_mesh
	
	# Create a material
	var material = StandardMaterial3D.new()
	material.albedo_color = sphere_color
	material.flags_transparent = true
	material.flags_unshaded = true
	material.no_depth_test = true
	sphere.material_override = material
	
	# Position the sphere
	sphere.position = position
	add_child(sphere)
	
	return sphere

func clear_debug_spheres():
	"""Remove all debug spheres"""
	for sphere in debug_spheres:
		if is_instance_valid(sphere):
			sphere.queue_free()
	debug_spheres.clear()

func add_tread_position(position: Vector3):
	"""Add a new tread position"""
	tread_positions.append(position)
	if show_debug_spheres:
		create_debug_spheres()

func remove_tread_position(index: int):
	"""Remove a tread position by index"""
	if index >= 0 and index < tread_positions.size():
		tread_positions.remove_at(index)
		if show_debug_spheres:
			create_debug_spheres()

func get_tread_positions() -> Array[Vector3]:
	"""Get all tread positions"""
	return tread_positions

func set_tread_positions(positions: Array[Vector3]):
	"""Set all tread positions"""
	tread_positions = positions
	if show_debug_spheres:
		create_debug_spheres()

func _input(event):
	"""Handle input for adding tread positions"""
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT and Input.is_key_pressed(KEY_CTRL):
			# Ctrl+Click to add tread position at mouse position
			var camera = get_viewport().get_camera_3d()
			if camera:
				var space_state = get_world_3d().direct_space_state
				var mouse_pos = get_viewport().get_mouse_position()
				var from = camera.project_ray_origin(mouse_pos)
				var to = from + camera.project_ray_normal(mouse_pos) * 1000
				var query = PhysicsRayQueryParameters3D.create(from, to)
				var result = space_state.intersect_ray(query)
				
				if result:
					var world_pos = result.position
					var local_pos = to_local(world_pos)
					add_tread_position(local_pos)
					print("Added tread position at: ", local_pos)
