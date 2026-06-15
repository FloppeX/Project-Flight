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
@export var medium_collective_negative_droop_threshold: float = 0.5
@export var high_collective_negative_droop_threshold: float = 0.75
@export var medium_collective_negative_droop_deg: float = 1.0
@export var high_collective_negative_droop_deg: float = 2.0
@export var debug_console_enabled: bool = false
@export var debug_interval_s: float = 1.0
@export var blur_start_power: float = 0.5
@export var blur_full_power: float = 0.9
@export var rotor_audio_stream: AudioStream = null
@export var rotor_audio_volume_db: float = 6.0
@export var rotor_audio_silent_db: float = -24.0
@export var rotor_audio_min_pitch: float = 0.82
@export var rotor_audio_max_pitch: float = 1.12
@export var rotor_audio_unit_size: float = 38.0
@export var rotor_audio_max_distance: float = 2200.0

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
var _upper_disc: Node3D = null
var _lower_disc: Node3D = null
var _rotor_audio_player: AudioStreamPlayer3D = null


func _ready() -> void:
	_cache_blade_rest_pose(upper_rotor)
	_cache_blade_rest_pose(lower_rotor)
	_setup_rotor_discs()
	_setup_rotor_audio()
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
	_update_rotor_transparency()
	_update_blade_segments()
	_update_rotor_audio()
	if _fold_t > 0.001:
		_power = 0.0
		_update_rotor_audio()
		_maybe_print_debug_line(delta)
		return
	if _power <= 0.0:
		_update_rotor_audio()
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


func _setup_rotor_audio() -> void:
	if rotor_audio_stream == null:
		return
	_make_stream_loop(rotor_audio_stream)
	_rotor_audio_player = AudioStreamPlayer3D.new()
	_rotor_audio_player.name = "RotorAudio"
	_rotor_audio_player.stream = rotor_audio_stream
	_rotor_audio_player.bus = "Master"
	_rotor_audio_player.volume_db = rotor_audio_silent_db
	_rotor_audio_player.unit_size = maxf(rotor_audio_unit_size, 1.0)
	_rotor_audio_player.max_distance = maxf(rotor_audio_max_distance, rotor_audio_unit_size)
	_rotor_audio_player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	_rotor_audio_player.add_to_group("3d_audio")
	add_child(_rotor_audio_player)


func _make_stream_loop(stream: AudioStream) -> void:
	if stream is AudioStreamWAV:
		var wav_stream: AudioStreamWAV = stream as AudioStreamWAV
		wav_stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	elif stream is AudioStreamOggVorbis:
		var ogg_stream: AudioStreamOggVorbis = stream as AudioStreamOggVorbis
		ogg_stream.loop = true


func _update_rotor_audio() -> void:
	if _rotor_audio_player == null:
		return
	var audio_power: float = clampf(_power, 0.0, 1.0)
	if audio_power <= 0.01:
		if _rotor_audio_player.playing:
			_rotor_audio_player.stop()
		_rotor_audio_player.volume_db = rotor_audio_silent_db
		return
	if not _rotor_audio_player.playing:
		_rotor_audio_player.play()
	var audible_power: float = sqrt(audio_power)
	_rotor_audio_player.volume_db = lerpf(rotor_audio_silent_db, rotor_audio_volume_db, audible_power)
	_rotor_audio_player.pitch_scale = lerpf(
		maxf(rotor_audio_min_pitch, 0.01),
		maxf(rotor_audio_max_pitch, 0.01),
		audible_power
	)


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
		if not child.name.begins_with("Blade"):
			continue
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
			_get_blade_count(rotor),
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
	var blade_count := _get_blade_count(rotor)
	for child in rotor.get_children():
		if not child.name.begins_with("Blade"):
			continue
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
			_get_stowed_stack_offset(index, blade_count, unfold_t),
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
	var segment_angle := lerpf(resting_blade_segment_angle_deg, powered_blade_segment_angle_deg, power_t)
	var collective := clampf(_collective_power, 0.0, 1.0)
	if collective > high_collective_negative_droop_threshold:
		segment_angle -= high_collective_negative_droop_deg
	elif collective > medium_collective_negative_droop_threshold:
		segment_angle -= medium_collective_negative_droop_deg
	return segment_angle


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
		if not child.name.begins_with("Blade"):
			continue
		var blade := child as Node3D
		if blade == null:
			continue
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
		_get_blade_count(rotor),
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
		if child is Node3D and child.name.begins_with("Blade"):
			index += 1
	return index


func _get_blade_count(rotor: Node3D) -> int:
	if rotor == null:
		return 0
	var count := 0
	for child in rotor.get_children():
		if child.name.begins_with("Blade"):
			count += 1
	return count


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


