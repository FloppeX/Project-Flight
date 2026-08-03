extends Node

## Reversible rendering LOD policy for a single vehicle hierarchy.
## Imported meshes keep their authored/generated LODs; this controller only
## selects how aggressively Godot uses them and culls sub-pixel wheel detail.

const VISUAL_FOCUS_HELPER = preload("res://Effects/VisualFocus.gd")

enum DetailTier { NEAR, MID, FAR }

var _host: Node3D = null
var _meshes: Array[MeshInstance3D] = []
var _original_lod_biases: Array[float] = []
var _original_visibility_range_ends: Array[float] = []
var _original_visibility_fade_modes: Array = []
var _original_shadow_settings: Array = []
var _wheel_mesh_flags: Array[bool] = []
var _update_timer_s: float = 0.0
var _current_tier: DetailTier = DetailTier.NEAR
var _current_lod_bias_multiplier: float = 1.0
var _last_wheel_visibility_distance_m: float = -1.0
var _last_shadows_disabled: bool = false
var _policy_applied: bool = false

func setup(host: Node3D) -> void:
	_host = host
	_collect_meshes()
	_update_timer_s = randf_range(0.0, 0.25)

func update_policy(
	delta: float,
	camera: Camera3D,
	enabled: bool,
	update_interval_s: float,
	near_distance_m: float,
	far_distance_m: float,
	mid_lod_bias_multiplier: float,
	far_lod_bias_multiplier: float,
	wheel_visibility_distance_m: float,
	shadow_visibility_distance_m: float
) -> void:
	if not enabled:
		if _policy_applied:
			_restore_original_settings()
		return
	if _host == null or not is_instance_valid(_host):
		return
	_update_timer_s -= delta
	if _update_timer_s > 0.0:
		return
	_update_timer_s = maxf(update_interval_s, 0.02)
	if _meshes.is_empty():
		_collect_meshes()
	if _meshes.is_empty():
		return

	_apply_wheel_visibility_range(wheel_visibility_distance_m)
	var distance_m := INF
	var force_near_detail := VISUAL_FOCUS_HELPER.is_node_in_target_camera_focus(self, _host)
	if camera != null and is_instance_valid(camera):
		distance_m = _host.global_position.distance_to(camera.global_position)
	var tier := DetailTier.FAR
	if force_near_detail or distance_m <= maxf(near_distance_m, 0.0):
		tier = DetailTier.NEAR
	elif distance_m <= maxf(far_distance_m, near_distance_m):
		tier = DetailTier.MID

	var lod_multiplier := 1.0
	match tier:
		DetailTier.MID:
			lod_multiplier = clampf(mid_lod_bias_multiplier, 0.02, 1.0)
		DetailTier.FAR:
			lod_multiplier = clampf(far_lod_bias_multiplier, 0.02, 1.0)
	var disable_shadows := (
		shadow_visibility_distance_m > 0.0
		and not force_near_detail
		and distance_m > shadow_visibility_distance_m
	)
	if tier != _current_tier or not is_equal_approx(lod_multiplier, _current_lod_bias_multiplier) or disable_shadows != _last_shadows_disabled or not _policy_applied:
		_apply_dynamic_settings(tier, lod_multiplier, disable_shadows)

func force_refresh() -> void:
	_update_timer_s = 0.0

func get_mesh_count() -> int:
	return _meshes.size()

func get_wheel_mesh_count() -> int:
	var count := 0
	for is_wheel in _wheel_mesh_flags:
		if is_wheel:
			count += 1
	return count

func get_current_lod_bias_multiplier() -> float:
	return _current_lod_bias_multiplier

func _collect_meshes() -> void:
	_meshes.clear()
	_original_lod_biases.clear()
	_original_visibility_range_ends.clear()
	_original_visibility_fade_modes.clear()
	_original_shadow_settings.clear()
	_wheel_mesh_flags.clear()
	if _host == null or not is_instance_valid(_host):
		return
	for descendant in _host.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := descendant as MeshInstance3D
		if mesh_instance == null:
			continue
		_meshes.append(mesh_instance)
		_original_lod_biases.append(mesh_instance.lod_bias)
		_original_visibility_range_ends.append(mesh_instance.visibility_range_end)
		_original_visibility_fade_modes.append(mesh_instance.visibility_range_fade_mode)
		_original_shadow_settings.append(mesh_instance.cast_shadow)
		_wheel_mesh_flags.append(_is_wheel_mesh(mesh_instance))

func _is_wheel_mesh(mesh_instance: MeshInstance3D) -> bool:
	var cursor: Node = mesh_instance
	while cursor != null and cursor != _host:
		if "wheel" in cursor.name.to_lower():
			return true
		cursor = cursor.get_parent()
	return false

func _apply_wheel_visibility_range(distance_m: float) -> void:
	if is_equal_approx(distance_m, _last_wheel_visibility_distance_m) and _policy_applied:
		return
	_last_wheel_visibility_distance_m = distance_m
	for i in range(_meshes.size()):
		var mesh_instance := _meshes[i]
		if mesh_instance == null or not is_instance_valid(mesh_instance) or not _wheel_mesh_flags[i]:
			continue
		var original_end: float = _original_visibility_range_ends[i]
		if distance_m <= 0.0:
			mesh_instance.visibility_range_end = original_end
			mesh_instance.visibility_range_fade_mode = _original_visibility_fade_modes[i]
		else:
			mesh_instance.visibility_range_end = distance_m if original_end <= 0.0 else minf(original_end, distance_m)
			mesh_instance.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF

func _apply_dynamic_settings(tier: DetailTier, lod_multiplier: float, disable_shadows: bool) -> void:
	_current_tier = tier
	_current_lod_bias_multiplier = lod_multiplier
	_last_shadows_disabled = disable_shadows
	_policy_applied = true
	for i in range(_meshes.size()):
		var mesh_instance := _meshes[i]
		if mesh_instance == null or not is_instance_valid(mesh_instance):
			continue
		mesh_instance.lod_bias = maxf(_original_lod_biases[i] * lod_multiplier, 0.02)
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if disable_shadows else _original_shadow_settings[i]

func _restore_original_settings() -> void:
	for i in range(_meshes.size()):
		var mesh_instance := _meshes[i]
		if mesh_instance == null or not is_instance_valid(mesh_instance):
			continue
		mesh_instance.lod_bias = _original_lod_biases[i]
		mesh_instance.visibility_range_end = _original_visibility_range_ends[i]
		mesh_instance.visibility_range_fade_mode = _original_visibility_fade_modes[i]
		mesh_instance.cast_shadow = _original_shadow_settings[i]
	_current_tier = DetailTier.NEAR
	_current_lod_bias_multiplier = 1.0
	_last_wheel_visibility_distance_m = -1.0
	_last_shadows_disabled = false
	_policy_applied = false
