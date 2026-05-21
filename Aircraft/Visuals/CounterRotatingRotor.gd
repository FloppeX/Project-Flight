extends Node3D

@export var upper_rotor_path: NodePath = NodePath("UpperRotor")
@export var lower_rotor_path: NodePath = NodePath("LowerRotor")
@export var max_rotation_speed_rad_s: float = 120.0
@export var spool_rate: float = 1.2
@export var upper_rotor_direction: float = -1.0
@export var lower_rotor_direction: float = 1.0
@export var fold_duration_s: float = 5.0
@export var folded_yaw_deg: float = 180.0
@export var upper_blade_yaws_deg: PackedFloat32Array = PackedFloat32Array([0.0, 120.0, -120.0])
@export var lower_blade_yaws_deg: PackedFloat32Array = PackedFloat32Array([0.0, -120.0, 120.0])
@export var debug_console_enabled: bool = false
@export var debug_interval_s: float = 1.0

@onready var upper_rotor: Node3D = get_node_or_null(upper_rotor_path) as Node3D
@onready var lower_rotor: Node3D = get_node_or_null(lower_rotor_path) as Node3D

var _target_power: float = 0.0
var _requested_power: float = 0.0
var _power: float = 0.0
var _fold_t: float = 1.0
var _fold_target: float = 1.0
var _engine_active: bool = false
var _unfold_requested: bool = false
var _startup_unfold_latched: bool = false
var _blade_origins: Dictionary = {}
var _rotor_rest_transforms: Dictionary = {}
var _debug_timer_s: float = 0.0


func _ready() -> void:
	_cache_blade_rest_pose(upper_rotor)
	_cache_blade_rest_pose(lower_rotor)
	_apply_fold_pose()
	_print_debug_line("ready")


func update_interface(values: Dictionary) -> void:
	var engine_active := _variant_to_bool(values.get("engine_active", false))
	var engine_power := float(values.get("engine_power", 0.0))
	_engine_active = engine_active
	_requested_power = engine_power
	if engine_active:
		_unfold_requested = true
		_startup_unfold_latched = false
	elif _startup_unfold_latched:
		_unfold_requested = true
	_fold_target = 0.0 if engine_active else _get_idle_fold_target()
	_target_power = _requested_power if engine_active and _fold_t <= 0.01 else 0.0
	_print_debug_line("update_interface")


func prepare_for_engine_start() -> void:
	_unfold_requested = true
	_startup_unfold_latched = true
	_fold_target = 0.0
	_print_debug_line("prepare_start_begin")
	while _fold_t > 0.01 and is_inside_tree():
		await get_tree().physics_frame
	_print_debug_line("prepare_start_done")


func _physics_process(delta: float) -> void:
	_update_fold(delta)
	_target_power = _requested_power if _engine_active and _fold_t <= 0.01 else 0.0
	_power = move_toward(_power, _target_power, spool_rate * delta)
	_maybe_print_debug_line(delta)
	if _fold_t > 0.001:
		_power = 0.0
		return
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
	if _fold_t <= 0.01 and not _engine_active and not _startup_unfold_latched:
		_unfold_requested = false


func _get_idle_fold_target() -> float:
	var aircraft := get_parent()
	if aircraft != null:
		var parking_brake := aircraft.has_meta("parking_brake") and _variant_to_bool(aircraft.get_meta("parking_brake"))
		var transport := aircraft.has_meta("carrier_transport_mode") and _variant_to_bool(aircraft.get_meta("carrier_transport_mode"))
		if parking_brake or transport:
			return 1.0
	return 1.0


func _variant_to_bool(value: Variant) -> bool:
	if typeof(value) == TYPE_BOOL:
		return value as bool
	if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
		return float(value) != 0.0
	if typeof(value) == TYPE_STRING:
		return str(value).to_lower() in ["true", "1", "yes", "on"]
	return false


func _cache_blade_rest_pose(rotor: Node3D) -> void:
	if rotor == null:
		return
	_rotor_rest_transforms[rotor.get_path()] = rotor.transform
	for child in rotor.get_children():
		var blade := child as Node3D
		if blade == null:
			continue
		_blade_origins[str(blade.get_path())] = blade.transform.origin
	if debug_console_enabled:
		print("ROTOR_DEBUG event=cache rotor=%s child_count=%d cached_total=%d" % [
			rotor.name,
			rotor.get_child_count(),
			_blade_origins.size()
		])


