extends Node3D
class_name DustEffect

## Spawns rising dust puffs at ground contact points while moving.

const VISUAL_FOCUS_HELPER = preload("res://Effects/VisualFocus.gd")

@export var min_speed_mps: float = 2.0
@export var spawn_interval_s: float = 0.25
@export var puff_scale_min: float = 0.6
@export var puff_scale_max: float = 2.0
@export var puff_opacity_multiplier: float = 1.35
@export var full_speed_mps: float = 20.0
@export var puff_lifetime_s: float = 5.0
@export var puff_rise_speed: float = 7.0
@export var max_effect_distance_m: float = 800.0
@export var require_camera_frustum: bool = true
@export var camera_frustum_padding_m: float = 25.0
@export var cache_camera_visibility: bool = true
@export var camera_visibility_check_interval_s: float = 0.15
@export var lazy_initialize_pool: bool = true
@export var pooled_puff_count: int = 16
@export var auto_size_pool: bool = true
@export var max_pooled_puff_count: int = 128
@export var visual_budget_enabled: bool = true

var _emit_offsets: Array[Vector3] = []
var _timers: Array[float] = []
var _parent_node: Node3D = null
var _last_position: Vector3 = Vector3.ZERO
var _speed: float = 0.0
var _exclude_rids: Array[RID] = []
var _cached_camera: Camera3D = null
var _camera_cache_timer_s: float = 0.0
var _cached_should_emit_for_camera: bool = false
var _camera_visibility_timer_s: float = 0.0
var _puff_pool: Array[MeshInstance3D] = []
var _available_puff_indices: Array[int] = []
var _pool_target_count: int = 0

# Shared across all instances
static var _shared_dust_color: Color = Color(0.78, 0.46, 0.26, 1.0)
static var _shared_mesh: SphereMesh = null
static var _shared_color_sample_cooldown: float = 0.0
static var dust_enabled: bool = true

func set_visual_budget_enabled(value: bool) -> void:
	visual_budget_enabled = value

static func _sanitize_dust_color(color: Color) -> Color:
	var clean := Color(
		clampf(color.r, 0.38, 0.95),
		clampf(color.g, 0.24, 0.78),
		clampf(color.b, 0.12, 0.58),
		1.0
	)
	var luma := clean.get_luminance()
	if luma < 0.42:
		clean = clean.lerp(Color(0.82, 0.50, 0.28, 1.0), 0.55)
	elif luma > 0.72:
		var scale := 0.72 / maxf(luma, 0.0001)
		clean.r *= scale
		clean.g *= scale
		clean.b *= scale
	return clean

func _is_terrain_hit(hit: Dictionary) -> bool:
	if hit.is_empty():
		return false
	if not hit.has("collider"):
		return false
	var node: Node = hit["collider"] as Node
	if node == null:
		return false
	if node.is_in_group("terrain"):
		return true
	var parent: Node = node.get_parent()
	while parent != null:
		if parent.is_in_group("terrain"):
			return true
		parent = parent.get_parent()
	return false

func _ready() -> void:
	add_to_group("origin_shifter")
	_parent_node = get_parent() as Node3D
	if _parent_node == null:
		push_warning("DustEffect: parent is not Node3D")
		set_physics_process(false)
		return

	# Create shared mesh once
	if _shared_mesh == null:
		_shared_mesh = SphereMesh.new()
		_shared_mesh.radial_segments = 4
		_shared_mesh.rings = 2

	await get_tree().process_frame

	# Build RID exclusion list so raycasts skip the parent and its physics children
	if _parent_node is CollisionObject3D:
		_exclude_rids.append((_parent_node as CollisionObject3D).get_rid())
	for child in _parent_node.get_children():
		if child is CollisionObject3D:
			_exclude_rids.append((child as CollisionObject3D).get_rid())
	if _parent_node is CarrierTread and _parent_node.carrier is CollisionObject3D:
		_exclude_rids.append((_parent_node.carrier as CollisionObject3D).get_rid())

	if _parent_node is CarrierTread:
		_setup_carrier_tread()
	elif _parent_node.has_method("_update_wheel_visuals"):
		_setup_vehicle_wheels()
	else:
		_emit_offsets.append(Vector3.ZERO)
		_timers.append(0.0)

	if lazy_initialize_pool:
		_pool_target_count = _get_target_pool_count()
	else:
		_initialize_puff_pool()
	_last_position = _parent_node.global_position
	_camera_visibility_timer_s = randf_range(0.0, maxf(camera_visibility_check_interval_s, 0.01))

