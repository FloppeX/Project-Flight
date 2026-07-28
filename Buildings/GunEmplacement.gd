extends StaticBody3D
class_name GunEmplacement

signal destroyed(emplacement)
signal damaged(amount: float, health: float)

@export var max_health: float = 150.0
@export var team: int = 2
@export var destroyed_scene_path: String = ""
@export var turret_controller_path: NodePath = NodePath("TurretController")
@export var activation_distance_m: float = 1500.0
@export var deactivation_distance_m: float = 1800.0
@export var activation_check_interval_s: float = 1.0
@export var inactive_when_no_targets: bool = true
@export var full_deactivation_when_no_targets: bool = true
@export var collider_ground_clearance_m: float = 0.0
@export var is_dummy: bool = false
@export var weapon_scene_10mm: PackedScene = preload("res://Weapons/Turrets/bullet_weapon.tscn")
@export var weapon_scene_15mm: PackedScene = preload("res://Weapons/Turrets/bullet_weapon_15mm.tscn")
@export var weapon_scene_20mm: PackedScene = preload("res://Weapons/Turrets/bullet_weapon_20mm.tscn")

var current_health: float = 0.0
var is_destroyed: bool = false
var _explosion_scene: PackedScene = null
var _turret_controller: TurretController = null
var _active: bool = true
var _full_presence_active: bool = true
var _activation_timer_s: float = 0.0
var _presence_collision_shape_refs: Array[WeakRef] = []
var _original_root_visible: bool = true

func _ready() -> void:
	current_health = max_health
	_explosion_scene = load("res://Projectiles/Explosion/explosion.tscn")
	_original_root_visible = visible

	add_to_group("gun_emplacements")
	add_to_group("buildings")
	add_to_group("team_" + str(team))
	if team == 1:
		add_to_group("friendlies")
	else:
		add_to_group("enemies")

	_turret_controller = get_node_or_null(turret_controller_path) as TurretController
	if _turret_controller:
		_turret_controller.team = team
		if is_dummy:
			_turret_controller.weapon_scene = null
		else:
			_assign_random_weapon_scene()
	_apply_team_main_color()
	call_deferred("_apply_team_main_color")
	if inactive_when_no_targets:
		_set_turret_active(false)
		if full_deactivation_when_no_targets:
			_set_full_presence_active(false)
		_activation_timer_s = randf_range(0.0, maxf(activation_check_interval_s, 0.1))
	set_process(true)

func _process(delta: float) -> void:
	if is_destroyed or not inactive_when_no_targets:
		return
	_activation_timer_s -= delta
	if _activation_timer_s > 0.0:
		return
	_activation_timer_s = maxf(activation_check_interval_s, 0.1)
	var should_activate: bool = _has_hostile_within_relevance_range()
	if should_activate != _active:
		_set_turret_active(should_activate)
	if full_deactivation_when_no_targets and should_activate != _full_presence_active:
		_set_full_presence_active(should_activate)

func get_team() -> int:
	return team

func is_turret_active() -> bool:
	return _active

func is_full_presence_active() -> bool:
	return _full_presence_active

func take_damage(damage_amount: float) -> void:
	if is_destroyed:
		return
	current_health = maxf(current_health - damage_amount, 0.0)
	damaged.emit(damage_amount, current_health)
	if current_health <= 0.0:
		_destroy()

func _destroy() -> void:
	if is_destroyed:
		return
	is_destroyed = true
	destroyed.emit(self)

	if destroyed_scene_path != "":
		var destroyed_scene: PackedScene = load(destroyed_scene_path)
		if destroyed_scene:
			var wreck: Node3D = destroyed_scene.instantiate()
			get_tree().current_scene.add_child(wreck)
			wreck.global_transform = global_transform

	if _explosion_scene:
		var exp: Node3D = _explosion_scene.instantiate()
		get_tree().current_scene.add_child(exp)
		exp.global_position = global_position + Vector3(0.0, 1.2, 0.0)

	queue_free()

func _assign_random_weapon_scene() -> void:
	if is_dummy or _turret_controller == null:
		return
	var pool: Array[PackedScene] = []
	if weapon_scene_10mm != null:
		pool.append(weapon_scene_10mm)
	if weapon_scene_15mm != null:
		pool.append(weapon_scene_15mm)
	if weapon_scene_20mm != null:
		pool.append(weapon_scene_20mm)
	if pool.is_empty():
		return
	var selected_scene: PackedScene = pool[randi() % pool.size()]
	_turret_controller.weapon_scene = selected_scene
	_turret_controller.mount_weapon(selected_scene)

func _set_turret_active(enabled: bool) -> void:
	_active = enabled
	if _turret_controller == null:
		return
	_turret_controller.set_process(enabled)
	_turret_controller.set_physics_process(enabled)
	if not enabled:
		if _turret_controller.turret:
			_turret_controller.turret.set_target(null)
		if _turret_controller.weapon_instance and _turret_controller.weapon_instance.has_method("stop_firing"):
			_turret_controller.weapon_instance.stop_firing()

