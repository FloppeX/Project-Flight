extends ProjectileNew
class_name Bullet

# Visual effects specific to bullets
@export var tracer_enabled: bool = true
@export var tracer_color: Color = Color.YELLOW
@export var tracer_width: float = 0.1
@export var tracer_visual_length: float = 8.0
@export var tracer_hidden_physics_frames: int = 2
@export var damage_amount: float = 10.0
@export var ground_mark_lifetime_s: float = 12.0
@export var ground_mark_size: Vector3 = Vector3(0.56, 0.05, 0.56)
@export var ground_particle_count: int = 3
@export var ground_particle_lifetime_s: float = 0.75
@export var hit_debris_count: int = 4
@export var hit_debris_lifetime_s: float = 0.6

var trail_mesh: MeshInstance3D
var tracer_box_mesh: BoxMesh
var tracer_physics_frames_elapsed: int = 0

const SCORCH_TEXTURE_PATH: String = "res://Projectiles/Explosion/scorch_mark.png"

func _ready():
	hit_assist_enabled = true
	# Call parent's _ready first to get all the base functionality
	super._ready()

	# Ballistic predictors assume bullets keep their muzzle speed except for gravity.
	# Override project/world damping so rigid-body drag does not pull shots low/short.
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.0
	angular_damp = 0.0

	# Keep bullets as real rigid bodies for flight/gravity, but avoid physical shove-on-contact.
	# Impact resolution already comes from ProjectileNew's raycast path.
	collision_layer = 0
	collision_mask = 0
	# Bullet impacts are resolved by ProjectileNew's raycast path, so we do not need
	# rigid-body contact reporting for every round.
	contact_monitor = false
	max_contacts_reported = 0
	if body_entered.is_connected(_on_body_entered):
		body_entered.disconnect(_on_body_entered)
	
	# This projectile should not create an explosion on impact
	creates_explosion = false
	# Set base damage lower than default ProjectileNew
	damage = damage_amount
	
	# Add bullet-specific visual effects
	make_bullet_glowy()
	
	# Create tracer trail
	if tracer_enabled:
		create_tracer_mesh()

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

func create_tracer_mesh():
	trail_mesh = MeshInstance3D.new()
	add_child(trail_mesh)

	tracer_box_mesh = BoxMesh.new()
	tracer_box_mesh.size = Vector3(tracer_width, tracer_width, tracer_visual_length)
	trail_mesh.mesh = tracer_box_mesh
	
	var trail_material = StandardMaterial3D.new()
	trail_material.flags_unshaded = true
	trail_material.emission_enabled = true
	trail_material.emission = tracer_color
	trail_material.emission_energy = 2.0
	trail_material.flags_transparent = true
	trail_material.albedo_color = tracer_color
	trail_mesh.material_override = trail_material
	trail_mesh.position = Vector3(0.0, 0.0, tracer_visual_length * 0.5)

func fire(initial_velocity: Vector3, firing_aircraft: Node3D):
	# Call parent's fire method to get all the base functionality
	super.fire(initial_velocity, firing_aircraft)
	tracer_physics_frames_elapsed = 0
	
	# Inherit the firing platform's point velocity at the muzzle so rounds stay
	# aligned with the gun line during hard turns and rolls.
	if not firing_aircraft or not is_instance_valid(firing_aircraft):
		return

	var inherited_velocity = firing_aircraft.get("linear_velocity")
	if inherited_velocity is Vector3:
		linear_velocity += inherited_velocity
	elif firing_aircraft.get("velocity") is Vector3:
		linear_velocity += firing_aircraft.get("velocity")
	elif firing_aircraft.has_method("get_linear_velocity"):
		var getter_velocity = firing_aircraft.call("get_linear_velocity")
		if getter_velocity is Vector3:
			linear_velocity += getter_velocity

	var angular_velocity = firing_aircraft.get("angular_velocity")
	if angular_velocity is Vector3 and firing_aircraft is Node3D:
		var r_offset: Vector3 = global_position - (firing_aircraft as Node3D).global_position
		linear_velocity += (angular_velocity as Vector3).cross(r_offset)

func _physics_process(delta):
	# Call parent's physics process first
	super._physics_process(delta)
	
	# Point projectile in direction of travel
	if linear_velocity.length() > 0.1:
		look_at(global_position + linear_velocity, Vector3.UP)
	
	# Update tracer trail
	if tracer_enabled:
		update_tracer_mesh()
	tracer_physics_frames_elapsed += 1

func _on_body_entered(body):
	if is_ground_or_terrain(body):
		_create_ground_bullet_mark(body)
		_spawn_ground_impact_particles(body)
	else:
		_spawn_aircraft_hit_debris(body)
	# Then run default impact handling (damage, cleanup)
	super._on_body_entered(body)

func _resolve_impact_surface(body: Object) -> Dictionary:
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var dir: Vector3 = linear_velocity.normalized()
	if dir == Vector3.ZERO:
		dir = Vector3.FORWARD
	# Cast a short ray through the impact point to recover the surface normal
	var from: Vector3 = global_position - dir * 1.0
	var to: Vector3 = global_position + dir * 0.5
	var params: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to)
	params.exclude = [self]
	if shooter and is_instance_valid(shooter):
		params.exclude.append(shooter)
	var hit: Dictionary = space_state.intersect_ray(params)
	var hit_pos: Vector3 = global_position
	var hit_normal: Vector3 = -dir
	if hit and hit.has("position") and hit.has("normal"):
		hit_pos = hit.position
		hit_normal = (hit.normal as Vector3).normalized()

	var parent_node: Node3D = null
	if body is Node3D:
		parent_node = body as Node3D

	return {
		"position": hit_pos,
		"normal": hit_normal,
		"parent_node": parent_node,
	}

