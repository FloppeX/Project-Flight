extends RigidBody3D
class_name ProjectileNew

@export var damage: float = 10.0
@export var lifetime: float = 1.0
@export var impact_effect: PackedScene  # Explosion/impact visual
@export var creates_explosion: bool = true  # Whether this projectile explodes
@export var explosion_scene: PackedScene  # Reference to explosion scene
@export var target_mark_lifetime_s: float = 12.0
@export var target_mark_size: Vector3 = Vector3(0.9, 8.0, 0.9)
@export var hit_assist_enabled: bool = false
@export var hit_assist_check_interval_s: float = 0.05
@export var hit_assist_max_candidate_distance_m: float = 2500.0
@export var hit_assist_use_physics_broadphase: bool = true
@export var hit_assist_broadphase_extra_radius_m: float = 20.0
@export var hit_assist_broadphase_max_results: int = 32
@export var hit_assist_direct_candidate_limit: int = 24

# Reusable projectiles manage lifetime from physics ticks and retire through a
# virtual hook. The default remains the existing one-shot timer/queue_free path
# so bombs, rockets, and missiles are unaffected.
var reusable_lifecycle: bool = false

# Preloaded impact sounds to avoid per-hit load() calls
static var _metal_sounds: Array[AudioStream] = []
static var _dirt_sounds: Array[AudioStream] = []
static var _scorch_texture: Texture2D = null
static var _sounds_loaded: bool = false
static var hit_assist_radius_m: float = 0.2
const HIT_ASSIST_MIN_RADIUS_M: float = 0.0
const HIT_ASSIST_MAX_RADIUS_M: float = 6.0
const HIT_ASSIST_CANDIDATE_CACHE_MS: int = 200
const MAX_BULLET_DECALS_PER_AIRCRAFT: int = 15
const AIRCRAFT_BULLET_DECAL_META_KEY: StringName = &"_bullet_decal_nodes"
static var _hit_assist_target_radius_cache: Dictionary = {}
static var _hit_assist_target_shape_cache: Dictionary = {}
static var _hit_assist_candidate_cache_by_team: Dictionary = {}
static var _hit_assist_candidate_cache_expire_msec_by_team: Dictionary = {}

var shooter: Node3D  # Reference to whoever fired this
var last_position: Vector3 = Vector3.ZERO
var has_impacted: bool = false
var _hit_assist_time_accum_s: float = 0.0
var _hit_assist_segment_start: Vector3 = Vector3.ZERO
var _hit_assist_broadphase_shape: SphereShape3D = null
var _lifetime_elapsed_s: float = 0.0
var _activation_serial: int = 0
var _impact_target_shape_index: int = -1
var _impact_world_position: Vector3 = Vector3.INF

static func get_hit_assist_radius_m() -> float:
	return hit_assist_radius_m

static func set_hit_assist_radius_m(new_radius_m: float) -> float:
	hit_assist_radius_m = clampf(new_radius_m, HIT_ASSIST_MIN_RADIUS_M, HIT_ASSIST_MAX_RADIUS_M)
	return hit_assist_radius_m

static func adjust_hit_assist_radius_m(delta_m: float) -> float:
	return set_hit_assist_radius_m(hit_assist_radius_m + delta_m)

static func clear_hit_assist_candidate_cache() -> void:
	_hit_assist_candidate_cache_by_team.clear()
	_hit_assist_candidate_cache_expire_msec_by_team.clear()

static func _ensure_sounds_loaded() -> void:
	if _sounds_loaded:
		return
	_sounds_loaded = true
	for i in range(1, 9):
		var metal := load("res://Audio/impacts/bullet_impact_metal_heavy_%02d.wav" % i)
		if metal:
			_metal_sounds.append(metal)
		var dirt := load("res://Audio/impacts/bullet_impact_dirt_%02d.wav" % i)
		if dirt:
			_dirt_sounds.append(dirt)
	_scorch_texture = load("res://Projectiles/Explosion/scorch_mark.png")

func _ready():
	_ensure_sounds_loaded()
	mass = 0.01
	gravity_scale = maxf(gravity_scale, 0.0)
	physics_material_override = PhysicsMaterial.new()
	physics_material_override.bounce = 0.0
	physics_material_override.friction = 0.0
	# IMPORTANT: Enable collision detection
	contact_monitor = true
	max_contacts_reported = 10
	
	# Auto-destroy after lifetime. Reusable bullets cannot keep one-shot timers
	# because an old activation's timer could retire a newly reused round.
	if not reusable_lifecycle:
		get_tree().create_timer(lifetime).timeout.connect(_on_timeout)
	
	# Connect collision detection
	body_entered.connect(_on_body_entered)
	
	# Initialize last position for raycast tunneling detection
	last_position = global_position
	_hit_assist_segment_start = global_position
	_hit_assist_broadphase_shape = SphereShape3D.new()

