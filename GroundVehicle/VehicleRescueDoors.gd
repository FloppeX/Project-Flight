extends Node
## Animates the separate door meshes in the authored friendly-vehicle GLB.

@export var swing_angle_degrees: float = 78.0
@export var opening_time_s: float = 0.9
@export var boarding_clearance_m: float = 0.75

var _vehicle: Node3D
var _left_hinge: Node3D
var _right_hinge: Node3D
var _body: Node3D
var _boarding_x_m: float = 2.6
var _boarding_z_m: float = 0.7
var _open_target: bool = false
var _open_t: float = 0.0


func _ready() -> void:
	_vehicle = get_parent() as Node3D
	_body = _vehicle.get_node_or_null("Body") as Node3D
	if _body == null:
		push_warning("VehicleRescueDoors: Missing Body on %s" % _vehicle.name)
		return
	_left_hinge = _make_hinge("door left", "LeftDoorHinge")
	_right_hinge = _make_hinge("door right", "RightDoorHinge")
	if _left_hinge == null or _right_hinge == null:
		push_warning("VehicleRescueDoors: Missing authored door mesh on %s" % _vehicle.name)
		return
	var body_mesh := _body.get_node_or_null("body") as MeshInstance3D
	if body_mesh != null:
		var body_bounds: AABB = body_mesh.transform * body_mesh.get_aabb()
		_boarding_x_m = maxf(absf(body_bounds.position.x), absf(body_bounds.end.x)) + boarding_clearance_m
	_boarding_z_m = (_left_hinge.position.z + _right_hinge.position.z) * 0.5 - 0.5
	_apply_pose()


func _physics_process(delta: float) -> void:
	if _left_hinge == null or _right_hinge == null:
		return
	var next := move_toward(_open_t, 1.0 if _open_target else 0.0,
		delta / maxf(opening_time_s, 0.01))
	if is_equal_approx(next, _open_t):
		return
	_open_t = next
	_apply_pose()


func set_open(open: bool) -> void:
	_open_target = open


func is_open_for_boarding() -> bool:
	return _left_hinge != null and _right_hinge != null and _open_t >= 0.85


func get_boarding_position(from_position: Vector3) -> Vector3:
	var local := _vehicle.to_local(from_position)
	var side := -1.0 if local.x < 0.0 else 1.0
	return _vehicle.to_global(Vector3(side * _boarding_x_m, 0.0, _boarding_z_m))


func _make_hinge(mesh_name: String, hinge_name: String) -> Node3D:
	var door := _body.get_node_or_null(mesh_name) as MeshInstance3D
	if door == null:
		return null
	var bounds: AABB = door.transform * door.get_aabb()
	var hinge := Node3D.new()
	hinge.name = hinge_name
	hinge.position = Vector3(bounds.get_center().x, bounds.get_center().y, bounds.end.z)
	_body.add_child(hinge)
	door.reparent(hinge, true)
	return hinge


func _apply_pose() -> void:
	var eased := _open_t * _open_t * (3.0 - 2.0 * _open_t)
	var angle := deg_to_rad(swing_angle_degrees) * eased
	_left_hinge.rotation.y = -angle
	_right_hinge.rotation.y = angle
