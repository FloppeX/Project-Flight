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
@export var use_manual_ballistics: bool = true
@export var bullet_body_visual_enabled: bool = false
@export var visual_lod_enabled: bool = true
@export var full_tracer_distance_m: float = 600.0
@export var max_tracer_distance_m: float = 1500.0
@export var distant_tracer_stride: int = 4
@export var visual_policy_interval_s: float = 0.10
@export var distant_hit_assist_interval_s: float = 0.09
@export var hidden_hit_assist_interval_s: float = 0.12

var trail_mesh: MeshInstance3D
var tracer_box_mesh: BoxMesh
var tracer_physics_frames_elapsed: int = 0
var _debug_target_node: Node3D = null
var _debug_target_radius_m: float = 0.0
var _debug_closest_center_distance_m: float = INF
var _debug_closest_offset_m: Vector3 = Vector3.ZERO
var _debug_report_sent: bool = false
var _debug_age_s: float = 0.0
var _debug_distance_traveled_m: float = 0.0
var _debug_speed_time_integral: float = 0.0
var _debug_initial_speed_mps: float = 0.0
var _debug_closest_time_s: float = 0.0
var _debug_peak_speed_mps: float = 0.0
var _debug_tracking_enabled: bool = false
var _visual_policy_accum_s: float = 0.0
var _visual_allowed: bool = true
var _visual_is_distant: bool = false
var _visual_sample_selected: bool = true
var _visual_distance_m: float = 0.0

const SCORCH_TEXTURE_PATH: String = "res://Projectiles/Explosion/scorch_mark.png"
static var _tracer_mesh_cache: Dictionary = {}
static var _tracer_material_cache: Dictionary = {}
static var _bullet_material_cache: Dictionary = {}
static var _activation_counter: int = 0

func _ready():
	reusable_lifecycle = true
	hit_assist_enabled = true
	# The segment ray remains authoritative. Hit assist is only a forgiving
	# secondary query, so its broadphase can be much tighter than the old 20 m.
	hit_assist_broadphase_extra_radius_m = 6.0
	hit_assist_broadphase_max_results = mini(hit_assist_broadphase_max_results, 16)
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
	if use_manual_ballistics:
		freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
		freeze = true
	
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
		var mesh_node: MeshInstance3D = get_node("MeshInstance3D") as MeshInstance3D
		mesh_node.visible = bullet_body_visual_enabled
		mesh_node.material_override = _get_cached_bullet_material()
		
		# Make bullet slightly bigger
		mesh_node.scale = Vector3(0.5, 0.5, 0.5)

func create_tracer_mesh():
	trail_mesh = MeshInstance3D.new()
	add_child(trail_mesh)

	tracer_box_mesh = _get_cached_tracer_mesh()
	trail_mesh.mesh = tracer_box_mesh
	trail_mesh.material_override = _get_cached_tracer_material()
	trail_mesh.position = Vector3(0.0, 0.0, tracer_visual_length * 0.5)

func _get_cached_bullet_material() -> StandardMaterial3D:
	var key: String = _color_cache_key(tracer_color)
	var cached_variant: Variant = _bullet_material_cache.get(key, null)
	if cached_variant is StandardMaterial3D:
		return cached_variant as StandardMaterial3D
	var material := StandardMaterial3D.new()
	material.flags_unshaded = true
	material.emission_enabled = true
	material.emission = tracer_color
	material.emission_energy = 3.0
	material.albedo_color = tracer_color
	_bullet_material_cache[key] = material
	return material

func _get_cached_tracer_mesh() -> BoxMesh:
	var key: String = "%.3f|%.3f" % [tracer_width, tracer_visual_length]
	var cached_variant: Variant = _tracer_mesh_cache.get(key, null)
	if cached_variant is BoxMesh:
		return cached_variant as BoxMesh
	var mesh := BoxMesh.new()
	mesh.size = Vector3(tracer_width, tracer_width, tracer_visual_length)
	_tracer_mesh_cache[key] = mesh
	return mesh

func _get_cached_tracer_material() -> StandardMaterial3D:
	var key: String = _color_cache_key(tracer_color)
	var cached_variant: Variant = _tracer_material_cache.get(key, null)
	if cached_variant is StandardMaterial3D:
		return cached_variant as StandardMaterial3D
	var material := StandardMaterial3D.new()
	material.flags_unshaded = true
	material.emission_enabled = true
	material.emission = tracer_color
	material.emission_energy = 2.0
	material.flags_transparent = true
	material.albedo_color = tracer_color
	_tracer_material_cache[key] = material
	return material