func get_child_collision_shape() -> CollisionShape3D:
	for child in get_children():
		if child is CollisionShape3D:
			return child
	return null

func _physics_process(delta):
	if has_impacted:
		return
	if reusable_lifecycle:
		_lifetime_elapsed_s += delta
		if _lifetime_elapsed_s >= maxf(lifetime, 0.001):
			_on_timeout()
			return
	# Raycast between last position and current position to catch tunneling
	if last_position != Vector3.ZERO:
		var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(last_position, global_position)
		query.exclude = _get_projectile_query_excludes()
		# Use all layers so projectile collision works with project-specific Terrain3D setup.
		query.collision_mask = 0xFFFFFFFF
			
		var result: Dictionary = space_state.intersect_ray(query)
		if result and not has_impacted:
			_impact_target_shape_index = int(result.get("shape", -1))
			_impact_world_position = result.get("position", global_position) as Vector3
			global_position = result.position
			# Call _on_body_entered BEFORE setting has_impacted to avoid early return
			_on_body_entered(result.collider)
			return
		if hit_assist_enabled:
			_hit_assist_time_accum_s += delta
			var interval_s: float = maxf(_get_hit_assist_check_interval_s(), 0.0)
			if interval_s <= 0.0 or _hit_assist_time_accum_s >= interval_s:
				var assist_hit: Dictionary = _check_hit_assist(_hit_assist_segment_start, global_position)
				_hit_assist_segment_start = global_position
				_hit_assist_time_accum_s = 0.0
				if not assist_hit.is_empty() and not has_impacted:
					_impact_target_shape_index = -1
					_impact_world_position = assist_hit.get("position", global_position) as Vector3
					global_position = assist_hit.get("position", global_position)
					_on_body_entered(assist_hit.get("target", null))
					return
		else:
			_hit_assist_segment_start = global_position
			_hit_assist_time_accum_s = 0.0
		# Fallback for Terrain3D setups where physics collider/raycast may miss:
		# detect if the projectile segment crossed below terrain height data.
		var terrain := _get_cached_terrain_node()
		if terrain:
			var h_prev: float = _get_terrain_height_at_position(last_position)
			var h_curr: float = _get_terrain_height_at_position(global_position)
			if not is_nan(h_prev) and not is_nan(h_curr):
				var prev_above: bool = last_position.y >= h_prev
				var curr_above: bool = global_position.y >= h_curr
				if (not curr_above) or (prev_above and not curr_above):
					# Clamp to terrain surface and trigger impact.
					global_position.y = h_curr + 0.02
					_on_body_entered(terrain)
					return
	
	last_position = global_position

func fire(initial_velocity: Vector3, firing_aircraft: Node3D):
	_activation_serial += 1
	_lifetime_elapsed_s = 0.0
	has_impacted = false
	_impact_target_shape_index = -1
	_impact_world_position = Vector3.INF
	shooter = firing_aircraft
	linear_velocity = initial_velocity
	_hit_assist_time_accum_s = 0.0
	# Weapons may offset the projectile after _ready() so it starts clear of the
	# muzzle. Start impact raycasts from the final launch position, not the
	# original instantiation point inside the firing rig.
	last_position = global_position
	_hit_assist_segment_start = global_position
	
	# Disable collision with the firing entity initially.
	# Ground vehicles are CharacterBody3D, not RigidBody3D, and turret bullets can
	# otherwise spawn inside the host collider and die immediately.
	if firing_aircraft and firing_aircraft is CollisionObject3D:
		add_collision_exception_with(firing_aircraft)
		# Re-enable collision after a short delay (once projectile is clear)
		var projectile_ref: WeakRef = weakref(self)
		var shooter_ref: WeakRef = weakref(firing_aircraft)
		var activation_serial: int = _activation_serial
		get_tree().create_timer(0.2).timeout.connect(func() -> void:
			var projectile_obj: Object = projectile_ref.get_ref()
			var shooter_obj: Object = shooter_ref.get_ref()
			if projectile_obj is ProjectileNew and is_instance_valid(projectile_obj) and (projectile_obj as ProjectileNew)._activation_serial == activation_serial and shooter_obj is CollisionObject3D and is_instance_valid(shooter_obj):
				(projectile_obj as ProjectileNew).remove_collision_exception_with(shooter_obj as CollisionObject3D)
		)