func _apply_fold_pose() -> void:
	for path_variant in _rotor_rest_transforms.keys():
		var rotor := get_node_or_null(path_variant as NodePath) as Node3D
		if rotor == null:
			continue
		rotor.transform = _rotor_rest_transforms[path_variant]
	var unfold_t: float = 1.0 - clampf(_fold_t, 0.0, 1.0)
	_apply_rotor_blade_layout(upper_rotor, upper_blade_yaws_deg, unfold_t)
	_apply_rotor_blade_layout(lower_rotor, lower_blade_yaws_deg, unfold_t)


func _apply_rotor_blade_layout(rotor: Node3D, deployed_yaws_deg: PackedFloat32Array, unfold_t: float) -> void:
	if rotor == null:
		return
	var index := 0
	for child in rotor.get_children():
		var blade := child as Node3D
		if blade == null:
			continue
		var deployed_yaw := _get_deployed_yaw_for_blade(blade, index, deployed_yaws_deg)
		var yaw := lerpf(folded_yaw_deg, deployed_yaw, unfold_t)
		var origin: Vector3 = _blade_origins.get(str(blade.get_path()), blade.transform.origin)
		blade.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(yaw)), origin)
		index += 1


func _get_deployed_yaw_for_blade(blade: Node3D, index: int, deployed_yaws_deg: PackedFloat32Array) -> float:
	if index >= 0 and index < deployed_yaws_deg.size():
		return deployed_yaws_deg[index]
	var parsed := _parse_yaw_from_blade_name(blade.name)
	if not is_nan(parsed):
		return parsed
	return float(index) * 120.0


func _parse_yaw_from_blade_name(blade_name: String) -> float:
	if blade_name.ends_with("120"):
		return 120.0
	if blade_name.ends_with("240"):
		return -120.0
	if blade_name.ends_with("0"):
		return 0.0
	return NAN


func _maybe_print_debug_line(delta: float) -> void:
	if not debug_console_enabled:
		return
	_debug_timer_s -= delta
	if _debug_timer_s > 0.0:
		return
	_debug_timer_s = maxf(debug_interval_s, 0.1)
	_print_debug_line("tick")


func _print_debug_line(event_name: String) -> void:
	if not debug_console_enabled:
		return
	var upper_summary := _get_rotor_debug_summary(upper_rotor)
	var lower_summary := _get_rotor_debug_summary(lower_rotor)
	print("ROTOR_DEBUG event=%s fold=%.3f target=%.3f unfold_requested=%s startup_latched=%s engine=%s power=%.3f target_power=%.3f cached_blades=%d upper={%s} lower={%s}" % [
		event_name,
		_fold_t,
		_fold_target,
		str(_unfold_requested),
		str(_startup_unfold_latched),
		str(_engine_active),
		_power,
		_target_power,
		_blade_origins.size(),
		upper_summary,
		lower_summary
	])


func _get_rotor_debug_summary(rotor: Node3D) -> String:
	if rotor == null:
		return "missing"
	var parts := PackedStringArray()
	for child in rotor.get_children():
		if not (child is Node3D):
			continue
		var blade := child as Node3D
		var rest_yaw := _get_deployed_yaw_for_blade(blade, _get_blade_index(blade), _get_rotor_deployed_yaws(rotor))
		parts.append("%s yaw=%.1f rest_yaw=%.1f visible=%s %s" % ([
			blade.name,
			rad_to_deg(blade.rotation.y),
			rest_yaw,
			str(blade.visible)
		] + _get_blade_visual_tip_fields(rotor, blade)))
	return "count=%d %s" % [rotor.get_child_count(), ";".join(parts)]


func _get_rotor_deployed_yaws(rotor: Node3D) -> PackedFloat32Array:
	if rotor == upper_rotor:
		return upper_blade_yaws_deg
	return lower_blade_yaws_deg


func _get_blade_index(blade: Node3D) -> int:
	var parent := blade.get_parent()
	if parent == null:
		return 0
	var index := 0
	for child in parent.get_children():
		if child == blade:
			return index
		if child is Node3D:
			index += 1
	return index


func _get_blade_visual_tip_fields(rotor: Node3D, blade: Node3D) -> Array:
	var tip := Vector3.ZERO
	var best_distance := -1.0
	for mesh in _get_mesh_instances(blade):
		var local_position := rotor.to_local(mesh.global_position)
		var horizontal_distance := Vector2(local_position.x, local_position.z).length_squared()
		if horizontal_distance > best_distance:
			best_distance = horizontal_distance
			tip = local_position
	if best_distance < 0.0:
		return ["mesh_tip=none"]
	return ["mesh_tip=(%.1f,%.1f)" % [tip.x, tip.z]]


func _get_mesh_instances(node: Node) -> Array[MeshInstance3D]:
	var meshes: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		meshes.append(node as MeshInstance3D)
	for child in node.get_children():
		meshes.append_array(_get_mesh_instances(child))
	return meshes