func _set_full_presence_active(enabled: bool) -> void:
	_full_presence_active = enabled
	_cache_presence_nodes()
	visible = _original_root_visible if enabled else false

	for ref: WeakRef in _presence_collision_shape_refs:
		var collision_shape: CollisionShape3D = _resolve_weak_node(ref) as CollisionShape3D
		if collision_shape == null:
			continue
		if enabled:
			var original_disabled: Variant = collision_shape.get_meta("gun_emplacement_original_disabled", false)
			collision_shape.disabled = bool(original_disabled)
		else:
			collision_shape.disabled = true

func _cache_presence_nodes() -> void:
	if not _presence_collision_shape_refs.is_empty():
		return
	_cache_presence_nodes_recursive(self)

func _cache_presence_nodes_recursive(node: Node) -> void:
	if node is CollisionShape3D:
		var collision_shape: CollisionShape3D = node as CollisionShape3D
		if not collision_shape.has_meta("gun_emplacement_original_disabled"):
			collision_shape.set_meta("gun_emplacement_original_disabled", collision_shape.disabled)
		_presence_collision_shape_refs.append(weakref(collision_shape))
	for child: Node in node.get_children():
		_cache_presence_nodes_recursive(child)

func _resolve_weak_node(ref: WeakRef) -> Node:
	var object: Object = ref.get_ref()
	if object == null or not is_instance_valid(object):
		return null
	return object as Node

func _has_hostile_within_relevance_range() -> bool:
	var range_m: float = activation_distance_m
	if _active:
		range_m = maxf(deactivation_distance_m, activation_distance_m)
	return _has_hostile_within_range(range_m)

func _has_hostile_within_range(range_m: float) -> bool:
	range_m = maxf(range_m, 10.0)
	var range_sq: float = range_m * range_m
	var groups: Array[String] = _get_hostile_groups_for_team(team)
	for group_name in groups:
		var nodes: Array = get_tree().get_nodes_in_group(group_name)
		for node in nodes:
			if not (node is Node3D):
				continue
			if not is_instance_valid(node):
				continue
			if node == self:
				continue
			var node3d := node as Node3D
			if global_position.distance_squared_to(node3d.global_position) > range_sq:
				continue
			if node3d.has_method("get_team"):
				var node_team: int = int(node3d.call("get_team"))
				if node_team == team:
					continue
			return true
	return false

func _get_hostile_groups_for_team(team_id: int) -> Array[String]:
	if team_id == 1:
		return ["enemies", "aircraft", "ai_aircraft", "ground_vehicles"]
	return ["aircraft", "friendlies", "carrier", "ground_vehicles"]

func _apply_team_main_color() -> void:
	var team_color: Color = _get_team_main_color()
	var root_node: Node = self
	_apply_main_color_recursive(root_node, team_color)

func _get_team_main_color() -> Color:
	var fallback_color: Color = Color(0.78, 0.20, 0.15) if team == 2 else Color(0.22, 0.44, 0.76)
	var livery_node: Node = get_node_or_null("/root/Livery")
	if livery_node != null and livery_node.has_method("_get_team_upper_color"):
		var color_variant: Variant = livery_node.call("_get_team_upper_color", team)
		if color_variant is Color:
			return color_variant as Color
	if livery_node != null:
		var upper_variant: Variant = livery_node.get("upper_color")
		if upper_variant is Color:
			return upper_variant as Color
	return fallback_color

func _apply_main_color_recursive(node: Node, team_color: Color) -> void:
	if node is MeshInstance3D:
		_apply_main_color_to_mesh(node as MeshInstance3D, team_color)
	for child in node.get_children():
		_apply_main_color_recursive(child, team_color)

func _apply_main_color_to_mesh(mesh_instance: MeshInstance3D, team_color: Color) -> void:
	var mesh: Mesh = mesh_instance.mesh
	if mesh == null:
		return
	var surface_count: int = mesh.get_surface_count()
	for surface_idx in range(surface_count):
		var source_material: Material = mesh_instance.get_active_material(surface_idx)
		if source_material == null:
			source_material = mesh.surface_get_material(surface_idx)
		if source_material == null:
			continue

		var override_material: Material = source_material.duplicate()
		if override_material is StandardMaterial3D and _is_main_color_material(source_material):
			var standard_material: StandardMaterial3D = override_material as StandardMaterial3D
			standard_material.albedo_color = team_color
		elif override_material is ShaderMaterial:
			var shader_material: ShaderMaterial = override_material as ShaderMaterial
			var changed_shader: bool = false
			changed_shader = _set_shader_color_if_declared(shader_material, "Main_Color", team_color) or changed_shader
			changed_shader = _set_shader_color_if_declared(shader_material, "main_color", team_color) or changed_shader
			changed_shader = _set_shader_color_if_declared(shader_material, "Main_Color_Dark", team_color.darkened(0.35)) or changed_shader
			changed_shader = _set_shader_color_if_declared(shader_material, "main_color_dark", team_color.darkened(0.35)) or changed_shader
			if not changed_shader:
				continue
		else:
			continue
		mesh_instance.set_surface_override_material(surface_idx, override_material)