func _create_ground_bullet_mark(body: Object) -> void:
	var impact: Dictionary = _resolve_impact_surface(body)
	var hit_pos: Vector3 = impact.get("position", global_position)
	var hit_normal: Vector3 = impact.get("normal", Vector3.UP)
	var parent_node: Node3D = impact.get("parent_node", null)

	# Build decal aligned to the surface
	var decal: Decal = Decal.new()
	decal.texture_albedo = load(SCORCH_TEXTURE_PATH)
	decal.size = ground_mark_size
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
	decal.modulate = Color(0.17, 0.15, 0.13, 0.95)
	
	if parent_node and is_instance_valid(parent_node):
		parent_node.add_child(decal)
	else:
		get_tree().current_scene.add_child(decal)

	if ground_mark_lifetime_s > 0.0:
		get_tree().create_timer(ground_mark_lifetime_s).timeout.connect(func():
			if is_instance_valid(decal):
				decal.queue_free()
		)

func _spawn_ground_impact_particles(body: Object) -> void:
	var count: int = max(ground_particle_count, 0)
	if count <= 0:
		return
	var impact: Dictionary = _resolve_impact_surface(body)
	var hit_pos: Vector3 = impact.get("position", global_position)
	var hit_normal: Vector3 = impact.get("normal", Vector3.UP)
	if not ParticleManager:
		return

	for i in range(count):
		var chip := MeshInstance3D.new()
		get_tree().current_scene.add_child(chip)
		chip.global_position = hit_pos + hit_normal * 0.03

		var rock_mesh := BoxMesh.new()
		var size: float = randf_range(0.10, 0.24)
		rock_mesh.size = Vector3(size, size, size)
		chip.mesh = rock_mesh

		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.44, 0.34, 0.22, 1.0)
		mat.roughness = 1.0
		mat.flags_unshaded = false
		chip.material_override = mat

		var lateral_dir := Vector3(
			randf_range(-1.0, 1.0),
			randf_range(0.5, 1.2),
			randf_range(-1.0, 1.0)
		).normalized()
		var launch_velocity: Vector3 = (hit_normal * randf_range(1.5, 3.0) + lateral_dir * randf_range(1.0, 3.0)).normalized() * randf_range(3.0, 8.0)
		ParticleManager.add_spark_particle(
			chip,
			ground_particle_lifetime_s,
			Vector3.ONE,
			launch_velocity
		)


func _spawn_aircraft_hit_debris(_body: Object) -> void:
	if hit_debris_count <= 0 or not ParticleManager:
		return
	var hit_pos: Vector3 = global_position
	var hit_dir: Vector3 = linear_velocity.normalized() if linear_velocity.length() > 0.1 else Vector3.BACK
	for i in range(hit_debris_count):
		var chip := MeshInstance3D.new()
		get_tree().current_scene.add_child(chip)
		chip.global_position = hit_pos

		var box := BoxMesh.new()
		var s: float = randf_range(0.06, 0.18)
		box.size = Vector3(s, s * randf_range(0.4, 1.0), s * randf_range(0.6, 1.6))
		chip.mesh = box

		var mat := StandardMaterial3D.new()
		# Mix of bare metal grey and a touch of warm orange for hot fragments
		var grey: float = randf_range(0.35, 0.65)
		mat.albedo_color = Color(grey + randf_range(0.0, 0.15), grey, grey * randf_range(0.7, 1.0), 1.0)
		mat.roughness = 0.6
		mat.metallic = 0.7
		chip.material_override = mat

		# Scatter mostly away from the bullet direction, with some upward bias
		var scatter := Vector3(
			randf_range(-1.0, 1.0),
			randf_range(0.2, 1.0),
			randf_range(-1.0, 1.0)
		).normalized()
		var speed: float = randf_range(4.0, 10.0)
		var launch: Vector3 = (hit_dir * randf_range(0.2, 0.6) + scatter).normalized() * speed
		ParticleManager.add_spark_particle(chip, hit_debris_lifetime_s, Vector3.ONE, launch)

func update_tracer_mesh() -> void:
	if trail_mesh == null or tracer_box_mesh == null:
		return
	if _should_hide_tracer_for_startup_frames():
		trail_mesh.visible = false
		return
	trail_mesh.visible = true
	var speed: float = linear_velocity.length()
	var visual_length: float = maxf(tracer_visual_length, speed * 0.01)
	tracer_box_mesh.size = Vector3(tracer_width, tracer_width, visual_length)
	# Node3D.look_at points local -Z toward travel, so place the tracer behind the bullet on +Z.
	trail_mesh.position = Vector3(0.0, 0.0, visual_length * 0.5)

func _should_hide_tracer_for_startup_frames() -> bool:
	return tracer_physics_frames_elapsed < max(tracer_hidden_physics_frames, 0)

# _on_timeout is handled by the parent class now
