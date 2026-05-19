extends Node3D

@export var upper_rotor_path: NodePath = NodePath("UpperRotor")
@export var lower_rotor_path: NodePath = NodePath("LowerRotor")
@export var max_rotation_speed_rad_s: float = 120.0
@export var spool_rate: float = 1.2
@export var upper_rotor_direction: float = -1.0
@export var lower_rotor_direction: float = 1.0
@export var fold_duration_s: float = 5.0
@export var folded_yaw_deg: float = 180.0

@onready var upper_rotor: Node3D = get_node_or_null(upper_rotor_path) as Node3D
@onready var lower_rotor: Node3D = get_node_or_null(lower_rotor_path) as Node3D

var _target_power: float = 0.0
var _power: float = 0.0
var _fold_t: float = 1.0
var _fold_target: float = 1.0
var _engine_active: bool = false
var _unfold_requested: bool = false
var _blade_rest_quats: Dictionary = {}
var _rotor_rest_quats: Dictionary = {}


func _ready() -> void:
	_cache_blade_rest_pose(upper_rotor)
	_cache_blade_rest_pose(lower_rotor)
	_apply_fold_pose()


func update_interface(values: Dictionary) -> void:
	var engine_active := bool(values.get("engine_active", false))
	var engine_power := float(values.get("engine_power", 0.0))
	_engine_active = engine_active
	if engine_active:
		_unfold_requested = true
	_fold_target = 0.0 if engine_active else _get_idle_fold_target()
	_target_power = engine_power if engine_active and _fold_t <= 0.01 else 0.0


func prepare_for_engine_start() -> void:
	_unfold_requested = true
	_fold_target = 0.0
	while _fold_t > 0.01 and is_inside_tree():
		await get_tree().process_frame


func _physics_process(delta: float) -> void:
	_update_fold(delta)
	_power = move_toward(_power, _target_power, spool_rate * delta)
	if _power <= 0.0:
		return

	var step := max_rotation_speed_rad_s * _power * delta
	if upper_rotor != null:
		upper_rotor.rotate_y(step * upper_rotor_direction)
	if lower_rotor != null:
		lower_rotor.rotate_y(step * lower_rotor_direction)


func _update_fold(delta: float) -> void:
	if _engine_active or _unfold_requested or not is_zero_approx(_target_power):
		_fold_target = 0.0
	elif _fold_target > 0.0:
		_fold_target = _get_idle_fold_target()

	var previous_fold_t := _fold_t
	_fold_t = move_toward(_fold_t, _fold_target, delta / maxf(fold_duration_s, 0.01))
	if not is_equal_approx(previous_fold_t, _fold_t):
		_apply_fold_pose()
	if _fold_t <= 0.01 and not _engine_active:
		_unfold_requested = false


func _get_idle_fold_target() -> float:
	var aircraft := get_parent()
	if aircraft != null:
		var parking_brake := aircraft.has_meta("parking_brake") and bool(aircraft.get_meta("parking_brake"))
		var transport := aircraft.has_meta("carrier_transport_mode") and bool(aircraft.get_meta("carrier_transport_mode"))
		if parking_brake or transport:
			return 1.0
	return 1.0


func _cache_blade_rest_pose(rotor: Node3D) -> void:
	if rotor == null:
		return
	_rotor_rest_quats[rotor.get_path()] = rotor.quaternion
	for child in rotor.get_children():
		var blade := child as Node3D
		if blade == null:
			continue
		_blade_rest_quats[blade.get_path()] = blade.quaternion


func _apply_fold_pose() -> void:
	var folded_quat := Quaternion(Vector3.UP, deg_to_rad(folded_yaw_deg))
	for path_variant in _rotor_rest_quats.keys():
		var rotor := get_node_or_null(path_variant as NodePath) as Node3D
		if rotor == null:
			continue
		rotor.quaternion = _rotor_rest_quats[path_variant]
	for path_variant in _blade_rest_quats.keys():
		var blade := get_node_or_null(path_variant as NodePath) as Node3D
		if blade == null:
			continue
		var rest_quat: Quaternion = _blade_rest_quats[path_variant]
		blade.quaternion = folded_quat.slerp(rest_quat, 1.0 - clampf(_fold_t, 0.0, 1.0))
