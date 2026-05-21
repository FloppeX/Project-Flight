extends Node3D

@export var upper_rotor_path: NodePath = NodePath("UpperRotor")
@export var lower_rotor_path: NodePath = NodePath("LowerRotor")
@export var rotor_spool_up_rate: float = 0.18
@export var rotor_spool_down_rate: float = 0.12
@export var rotor_stop_fold_threshold: float = 0.02
@export var upper_rotor_direction: float = -1.0
@export var lower_rotor_direction: float = 1.0
@export var fold_duration_s: float = 5.0
@export var folded_yaw_deg: float = 180.0
@export var stowed_blade_stack_spacing_m: float = 0.05
@export var upper_blade_yaws_deg: PackedFloat32Array = PackedFloat32Array([0.0, 120.0, -120.0])
@export var lower_blade_yaws_deg: PackedFloat32Array = PackedFloat32Array([0.0, -120.0, 120.0])
@export var resting_blade_segment_angle_deg: float = 3.0
@export var powered_blade_segment_angle_deg: float = 0.0
@export var blade_segment_flat_power: float = 0.85
@export var debug_console_enabled: bool = false
@export var debug_interval_s: float = 1.0

const ROTOR_VISUAL_RATE_RAD_S: float = 240.0

@onready var upper_rotor: Node3D = get_node_or_null(upper_rotor_path) as Node3D
@onready var lower_rotor: Node3D = get_node_or_null(lower_rotor_path) as Node3D

var _target_power: float = 0.0
var _collective_power: float = 0.0
var _power: float = 0.0
var _fold_t: float = 1.0
var _fold_target: float = 1.0
var _engine_active: bool = false
var _unfold_requested: bool = false
var _startup_unfold_latched: bool = false
var _blade_origins: Dictionary = {}
var _blade_rest_transforms: Dictionary = {}
var _blade_droop_signs: Dictionary = {}
var _blade_section_rest_transforms: Dictionary = {}
var _blade_section_hinges: Dictionary = {}
var _rotor_rest_transforms: Dictionary = {}
var _debug_timer_s: float = 0.0
var _last_blade_segment_angle_deg: float = INF
var _last_upper_step_rad: float = 0.0
var _last_lower_step_rad: float = 0.0


func _ready() -> void:
	_cache_blade_rest_pose(upper_rotor)
	_cache_blade_rest_pose(lower_rotor)
	_apply_fold_pose()
	_print_debug_line("ready")


func update_interface(values: Dictionary) -> void:
	var engine_active := _variant_to_bool(values.get("engine_active", false))
	var engine_power := float(values.get("engine_power", 0.0))
	_engine_active = engine_active
	_collective_power = engine_power
	if engine_active:
		_unfold_requested = true
		_startup_unfold_latched = false
	elif _startup_unfold_latched:
		_unfold_requested = true
	_update_targets()
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
	_last_upper_step_rad = 0.0
	_last_lower_step_rad = 0.0
	_update_targets()
	_update_fold(delta)
	var rpm_rate := rotor_spool_up_rate if _target_power >= _power else rotor_spool_down_rate
	_power = move_toward(_power, _target_power, maxf(rpm_rate, 0.001) * delta)
	_update_blade_segments()
	if _fold_t > 0.001:
		_power = 0.0
		_maybe_print_debug_line(delta)
		return
	if _power <= 0.0:
		_maybe_print_debug_line(delta)
		return

	var step := ROTOR_VISUAL_RATE_RAD_S * _power * delta
	if upper_rotor != null:
		_last_upper_step_rad = step * upper_rotor_direction
		upper_rotor.rotate_y(_last_upper_step_rad)
	if lower_rotor != null:
		_last_lower_step_rad = step * lower_rotor_direction
		lower_rotor.rotate_y(_last_lower_step_rad)
	_maybe_print_debug_line(delta)


func _update_targets() -> void:
	if _engine_active:
		_fold_target = 0.0
		_target_power = 1.0 if _fold_t <= 0.01 else 0.0
		return
	_target_power = 0.0
	if _startup_unfold_latched or _power > rotor_stop_fold_threshold:
		_fold_target = 0.0
	else:
		_unfold_requested = false
		_fold_target = _get_idle_fold_target()


