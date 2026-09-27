extends Node

## Visual deflection follows the same filtered controls used by the aerodynamics.
@export var aileron_deflection_degrees: float = 22.0
@export var elevator_deflection_degrees: float = 18.0
@export var rudder_deflection_degrees: float = 25.0

const SURFACE_PATHS := [
	"../Aircraft 3/wing left/aileron left",
	"../Aircraft 3/wing right/aileron right",
	"../Aircraft 3/tail_002/elevator",
	"../Aircraft 3/tail_002/rudder",
]
var _aero: Node
var _surfaces: Array[Node3D] = []
var _rest: Array[Basis] = []


func _ready() -> void:
	if not bind_surfaces():
		push_warning("Aircraft 3 control surfaces are missing from the imported model")


func bind_surfaces() -> bool:
	_aero = get_node_or_null("../SimpleAero")
	_surfaces.clear()
	_rest.clear()
	for path: String in SURFACE_PATHS:
		var surface := get_node_or_null(path) as Node3D
		if surface == null:
			return false
		_surfaces.append(surface)
		_rest.append(surface.transform.basis)
	return _aero != null


func _process(_delta: float) -> void:
	if is_instance_valid(_aero):
		apply_control_surface_inputs(float(_aero.get("actual_pitch_control")),
			float(_aero.get("actual_roll_control")), float(_aero.get("actual_yaw_control")))


func apply_control_surface_inputs(pitch: float, roll: float, yaw: float) -> void:
	var angles := [clampf(roll, -1.0, 1.0) * aileron_deflection_degrees,
		-clampf(roll, -1.0, 1.0) * aileron_deflection_degrees,
		clampf(pitch, -1.0, 1.0) * elevator_deflection_degrees,
		-clampf(yaw, -1.0, 1.0) * rudder_deflection_degrees]
	for index in range(_surfaces.size()):
		var surface := _surfaces[index]
		if is_instance_valid(surface):
			surface.basis = _rest[index] * Basis(Vector3.UP if index == 3 else Vector3.RIGHT,
				deg_to_rad(angles[index]))
