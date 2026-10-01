extends Node3D

@export var hook_area: NodePath
@export var hook_body_collision: NodePath
@export var hook_mesh: NodePath
## Mount in aircraft-local coordinates: lower middle of the fuselage centerline.
@export var stowed_mount_position := Vector3(0.0, -0.65, 0.0)
@export_range(0.05, 5.0) var deployment_duration_s: float = 0.8
@export_range(0.0, 0.3) var deck_tip_clearance_m: float = 0.08

# Identify this module for external systems (e.g., FlightDeckManager)
var ModuleType: String = "tailhook"

# Legacy scene properties. Contact now pivots the hook instead of lifting the airframe.
@export var spring_strength: float = 2500.0       # N/m (small compared to landing gear)
@export var spring_damping: float = 1200.0        # N*s/m
@export var wheel_rest_height: float = 0.2        # m from hook tip to deck at rest
@export var max_compression: float = 0.15         # m
@export var ray_length_margin: float = 0.4        # m ray length (rest + margin)

var _area: Area3D
var _body_col: CollisionShape3D
var _mesh_node: Node3D
var _aircraft: RigidBody3D
var _is_deployed: bool = false
var _technical_index_preview_fraction: float = 1.0
var _visual_fraction: float = 0.0
var _visual_tween: Tween
var _shaft_length: float = 0.0
var _contact_tip: Vector3
var _contact_tip_valid := false

func _ready():
	# Resolve contact before the cable reads its capture area's position.
	process_physics_priority = -10
	_cache_nodes()
	if bool(get_meta("technical_index_preview_component", false)):
		set_technical_index_preview_fraction(_technical_index_preview_fraction)
		return
	add_to_group("tailhook")
	# Ensure the hook Area is in the expected group for the cable to detect
	if _area and not _area.is_in_group("tailhook"):
		_area.add_to_group("tailhook")
	_aircraft = _find_aircraft()
	# Default to stowed on start
	stow()

func _cache_nodes() -> void:
	_area = get_node_or_null(hook_area)
	_body_col = get_node_or_null(hook_body_collision) as CollisionShape3D
	_mesh_node = get_node_or_null(hook_mesh) as Node3D
	if _mesh_node != null and _shaft_length <= 0.0:
		for child in _mesh_node.find_children("*", "MeshInstance3D", true, false):
			var mesh := child as MeshInstance3D
			if mesh.mesh != null:
				var local_transform := mesh.transform
				var ancestor := mesh.get_parent() as Node3D
				while ancestor != null and ancestor != _mesh_node:
					local_transform = ancestor.transform * local_transform
					ancestor = ancestor.get_parent() as Node3D
				var bounds: AABB = local_transform * mesh.mesh.get_aabb()
				_shaft_length = maxf(_shaft_length, bounds.end.y)
		_shaft_length = maxf(_shaft_length, 0.01)

func prepare_technical_index_preview() -> bool:
	var aircraft_root := get_parent()
	var landing_gear := aircraft_root.get_node_or_null("LandingGear") if aircraft_root != null else null
	if landing_gear == null or bool(landing_gear.get("lock_deployed")):
		return false
	_cache_nodes()
	if _mesh_node == null:
		return false
	set_technical_index_preview_fraction(1.0)
	return true

func set_technical_index_preview_fraction(deploy_fraction: float) -> void:
	_technical_index_preview_fraction = clampf(deploy_fraction, 0.0, 1.0)
	if _mesh_node == null:
		_cache_nodes()
	if _visual_tween != null:
		_visual_tween.kill()
	_apply_visual_fraction(_technical_index_preview_fraction)

func get_technical_index_preview_fraction() -> float:
	return _technical_index_preview_fraction

func get_technical_index_preview_duration() -> float:
	return deployment_duration_s

func get_technical_index_preview_kind() -> StringName:
	return &"gear"

func deploy():
	_is_deployed = true
	set_physics_process(true)
	if _area:
		_area.monitoring = true
		var cs := _area.get_node_or_null("CollisionShape3D") as CollisionShape3D
		if cs:
			cs.disabled = false
	if _body_col:
		_body_col.disabled = false
	_animate_visual_to(1.0)

func stow():
	_is_deployed = false
	_contact_tip_valid = false
	if _area:
		_area.position = Vector3.ZERO
	set_physics_process(false)
	if _area:
		_area.monitoring = false
		var cs := _area.get_node_or_null("CollisionShape3D") as CollisionShape3D
		if cs:
			cs.disabled = true
	if _body_col:
		_body_col.disabled = true
	_animate_visual_to(0.0)

