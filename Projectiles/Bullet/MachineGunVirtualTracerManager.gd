extends Node3D
class_name MachineGunVirtualTracerManager

const TRACER_VISUAL_FACTORY := preload("res://Projectiles/Bullet/TracerVisualFactory.gd")

## Batches cosmetic machine-gun rounds into one MultiMesh. These tracers carry
## no collision or damage; physical projectiles remain on the authored gun rate.

@export var max_active_tracers: int = 512
@export var tracer_color: Color = Color(1.0, 0.72, 0.16, 1.0)
@export var tracer_emission_energy: float = 5.0
@export var tracer_length_ramp_s: float = 0.05

var _tracers: Array[Dictionary] = []
var _multimesh_instance: MultiMeshInstance3D
var _multimesh: MultiMesh


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	add_to_group("origin_shifter")
	_build_batch()
	set_physics_process(false)


func spawn_tracer(
	world_position: Vector3,
	muzzle_velocity: Vector3,
	firing_entity: Node3D,
	lifetime_s: float,
	width_m: float,
	length_m: float,
	initial_age_s: float = 0.0
) -> bool:
	var initial_age := maxf(initial_age_s, 0.0)
	if muzzle_velocity.length_squared() <= 0.01 or lifetime_s <= initial_age:
		return false
	if _multimesh == null:
		_build_batch()
	if _multimesh == null:
		return false

	var velocity := muzzle_velocity + _get_motion_velocity(firing_entity)
	if firing_entity != null and is_instance_valid(firing_entity):
		var angular_velocity := _get_motion_angular_velocity(firing_entity)
		if angular_velocity.length_squared() > 0.000001:
			velocity += angular_velocity.cross(world_position - firing_entity.global_position)
	var gravity := _get_gravity()
	world_position += velocity * initial_age + gravity * (0.5 * initial_age * initial_age)
	velocity += gravity * initial_age

	if _tracers.size() >= maxi(max_active_tracers, 1):
		_tracers.remove_at(0)
	_tracers.append({
		"position": world_position,
		"velocity": velocity,
		"age_s": initial_age,
		"lifetime_s": lifetime_s,
		"width_m": maxf(width_m, 0.01),
		"length_m": maxf(length_m, 0.05),
	})
	_sync_batch()
	set_physics_process(true)
	return true


func _physics_process(delta: float) -> void:
	var gravity := _get_gravity()
	for index in range(_tracers.size() - 1, -1, -1):
		var tracer: Dictionary = _tracers[index]
		var age_s := float(tracer.get("age_s", 0.0)) + delta
		if age_s >= float(tracer.get("lifetime_s", 0.0)):
			_tracers.remove_at(index)
			continue
		var position_value: Vector3 = tracer.get("position", Vector3.ZERO)
		var velocity_value: Vector3 = tracer.get("velocity", Vector3.ZERO)
		position_value += velocity_value * delta + gravity * (0.5 * delta * delta)
		velocity_value += gravity * delta
		tracer["position"] = position_value
		tracer["velocity"] = velocity_value
		tracer["age_s"] = age_s
		_tracers[index] = tracer
	_sync_batch()
	if _tracers.is_empty():
		set_physics_process(false)


func _get_gravity() -> Vector3:
	var gravity_direction: Vector3 = ProjectSettings.get_setting(
		"physics/3d/default_gravity_vector",
		Vector3(0.0, -1.0, 0.0)
	)
	var gravity_magnitude := float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	return gravity_direction.normalized() * gravity_magnitude


func apply_origin_shift(offset: Vector3) -> void:
	for index in _tracers.size():
		var tracer: Dictionary = _tracers[index]
		tracer["position"] = (tracer.get("position", Vector3.ZERO) as Vector3) - offset
		_tracers[index] = tracer
	_sync_batch()


func get_stats() -> Dictionary:
	return {
		"active": _tracers.size(),
		"capacity": maxi(max_active_tracers, 1),
		"draw_batches": 1 if _multimesh_instance != null else 0,
		"physics_projectiles": 0,
	}