func _update_fold(delta: float) -> void:
	if _engine_active or _startup_unfold_latched or _power > rotor_stop_fold_threshold:
		_fold_target = 0.0
	elif _fold_target > 0.0:
		_fold_target = _get_idle_fold_target()

	var previous_fold_t := _fold_t
	_fold_t = move_toward(_fold_t, _fold_target, delta / maxf(fold_duration_s, 0.01))
	if not is_equal_approx(previous_fold_t, _fold_t):
		_apply_fold_pose()
	if not _engine_active and not _startup_unfold_latched and _power <= rotor_stop_fold_threshold:
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
	_rotor_rest_transforms[_get_node_cache_key(rotor)] = rotor.transform
	for child in rotor.get_children():
		var blade := child as Node3D
		if blade == null:
			continue
		var blade_key := _get_node_cache_key(blade)
		_blade_origins[blade_key] = blade.transform.origin
		_blade_rest_transforms[blade_key] = blade.transform
		_blade_droop_signs[blade_key] = -1.0 if blade.transform.basis.y.dot(Vector3.UP) >= 0.0 else 1.0
		_cache_blade_sections(blade)
	if debug_console_enabled:
		print("ROTOR_DEBUG event=cache rotor=%s child_count=%d cached_total=%d" % [
			rotor.name,
			rotor.get_child_count(),
			_blade_origins.size()
		])


func _apply_fold_pose() -> void:
	for path_variant in _rotor_rest_transforms.keys():
		var rotor := instance_from_id(path_variant as int) as Node3D
		if rotor == null:
			continue
		rotor.transform = _rotor_rest_transforms[path_variant]
	var unfold_t: float = 1.0 - clampf(_fold_t, 0.0, 1.0)
	_apply_rotor_blade_layout(upper_rotor, upper_blade_yaws_deg, unfold_t)
	_apply_rotor_blade_layout(lower_rotor, lower_blade_yaws_deg, unfold_t)
	_last_blade_segment_angle_deg = INF
	_update_blade_segments()


func _apply_rotor_blade_layout(rotor: Node3D, deployed_yaws_deg: PackedFloat32Array, unfold_t: float) -> void:
	if rotor == null:
		return
	var index := 0
	for child in rotor.get_children():
		var blade := child as Node3D
		if blade == null:
			continue
		var blade_key := _get_node_cache_key(blade)
		var deployed_yaw := _get_deployed_yaw_for_blade(blade, index, deployed_yaws_deg)
		var yaw := lerpf(folded_yaw_deg, deployed_yaw, unfold_t)
		var rest_transform: Transform3D = _blade_rest_transforms.get(blade_key, blade.transform)
		var yaw_delta := deg_to_rad(yaw - deployed_yaw)
		var transform := Transform3D(Basis(Vector3.UP, yaw_delta), Vector3.ZERO) * rest_transform
		var origin: Vector3 = rest_transform.origin
		origin.y += clampf(
			_get_stowed_stack_offset(index, rotor.get_child_count(), unfold_t),
			-absf(stowed_blade_stack_spacing_m),
			absf(stowed_blade_stack_spacing_m)
		)
		transform.origin = origin
		blade.transform = transform
		_apply_blade_segment_pose(blade, _get_current_blade_segment_angle_deg())
		index += 1


func _cache_blade_sections(blade: Node3D) -> void:
	var sections := _get_sorted_blade_sections(blade)
	var rest_transforms: Array[Transform3D] = []
	var hinges: Array[Vector3] = []
	for section in sections:
		var aabb := section.get_aabb()
		var hinge_z := section.transform.origin.z + aabb.position.z
		rest_transforms.append(section.transform)
		hinges.append(Vector3(section.transform.origin.x, section.transform.origin.y, hinge_z))
	var blade_key := _get_node_cache_key(blade)
	_blade_section_rest_transforms[blade_key] = rest_transforms
	_blade_section_hinges[blade_key] = hinges