func _get_hit_assist_check_interval_s() -> float:
	return hit_assist_check_interval_s

func _get_projectile_query_excludes() -> Array:
	var excludes: Array = []
	if self is CollisionObject3D:
		excludes.append(get_rid())
	if shooter and is_instance_valid(shooter) and shooter is CollisionObject3D:
		excludes.append((shooter as CollisionObject3D).get_rid())
	return excludes


func is_shooter_body(body: Node) -> bool:
	# A physics contact reports the collider that was hit, which may be a child
	# CollisionShape3D of the shooter, or the shooter's root reached via the parent
	# chain — a direct `body == shooter` test misses both. Walk up from the hit body
	# and treat anything belonging to the shooter as self, so the projectile never
	# damages the aircraft that fired it (the Aircraft_9 self-hit bug).
	if shooter == null or not is_instance_valid(shooter):
		return false
	var node: Node = body
	while node:
		if node == shooter:
			return true
		node = node.get_parent()
	return false

func _check_hit_assist(from_pos: Vector3, to_pos: Vector3) -> Dictionary:
	if not hit_assist_enabled:
		return {}
	var assist_radius: float = get_hit_assist_radius_m()
	if assist_radius <= 0.0:
		return {}
	var target_data: Dictionary = _find_best_hit_assist_target(from_pos, to_pos, assist_radius)
	if target_data.is_empty():
		return {}
	return target_data

func _find_best_hit_assist_target(from_pos: Vector3, to_pos: Vector3, assist_radius: float) -> Dictionary:
	var candidates: Array = _get_hit_assist_candidates_for_segment(from_pos, to_pos, assist_radius)
	if candidates.is_empty():
		return {}

	var best_t: float = INF
	var best_target: Node3D = null
	var best_point: Vector3 = Vector3.ZERO
	var max_distance_sq: float = INF
	if hit_assist_max_candidate_distance_m > 0.0:
		max_distance_sq = hit_assist_max_candidate_distance_m * hit_assist_max_candidate_distance_m
	for candidate_variant in candidates:
		var candidate: Node3D = _as_valid_node3d(candidate_variant)
		if candidate == null:
			continue
		if not _is_valid_hit_assist_target(candidate):
			continue
		if is_finite(max_distance_sq) and candidate.global_position.distance_squared_to(to_pos) > max_distance_sq:
			continue
		var target_center: Vector3 = _get_hit_assist_target_center(candidate)
		var closest_point: Vector3 = _closest_point_on_segment(target_center, from_pos, to_pos)
		var target_radius: float = _get_hit_assist_target_radius(candidate)
		var effective_radius: float = assist_radius + target_radius
		if target_center.distance_squared_to(closest_point) > effective_radius * effective_radius:
			continue
		var segment_t: float = _segment_fraction_for_point(closest_point, from_pos, to_pos)
		if segment_t < best_t:
			best_t = segment_t
			best_target = candidate
			best_point = closest_point

	if best_target == null:
		return {}
	return {
		"target": best_target,
		"position": best_point,
	}

func _get_hit_assist_candidates_for_segment(from_pos: Vector3, to_pos: Vector3, assist_radius: float) -> Array:
	var registered_candidates: Array = _get_hit_assist_candidates()
	if registered_candidates.is_empty():
		return []
	# A cached list is cheaper than a shape query when battles contain only a
	# modest number of valid targets. Switch to physics broadphase only once the
	# candidate population is large enough for spatial pruning to pay for itself.
	if hit_assist_use_physics_broadphase and registered_candidates.size() > max(hit_assist_direct_candidate_limit, 0):
		return _get_hit_assist_candidates_from_physics(from_pos, to_pos, assist_radius)
	return registered_candidates