func _color_cache_key(color: Color) -> String:
	return "%.3f|%.3f|%.3f|%.3f" % [color.r, color.g, color.b, color.a]

func fire(initial_velocity: Vector3, firing_aircraft: Node3D):
	# Call parent's fire method to get all the base functionality
	super.fire(initial_velocity, firing_aircraft)
	if use_manual_ballistics:
		freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
		freeze = true
	tracer_physics_frames_elapsed = 0
	_activation_counter += 1
	_visual_sample_selected = distant_tracer_stride <= 1 or (_activation_counter % distant_tracer_stride) == 0
	_visual_policy_accum_s = visual_policy_interval_s
	_refresh_visual_policy(0.0, true)
	var assist_interval_s: float = maxf(_get_hit_assist_check_interval_s(), 0.001)
	# Spread optional broadphase work across physics frames. The per-frame segment
	# ray still runs for every bullet, so this does not defer real collider hits.
	_hit_assist_time_accum_s = -fmod(float(_activation_counter) * 0.61803398875, 1.0) * assist_interval_s
	_setup_debug_target_tracking()
	
	# Inherit the firing platform's point velocity at the muzzle so rounds stay
	# aligned with the gun line during hard turns and rolls.
	if not firing_aircraft or not is_instance_valid(firing_aircraft):
		return

	linear_velocity += _get_motion_velocity(firing_aircraft)

	var angular_velocity: Vector3 = _get_motion_angular_velocity(firing_aircraft)
	if angular_velocity.length_squared() > 0.000001 and firing_aircraft is Node3D:
		var r_offset: Vector3 = global_position - (firing_aircraft as Node3D).global_position
		linear_velocity += angular_velocity.cross(r_offset)
	_debug_initial_speed_mps = linear_velocity.length()
	_debug_peak_speed_mps = _debug_initial_speed_mps

func _get_motion_velocity(node: Node) -> Vector3:
	if node == null or not is_instance_valid(node):
		return Vector3.ZERO
	var linear_variant: Variant = node.get("linear_velocity")
	if linear_variant is Vector3:
		return linear_variant
	var velocity_variant: Variant = node.get("velocity")
	if velocity_variant is Vector3:
		return velocity_variant
	if node.has_method("get_linear_velocity"):
		var getter_velocity_variant: Variant = node.call("get_linear_velocity")
		if getter_velocity_variant is Vector3:
			return getter_velocity_variant
	if node.has_method("get_velocity_vector"):
		var vector_velocity_variant: Variant = node.call("get_velocity_vector")
		if vector_velocity_variant is Vector3:
			return vector_velocity_variant
	return Vector3.ZERO

func _get_motion_angular_velocity(node: Node) -> Vector3:
	if node == null or not is_instance_valid(node):
		return Vector3.ZERO
	var angular_variant: Variant = node.get("angular_velocity")
	if angular_variant is Vector3:
		return angular_variant
	if node.has_method("get_angular_velocity"):
		var getter_angular_variant: Variant = node.call("get_angular_velocity")
		if getter_angular_variant is Vector3:
			return getter_angular_variant
	return Vector3.ZERO

func _physics_process(delta):
	var prev_pos: Vector3 = global_position
	if use_manual_ballistics and not has_impacted:
		_apply_manual_ballistics(delta)
	# Call parent's physics process first
	super._physics_process(delta)
	if has_impacted:
		return
	if _debug_tracking_enabled:
		_debug_age_s += delta
		var speed_now_mps: float = linear_velocity.length()
		_debug_distance_traveled_m += speed_now_mps * delta
		_debug_speed_time_integral += speed_now_mps * delta
		_debug_peak_speed_mps = maxf(_debug_peak_speed_mps, speed_now_mps)
		if (_debug_target_node == null or not is_instance_valid(_debug_target_node)):
			_try_acquire_debug_target_from_meta()
		_update_debug_closest_center_distance(prev_pos, global_position)
	
	_refresh_visual_policy(delta)
	# Orientation only matters when a bullet visual is actually being rendered.
	if _visual_allowed and linear_velocity.length() > 0.1:
		look_at(global_position + linear_velocity, Vector3.UP)
	
	# Update tracer trail
	if tracer_enabled:
		update_tracer_mesh()
	tracer_physics_frames_elapsed += 1

