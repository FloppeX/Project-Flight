extends Node3D
class_name RotorWashEffect

const VISUAL_FOCUS_HELPER = preload("res://Effects/VisualFocus.gd")

@export var spawn_interval_s: float = 0.08
@export var puff_scale_min: float = 1.0
@export var puff_scale_max: float = 2.5
@export var puff_opacity_multiplier: float = 1.35
@export var puff_lifetime_s: float = 3.0
@export var puff_rise_speed: float = 1.0
@export var outward_speed: float = 15.0
@export var max_effect_distance_m: float = 800.0
@export var require_camera_frustum: bool = true
@export var camera_frustum_padding_m: float = 25.0
@export var pooled_puff_count: int = 64
@export var max_agl_m: float = 25.0
@export_range(0.0, 1.0, 0.01) var min_rotor_power_for_dust: float = 0.35
@export_range(0.0, 1.0, 0.01) var full_rotor_power_for_dust: float = 0.8
@export var rotor_wash_power_response: float = 2.5
@export var visual_budget_enabled: bool = true

var rotor_radius: float = 10.0
var is_engine_on: bool = false
var rotor_power: float = 0.0
var current_agl: float = INF

var _spawn_timer: float = 0.0
var _parent_node: Node3D = null
var _exclude_rids: Array[RID] = []
var _cached_camera: Camera3D = null
var _camera_cache_timer_s: float = 0.0
var _puff_pool: Array[MeshInstance3D] = []
var _available_puff_indices: Array[int] = []
var _smoothed_rotor_power: float = 0.0

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
	_parent_node = get_parent() as Node3D
	if _parent_node == null:
		set_physics_process(false)
		return

	if _shared_mesh == null:
		_shared_mesh = SphereMesh.new()
		_shared_mesh.radial_segments = 4
		_shared_mesh.rings = 2

	await get_tree().process_frame

	if _parent_node is CollisionObject3D:
		_exclude_rids.append((_parent_node as CollisionObject3D).get_rid())
	for child in _parent_node.get_children():
		if child is CollisionObject3D:
			_exclude_rids.append((child as CollisionObject3D).get_rid())

	_initialize_puff_pool()

func _exit_tree() -> void:
	for puff in _puff_pool:
		if puff and is_instance_valid(puff):
			puff.queue_free()
	_puff_pool.clear()
	_available_puff_indices.clear()

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
		mat.albedo_color = Color(_shared_dust_color.r, _shared_dust_color.g, _shared_dust_color.b, 0.0)
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
	var wash_power := _get_rotor_wash_power(delta)
	if not visual_budget_enabled or not dust_enabled or wash_power <= 0.0 or current_agl > max_agl_m or not _should_emit_for_camera(delta):
		return

	_shared_color_sample_cooldown -= delta
	if _shared_color_sample_cooldown <= 0.0:
		_shared_color_sample_cooldown = 2.0
		_sample_ground_color()

	_spawn_timer -= delta
	if _spawn_timer <= 0.0:
		_spawn_timer = spawn_interval_s / lerpf(0.35, 1.0, wash_power)
		_spawn_dust_ring(wash_power)

func _get_rotor_wash_power(delta: float) -> float:
	var target_power := clampf(rotor_power, 0.0, 1.0) if is_engine_on else 0.0
	_smoothed_rotor_power = move_toward(
		_smoothed_rotor_power,
		target_power,
		maxf(rotor_wash_power_response, 0.0) * maxf(delta, 0.0)
	)
	var min_power := clampf(min_rotor_power_for_dust, 0.0, 1.0)
	var full_power := maxf(clampf(full_rotor_power_for_dust, 0.0, 1.0), min_power + 0.001)
	var ramp := clampf((_smoothed_rotor_power - min_power) / (full_power - min_power), 0.0, 1.0)
	return ramp * ramp * (3.0 - 2.0 * ramp)

func _get_active_camera(delta: float) -> Camera3D:
	_camera_cache_timer_s = maxf(_camera_cache_timer_s - delta, 0.0)
	if _cached_camera and is_instance_valid(_cached_camera) and _camera_cache_timer_s > 0.0:
		return _cached_camera
	_cached_camera = get_viewport().get_camera_3d()
	_camera_cache_timer_s = 0.25
	return _cached_camera

func _should_emit_for_camera(delta: float) -> bool:
	if VISUAL_FOCUS_HELPER.is_node_in_target_camera_focus(self, _parent_node):
		return true
	var camera := _get_active_camera(delta)
	if camera == null or not is_instance_valid(camera):
		return false
	if _parent_node.global_position.distance_squared_to(camera.global_position) > max_effect_distance_m * max_effect_distance_m:
		return false
	if require_camera_frustum and not _is_effect_in_camera_frustum(camera):
		return false
	return true

func _is_effect_in_camera_frustum(camera: Camera3D) -> bool:
	var base_pos := _parent_node.global_position
	if camera.is_position_in_frustum(base_pos):
		return true
	var radius := maxf(rotor_radius, 1.0)
	var height := maxf(camera_frustum_padding_m, 0.0)
	for offset in [
		Vector3(radius, 0.0, 0.0),
		Vector3(-radius, 0.0, 0.0),
		Vector3(0.0, 0.0, radius),
		Vector3(0.0, 0.0, -radius),
		Vector3(0.0, -maxf(current_agl, 0.0), 0.0),
		Vector3(0.0, height, 0.0),
	]:
		if camera.is_position_in_frustum(base_pos + offset):
			return true
	return false

