extends ProjectileNew
class_name Bullet

# Visual effects specific to bullets
@export var tracer_enabled: bool = true
@export var tracer_length: int = 8  # How many trail points
@export var tracer_color: Color = Color.YELLOW
@export var tracer_width: float = 0.1
@export var damage_amount: float = 10.0

var trail_points = []
var trail_mesh: MeshInstance3D
var immediate_mesh: ImmediateMesh

const SCORCH_TEXTURE_PATH: String = "res://Projectiles/Explosion/scorch_mark.png"

func _ready():
	# Call parent's _ready first to get all the base functionality
	super._ready()
	
	# This projectile should not create an explosion on impact
	creates_explosion = false
	# Set base damage lower than default ProjectileNew
	damage = damage_amount
	
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
		linear_velocity += firing_aircraft.linear_velocity

func _physics_process(delta):
	# Call parent's physics process first
	super._physics_process(delta)
	
	# Point projectile in direction of travel
	if linear_velocity.length() > 0.1:
		look_at(global_position + linear_velocity, Vector3.UP)
	
	# Update tracer trail
	if tracer_enabled:
		update_tracer_trail()

func _on_body_entered(body):
	# Create a small bullet mark decal at the impact point using the scorch texture
	_create_bullet_mark(body)
	# Then run default impact handling (damage, cleanup)
	super._on_body_entered(body)

func _create_bullet_mark(body: Object) -> void:
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var dir: Vector3 = linear_velocity.normalized()
	if dir == Vector3.ZERO:
		dir = Vector3.FORWARD
	# Cast a short ray through the impact point to recover the surface normal
	var from: Vector3 = global_position - dir * 1.0
	var to: Vector3 = global_position + dir * 0.5
	var params: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to)
	params.exclude = [self]
	if body:
		params.exclude.append(body)
	var hit: Dictionary = space_state.intersect_ray(params)
	var hit_pos: Vector3 = global_position
	var hit_normal: Vector3 = -dir
	if hit and hit.has("position") and hit.has("normal"):
		hit_pos = hit.position
		hit_normal = (hit.normal as Vector3).normalized()

	# Build decal aligned to the surface
	var decal: Decal = Decal.new()
	decal.texture_albedo = load(SCORCH_TEXTURE_PATH)
	# Small size for bullet mark
	decal.size = Vector3(0.5, 0.05, 0.5)
	# Offset slightly along normal to avoid z-fighting
	decal.global_position = hit_pos + hit_normal * 0.01
	
	# Create basis from normal (Y axis) and random yaw around it
	var y_axis: Vector3 = hit_normal
	var x_axis: Vector3 = y_axis.cross(Vector3.FORWARD)
	if x_axis.length() < 0.001:
		x_axis = y_axis.cross(Vector3.RIGHT)
	x_axis = x_axis.normalized()
	var z_axis: Vector3 = x_axis.cross(y_axis).normalized()
	var basis: Basis = Basis(x_axis, y_axis, z_axis)
	# Random rotate around normal for variation
	var random_yaw: float = randf() * TAU
	var rot: Basis = Basis(y_axis, random_yaw)
	decal.global_basis = rot * basis
	
	# Prefer to attach to the hit body if possible so the mark moves with it
	var parent_node: Node3D = null
	if body is Node3D:
		parent_node = body as Node3D
	if parent_node and is_instance_valid(parent_node):
		parent_node.add_child(decal)
	else:
		get_tree().current_scene.add_child(decal)

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