func _apply_manual_ballistics(delta: float) -> void:
	var gravity: Vector3 = ProjectSettings.get_setting("physics/3d/default_gravity_vector", Vector3(0.0, -1.0, 0.0))
	var gravity_magnitude: float = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	var gravity_vec: Vector3 = gravity.normalized() * gravity_magnitude * gravity_scale
	global_position += linear_velocity * delta + 0.5 * gravity_vec * delta * delta
	linear_velocity += gravity_vec * delta

func _on_body_entered(body):
	if has_impacted or is_shooter_body(body):
		return
	_emit_debug_report("impact", body)
	if is_ground_or_terrain(body):
		_create_ground_bullet_mark(body)
		_spawn_ground_impact_particles(body)
	else:
		_spawn_aircraft_hit_debris(body)
	# Then run default impact handling (damage, cleanup)
	super._on_body_entered(body)

func _on_timeout() -> void:
	_emit_debug_report("timeout", null)
	super._on_timeout()

func _retire_projectile() -> void:
	var pool: Node = get_node_or_null("/root/BulletPool")
	if pool and pool.has_method("release"):
		pool.call("release", self)
	else:
		queue_free()

func prepare_for_pool() -> void:
	_activation_serial += 1
	has_impacted = true
	set_physics_process(false)
	freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	freeze = true
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	if shooter and is_instance_valid(shooter) and shooter is CollisionObject3D:
		remove_collision_exception_with(shooter as CollisionObject3D)
	shooter = null
	visible = false
	if trail_mesh:
		trail_mesh.visible = false
	for meta_key in [&"debug_target_node", &"debug_report_callback", &"debug_nominal_flight_time_s", &"debug_nominal_bullet_speed_mps"]:
		if has_meta(meta_key):
			remove_meta(meta_key)
	_debug_tracking_enabled = false

func prepare_for_reuse() -> void:
	_activation_serial += 1
	has_impacted = false
	_lifetime_elapsed_s = 0.0
	visible = true
	freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	freeze = true
	sleeping = false
	set_physics_process(true)
	_visual_policy_accum_s = visual_policy_interval_s
	if has_node("MeshInstance3D"):
		(get_node("MeshInstance3D") as MeshInstance3D).visible = bullet_body_visual_enabled
	if trail_mesh:
		trail_mesh.visible = false

func _get_hit_assist_check_interval_s() -> float:
	if not visual_lod_enabled:
		return hit_assist_check_interval_s
	if not _visual_allowed:
		return hidden_hit_assist_interval_s
	if _visual_is_distant:
		return distant_hit_assist_interval_s
	return hit_assist_check_interval_s

func _refresh_visual_policy(delta: float, force: bool = false) -> void:
	if not visual_lod_enabled:
		_visual_allowed = true
		_visual_is_distant = false
		return
	_visual_policy_accum_s += delta
	if not force and _visual_policy_accum_s < maxf(visual_policy_interval_s, 0.01):
		return
	_visual_policy_accum_s = 0.0
	var viewport := get_viewport()
	var camera: Camera3D = viewport.get_camera_3d() if viewport else null
	if camera == null or not is_instance_valid(camera):
		_visual_allowed = true
		_visual_is_distant = false
		return
	_visual_distance_m = camera.global_position.distance_to(global_position)
	_visual_is_distant = _visual_distance_m > full_tracer_distance_m
	_visual_allowed = (max_tracer_distance_m <= 0.0 or _visual_distance_m <= max_tracer_distance_m) \
		and camera.is_position_in_frustum(global_position) \
		and (not _visual_is_distant or _visual_sample_selected)