func _get_hit_assist_candidates_from_physics(from_pos: Vector3, to_pos: Vector3, assist_radius: float) -> Array:
	if _hit_assist_broadphase_shape == null:
		_hit_assist_broadphase_shape = SphereShape3D.new()
	var segment: Vector3 = to_pos - from_pos
	var midpoint: Vector3 = from_pos + segment * 0.5
	var segment_half_len: float = segment.length() * 0.5
	_hit_assist_broadphase_shape.radius = maxf(segment_half_len + assist_radius + hit_assist_broadphase_extra_radius_m, assist_radius)

	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _hit_assist_broadphase_shape
	query.transform = Transform3D(Basis.IDENTITY, midpoint)
	query.collision_mask = 0xFFFFFFFF
	query.collide_with_bodies = true
	query.collide_with_areas = true
	query.exclude = [get_rid()]
	if shooter and shooter is CollisionObject3D:
		query.exclude.append((shooter as CollisionObject3D).get_rid())

	var results: Array = get_world_3d().direct_space_state.intersect_shape(query, max(hit_assist_broadphase_max_results, 1))
	if results.is_empty():
		return []

	var out: Array = []
	var seen: Dictionary = {}
	for hit in results:
		if not (hit is Dictionary):
			continue
		var collider_variant: Variant = (hit as Dictionary).get("collider", null)
		if typeof(collider_variant) != TYPE_OBJECT or not is_instance_valid(collider_variant):
			continue
		var candidate: Node3D = _resolve_hit_assist_candidate_from_collider(collider_variant as Object)
		if candidate == null:
			continue
		var instance_id: int = candidate.get_instance_id()
		if seen.has(instance_id):
			continue
		seen[instance_id] = true
		out.append(candidate)
	return out

func _resolve_hit_assist_candidate_from_collider(collider_obj: Object) -> Node3D:
	if collider_obj == null:
		return null
	if collider_obj is Node3D and _is_hit_assist_target_node(collider_obj as Node3D):
		return collider_obj as Node3D
	if not (collider_obj is Node):
		return null
	var node: Node = collider_obj as Node
	while node != null:
		if node is Node3D and _is_hit_assist_target_node(node as Node3D):
			return node as Node3D
		node = node.get_parent()
	return null

func _get_hit_assist_candidates() -> Array:
	var tree: SceneTree = get_tree()
	if tree == null:
		return []
	var shooter_team: int = _get_shooter_team()
	var now_ms: int = Time.get_ticks_msec()
	var cache_key: int = shooter_team
	var expiry_variant: Variant = _hit_assist_candidate_cache_expire_msec_by_team.get(cache_key, 0)
	var cache_expiry_ms: int = int(expiry_variant)
	var cached_variant: Variant = _hit_assist_candidate_cache_by_team.get(cache_key, [])
	var cached_nodes: Array = cached_variant if cached_variant is Array else []
	if now_ms <= cache_expiry_ms:
		return _filter_valid_hit_assist_candidates(cached_nodes)

	var rebuilt: Array = _rebuild_hit_assist_candidates(tree, shooter_team)
	_hit_assist_candidate_cache_by_team[cache_key] = rebuilt
	_hit_assist_candidate_cache_expire_msec_by_team[cache_key] = now_ms + HIT_ASSIST_CANDIDATE_CACHE_MS
	return _filter_valid_hit_assist_candidates(rebuilt)

func _rebuild_hit_assist_candidates(tree: SceneTree, shooter_team: int) -> Array:
	var out: Array = []
	var seen: Dictionary = {}

	var registry: Node = tree.root.get_node_or_null("EnemyRegistry")
	if shooter_team != 0 and registry and registry.has_method("get_enemies_for_team"):
		var registry_targets: Variant = registry.call("get_enemies_for_team", shooter_team)
		if registry_targets is Array:
			for target_variant in registry_targets:
				var target_node: Node3D = _as_valid_node3d(target_variant)
				if target_node == null:
					continue
				var instance_id: int = target_node.get_instance_id()
				if not seen.has(instance_id):
					seen[instance_id] = true
					out.append(target_node)

	if out.is_empty():
		for group_name in ["aircraft", "ai_aircraft", "ground_vehicles", "buildings"]:
			var group_nodes: Array = tree.get_nodes_in_group(group_name)
			for target_variant in group_nodes:
				var target_node: Node3D = _as_valid_node3d(target_variant)
				if target_node == null:
					continue
				var instance_id: int = target_node.get_instance_id()
				if not seen.has(instance_id):
					seen[instance_id] = true
					out.append(target_node)
	return out

func _filter_valid_hit_assist_candidates(candidates: Array) -> Array:
	var filtered: Array = []
	for candidate_variant in candidates:
		var candidate: Node3D = _as_valid_node3d(candidate_variant)
		if candidate == null:
			continue
		filtered.append(candidate)
	return filtered

