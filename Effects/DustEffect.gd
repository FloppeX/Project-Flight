extends Node3D
class_name DustEffect

## Spawns rising dust puffs at ground contact points while moving.

@export var min_speed_mps: float = 2.0
@export var spawn_interval_s: float = 0.25
@export var puff_scale_min: float = 0.6
@export var puff_scale_max: float = 2.0
@export var full_speed_mps: float = 20.0
@export var puff_lifetime_s: float = 5.0
@export var puff_rise_speed: float = 7.0
@export var max_effect_distance_m: float = 800.0
@export var pooled_puff_count: int = 16

var _emit_offsets: Array[Vector3] = []
var _timers: Array[float] = []
var _parent_node: Node3D = null
var _last_position: Vector3 = Vector3.ZERO
var _speed: float = 0.0
var _exclude_rids: Array[RID] = []
var _cached_camera: Camera3D = null
var _camera_cache_timer_s: float = 0.0
var _puff_pool: Array[MeshInstance3D] = []
var _available_puff_indices: Array[int] = []

# Shared across all instances
static var _shared_dust_color: Color = Color(0.55, 0.30, 0.18, 1.0)
static var _shared_mesh: SphereMesh = null
static var _shared_color_sample_cooldown: float = 0.0
static var dust_enabled: bool = true

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

	_initialize_puff_pool()
	_last_position = _parent_node.global_position

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
	var scene_root := get_tree().current_scene
	if scene_root == null:
		return
	_shared_mesh.radius = 1.0
	_shared_mesh.height = 2.0
	for i in range(maxi(pooled_puff_count, 1)):
		var puff := MeshInstance3D.new()
		puff.visible = false
		puff.mesh = _shared_mesh
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.albedo_color = Color(1.0, 1.0, 1.0, 0.0)
		puff.material_override = mat
		puff.set_meta("dust_pool_index", i)
		scene_root.add_child(puff)
		_puff_pool.append(puff)
		_available_puff_indices.append(i)

func _acquire_pooled_puff() -> MeshInstance3D:
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
	if _parent_node == null or not is_instance_valid(_parent_node):
		return

	var current_pos := _parent_node.global_position
	_speed = current_pos.distance_to(_last_position) / maxf(delta, 0.001)
	_last_position = current_pos

	if not dust_enabled or _speed < min_speed_mps or not _should_emit_for_camera(delta):
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
	if _cached_camera and is_instance_valid(_cached_camera) and _camera_cache_timer_s > 0.0:
		return _cached_camera
	_cached_camera = get_viewport().get_camera_3d()
	_camera_cache_timer_s = 0.25
	return _cached_camera

func _should_emit_for_camera(delta: float) -> bool:
	var camera := _get_active_camera(delta)
	if camera == null or not is_instance_valid(camera):
		return false
	if _parent_node.global_position.distance_squared_to(camera.global_position) > max_effect_distance_m * max_effect_distance_m:
		return false
	if camera.is_position_behind(_parent_node.global_position):
		return false
	return true

func _sample_ground_color() -> void:
	var camera := _get_active_camera(0.0)
	if camera == null:
		return
	var space := _parent_node.get_world_3d().direct_space_state
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
	_shared_dust_color = _shared_dust_color.lerp(pixel, 0.3)

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
	if not _is_terrain_hit(hit):
		return

	var puff := _acquire_pooled_puff()
	if puff == null:
		return
	puff.visible = true
	puff.global_position = hit.position

	# Reuse shared mesh — only vary scale per puff
	var r: float = lerpf(puff_scale_min, puff_scale_max, speed_ratio) * randf_range(0.7, 1.3)

	var s: float = randf_range(0.8, 1.2) * r
	puff.scale = Vector3(s, s * randf_range(0.6, 1.0), s)

	var mat := puff.material_override as StandardMaterial3D
	if mat == null:
		return
	var variation: float = randf_range(-0.04, 0.04)
	var base_color: Color = _shared_dust_color
	mat.albedo_color = Color(
		base_color.r + variation,
		base_color.g + variation,
		base_color.b + variation,
		lerpf(0.05, 0.12, speed_ratio)
	)

	var yaw_speed: float = randf_range(-0.5, 0.5)
	var rise: float = puff_rise_speed * randf_range(0.6, 1.6)
	ParticleManager.add_rising_smoke(puff, puff_lifetime_s, puff.scale, rise, yaw_speed, {
		"on_finish": Callable(self, "_release_pooled_puff")
	})