func _resolve_impact_surface(body: Object) -> Dictionary:
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var dir: Vector3 = linear_velocity.normalized()
	if dir == Vector3.ZERO:
		dir = Vector3.FORWARD
	# Cast a short ray through the impact point to recover the surface normal
	var from: Vector3 = global_position - dir * 1.0
	var to: Vector3 = global_position + dir * 0.5
	var params: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to)
	params.exclude = _get_projectile_query_excludes()
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
	var impact_budget: Node = get_node_or_null("/root/BulletImpactBudget")
	if impact_budget and not bool(impact_budget.call("should_spawn_visual", hit_pos)):
		return
	var hit_normal: Vector3 = impact.get("normal", Vector3.UP)
	var parent_node: Node3D = impact.get("parent_node", null)

	# Build decal aligned to the surface. Transient marks use the global pool.
	var decal_parent: Node = parent_node if parent_node and is_instance_valid(parent_node) else get_tree().current_scene
	var decal: Decal = impact_budget.call("acquire_decal", decal_parent) as Decal if impact_budget else Decal.new()
	decal.texture_albedo = _scorch_texture if _scorch_texture != null else load(SCORCH_TEXTURE_PATH)
	decal.size = ground_mark_size
	decal.sorting_offset = 20.0
	if impact_budget == null:
		decal_parent.add_child(decal)
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
	
	if impact_budget:
		impact_budget.call("register_decal", decal, ground_mark_lifetime_s)
	elif ground_mark_lifetime_s > 0.0:
		var decal_ref: WeakRef = weakref(decal)
		get_tree().create_timer(ground_mark_lifetime_s).timeout.connect(func() -> void:
			var decal_obj: Object = decal_ref.get_ref()
			if decal_obj is Node and is_instance_valid(decal_obj):
				(decal_obj as Node).queue_free()
		)

func _spawn_ground_impact_particles(body: Object) -> void:
	var count: int = max(ground_particle_count, 0)
	if count <= 0:
		return
	var impact: Dictionary = _resolve_impact_surface(body)
	var hit_pos: Vector3 = impact.get("position", global_position)
	var hit_normal: Vector3 = impact.get("normal", Vector3.UP)
	if get_node_or_null("/root/BulletImpactBudget") == null:
		return

	for i in range(count):
		var size: float = randf_range(0.10, 0.24)
		var lateral_dir := Vector3(
			randf_range(-1.0, 1.0),
			randf_range(0.5, 1.2),
			randf_range(-1.0, 1.0)
		).normalized()
		var launch_velocity: Vector3 = (hit_normal * randf_range(1.5, 3.0) + lateral_dir * randf_range(1.0, 3.0)).normalized() * randf_range(3.0, 8.0)
		var impact_budget: Node = get_node_or_null("/root/BulletImpactBudget")
		if impact_budget:
			impact_budget.call("spawn_debris",
			hit_pos + hit_normal * 0.03,
			Vector3(size, size, size),
			Color(0.44, 0.34, 0.22, 1.0),
			0.0,
			1.0,
			launch_velocity,
			ground_particle_lifetime_s)


func _spawn_aircraft_hit_debris(_body: Object) -> void:
	if hit_debris_count <= 0 or get_node_or_null("/root/BulletImpactBudget") == null:
		return
	var hit_pos: Vector3 = global_position
	var hit_dir: Vector3 = linear_velocity.normalized() if linear_velocity.length() > 0.1 else Vector3.BACK
	for i in range(hit_debris_count):
		var s: float = randf_range(0.06, 0.18)
		# Mix of bare metal grey and a touch of warm orange for hot fragments
		var grey: float = randf_range(0.35, 0.65)
		# Scatter mostly away from the bullet direction, with some upward bias
		var scatter := Vector3(
			randf_range(-1.0, 1.0),
			randf_range(0.2, 1.0),
			randf_range(-1.0, 1.0)
		).normalized()
		var speed: float = randf_range(4.0, 10.0)
		var launch: Vector3 = (hit_dir * randf_range(0.2, 0.6) + scatter).normalized() * speed
		var impact_budget: Node = get_node_or_null("/root/BulletImpactBudget")
		if impact_budget:
			impact_budget.call("spawn_debris",
			hit_pos,
			Vector3(s, s * randf_range(0.4, 1.0), s * randf_range(0.6, 1.6)),
			Color(grey + randf_range(0.0, 0.15), grey, grey * randf_range(0.7, 1.0), 1.0),
			0.7,
			0.6,
			launch,
			hit_debris_lifetime_s)

func update_tracer_mesh() -> void:
	if trail_mesh == null or tracer_box_mesh == null:
		return
	if not _visual_allowed or _should_hide_tracer_for_startup_frames():
		trail_mesh.visible = false
		return
	trail_mesh.visible = true
	# Keep tracer geometry static to avoid per-frame mesh updates for high bullet counts.
	# Node3D.look_at points local -Z toward travel, so place the tracer behind the bullet on +Z.
	trail_mesh.position = Vector3(0.0, 0.0, tracer_visual_length * 0.5)