func _animate_visual_to(target: float) -> void:
	if _visual_tween != null:
		_visual_tween.kill()
	if is_equal_approx(_visual_fraction, target):
		_apply_visual_fraction(target)
		return
	_visual_tween = create_tween()
	_visual_tween.tween_method(_apply_visual_fraction, _visual_fraction, target,
		deployment_duration_s * absf(target - _visual_fraction)).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _apply_visual_fraction(fraction: float) -> void:
	_visual_fraction = clampf(fraction, 0.0, 1.0)
	if _mesh_node == null:
		return
	_mesh_node.visible = _visual_fraction > 0.001
	# The mount stays fixed; deck contact rotates the full-length deployed shaft.
	# The cable detector follows that same tip, rather than the authored rest tip.
	var tip := _contact_tip if _contact_tip_valid else position
	var shaft := stowed_mount_position - tip
	if shaft.length_squared() < 0.0001:
		return
	var axis_y := shaft.normalized()
	var axis_x := Vector3.RIGHT
	if absf(axis_y.dot(axis_x)) > 0.99:
		axis_x = Vector3.FORWARD
	var axis_z := axis_x.cross(axis_y).normalized()
	axis_x = axis_y.cross(axis_z).normalized()
	var extension := maxf(_visual_fraction, 0.001)
	var visual_basis := Basis(axis_x, axis_y * shaft.length() * extension / _shaft_length, axis_z)
	var visual_tip := stowed_mount_position.lerp(tip, _visual_fraction)
	_mesh_node.transform = transform.affine_inverse() * Transform3D(visual_basis, visual_tip)

func _physics_process(_delta: float) -> void:
	if not _is_deployed:
		return
	if not _aircraft or not is_instance_valid(_aircraft):
		_aircraft = _find_aircraft()
		if not _aircraft:
			return
	var parent := get_parent() as Node3D
	var rest_tip := parent.to_global(position)
	var length := position.distance_to(stowed_mount_position)
	# Start above the rest tip: a downward ray from an already submerged hook
	# misses the top of the deck. Keep this probe independent of last frame's bend.
	var query := PhysicsRayQueryParameters3D.create(
		rest_tip + Vector3.UP * (length + ray_length_margin),
		rest_tip + Vector3.DOWN * (wheel_rest_height + ray_length_margin))
	query.exclude = [_aircraft.get_rid()]
	query.collision_mask = (1 << 0) | (1 << 9)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	_contact_tip = position
	if not hit.is_empty():
		var normal: Vector3 = hit.normal
		var plane_point := parent.to_local(hit.position + normal * deck_tip_clearance_m)
		var local_normal := (parent.global_basis.transposed() * normal).normalized()
		_contact_tip = _solve_hinged_tip(plane_point, local_normal)
	_contact_tip_valid = true
	if _area:
		_area.position = transform.affine_inverse() * _contact_tip
	_apply_visual_fraction(_visual_fraction)

func _solve_hinged_tip(plane_point: Vector3, plane_normal: Vector3) -> Vector3:
	if (position - plane_point).dot(plane_normal) >= 0.0:
		return position
	var arm := position - stowed_mount_position
	var direction := 1.0 if Vector3.RIGHT.cross(arm).dot(plane_normal) >= 0.0 else -1.0
	var low := 0.0
	# Find the first contact-clearing angle without changing the shaft length.
	for step in range(1, 37):
		var high := deg_to_rad(float(step) * 5.0)
		var candidate := stowed_mount_position + arm.rotated(Vector3.RIGHT, high * direction)
		if (candidate - plane_point).dot(plane_normal) >= 0.0:
			for iteration in range(16):
				var middle := (low + high) * 0.5
				candidate = stowed_mount_position + arm.rotated(Vector3.RIGHT, middle * direction)
				if (candidate - plane_point).dot(plane_normal) >= 0.0:
					high = middle
				else:
					low = middle
			return stowed_mount_position + arm.rotated(Vector3.RIGHT, high * direction)
		low = high
	# An unreachable plane means the fuselage itself is below the surface.
	return position

func _find_aircraft() -> RigidBody3D:
	var n: Node = self
	while n:
		if n is RigidBody3D:
			return n
		n = n.get_parent()
	return null