func _sample_ground_color() -> void:
	var space := _parent_node.get_world_3d().direct_space_state
	var origin := _parent_node.global_position

	var ray_from := Vector3(origin.x, origin.y + 10.0, origin.z)
	var ray_to := Vector3(origin.x, origin.y - max_agl_m - 10.0, origin.z)
	var params := PhysicsRayQueryParameters3D.create(ray_from, ray_to)
	params.collision_mask = 1
	params.exclude = _exclude_rids
	var hit := space.intersect_ray(params)
	if not _is_terrain_hit(hit):
		return
	var ground_pos: Vector3 = hit.position

	var terrain_color: Variant = _get_terrain_surface_color(ground_pos)
	if terrain_color is Color:
		_shared_dust_color = _shared_dust_color.lerp(_sanitize_dust_color(terrain_color), 0.4)
		return

	var camera := _get_active_camera(0.0)
	if camera == null:
		return
	if camera.is_position_behind(ground_pos):
		return

	var screen_pos := camera.unproject_position(ground_pos)
	var vp_size := get_viewport().get_visible_rect().size
	var px := int(clampf(screen_pos.x, 0, vp_size.x - 1))
	var py := int(clampf(screen_pos.y, 0, vp_size.y - 1))

	var image := get_viewport().get_texture().get_image()
	if image == null:
		return
	var pixel: Color = image.get_pixel(px, py)
	if pixel.get_luminance() < 0.15:
		return
	_shared_dust_color = _shared_dust_color.lerp(_sanitize_dust_color(pixel), 0.4)

func _get_terrain_surface_color(world_pos: Vector3) -> Variant:
	var terrain := TerrainReference.get_terrain_node()
	if terrain != null and terrain.has_method("get_surface_color"):
		var color_variant: Variant = terrain.call("get_surface_color", world_pos)
		if color_variant is Color:
			return color_variant
	return null

func _spawn_dust_ring(wash_power: float) -> void:
	# Calculate intensity based on AGL (closer to ground = more intense)
	var height_intensity := clampf(1.0 - (current_agl / max_agl_m), 0.1, 1.0)
	var intensity := height_intensity * clampf(wash_power, 0.0, 1.0)
	var puffs_to_spawn := maxi(int(4 * intensity), 2)
	
	var space := _parent_node.get_world_3d().direct_space_state
	var base_origin := _parent_node.global_position
	
	# Raycast down from center to get ground height
	var center_ray_from := Vector3(base_origin.x, base_origin.y + 10.0, base_origin.z)
	var center_ray_to := Vector3(base_origin.x, base_origin.y - max_agl_m - 10.0, base_origin.z)
	var center_params := PhysicsRayQueryParameters3D.create(center_ray_from, center_ray_to)
	center_params.collision_mask = 1
	center_params.exclude = _exclude_rids
	var center_hit := space.intersect_ray(center_params)
	
	if not _is_terrain_hit(center_hit):
		return # Over carrier or deep water, no dust
		
	var ground_y: float = center_hit.position.y

	var angle_offset := randf() * TAU
	for i in range(puffs_to_spawn):
		var puff := _acquire_pooled_puff()
		if puff == null:
			break
			
		var angle := angle_offset + (float(i) / float(puffs_to_spawn)) * TAU
		var ring_radius := rotor_radius * randf_range(0.8, 1.1)
		
		var offset_x := cos(angle) * ring_radius
		var offset_z := sin(angle) * ring_radius
		
		# Spawn at ground level at the radius
		var puff_pos := Vector3(base_origin.x + offset_x, ground_y + 0.5, base_origin.z + offset_z)
		
		puff.visible = true
		puff.global_position = puff_pos

		var r: float = lerpf(puff_scale_min, puff_scale_max, intensity) * randf_range(0.7, 1.3)
		var s: float = randf_range(0.8, 1.2) * r
		puff.scale = Vector3(s, s * randf_range(0.6, 1.0), s)

		var mat := puff.material_override as StandardMaterial3D
		if mat:
			var variation: float = randf_range(-0.04, 0.04)
			var base_color: Color = _sanitize_dust_color(_shared_dust_color)
			mat.albedo_color = Color(
				clampf(base_color.r + variation, 0.0, 1.0),
				clampf(base_color.g + variation, 0.0, 1.0),
				clampf(base_color.b + variation, 0.0, 1.0),
				clampf(lerpf(0.05, 0.15, intensity) * maxf(puff_opacity_multiplier, 0.0), 0.0, 1.0)
			)

		var yaw_speed: float = randf_range(-0.5, 0.5)
		var rise: float = puff_rise_speed * randf_range(0.6, 1.6)
		
		# Push outwards from center
		var out_dir := Vector3(offset_x, 0, offset_z).normalized()
		var vel := out_dir * outward_speed * randf_range(0.8, 1.2) * intensity
		
		ParticleManager.add_outward_dust(puff, puff_lifetime_s, puff.scale, vel, rise, yaw_speed, {
			"on_finish": Callable(self, "_release_pooled_puff")
		})
