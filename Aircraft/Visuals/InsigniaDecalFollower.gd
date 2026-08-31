extends Decal

## Keeps a decal in aircraft-root space while applying only an animated part's
## motion relative to its authored rest pose. This avoids inheriting imported
## mesh scale, which can distort Decal projection size when parented to the mesh.

var _aircraft_root: Node3D
var _follow_target: Node3D
var _host_rest_in_aircraft := Transform3D.IDENTITY
var _marker_rest_in_aircraft := Transform3D.IDENTITY


func configure_follow(
	aircraft_root: Node3D,
	follow_target: Node3D,
	host_rest_in_aircraft: Transform3D,
	marker_rest_in_aircraft: Transform3D
) -> void:
	_aircraft_root = aircraft_root
	_follow_target = follow_target
	_host_rest_in_aircraft = host_rest_in_aircraft
	_marker_rest_in_aircraft = marker_rest_in_aircraft
	# Wing-fold controllers use the default priority. Run afterward so the decal
	# consumes the final wing pose for this frame.
	process_priority = 10
	update_follow_transform()
	set_process(true)


func get_follow_target() -> Node3D:
	return _follow_target


func _process(_delta: float) -> void:
	update_follow_transform()


func update_follow_transform() -> void:
	if not is_instance_valid(_aircraft_root) or not is_instance_valid(_follow_target):
		set_process(false)
		return
	var current_host_in_aircraft := _transform_relative_to_ancestor(_aircraft_root, _follow_target)
	var motion_from_rest := current_host_in_aircraft * _host_rest_in_aircraft.affine_inverse()
	transform = motion_from_rest * _marker_rest_in_aircraft


func _transform_relative_to_ancestor(ancestor: Node3D, node: Node3D) -> Transform3D:
	var local_chain: Array[Transform3D] = []
	var current: Node = node
	while current != null and current != ancestor:
		if current is Node3D:
			local_chain.push_front((current as Node3D).transform)
		current = current.get_parent()
	if current != ancestor:
		if ancestor.is_inside_tree() and node.is_inside_tree():
			return ancestor.global_transform.affine_inverse() * node.global_transform
		return node.transform
	var result := Transform3D.IDENTITY
	for local_transform in local_chain:
		result *= local_transform
	return result