func apply_origin_shift(offset: Vector3) -> void:
	_last_position -= offset

func _exit_tree() -> void:
	for puff in _puff_pool:
		if puff and is_instance_valid(puff):
			puff.queue_free()
	_puff_pool.clear()
	_available_puff_indices.clear()

func _setup_carrier_tread() -> void:
	# Emit from outer edge only. Right treads have 180° Y flip so local X is inverted.
	# Use -5 for all treads in local space: on left treads (no flip) this is outward-left,
	# on right treads (180° Y flip) this becomes outward-right in world space.
	_emit_offsets.append(Vector3(-5.0, 0, -12.0))
	_emit_offsets.append(Vector3(-5.0, 0,  12.0))
	for i in range(_emit_offsets.size()):
		_timers.append(0.0)

func _setup_vehicle_wheels() -> void:
	var wheel_nodes: Array[Node3D] = []
	if "_all_wheel_nodes" in _parent_node:
		wheel_nodes = _parent_node._all_wheel_nodes
	if wheel_nodes.is_empty():
		for child in _parent_node.get_children():
			if child is Node3D and "heel" in child.name.to_lower():
				wheel_nodes.append(child)
	if wheel_nodes.is_empty():
		_emit_offsets.append(Vector3.ZERO)
		_timers.append(0.0)
		return
	for w in wheel_nodes:
		_emit_offsets.append(Vector3(w.position.x, 0, w.position.z))
		_timers.append(0.0)

func _initialize_puff_pool() -> void:
	_shared_mesh.radius = 1.0
	_shared_mesh.height = 2.0
	_pool_target_count = _get_target_pool_count()
	var initial_count := mini(maxi(pooled_puff_count, 1), _pool_target_count)
	for i in range(initial_count):
		_create_pooled_puff()

func _get_target_pool_count() -> int:
	var requested_count := maxi(pooled_puff_count, 1)
	if not auto_size_pool:
		return requested_count
	var emit_count := maxi(_emit_offsets.size(), 1)
	var fastest_interval := maxf(spawn_interval_s * 0.5, 0.02)
	var needed_for_lifetime := int(ceil(float(emit_count) * maxf(puff_lifetime_s, fastest_interval) / fastest_interval)) + emit_count
	var capped_max := maxi(max_pooled_puff_count, requested_count)
	return mini(maxi(requested_count, needed_for_lifetime), capped_max)

func _create_pooled_puff() -> void:
	var scene_root := get_tree().current_scene
	if scene_root == null:
		return
	var pool_index := _puff_pool.size()
	var puff := MeshInstance3D.new()
	puff.visible = false
	puff.mesh = _shared_mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(_shared_dust_color.r, _shared_dust_color.g, _shared_dust_color.b, 0.0)
	puff.material_override = mat
	puff.set_meta("dust_pool_index", pool_index)
	scene_root.add_child(puff)
	_puff_pool.append(puff)
	_available_puff_indices.append(pool_index)

func _acquire_pooled_puff() -> MeshInstance3D:
	if _pool_target_count <= 0:
		_pool_target_count = _get_target_pool_count()
	if _available_puff_indices.is_empty() and _puff_pool.size() < _pool_target_count:
		_create_pooled_puff()
	if _available_puff_indices.is_empty():
		return null
	var pool_index: int = _available_puff_indices.pop_back()
	if pool_index < 0 or pool_index >= _puff_pool.size():
		return null
	return _puff_pool[pool_index]

func _release_pooled_puff(puff: MeshInstance3D) -> void:
	if puff == null or not is_instance_valid(puff):
		return
	puff.visible = false
	puff.scale = Vector3.ONE
	if puff.material_override:
		puff.material_override.albedo_color.a = 0.0
	var pool_index_variant = puff.get_meta("dust_pool_index", -1)
	if typeof(pool_index_variant) in [TYPE_INT, TYPE_FLOAT]:
		var pool_index: int = int(pool_index_variant)
		if pool_index >= 0 and not _available_puff_indices.has(pool_index):
			_available_puff_indices.append(pool_index)