func _is_main_color_material(material: Material) -> bool:
	if material == null:
		return false
	var material_name: String = String(material.resource_name).to_lower().replace("_", " ").replace("-", " ")
	if "main color" in material_name:
		return true
	if material is StandardMaterial3D:
		var standard_material := material as StandardMaterial3D
		var albedo_texture: Texture2D = standard_material.albedo_texture
		if albedo_texture != null:
			var texture_name: String = String(albedo_texture.resource_name).to_lower().replace("_", " ").replace("-", " ")
			var texture_path: String = String(albedo_texture.resource_path).to_lower().replace("_", " ").replace("-", " ")
			return "main color" in texture_name or "main color" in texture_path
	return false

func _set_shader_color_if_declared(shader_material: ShaderMaterial, parameter_name: String, value: Color) -> bool:
	if shader_material == null or shader_material.shader == null:
		return false
	var shader_code: String = shader_material.shader.code
	if shader_code.find(parameter_name) == -1:
		return false
	shader_material.set_shader_parameter(parameter_name, value)
	return true

func snap_collider_to_ground() -> void:
	var terrain_y: float = TerrainNavGrid.sample_height(global_position.x, global_position.z)
	if terrain_y <= TerrainNavGrid.IMPASSABLE * 0.5:
		return
	var lowest_local_y: float = _get_lowest_collision_local_y()
	global_position.y = terrain_y - lowest_local_y + collider_ground_clearance_m

func _get_lowest_collision_local_y() -> float:
	var lowest_local_y: float = INF
	for node in find_children("*", "CollisionShape3D", true, false):
		var collision_shape: CollisionShape3D = node as CollisionShape3D
		if collision_shape == null or collision_shape.shape == null:
			continue
		lowest_local_y = minf(lowest_local_y, _get_collision_shape_min_local_y(collision_shape))
	if is_finite(lowest_local_y):
		return lowest_local_y
	return 0.0

func _get_collision_shape_min_local_y(collision_shape: CollisionShape3D) -> float:
	var local_aabb: AABB = _get_shape_local_aabb(collision_shape.shape)
	var min_local_y: float = INF
	for xi in range(2):
		for yi in range(2):
			for zi in range(2):
				var corner := Vector3(
					local_aabb.position.x + (local_aabb.size.x if xi == 1 else 0.0),
					local_aabb.position.y + (local_aabb.size.y if yi == 1 else 0.0),
					local_aabb.position.z + (local_aabb.size.z if zi == 1 else 0.0)
				)
				var transformed: Vector3 = collision_shape.transform * corner
				min_local_y = minf(min_local_y, transformed.y)
	if is_finite(min_local_y):
		return min_local_y
	return collision_shape.position.y

func _get_shape_local_aabb(shape: Shape3D) -> AABB:
	if shape is BoxShape3D:
		var box: BoxShape3D = shape as BoxShape3D
		var half := box.size * 0.5
		return AABB(-half, box.size)
	if shape is SphereShape3D:
		var sphere: SphereShape3D = shape as SphereShape3D
		var diameter := sphere.radius * 2.0
		return AABB(Vector3(-sphere.radius, -sphere.radius, -sphere.radius), Vector3(diameter, diameter, diameter))
	if shape is CapsuleShape3D:
		var capsule: CapsuleShape3D = shape as CapsuleShape3D
		var half_height := maxf(capsule.radius, capsule.height * 0.5)
		var diameter := capsule.radius * 2.0
		return AABB(Vector3(-capsule.radius, -half_height, -capsule.radius), Vector3(diameter, half_height * 2.0, diameter))
	if shape is CylinderShape3D:
		var cylinder: CylinderShape3D = shape as CylinderShape3D
		var half_height := cylinder.height * 0.5
		var diameter := cylinder.radius * 2.0
		return AABB(Vector3(-cylinder.radius, -half_height, -cylinder.radius), Vector3(diameter, cylinder.height, diameter))
	if shape is ConvexPolygonShape3D:
		var convex: ConvexPolygonShape3D = shape as ConvexPolygonShape3D
		var points: PackedVector3Array = convex.points
		if not points.is_empty():
			var aabb: AABB = AABB(points[0], Vector3.ZERO)
			for i in range(1, points.size()):
				aabb = aabb.expand(points[i])
			return aabb
	var debug_mesh: Mesh = shape.get_debug_mesh()
	if debug_mesh != null:
		return debug_mesh.get_aabb()
	return AABB(Vector3.ZERO, Vector3.ZERO)