func _as_valid_node3d(value: Variant) -> Node3D:
	if typeof(value) != TYPE_OBJECT:
		return null
	if not is_instance_valid(value):
		return null
	if not (value is Node3D):
		return null
	return value as Node3D

func _is_valid_hit_assist_target(candidate: Node3D) -> bool:
	if candidate == null or not is_instance_valid(candidate):
		return false
	if candidate == self:
		return false
	if shooter != null and candidate == shooter:
		return false
	if not _is_hit_assist_target_node(candidate):
		return false
	var shooter_team: int = _get_shooter_team()
	if shooter_team != 0 and candidate.has_method("get_team"):
		if int(candidate.call("get_team")) == shooter_team:
			return false
	if shooter_team != 0 and candidate.is_in_group("team_" + str(shooter_team)):
		return false
	return true

func _is_hit_assist_target_node(candidate: Node3D) -> bool:
	if candidate.is_in_group("aircraft") or candidate.is_in_group("ai_aircraft"):
		return true
	if candidate.is_in_group("ground_vehicles") or candidate.is_in_group("buildings"):
		return true
	return is_aircraft(candidate)

func _get_shooter_team() -> int:
	if shooter and is_instance_valid(shooter) and shooter.has_method("get_team"):
		return int(shooter.call("get_team"))
	return 0

func _get_hit_assist_target_center(target: Node3D) -> Vector3:
	var shape_node: CollisionShape3D = _get_cached_target_collision_shape(target)
	if shape_node and is_instance_valid(shape_node):
		return shape_node.global_position
	return target.global_position

func _get_hit_assist_target_radius(target: Node3D) -> float:
	if target == null or not is_instance_valid(target):
		return 2.5
	var instance_id: int = target.get_instance_id()
	if _hit_assist_target_radius_cache.has(instance_id):
		return float(_hit_assist_target_radius_cache[instance_id])

	var radius: float = 2.5
	var shape_node: CollisionShape3D = _get_cached_target_collision_shape(target)
	if shape_node and is_instance_valid(shape_node) and shape_node.shape:
		var shape_scale: Vector3 = shape_node.global_transform.basis.get_scale().abs()
		var max_scale: float = maxf(maxf(shape_scale.x, shape_scale.y), shape_scale.z)
		var shape: Shape3D = shape_node.shape
		if shape is SphereShape3D:
			radius = maxf(radius, (shape as SphereShape3D).radius * max_scale)
		elif shape is CapsuleShape3D:
			var capsule: CapsuleShape3D = shape as CapsuleShape3D
			radius = maxf(radius, (capsule.height * 0.5 + capsule.radius) * max_scale)
		elif shape is BoxShape3D:
			var box: BoxShape3D = shape as BoxShape3D
			radius = maxf(radius, box.size.length() * 0.5 * max_scale)

	_hit_assist_target_radius_cache[instance_id] = radius
	return radius

func _get_cached_target_collision_shape(target: Node3D) -> CollisionShape3D:
	if target == null or not is_instance_valid(target):
		return null
	var instance_id: int = target.get_instance_id()
	var cached_ref_variant: Variant = _hit_assist_target_shape_cache.get(instance_id, null)
	if cached_ref_variant is WeakRef:
		var cached_shape_variant: Variant = (cached_ref_variant as WeakRef).get_ref()
		if cached_shape_variant is CollisionShape3D:
			var cached_shape: CollisionShape3D = cached_shape_variant as CollisionShape3D
			if is_instance_valid(cached_shape) and not cached_shape.disabled:
				return cached_shape
		_hit_assist_target_shape_cache.erase(instance_id)
		_hit_assist_target_radius_cache.erase(instance_id)
	var discovered_shape: CollisionShape3D = _find_first_collision_shape(target)
	if discovered_shape != null and is_instance_valid(discovered_shape):
		_hit_assist_target_shape_cache[instance_id] = weakref(discovered_shape)
	return discovered_shape

func _find_first_collision_shape(root: Node) -> CollisionShape3D:
	for child in root.get_children():
		if child is CollisionShape3D:
			var collision: CollisionShape3D = child as CollisionShape3D
			if collision.disabled:
				continue
			return collision
		var nested: CollisionShape3D = _find_first_collision_shape(child)
		if nested:
			return nested
	return null