func _get_sorted_blade_sections(blade: Node3D) -> Array[MeshInstance3D]:
	var sections: Array[MeshInstance3D] = []
	for child in blade.get_children():
		if child is MeshInstance3D and str(child.name).to_lower().find("section") != -1:
			sections.append(child as MeshInstance3D)
	sections.sort_custom(func(a: MeshInstance3D, b: MeshInstance3D) -> bool:
		return a.transform.origin.z < b.transform.origin.z
	)
	return sections


func _update_blade_segments() -> void:
	var segment_angle_deg := _get_current_blade_segment_angle_deg()
	if is_equal_approx(segment_angle_deg, _last_blade_segment_angle_deg):
		return
	_last_blade_segment_angle_deg = segment_angle_deg
	var unfold_t: float = 1.0 - clampf(_fold_t, 0.0, 1.0)
	_apply_rotor_blade_layout(upper_rotor, upper_blade_yaws_deg, unfold_t)
	_apply_rotor_blade_layout(lower_rotor, lower_blade_yaws_deg, unfold_t)


func _get_current_blade_segment_angle_deg() -> float:
	var power_t := _smoothstep(0.0, maxf(blade_segment_flat_power, 0.001), _power)
	return lerpf(resting_blade_segment_angle_deg, powered_blade_segment_angle_deg, power_t)


func _get_stowed_stack_offset(index: int, blade_count: int, unfold_t: float) -> float:
	if blade_count <= 1 or is_zero_approx(stowed_blade_stack_spacing_m):
		return 0.0
	var center_index := (float(blade_count) - 1.0) * 0.5
	var folded_t := 1.0 - clampf(unfold_t, 0.0, 1.0)
	return (float(index) - center_index) * stowed_blade_stack_spacing_m * folded_t


func _apply_blade_segment_pose(blade: Node3D, segment_angle_deg: float) -> void:
	var sections := _get_sorted_blade_sections(blade)
	var blade_key := _get_node_cache_key(blade)
	var rest_transforms: Array = _blade_section_rest_transforms.get(blade_key, [])
	var hinges: Array = _blade_section_hinges.get(blade_key, [])
	if sections.is_empty() or rest_transforms.size() != sections.size() or hinges.size() != sections.size():
		return
	var droop_sign := -float(_blade_droop_signs.get(blade_key, 1.0))
	var segment_angle_rad := deg_to_rad(segment_angle_deg) * droop_sign
	var deform := Transform3D.IDENTITY
	for i in range(sections.size()):
		var section := sections[i]
		var rest_transform := rest_transforms[i] as Transform3D
		var hinge := hinges[i] as Vector3
		if not is_zero_approx(segment_angle_rad):
			var current_hinge := deform * hinge
			var current_axis := deform.basis.x.normalized()
			deform = _make_rotation_around_point(current_axis, segment_angle_rad, current_hinge) * deform
		section.transform = deform * rest_transform


func _make_rotation_around_point(axis: Vector3, angle_rad: float, point: Vector3) -> Transform3D:
	var basis := Basis(axis.normalized(), angle_rad)
	return Transform3D(basis, point - basis * point)


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