func clear_tracers() -> void:
	_tracers.clear()
	_sync_batch()
	set_physics_process(false)


func _build_batch() -> void:
	if _multimesh_instance != null:
		return
	_multimesh_instance = MultiMeshInstance3D.new()
	_multimesh_instance.name = "VirtualTracerBatch"
	_multimesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_multimesh_instance)

	var mesh: ArrayMesh = TRACER_VISUAL_FACTORY.create_unit_tracer_mesh()
	var material: StandardMaterial3D = TRACER_VISUAL_FACTORY.create_glow_material(
		tracer_color,
		tracer_emission_energy
	)
	mesh.surface_set_material(0, material)

	_multimesh = MultiMesh.new()
	_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_multimesh.instance_count = maxi(max_active_tracers, 1)
	_multimesh.visible_instance_count = 0
	_multimesh.mesh = mesh
	_multimesh_instance.multimesh = _multimesh


func _sync_batch() -> void:
	if _multimesh == null:
		return
	var visible_count := mini(_tracers.size(), _multimesh.instance_count)
	_multimesh.visible_instance_count = visible_count
	if visible_count <= 0:
		return

	var bounds := AABB()
	var bounds_started := false
	for index in visible_count:
		var tracer: Dictionary = _tracers[index]
		var position_value: Vector3 = tracer.get("position", Vector3.ZERO)
		var velocity_value: Vector3 = tracer.get("velocity", Vector3.ZERO)
		var width_m := float(tracer.get("width_m", 0.2))
		var length_m := float(tracer.get("length_m", 0.8))
		var age_s := float(tracer.get("age_s", 0.0))
		var ramp_t := clampf(age_s / maxf(tracer_length_ramp_s, 0.001), 0.0, 1.0)
		length_m *= lerpf(0.12, 1.0, smoothstep(0.0, 1.0, ramp_t))
		var transform_value := _make_tracer_transform(position_value, velocity_value, width_m, length_m)
		_multimesh.set_instance_transform(index, transform_value)
		var half_extent := Vector3.ONE * maxf(length_m, width_m)
		var tracer_bounds := AABB(transform_value.origin - half_extent, half_extent * 2.0)
		bounds = tracer_bounds if not bounds_started else bounds.merge(tracer_bounds)
		bounds_started = true
	if bounds_started:
		_multimesh.custom_aabb = bounds


func _make_tracer_transform(
	position_value: Vector3,
	velocity_value: Vector3,
	width_m: float,
	length_m: float
) -> Transform3D:
	var travel_direction := velocity_value.normalized()
	if travel_direction.length_squared() <= 0.0001:
		travel_direction = Vector3.FORWARD
	var up_hint := Vector3.UP
	if absf(travel_direction.dot(up_hint)) > 0.999:
		up_hint = Vector3.FORWARD
	var z_axis := -travel_direction
	var x_axis := up_hint.cross(z_axis).normalized()
	var y_axis := z_axis.cross(x_axis).normalized()
	var basis := Basis(x_axis, y_axis, z_axis).scaled(Vector3(width_m, width_m, length_m))
	# Unit mesh base is at local Z=0, so the wide end remains at the bullet and
	# local +Z tapers backward along -travel_direction.
	return Transform3D(basis, position_value)


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
		var getter_variant: Variant = node.call("get_linear_velocity")
		if getter_variant is Vector3:
			return getter_variant
	if node.has_method("get_velocity_vector"):
		var vector_variant: Variant = node.call("get_velocity_vector")
		if vector_variant is Vector3:
			return vector_variant
	return Vector3.ZERO


func _get_motion_angular_velocity(node: Node) -> Vector3:
	if node == null or not is_instance_valid(node):
		return Vector3.ZERO
	var angular_variant: Variant = node.get("angular_velocity")
	if angular_variant is Vector3:
		return angular_variant
	if node.has_method("get_angular_velocity"):
		var getter_variant: Variant = node.call("get_angular_velocity")
		if getter_variant is Vector3:
			return getter_variant
	return Vector3.ZERO
