extends Node

const META_REFERENCE_NODE := "motion_reference_node"
const META_REFERENCE_VELOCITY := "motion_reference_velocity"
const META_LEGACY_CARRIER_VELOCITY := "carrier_deck_velocity"


func set_reference_node(subject: Node, reference_node: Node) -> void:
	if subject == null:
		return
	if reference_node != null and is_instance_valid(reference_node):
		subject.set_meta(META_REFERENCE_NODE, reference_node)
		subject.set_meta(META_REFERENCE_VELOCITY, get_node_velocity(reference_node))
		subject.set_meta(META_LEGACY_CARRIER_VELOCITY, get_node_velocity(reference_node))
	else:
		clear_reference(subject)


func set_reference_velocity(subject: Node, velocity: Vector3) -> void:
	if subject == null:
		return
	subject.set_meta(META_REFERENCE_VELOCITY, velocity)
	subject.set_meta(META_LEGACY_CARRIER_VELOCITY, velocity)
	if subject.has_meta(META_REFERENCE_NODE):
		subject.remove_meta(META_REFERENCE_NODE)


func clear_reference(subject: Node) -> void:
	if subject == null:
		return
	if subject.has_meta(META_REFERENCE_NODE):
		subject.remove_meta(META_REFERENCE_NODE)
	if subject.has_meta(META_REFERENCE_VELOCITY):
		subject.remove_meta(META_REFERENCE_VELOCITY)
	if subject.has_meta(META_LEGACY_CARRIER_VELOCITY):
		subject.remove_meta(META_LEGACY_CARRIER_VELOCITY)


func get_reference_velocity(subject: Variant) -> Vector3:
	var node := subject as Node
	if node == null:
		return Vector3.ZERO

	if node.has_meta(META_REFERENCE_NODE):
		var reference = node.get_meta(META_REFERENCE_NODE)
		if reference is Node and is_instance_valid(reference):
			return get_node_velocity(reference)

	if node.has_meta(META_REFERENCE_VELOCITY):
		var velocity = node.get_meta(META_REFERENCE_VELOCITY)
		if typeof(velocity) == TYPE_VECTOR3:
			return velocity as Vector3

	if node.has_meta(META_LEGACY_CARRIER_VELOCITY):
		var carrier_velocity = node.get_meta(META_LEGACY_CARRIER_VELOCITY)
		if typeof(carrier_velocity) == TYPE_VECTOR3:
			return carrier_velocity as Vector3

	return Vector3.ZERO


func get_world_velocity(subject: Variant) -> Vector3:
	if subject == null:
		return Vector3.ZERO
	if subject is RigidBody3D:
		return (subject as RigidBody3D).linear_velocity
	if subject is Node and (subject as Node).has_method("get_deck_reference_velocity_vector"):
		var deck_velocity = (subject as Node).call("get_deck_reference_velocity_vector")
		if typeof(deck_velocity) == TYPE_VECTOR3:
			return deck_velocity as Vector3
	if subject is CharacterBody3D:
		return (subject as CharacterBody3D).velocity
	if subject is Node and (subject as Node).has_method("get_velocity_vector"):
		var velocity = (subject as Node).call("get_velocity_vector")
		if typeof(velocity) == TYPE_VECTOR3:
			return velocity as Vector3
	var node := subject as Node
	if node != null:
		var property_velocity = node.get("velocity")
		if typeof(property_velocity) == TYPE_VECTOR3:
			return property_velocity as Vector3
	return Vector3.ZERO


func get_node_velocity(node: Node) -> Vector3:
	return get_world_velocity(node)


func get_relative_velocity(subject: Variant, world_velocity: Variant = null) -> Vector3:
	var velocity: Vector3 = get_world_velocity(subject) if world_velocity == null else world_velocity as Vector3
	return velocity - get_reference_velocity(subject)


func to_relative_velocity(subject: Variant, world_velocity: Vector3) -> Vector3:
	return world_velocity - get_reference_velocity(subject)


func to_world_velocity(subject: Variant, relative_velocity: Vector3) -> Vector3:
	return relative_velocity + get_reference_velocity(subject)


func planar_speed(velocity: Vector3) -> float:
	return Vector2(velocity.x, velocity.z).length()