func _physics_process(delta: float) -> void:
	if _parent_node == null or not is_instance_valid(_parent_node) or not _parent_node.is_inside_tree():
		return

	var current_pos := _parent_node.global_position
	_speed = current_pos.distance_to(_last_position) / maxf(delta, 0.001)
	_last_position = current_pos

	if not visual_budget_enabled or not dust_enabled or _speed < min_speed_mps or not _should_emit_for_camera(delta):
		return

	# Only one instance samples color, and only every 5 seconds
	_shared_color_sample_cooldown -= delta
	if _shared_color_sample_cooldown <= 0.0:
		_shared_color_sample_cooldown = 5.0
		_sample_ground_color()

	var speed_ratio: float = clampf(_speed / full_speed_mps, 0.0, 1.0)
	var effective_interval: float = lerpf(spawn_interval_s, spawn_interval_s * 0.5, speed_ratio)

	for i in range(_emit_offsets.size()):
		_timers[i] -= delta
		if _timers[i] <= 0.0:
			_timers[i] = effective_interval
			_spawn_dust_puff(i, speed_ratio)

func _get_active_camera(delta: float) -> Camera3D:
	_camera_cache_timer_s = maxf(_camera_cache_timer_s - delta, 0.0)
	if _is_camera_usable(_cached_camera) and _camera_cache_timer_s > 0.0:
		return _cached_camera
	var viewport := get_viewport()
	var candidate: Camera3D = viewport.get_camera_3d() if viewport != null else null
	_cached_camera = candidate if _is_camera_usable(candidate) else null
	_camera_cache_timer_s = 0.25
	return _cached_camera

func _is_camera_usable(camera_value: Variant) -> bool:
	if typeof(camera_value) != TYPE_OBJECT or not is_instance_valid(camera_value):
		return false
	if not (camera_value is Camera3D):
		return false
	var camera := camera_value as Camera3D
	return camera.is_inside_tree() and camera.get_world_3d() != null

func _should_emit_for_camera(delta: float) -> bool:
	if not cache_camera_visibility:
		return _compute_should_emit_for_camera(delta)
	_camera_visibility_timer_s -= delta
	if _camera_visibility_timer_s > 0.0:
		return _cached_should_emit_for_camera
	_cached_should_emit_for_camera = _compute_should_emit_for_camera(delta)
	_camera_visibility_timer_s = maxf(camera_visibility_check_interval_s, 0.01)
	return _cached_should_emit_for_camera

func _compute_should_emit_for_camera(delta: float) -> bool:
	if _parent_node == null \
			or not is_instance_valid(_parent_node) \
			or not _parent_node.is_inside_tree() \
			or _parent_node.get_world_3d() == null:
		return false
	if VISUAL_FOCUS_HELPER.is_node_in_target_camera_focus(self, _parent_node):
		return true
	var camera := _get_active_camera(delta)
	if not _is_camera_usable(camera):
		return false
	if _parent_node.global_position.distance_squared_to(camera.global_position) > max_effect_distance_m * max_effect_distance_m:
		return false
	if require_camera_frustum and not _is_effect_in_camera_frustum(camera):
		return false
	return true

func _is_effect_in_camera_frustum(camera: Camera3D) -> bool:
	if not _is_camera_usable(camera) \
			or _parent_node == null \
			or not is_instance_valid(_parent_node) \
			or not _parent_node.is_inside_tree():
		return false
	var base_pos := _parent_node.global_position
	if camera.is_position_in_frustum(base_pos):
		return true
	for offset in _emit_offsets:
		var emit_pos := _parent_node.to_global(offset)
		if camera.is_position_in_frustum(emit_pos):
			return true
		if camera.is_position_in_frustum(emit_pos + Vector3.UP * maxf(camera_frustum_padding_m, 0.0)):
			return true
	return false