func _setup_rotor_discs() -> void:
	# 1. Search for manual disc nodes placed in the scene under RotorAssembly (self)
	var manual_discs: Array[Node3D] = []
	for child in get_children():
		if child is Node3D and child.name.to_lower().find("rotor disc") != -1:
			manual_discs.append(child as Node3D)
			
	# 2. Assign/Reparent manual discs to upper/lower rotors if found
	if not manual_discs.is_empty():
		if manual_discs.size() >= 2 and upper_rotor != null and lower_rotor != null:
			# Coaxial setup - sort by Y position to match lower/upper
			manual_discs.sort_custom(func(a: Node3D, b: Node3D) -> bool:
				return a.position.y < b.position.y
			)
			
			# Lower disc
			var lower_disc_node := manual_discs[0]
			var lower_y_offset := lower_disc_node.position.y - lower_rotor.position.y
			if lower_disc_node.get_parent() != lower_rotor:
				lower_disc_node.get_parent().remove_child(lower_disc_node)
				lower_rotor.add_child(lower_disc_node)
			lower_disc_node.name = "RotorDisc"
			lower_disc_node.position = Vector3(0.0, lower_y_offset, 0.0)
			_lower_disc = lower_disc_node
			
			# Upper disc
			var upper_disc_node := manual_discs[1]
			var upper_y_offset := upper_disc_node.position.y - upper_rotor.position.y
			if upper_disc_node.get_parent() != upper_rotor:
				upper_disc_node.get_parent().remove_child(upper_disc_node)
				upper_rotor.add_child(upper_disc_node)
			upper_disc_node.name = "RotorDisc"
			upper_disc_node.position = Vector3(0.0, upper_y_offset, 0.0)
			_upper_disc = upper_disc_node
			
		elif upper_rotor != null:
			# Single rotor setup
			var upper_disc_node := manual_discs[0]
			var upper_y_offset := upper_disc_node.position.y - upper_rotor.position.y
			if upper_disc_node.get_parent() != upper_rotor:
				upper_disc_node.get_parent().remove_child(upper_disc_node)
				upper_rotor.add_child(upper_disc_node)
			upper_disc_node.name = "RotorDisc"
			upper_disc_node.position = Vector3(0.0, upper_y_offset, 0.0)
			_upper_disc = upper_disc_node
			
			# Clean up any other extra manual discs
			for i in range(1, manual_discs.size()):
				manual_discs[i].queue_free()

	# 3. Dynamic fallback: instantiate the disc model if no manual discs exist in the scene tree
	var disc_scene = load("res://Models/Aircraft_9/rotor disc.glb")
	
	if upper_rotor != null and _upper_disc == null:
		_upper_disc = upper_rotor.find_child("RotorDisc", true, false)
		if _upper_disc == null and disc_scene != null:
			_upper_disc = disc_scene.instantiate()
			_upper_disc.name = "RotorDisc"
			upper_rotor.add_child(_upper_disc)
			_upper_disc.position = Vector3.ZERO
			
	if lower_rotor != null and _lower_disc == null:
		_lower_disc = lower_rotor.find_child("RotorDisc", true, false)
		if _lower_disc == null and disc_scene != null:
			_lower_disc = disc_scene.instantiate()
			_lower_disc.name = "RotorDisc"
			lower_rotor.add_child(_lower_disc)
			_lower_disc.position = Vector3.ZERO
			
	# 4. Apply scale and orientation adjustments to the resolved disc nodes
	if _upper_disc != null:
		_scale_and_align_disc(_upper_disc, upper_rotor)
	if _lower_disc != null:
		_scale_and_align_disc(_lower_disc, lower_rotor)


func _scale_and_align_disc(disc: Node3D, rotor: Node3D) -> void:
	# Keep local position Y offset (clearance), center X and Z
	disc.position = Vector3(0.0, disc.position.y, 0.0)
	disc.rotation = Vector3.ZERO
	
	# Calculate blade radius
	var blade_radius := 0.0
	for child in rotor.get_children():
		if child != disc and child.name.begins_with("Blade"):
			for grandchild in child.get_children():
				if grandchild is MeshInstance3D:
					var mesh_child := grandchild as MeshInstance3D
					var aabb := mesh_child.get_aabb()
					var pos_start: Vector3 = child.transform * (mesh_child.position + aabb.position)
					var pos_end: Vector3 = child.transform * (mesh_child.position + aabb.position + aabb.size)
					blade_radius = maxf(blade_radius, Vector3(pos_start.x, 0, pos_start.z).length())
					blade_radius = maxf(blade_radius, Vector3(pos_end.x, 0, pos_end.z).length())
					
	if blade_radius > 0.1:
		var scale_factor = blade_radius / 6.806614
		disc.scale = Vector3(scale_factor, 1.0, scale_factor)
	else:
		disc.scale = Vector3.ONE
	
	# Make sure it starts invisible
	disc.visible = false
	_set_node_transparency(disc, 1.0)


func _update_rotor_transparency() -> void:
	# Calculate a normalized visual blend factor t based on the spool speed _power
	var denom := maxf(blur_full_power - blur_start_power, 0.001)
	var t := clampf((_power - blur_start_power) / denom, 0.0, 1.0)
	
	# Transition variables
	var disc_transparency := 1.0 - t
	var blade_transparency := t * 0.8 # 0.0 when stopped, 0.8 (20% opaque) at full speed
	
	if _upper_disc != null:
		_upper_disc.visible = t > 0.001
		_set_node_transparency(_upper_disc, disc_transparency)
	if _lower_disc != null:
		_lower_disc.visible = t > 0.001
		_set_node_transparency(_lower_disc, disc_transparency)
		
	if upper_rotor != null:
		_set_blade_transparency(upper_rotor, blade_transparency)
	if lower_rotor != null:
		_set_blade_transparency(lower_rotor, blade_transparency)


func _set_blade_transparency(rotor: Node3D, transparency: float) -> void:
	if rotor == null:
		return
	for child in rotor.get_children():
		if child.name.begins_with("Blade"):
			_set_node_transparency(child, transparency)


func _set_node_transparency(node: Node, transparency: float) -> void:
	if node is MeshInstance3D:
		node.transparency = clampf(transparency, 0.0, 1.0)
	for child in node.get_children():
		_set_node_transparency(child, transparency)
