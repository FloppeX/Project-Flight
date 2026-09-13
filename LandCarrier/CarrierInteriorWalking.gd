extends RefCounted
## Carrier-local, stepped movement for the commander's existing anchored controller.
## Only the dedicated interior layer participates; aircraft and the parent hull
## cannot incorrectly block a room or become a floor on another deck.
const MASK: int = 1 << 20
const RADIUS: float = 0.28
const STEP: float = 0.30
var carrier: Node3D
var capsule := CapsuleShape3D.new()
var _reference_body: PhysicsBody3D
var _body_to_carrier := Transform3D.IDENTITY

func _init(owner_carrier: Node3D) -> void:
	carrier = owner_carrier
	capsule.radius = RADIUS
	capsule.height = 1.48
	_reference_body = carrier.get_node_or_null("CarrierModel/InteriorSurfaceCollision") as PhysicsBody3D
	if _reference_body != null:
		_body_to_carrier = (carrier.global_transform.affine_inverse() * _reference_body.global_transform).affine_inverse()

func _query_transform() -> Transform3D:
	if is_instance_valid(_reference_body):
		var physics_transform: Transform3D = PhysicsServer3D.body_get_state(
			_reference_body.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM)
		return physics_transform * _body_to_carrier
	return carrier.global_transform

func constrain(current: Vector3, desired: Vector3) -> Vector3:
	var distance := Vector2(desired.x - current.x, desired.z - current.z).length()
	var steps := maxi(1, ceili(distance / 0.08))
	var increment := (desired - current) / float(steps)
	increment.y = 0.0
	var result := current
	for i in steps:
		var candidate := supported_position(result, result + increment)
		if candidate != result:
			result = candidate
		else:
			result = supported_position(result, result + Vector3(increment.x, 0, 0))
			result = supported_position(result, result + Vector3(0, 0, increment.z))
	return result

func supported_position(current: Vector3, desired: Vector3) -> Vector3:
	var space := carrier.get_world_3d().direct_space_state
	var height := -INF
	var query_transform := _query_transform()
	var to_carrier := query_transform.affine_inverse()
	# A supporting footprint stops the character stepping off balconies or into
	# the lift shaft. The step range cannot select another room's floor above us.
	for offset in [Vector3.ZERO, Vector3(RADIUS, 0, 0), Vector3(-RADIUS, 0, 0), Vector3(0, 0, RADIUS), Vector3(0, 0, -RADIUS)]:
		var query := PhysicsRayQueryParameters3D.create(
			query_transform * (desired + offset + Vector3.UP * (STEP + 0.04)),
			query_transform * (desired + offset - Vector3.UP * 0.70), MASK)
		# Some authored deck sheets have reversed winding. They still support
		# walking; the bounded step range keeps other decks out of the query.
		query.hit_back_faces = true
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			return current
		if absf((to_carrier.basis * hit.normal).normalized().y) < 0.55:
			return current
		var local_hit: Vector3 = to_carrier * hit.position
		height = maxf(height, local_hit.y)
	if absf(height - current.y) > STEP + 0.04:
		return current
	desired.y = height
	var shape_query := PhysicsShapeQueryParameters3D.new()
	shape_query.shape = capsule
	shape_query.collision_mask = MASK
	shape_query.transform = query_transform * Transform3D(Basis.IDENTITY, desired + Vector3.UP * 1.05)
	shape_query.margin = 0.015
	var hits := space.intersect_shape(shape_query, 1)
	if not hits.is_empty():
		return current
	return desired