func _should_hide_tracer_for_startup_frames() -> bool:
	return tracer_physics_frames_elapsed < max(tracer_hidden_physics_frames, 0)

func _setup_debug_target_tracking() -> void:
	_debug_target_node = null
	_debug_target_radius_m = 0.0
	_debug_closest_center_distance_m = INF
	_debug_closest_offset_m = Vector3.ZERO
	_debug_report_sent = false
	_debug_age_s = 0.0
	_debug_distance_traveled_m = 0.0
	_debug_speed_time_integral = 0.0
	_debug_initial_speed_mps = linear_velocity.length()
	_debug_closest_time_s = 0.0
	_debug_peak_speed_mps = _debug_initial_speed_mps
	_debug_tracking_enabled = has_meta("debug_report_callback") or has_meta("debug_target_node")
	if not _debug_tracking_enabled:
		return
	_try_acquire_debug_target_from_meta()

func _try_acquire_debug_target_from_meta() -> void:
	if _debug_target_node != null and is_instance_valid(_debug_target_node):
		return
	if not has_meta("debug_target_node"):
		return

	var target_variant: Variant = get_meta("debug_target_node")
	if typeof(target_variant) != TYPE_OBJECT:
		return
	# Important: do not cast before validity checks. Casting a freed object throws.
	if not is_instance_valid(target_variant):
		return
	if not (target_variant is Node3D):
		return
	var target_node: Node3D = target_variant as Node3D
	_debug_target_node = target_node
	_debug_target_radius_m = _estimate_debug_target_radius(target_node)
	_update_debug_closest_center_distance(global_position, global_position)

func _update_debug_closest_center_distance(seg_start: Vector3, seg_end: Vector3) -> void:
	if _debug_target_node == null or not is_instance_valid(_debug_target_node):
		return
	var target_point: Vector3 = _get_debug_target_point(_debug_target_node)
	var closest_point: Vector3 = _closest_point_on_segment(target_point, seg_start, seg_end)
	var center_distance: float = target_point.distance_to(closest_point)
	if center_distance < _debug_closest_center_distance_m:
		_debug_closest_center_distance_m = center_distance
		_debug_closest_offset_m = target_point - closest_point
		_debug_closest_time_s = _debug_age_s

func _emit_debug_report(reason: String, impact_body: Object) -> void:
	if _debug_report_sent:
		return
	_debug_report_sent = true

	var callback_variant: Variant = get_meta("debug_report_callback", Callable())
	if not (callback_variant is Callable):
		return
	var callback: Callable = callback_variant
	if not callback.is_valid():
		return

	var closest_center_m: float = _debug_closest_center_distance_m
	if not is_finite(closest_center_m):
		if _debug_target_node != null and is_instance_valid(_debug_target_node):
			closest_center_m = _get_debug_target_point(_debug_target_node).distance_to(global_position)
		else:
			closest_center_m = INF

	var closest_edge_m: float = maxf(closest_center_m - _debug_target_radius_m, 0.0)
	var hit_target: bool = _did_hit_debug_target(impact_body)
	var target_name: String = _debug_target_node.name if _debug_target_node != null and is_instance_valid(_debug_target_node) else "<none>"
	var impact_body_name: String = "<none>"
	if impact_body is Node and is_instance_valid(impact_body):
		impact_body_name = String((impact_body as Node).name)
	var nominal_speed_variant: Variant = get_meta("debug_nominal_bullet_speed_mps", -1.0)
	var nominal_speed_mps: float = float(nominal_speed_variant)
	var nominal_flight_time_variant: Variant = get_meta("debug_nominal_flight_time_s", -1.0)
	var nominal_flight_time_s: float = float(nominal_flight_time_variant)
	var max_linear_velocity_variant: Variant = get("max_linear_velocity")
	var max_linear_velocity_mps: float = float(max_linear_velocity_variant) if typeof(max_linear_velocity_variant) in [TYPE_FLOAT, TYPE_INT] else -1.0
	var avg_speed_mps: float = _debug_distance_traveled_m / maxf(_debug_age_s, 0.0001)
	var integrated_avg_speed_mps: float = _debug_speed_time_integral / maxf(_debug_age_s, 0.0001)
	var speed_now_mps: float = linear_velocity.length()
	var report: Dictionary = {
		"target_name": target_name,
		"closest_center_m": closest_center_m,
		"closest_edge_m": closest_edge_m,
		"closest_offset_x_m": _debug_closest_offset_m.x,
		"closest_offset_y_m": _debug_closest_offset_m.y,
		"closest_offset_z_m": _debug_closest_offset_m.z,
		"target_radius_m": _debug_target_radius_m,
		"hit_target": hit_target,
		"reason": reason,
		"impact_body_name": impact_body_name,
		"bullet_age_s": _debug_age_s,
		"closest_time_s": _debug_closest_time_s,
		"bullet_initial_speed_mps": _debug_initial_speed_mps,
		"bullet_avg_speed_mps": avg_speed_mps,
		"bullet_avg_speed_integrated_mps": integrated_avg_speed_mps,
		"bullet_nominal_speed_mps": nominal_speed_mps,
		"bullet_nominal_flight_time_s": nominal_flight_time_s,
		"bullet_distance_traveled_m": _debug_distance_traveled_m,
		"bullet_speed_now_mps": speed_now_mps,
		"bullet_speed_peak_mps": _debug_peak_speed_mps,
		"bullet_max_linear_velocity_mps": max_linear_velocity_mps,
	}
	callback.call(report)