func _closest_point_on_segment(point: Vector3, seg_start: Vector3, seg_end: Vector3) -> Vector3:
	var segment: Vector3 = seg_end - seg_start
	var segment_len_sq: float = segment.length_squared()
	if segment_len_sq <= 0.0001:
		return seg_start
	var t: float = clampf((point - seg_start).dot(segment) / segment_len_sq, 0.0, 1.0)
	return seg_start + segment * t

func _segment_fraction_for_point(point: Vector3, seg_start: Vector3, seg_end: Vector3) -> float:
	var segment: Vector3 = seg_end - seg_start
	var segment_len_sq: float = segment.length_squared()
	if segment_len_sq <= 0.0001:
		return 0.0
	return clampf((point - seg_start).dot(segment) / segment_len_sq, 0.0, 1.0)

func _on_body_entered(body):
	if has_impacted:
		return
	if is_shooter_body(body):
		return

	var damage_target = find_damage_target(body)
	
	# Mark as impacted immediately to prevent duplicate hits
	has_impacted = true
	
	# Determine if we hit the ground/terrain for scorch mark
	var hit_ground = is_ground_or_terrain(body)
	
	# Create explosion effect
	if creates_explosion and explosion_scene:
		var explosion = explosion_scene.instantiate()
		get_tree().current_scene.add_child(explosion)
		explosion.global_position = global_position
		
		# Create scorch mark if we hit the ground
		if hit_ground:
			explosion.create_scorch_mark()
		if "source_attacker" in explosion and is_instance_valid(shooter):
			explosion.source_attacker = shooter
	
	# Fallback to old impact effect if no explosion
	elif impact_effect:
		var effect = impact_effect.instantiate()
		get_tree().current_scene.add_child(effect)
		effect.global_position = global_position
	
	# Play impact sound
	play_impact_sound(body)
	
	if damage_target and _supports_target_hit_mark(damage_target):
		create_bullet_scorch_mark(damage_target)
	
	# Apply damage if target has health
	if damage_target and damage_target.has_method("take_damage"):
		_report_damage_credit(damage_target, damage)
		_apply_impact_damage(damage_target, damage)
	_retire_projectile()


func _apply_impact_damage(damage_target: Node, damage_amount: float) -> void:
	if damage_target == null or not is_instance_valid(damage_target):
		return
	var impact_position := _impact_world_position
	if not is_finite(impact_position.x) or not is_finite(impact_position.y) or not is_finite(impact_position.z):
		impact_position = global_position
	if damage_target.has_method("take_damage_at"):
		damage_target.call("take_damage_at", damage_amount, impact_position, _impact_target_shape_index)
	elif damage_target.has_method("take_damage"):
		damage_target.call("take_damage", damage_amount)

func _report_damage_credit(damage_target: Node, damage_amount: float) -> void:
	if shooter == null or not is_instance_valid(shooter):
		return
	if PilotRoster == null or not is_instance_valid(PilotRoster):
		return
	if not PilotRoster.has_method("report_damage"):
		return
	PilotRoster.report_damage(shooter, damage_target, damage_amount)

func _get_cached_terrain_node() -> Node:
	return TerrainReference.get_terrain_node()

func _get_terrain_height_at_position(world_pos: Vector3) -> float:
	var terrain: Node = _get_cached_terrain_node()
	if not terrain:
		return NAN
	if terrain.has_method("get_height"):
		var h = terrain.get_height(world_pos)
		if typeof(h) == TYPE_FLOAT and not is_nan(float(h)):
			return float(h)
	if "data" in terrain and terrain.data and terrain.data.has_method("get_height"):
		var h2 = terrain.data.get_height(world_pos)
		if typeof(h2) == TYPE_FLOAT and not is_nan(float(h2)):
			return float(h2)
	return NAN