func _smoothstep(edge0: float, edge1: float, x: float) -> float:
	if is_equal_approx(edge0, edge1):
		return 1.0 if x >= edge1 else 0.0
	var t := clampf((x - edge0) / (edge1 - edge0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


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
	var visual_speed := ROTOR_VISUAL_RATE_RAD_S * _power if _fold_t <= 0.001 else 0.0
	var visual_rpm := visual_speed * 60.0 / TAU
	print("ROTOR_DEBUG event=%s fold=%.3f target=%.3f unfold_requested=%s startup_latched=%s engine=%s collective=%.3f power=%.3f target_power=%.3f visual_rad_s=%.1f visual_rpm=%.0f upper_step_deg=%.2f lower_step_deg=%.2f segment_angle=%.2f cached_blades=%d upper={%s} lower={%s}" % [
		event_name,
		_fold_t,
		_fold_target,
		str(_unfold_requested),
		str(_startup_unfold_latched),
		str(_engine_active),
		_collective_power,
		_power,
		_target_power,
		visual_speed,
		visual_rpm,
		rad_to_deg(_last_upper_step_rad),
		rad_to_deg(_last_lower_step_rad),
		_get_current_blade_segment_angle_deg(),
		_blade_origins.size(),
		upper_summary,
		lower_summary
	])


func _get_rotor_debug_summary(rotor: Node3D) -> String:
	if rotor == null:
		return "missing"
	var parts := PackedStringArray()
	var rotor_yaw := rad_to_deg(rotor.rotation.y)
	var rotor_global := rotor.global_position
	for child in rotor.get_children():
		if not (child is Node3D):
			continue
		var blade := child as Node3D
		var blade_index := _get_blade_index(blade)
		var rest_yaw := _get_deployed_yaw_for_blade(blade, blade_index, _get_rotor_deployed_yaws(rotor))
		var blade_fields := PackedStringArray()
		blade_fields.append_array(_get_blade_section_debug_fields(rotor, blade))
		blade_fields.append_array(_get_blade_visual_tip_fields(rotor, blade))
		parts.append("%s idx=%d yaw=%.1f rest_yaw=%.1f visible=%s local=%s global=%s rest=%s stack=%.3f %s" % [
			blade.name,
			blade_index,
			rad_to_deg(blade.rotation.y),
			rest_yaw,
			str(blade.visible),
			_format_vec3(blade.position),
			_format_vec3(blade.global_position),
			_format_vec3(_get_blade_rest_origin(blade)),
			blade.position.y - _get_blade_rest_origin(blade).y,
			" ".join(blade_fields)
		])
	return "count=%d rotor_yaw=%.1f rotor_global=%s %s" % [
		rotor.get_child_count(),
		rotor_yaw,
		_format_vec3(rotor_global),
		";".join(parts)
	]


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


func _get_blade_section_debug_fields(rotor: Node3D, blade: Node3D) -> Array:
	var sections := _get_sorted_blade_sections(blade)
	if sections.is_empty():
		return ["sections=0"]
	var local_min_y := INF
	var local_max_y := -INF
	var rotor_min_y := INF
	var rotor_max_y := -INF
	var global_min_y := INF
	var global_max_y := -INF
	var offsets := PackedStringArray()
	var rest_transforms: Array = _blade_section_rest_transforms.get(_get_node_cache_key(blade), [])
	for i in range(sections.size()):
		var section := sections[i]
		var local_y := section.position.y
		var rotor_position := rotor.to_local(section.global_position)
		var global_y := section.global_position.y
		var rest_y := local_y
		if i < rest_transforms.size():
			var rest_transform := rest_transforms[i] as Transform3D
			rest_y = rest_transform.origin.y
		local_min_y = minf(local_min_y, local_y)
		local_max_y = maxf(local_max_y, local_y)
		rotor_min_y = minf(rotor_min_y, rotor_position.y)
		rotor_max_y = maxf(rotor_max_y, rotor_position.y)
		global_min_y = minf(global_min_y, global_y)
		global_max_y = maxf(global_max_y, global_y)
		offsets.append("%s:y=%.3f/rest=%.3f/rotor_y=%.3f/global_y=%.3f" % [
			section.name,
			local_y,
			rest_y,
			rotor_position.y,
			global_y
		])
	return [
		"sections=%d" % sections.size(),
		"section_local_y=(%.3f,%.3f)" % [local_min_y, local_max_y],
		"section_rotor_y=(%.3f,%.3f)" % [rotor_min_y, rotor_max_y],
		"section_global_y=(%.3f,%.3f)" % [global_min_y, global_max_y],
		"section_offsets=[%s]" % ",".join(offsets)
	]


func _get_blade_rest_origin(blade: Node3D) -> Vector3:
	var blade_key := _get_node_cache_key(blade)
	if _blade_rest_transforms.has(blade_key):
		var rest_transform := _blade_rest_transforms[blade_key] as Transform3D
		return rest_transform.origin
	return _blade_origins.get(blade_key, blade.position) as Vector3


func _get_node_cache_key(node: Node) -> int:
	return node.get_instance_id()


func _format_vec3(value: Vector3) -> String:
	return "(%.3f,%.3f,%.3f)" % [value.x, value.y, value.z]


func _get_mesh_instances(node: Node) -> Array[MeshInstance3D]:
	var meshes: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		meshes.append(node as MeshInstance3D)
	for child in node.get_children():
		meshes.append_array(_get_mesh_instances(child))
	return meshes
