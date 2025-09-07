extends ProjectileNew
class_name Bullet

# Visual effects specific to bullets
@export var tracer_enabled: bool = true
@export var tracer_length: int = 8  # How many trail points
@export var tracer_color: Color = Color.YELLOW
@export var tracer_width: float = 0.1

var trail_points = []
var trail_mesh: MeshInstance3D
var immediate_mesh: ImmediateMesh

func _ready():
	# Call parent's _ready first to get all the base functionality
	super._ready()
	
	# Add bullet-specific visual effects
	make_bullet_glowy()
	
	# Create tracer trail
	if tracer_enabled:
		create_tracer_trail()

func make_bullet_glowy():
	# Make bullet bigger and glowing
	if has_node("MeshInstance3D"):
		var mesh_node = get_node("MeshInstance3D")
		var material = StandardMaterial3D.new()
		material.flags_unshaded = true
		material.emission_enabled = true
		material.emission = tracer_color
		material.emission_energy = 3.0
		material.albedo_color = tracer_color
		mesh_node.material_override = material
		
		# Make bullet slightly bigger
		mesh_node.scale = Vector3(0.5, 0.5, 0.5)

func create_tracer_trail():
	trail_mesh = MeshInstance3D.new()
	add_child(trail_mesh)
	
	immediate_mesh = ImmediateMesh.new()
	trail_mesh.mesh = immediate_mesh
	
	var trail_material = StandardMaterial3D.new()
	trail_material.flags_unshaded = true
	trail_material.emission_enabled = true
	trail_material.emission = tracer_color
	trail_material.emission_energy = 2.0
	trail_material.vertex_color_use_as_albedo = true
	trail_material.flags_transparent = true
	trail_mesh.material_override = trail_material

func fire(initial_velocity: Vector3, firing_aircraft: Node3D):
	# Call parent's fire method to get all the base functionality
	super.fire(initial_velocity, firing_aircraft)
	
	# Add some aircraft velocity inheritance for more realistic ballistics
	if firing_aircraft and firing_aircraft.has_method("get_linear_velocity"):
		linear_velocity += firing_aircraft.linear_velocity * 0.3

func _physics_process(delta):
	# Call parent's physics process first
	super._physics_process(delta)
	
	# Point projectile in direction of travel
	if linear_velocity.length() > 0.1:
		look_at(global_position + linear_velocity, Vector3.UP)
	
	# Update tracer trail
	if tracer_enabled:
		update_tracer_trail()

func update_tracer_trail():
	# Add current position to trail
	trail_points.append(global_position)
	if trail_points.size() > tracer_length:
		trail_points.pop_front()
	
	# Draw the trail
	if trail_points.size() > 1:
		immediate_mesh.clear_surfaces()
		immediate_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
		
		for i in range(trail_points.size()):
			var alpha = float(i) / float(trail_points.size())  # Fade out toward tail
			var color = Color(tracer_color.r, tracer_color.g, tracer_color.b, alpha)
			
			# Create a simple line with width
			var pos = to_local(trail_points[i])
			immediate_mesh.surface_set_color(color)
			immediate_mesh.surface_add_vertex(pos + Vector3(tracer_width, 0, 0))
			immediate_mesh.surface_set_color(color)
			immediate_mesh.surface_add_vertex(pos - Vector3(tracer_width, 0, 0))
		
		immediate_mesh.surface_end()

# _on_timeout is handled by the parent class now