func _did_hit_debug_target(impact_body: Object) -> bool:
	if _debug_target_node == null or not is_instance_valid(_debug_target_node):
		return false
	if impact_body == null:
		return false
	if impact_body == _debug_target_node:
		return true
	if impact_body is Node:
		var node: Node = impact_body as Node
		while node:
			if node == _debug_target_node:
				return true
			node = node.get_parent()
	return false

func _get_debug_target_point(target: Node3D) -> Vector3:
	if target == null or not is_instance_valid(target):
		return global_position
	var collision_shape: CollisionShape3D = _find_first_collision_shape(target)
	if collision_shape != null and is_instance_valid(collision_shape):
		return collision_shape.global_position
	return target.global_position

func _estimate_debug_target_radius(target: Node3D) -> float:
	var radius_m: float = 2.5
	if target == null or not is_instance_valid(target):
		return radius_m
	var collision_shape: CollisionShape3D = _find_first_collision_shape(target)
	if collision_shape == null or not is_instance_valid(collision_shape) or collision_shape.shape == null:
		return radius_m

	var shape_scale: Vector3 = collision_shape.global_transform.basis.get_scale().abs()
	var max_scale: float = maxf(maxf(shape_scale.x, shape_scale.y), shape_scale.z)
	var shape: Shape3D = collision_shape.shape
	if shape is SphereShape3D:
		radius_m = maxf(radius_m, (shape as SphereShape3D).radius * max_scale)
	elif shape is CapsuleShape3D:
		var capsule: CapsuleShape3D = shape as CapsuleShape3D
		radius_m = maxf(radius_m, (capsule.height * 0.5 + capsule.radius) * max_scale)
	elif shape is BoxShape3D:
		var box: BoxShape3D = shape as BoxShape3D
		radius_m = maxf(radius_m, box.size.length() * 0.5 * max_scale)
	elif shape is CylinderShape3D:
		var cylinder: CylinderShape3D = shape as CylinderShape3D
		radius_m = maxf(radius_m, maxf(cylinder.radius, cylinder.height * 0.5) * max_scale)
	return radius_m

func _find_first_collision_shape(root: Node) -> CollisionShape3D:
	for child in root.get_children():
		if child is CollisionShape3D:
			var collision_shape: CollisionShape3D = child as CollisionShape3D
			if collision_shape.disabled:
				continue
			return collision_shape
		var nested_shape: CollisionShape3D = _find_first_collision_shape(child)
		if nested_shape != null:
			return nested_shape
	return null

func _closest_point_on_segment(point: Vector3, segment_start: Vector3, segment_end: Vector3) -> Vector3:
	var segment: Vector3 = segment_end - segment_start
	var segment_length_sq: float = segment.length_squared()
	if segment_length_sq <= 0.0001:
		return segment_start
	var t: float = clampf((point - segment_start).dot(segment) / segment_length_sq, 0.0, 1.0)
	return segment_start + segment * t

# _on_timeout is handled by the parent class now