func play_impact_sound(body: Node) -> void:
	var impact_budget: Node = get_node_or_null("/root/BulletImpactBudget")
	# Pick from preloaded sound arrays
	var sound: AudioStream = null
	if is_aircraft(body):
		if not _metal_sounds.is_empty():
			sound = _metal_sounds[randi() % _metal_sounds.size()]
	elif is_ground_or_terrain(body):
		if not _dirt_sounds.is_empty():
			sound = _dirt_sounds[randi() % _dirt_sounds.size()]
	else:
		if not _metal_sounds.is_empty():
			sound = _metal_sounds[0]

	if not sound:
		return
	if impact_budget and impact_budget.has_method("play_impact_sound"):
		impact_budget.call("play_impact_sound", sound, global_position, -5.0, randf_range(0.9, 1.1))
		return
	if impact_budget and not bool(impact_budget.call("should_play_impact_sound", global_position)):
		return

	var audio_player = AudioStreamPlayer3D.new()
	get_tree().current_scene.add_child(audio_player)
	audio_player.global_position = global_position
	audio_player.stream = sound
	audio_player.volume_db = -5.0
	audio_player.pitch_scale = randf_range(0.9, 1.1)
	audio_player.play()

	var audio_ref: WeakRef = weakref(audio_player)
	audio_player.finished.connect(func() -> void:
		var audio_obj: Object = audio_ref.get_ref()
		if audio_obj is Node and is_instance_valid(audio_obj):
			(audio_obj as Node).queue_free()
	)
	get_tree().create_timer(3.0).timeout.connect(func():
		var audio_obj: Object = audio_ref.get_ref()
		if audio_obj is Node and is_instance_valid(audio_obj):
			(audio_obj as Node).queue_free()
	)

func create_bullet_scorch_mark(aircraft_body: Node) -> void:
	# Create a bullet scorch mark on the aircraft surface
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var impact_dir: Vector3 = linear_velocity.normalized()
	if impact_dir == Vector3.ZERO:
		impact_dir = Vector3.FORWARD
	
	# Cast a ray to get precise impact point and surface normal
	var from: Vector3 = global_position - impact_dir * 1.0
	var to: Vector3 = global_position + impact_dir * 0.5
	var params: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to)
	params.exclude = [self]
	if shooter:
		params.exclude.append(shooter)
	params.collision_mask = 0xFFFFFFFF
	
	var hit: Dictionary = space_state.intersect_ray(params)
	var hit_pos: Vector3 = global_position
	var hit_normal: Vector3 = -impact_dir
	
	if hit and hit.has("position") and hit.has("normal"):
		hit_pos = hit.position
		hit_normal = (hit.normal as Vector3).normalized()
	elif aircraft_body is Node3D:
		# Better fallback: point outward from the aircraft centre toward impact.
		var ac_center: Vector3 = (aircraft_body as Node3D).global_position
		var outward: Vector3 = global_position - ac_center
		if outward.length() > 0.01:
			hit_normal = outward.normalized()
	create_bullet_scorch_mark_at(aircraft_body, hit_pos, hit_normal)


func create_bullet_scorch_mark_at(
	aircraft_body: Node,
	hit_pos: Vector3,
	hit_normal: Vector3,
	mark_scale: float = 1.0
) -> bool:
	var impact_budget: Node = get_node_or_null("/root/BulletImpactBudget")
	if impact_budget and not bool(impact_budget.call("should_spawn_visual", hit_pos)):
		return false

	# Scale mark size with damage. sqrt keeps heavy rounds from looking absurd.
	# target_mark_size is calibrated for damage = 10.
	var dmg_scale: float = sqrt(maxf(damage, 1.0) / 10.0) * maxf(mark_scale, 0.1)
	var scaled_size := Vector3(
		target_mark_size.x * dmg_scale,
		target_mark_size.y * dmg_scale,
		target_mark_size.z * dmg_scale)

	# Aircraft keep their small per-aircraft history. Transient vehicle marks use
	# the global decal pool and return there when their lifetime expires.
	var decal: Decal
	if impact_budget and not is_aircraft(aircraft_body):
		decal = impact_budget.call("acquire_decal", aircraft_body if aircraft_body and is_instance_valid(aircraft_body) else get_tree().current_scene) as Decal
	else:
		decal = Decal.new()
	decal.texture_albedo = _scorch_texture
	decal.size = scaled_size
	# Disable distance fade so the mark stays sharp across the whole projection volume.
	decal.upper_fade = 0.0
	decal.lower_fade = 0.0
	decal.sorting_offset = 20.0

	# Parent first, then set global transform so placement is correct in world space.
	if decal.get_parent() == null:
		if aircraft_body and is_instance_valid(aircraft_body):
			aircraft_body.add_child(decal)
		else:
			get_tree().current_scene.add_child(decal)

	# Align projection with surface normal. Decals project along local -Y.
	var y_axis: Vector3 = hit_normal.normalized()
	var x_axis: Vector3 = y_axis.cross(Vector3.FORWARD)
	if x_axis.length() < 0.001:
		x_axis = y_axis.cross(Vector3.RIGHT)
	x_axis = x_axis.normalized()
	var z_axis: Vector3 = x_axis.cross(y_axis).normalized()
	var surface_basis: Basis = Basis(x_axis, y_axis, z_axis)
	var random_spin: Basis = Basis(y_axis, randf() * TAU)

	# Offset along normal to avoid z-fighting.
	decal.global_position = hit_pos + y_axis * 0.1
	decal.global_basis = random_spin * surface_basis
	decal.modulate = Color(1.0, 1.0, 1.0, 1.0)
	_enforce_aircraft_bullet_decal_cap(aircraft_body, decal)
	if impact_budget:
		impact_budget.call("register_decal", decal, 0.0 if is_aircraft(aircraft_body) else target_mark_lifetime_s)

	# Aircraft marks are cleaned up by the cap (last 15 stay permanently).
	# Only time-expire marks on non-aircraft targets (ground vehicles, etc.).
	if target_mark_lifetime_s > 0.0 and not is_aircraft(aircraft_body) and impact_budget == null:
		var decal_ref: WeakRef = weakref(decal)
		get_tree().create_timer(target_mark_lifetime_s).timeout.connect(func():
			var decal_obj: Object = decal_ref.get_ref()
			if decal_obj is Node and is_instance_valid(decal_obj):
				(decal_obj as Node).queue_free()
		)
	return true

