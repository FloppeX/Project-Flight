extends Area3D
## Sparse bullet target; physical disc contact uses a separate body-only query.
const BULLET_LAYER := 1 << 30
var model: AircraftPartDamageModel
var zone: StringName
var radius := 1.0
var blade_count := 3
var active := true
var _previous := Vector3.INF
var _query := PhysicsShapeQueryParameters3D.new()

func setup(owner_model: AircraftPartDamageModel, region: StringName, disc_radius: float, count: int) -> void:
	model = owner_model
	zone = region
	radius = disc_radius
	blade_count = count
	collision_layer = BULLET_LAYER
	collision_mask = 0
	monitoring = false
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = radius
	cylinder.height = 0.14
	shape.shape = cylinder
	add_child(shape)
	_query.shape = cylinder
	_query.collision_mask = 0xffffffff
	_query.exclude = [model.get_parent().get_rid()]
	_query.margin = 0.005

func accepts_bullet(world_point: Vector3, roll: float = -1.0) -> bool:
	if not active or model.is_zone_destroyed(zone): return false
	var point := to_local(world_point)
	if Vector2(point.x, point.z).length() < minf(radius * 0.18, 0.3): return true
	# One roll per projectile/disc, independent of frame rate and render phase.
	return (randf() if roll < 0.0 else roll) < clampf(blade_count * 0.025, 0.04, 0.18)

func take_damage(amount: float) -> void:
	model.get_parent().combat_damage_received.emit(amount, &"projectile")
	model.damage_zone(zone, amount)

func get_damage_credit_target() -> Node:
	return model.get_parent()

func reset_contact_history() -> void:
	_previous = Vector3.INF

func check_contact() -> void:
	if not active or model.is_zone_destroyed(zone): return
	var space := get_world_3d().direct_space_state
	_query.transform = global_transform
	_query.motion = Vector3.ZERO
	var contact := not space.intersect_shape(_query, 1).is_empty()
	if not contact and _previous.is_finite() and _previous.distance_to(global_position) < 128.0:
		_query.transform.origin = _previous
		_query.motion = global_position - _previous
		if _query.motion.length_squared() > 0.000001:
			var sweep := space.cast_motion(_query)
			contact = not sweep.is_empty() and sweep[0] < 1.0
	_previous = global_position
	if contact: model.damage_zone(zone, model.get_zone_health(zone))
