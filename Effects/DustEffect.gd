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

var _emit_offsets: Array[Vector3] = []
var _timers: Array[float] = []
var _parent_node: Node3D = null
var _last_position: Vector3 = Vector3.ZERO
var _speed: float = 0.0
var _exclude_rids: Array[RID] = []

# Shared across all instances
static var _shared_dust_color: Color = Color(0.55, 0.30, 0.18, 1.0)
static var _shared_mesh: SphereMesh = null
static var _shared_color_sample_cooldown: float = 0.0
static var dust_enabled: bool = true

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

	_last_position = _parent_node.global_position

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

func _physics_process(delta: float) -> void:
	if _parent_node == null or not is_instance_valid(_parent_node):
		return

	var current_pos := _parent_node.global_position
	_speed = current_pos.distance_to(_last_position) / maxf(delta, 0.001)
	_last_position = current_pos

	if not dust_enabled or _speed < min_speed_mps:
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

func _sample_ground_color() -> void:
	var camera := get_viewport().get_camera_3d()
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
	if hit.is_empty():
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
	if hit.is_empty():
		return

	var puff := MeshInstance3D.new()
	get_tree().current_scene.add_child(puff)
	puff.global_position = hit.position

	# Reuse shared mesh — only vary scale per puff
	var r: float = lerpf(puff_scale_min, puff_scale_max, speed_ratio) * randf_range(0.7, 1.3)
	_shared_mesh.radius = 1.0
	_shared_mesh.height = 2.0
	puff.mesh = _shared_mesh

	var s: float = randf_range(0.8, 1.2) * r
	puff.scale = Vector3(s, s * randf_range(0.6, 1.0), s)

	# One material per puff (needed for individual alpha fade) but minimal setup
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	var variation: float = randf_range(-0.04, 0.04)
	var base_color: Color = _shared_dust_color
	mat.albedo_color = Color(
		base_color.r + variation,
		base_color.g + variation,
		base_color.b + variation,
		lerpf(0.05, 0.12, speed_ratio)
	)
	puff.material_override = mat

	var yaw_speed: float = randf_range(-0.5, 0.5)
	var rise: float = puff_rise_speed * randf_range(0.6, 1.6)
	ParticleManager.add_rising_smoke(puff, puff_lifetime_s, puff.scale, rise, yaw_speed)
