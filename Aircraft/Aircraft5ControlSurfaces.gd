extends Node3D

@export var simple_aero_path: NodePath = NodePath("../SimpleAero")
@export var left_aileron_path: NodePath = NodePath("../aircraft_5/outer wing left/aileron left")
@export var right_aileron_path: NodePath = NodePath("../aircraft_5/outer wing right/aileron right")
@export var elevator_path: NodePath = NodePath("../aircraft_5/world_001/body/elevator")
@export var left_rudder_path: NodePath = NodePath("../aircraft_5/world_001/body/rudder left")
@export var right_rudder_path: NodePath = NodePath("../aircraft_5/world_001/body/rudder right")

@export_range(0.0, 45.0, 0.5) var aileron_deflection_degrees: float = 22.0
@export_range(0.0, 45.0, 0.5) var elevator_deflection_degrees: float = 18.0
@export_range(0.0, 45.0, 0.5) var rudder_deflection_degrees: float = 25.0

var _simple_aero: Node
var _left_aileron: Node3D
var _right_aileron: Node3D
var _elevator: Node3D
var _left_rudder: Node3D
var _right_rudder: Node3D
var _rest_bases: Dictionary = {}


func _ready() -> void:
	bind_surfaces()


func bind_surfaces() -> bool:
	_simple_aero = get_node_or_null(simple_aero_path)
	_left_aileron = get_node_or_null(left_aileron_path) as Node3D
	_right_aileron = get_node_or_null(right_aileron_path) as Node3D
	_elevator = get_node_or_null(elevator_path) as Node3D
	_left_rudder = get_node_or_null(left_rudder_path) as Node3D
	_right_rudder = get_node_or_null(right_rudder_path) as Node3D
	_rest_bases.clear()
	for surface in _get_surfaces():
		if surface != null:
			_rest_bases[surface] = surface.transform.basis
	return _simple_aero != null and _rest_bases.size() == 5


func _process(_delta: float) -> void:
	if not is_instance_valid(_simple_aero):
		return
	apply_control_surface_inputs(
		float(_simple_aero.get("actual_pitch_control")),
		float(_simple_aero.get("actual_roll_control")),
		float(_simple_aero.get("actual_yaw_control"))
	)


func apply_control_surface_inputs(pitch: float, roll: float, yaw: float) -> void:
	pitch = clampf(pitch, -1.0, 1.0)
	roll = clampf(roll, -1.0, 1.0)
	yaw = clampf(yaw, -1.0, 1.0)
	_set_surface_angle(_left_aileron, Vector3.RIGHT, deg_to_rad(aileron_deflection_degrees) * roll)
	# The mirrored right wing's authored span axis imports as local +Y.
	_set_surface_angle(_right_aileron, Vector3.UP, deg_to_rad(aileron_deflection_degrees) * roll)
	_set_surface_angle(_elevator, Vector3.RIGHT, deg_to_rad(elevator_deflection_degrees) * pitch)
	_set_surface_angle(_left_rudder, Vector3.UP, -deg_to_rad(rudder_deflection_degrees) * yaw)
	_set_surface_angle(_right_rudder, Vector3.UP, -deg_to_rad(rudder_deflection_degrees) * yaw)


func _set_surface_angle(surface: Node3D, axis: Vector3, angle: float) -> void:
	if not is_instance_valid(surface) or not _rest_bases.has(surface):
		return
	var transform_value := surface.transform
	transform_value.basis = (_rest_bases[surface] as Basis) * Basis(axis, angle)
	surface.transform = transform_value


func _get_surfaces() -> Array[Node3D]:
	return [_left_aileron, _right_aileron, _elevator, _left_rudder, _right_rudder]