func _sample_ground_color() -> void:
	if _parent_node == null or not is_instance_valid(_parent_node) or not _parent_node.is_inside_tree():
		return
	var world := _parent_node.get_world_3d()
	if world == null:
		return
	var space := world.direct_space_state
	var origin := _parent_node.global_position

	# Raycast to one point offset from the parent to find lit ground
	var sample_radius: float = 60.0 if _parent_node is CarrierTread else 15.0
	var angle: float = randf() * TAU
	var offset := Vector3(cos(angle) * sample_radius, 0, sin(angle) * sample_radius)
	var sample_origin := origin + offset
	var ray_from := Vector3(sample_origin.x, sample_origin.y + 30.0, sample_origin.z)
	var ray_to := Vector3(sample_origin.x, sample_origin.y - 80.0, sample_origin.z)
	var params := PhysicsRayQueryParameters3D.create(ray_from, ray_to)
	params.collision_mask = 1
	params.exclude = _exclude_rids
	var hit := space.intersect_ray(params)
	if not _is_terrain_hit(hit):
		return
	var ground_pos: Vector3 = hit.position

	var terrain_color: Variant = _get_terrain_surface_color(ground_pos)
	if terrain_color is Color:
		_shared_dust_color = _shared_dust_color.lerp(_sanitize_dust_color(terrain_color), 0.3)
		return

	var camera := _get_active_camera(0.0)
	if camera == null:
		return
	if camera.is_position_behind(ground_pos):
		return

	# Sample a single screen pixel at the ground point
	var screen_pos := camera.unproject_position(ground_pos)
	var vp_size := get_viewport().get_visible_rect().size
	var px := int(clampf(screen_pos.x, 0, vp_size.x - 1))
	var py := int(clampf(screen_pos.y, 0, vp_size.y - 1))

	var image := get_viewport().get_texture().get_image()
	if image == null:
		return
	var pixel: Color = image.get_pixel(px, py)
	# Skip if shadowed
	if pixel.get_luminance() < 0.15:
		return
	# Blend toward new sample gradually
	_shared_dust_color = _shared_dust_color.lerp(_sanitize_dust_color(pixel), 0.3)

func _get_terrain_surface_color(world_pos: Vector3) -> Variant:
	var terrain := TerrainReference.get_terrain_node()
	if terrain != null and terrain.has_method("get_surface_color"):
		var color_variant: Variant = terrain.call("get_surface_color", world_pos)
		if color_variant is Color:
			return color_variant
	return null

func _spawn_dust_puff(index: int, speed_ratio: float) -> void:
	var emit_world: Vector3 = _parent_node.to_global(_emit_offsets[index])
	emit_world.x += randf_range(-1.5, 1.5)
	emit_world.z += randf_range(-1.5, 1.5)

	# Raycast down to terrain, excluding parent
	var space := _parent_node.get_world_3d().direct_space_state
	var ray_from := Vector3(emit_world.x, emit_world.y + 30.0, emit_world.z)
	var ray_to := Vector3(emit_world.x, emit_world.y - 60.0, emit_world.z)
	var params := PhysicsRayQueryParameters3D.create(ray_from, ray_to)
	params.collision_mask = 1
	params.exclude = _exclude_rids
	var hit := space.intersect_ray(params)
	var puff_pos: Vector3 = emit_world  # fallback when raycast misses
	if _is_terrain_hit(hit):
		puff_pos = hit.position

	var puff := _acquire_pooled_puff()
	if puff == null:
		return
	puff.visible = true
	puff.global_position = puff_pos

	# Reuse shared mesh — only vary scale per puff
	var r: float = lerpf(puff_scale_min, puff_scale_max, speed_ratio) * randf_range(0.7, 1.3)

	var s: float = randf_range(0.8, 1.2) * r
	puff.scale = Vector3(s, s * randf_range(0.6, 1.0), s)

	var mat := puff.material_override as StandardMaterial3D
	if mat == null:
		return
	var variation: float = randf_range(-0.04, 0.04)
	var base_color: Color = _sanitize_dust_color(_shared_dust_color)
	mat.albedo_color = Color(
		clampf(base_color.r + variation, 0.0, 1.0),
		clampf(base_color.g + variation, 0.0, 1.0),
		clampf(base_color.b + variation, 0.0, 1.0),
		clampf(lerpf(0.05, 0.12, speed_ratio) * maxf(puff_opacity_multiplier, 0.0), 0.0, 1.0)
	)

	var yaw_speed: float = randf_range(-0.5, 0.5)
	var rise: float = puff_rise_speed * randf_range(0.6, 1.6)
	ParticleManager.add_rising_smoke(puff, puff_lifetime_s, puff.scale, rise, yaw_speed, {
		"on_finish": Callable(self, "_release_pooled_puff")
	})