func _enforce_aircraft_bullet_decal_cap(target: Node, newest_decal: Decal) -> void:
	if not target or not is_instance_valid(target):
		return
	if not is_aircraft(target):
		return
	var tracked_decals: Array = []
	var stored_variant: Variant = target.get_meta(AIRCRAFT_BULLET_DECAL_META_KEY, [])
	if stored_variant is Array:
		for decal_variant in stored_variant:
			if typeof(decal_variant) != TYPE_OBJECT:
				continue
			if not is_instance_valid(decal_variant):
				continue
			if decal_variant is Decal:
				tracked_decals.append(decal_variant as Decal)
	tracked_decals.append(newest_decal)
	while tracked_decals.size() > MAX_BULLET_DECALS_PER_AIRCRAFT:
		var oldest_variant: Variant = tracked_decals[0]
		tracked_decals.remove_at(0)
		if typeof(oldest_variant) != TYPE_OBJECT:
			continue
		if not is_instance_valid(oldest_variant):
			continue
		if oldest_variant is Decal:
			(oldest_variant as Decal).queue_free()
	target.set_meta(AIRCRAFT_BULLET_DECAL_META_KEY, tracked_decals)

func _supports_target_hit_mark(target: Node) -> bool:
	if not target or not is_instance_valid(target):
		return false
	if is_aircraft(target):
		return true
	if target.is_in_group("ground_vehicles"):
		return true
	return false

func find_damage_target(body: Node) -> Node:
	if body.has_method("take_damage"):
		return body
	if body is CollisionShape3D and body.get_parent() and body.get_parent().has_method("take_damage"):
		return body.get_parent()
	var node: Node = body
	while node:
		if node != body and node.has_method("take_damage"):
			return node
		node = node.get_parent()
	return null

func is_aircraft(body: Node) -> bool:
	# Check if the body is an aircraft
	var target = body
	
	# If we hit a CollisionShape3D, check its parent
	if body is CollisionShape3D and body.get_parent():
		target = body.get_parent()
	
	if target.name == "Aircraft" or "aircraft" in target.name.to_lower():
		return true
	if target.is_in_group("aircraft"):
		return true
	if target.is_in_group("ai_aircraft"):
		return true
	if target is Aircraft:
		return true
	return false

func is_ground_or_terrain(body: Node) -> bool:
	# Exclude aircraft and vehicles — they are not terrain
	if body is RigidBody3D:
		return false
	if is_aircraft(body):
		return false
	if body.is_in_group("ground_vehicles") or body.is_in_group("enemies") or body.is_in_group("buildings"):
		return false

	# Check for Terrain3D plugin
	if body.get_class() == "Terrain3D" or "terrain3d" in body.name.to_lower():
		return true

	# Check for groups
	if body.is_in_group("terrain") or body.is_in_group("ground") or body.is_in_group("terrain_provider"):
		return true

	# Check by name
	if "ground" in body.name.to_lower() or "terrain" in body.name.to_lower():
		return true

	# StaticBody3D without enemy/vehicle groups is likely terrain
	if body is StaticBody3D:
		return true

	return false

func _on_timeout():
	_retire_projectile()

func _retire_projectile() -> void:
	queue_free()
