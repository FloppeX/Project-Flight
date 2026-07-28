extends StaticBody3D
class_name CarrierTread

const DEFAULT_PLATE_MATERIAL_COLOR := Color(0.13, 0.14, 0.14, 1.0)
const DEBUG_MODE_NAMES := [
	"Final",
	"Path",
	"Spacing",
]

@export var tread_index: int = 0
@export var carrier_offset: Vector3 = Vector3.ZERO

@export_group("Track Plates")
@export var plate_count: int = 20:
	set(value):
		plate_count = maxi(value, 1)
		if is_inside_tree():
			_rebuild_track_multimesh()
@export var scroll_speed: float = 0.0
@export var plate_scene: PackedScene:
	set(value):
		plate_scene = value
		if is_inside_tree():
			_rebuild_track_multimesh()
@export_file("*.tscn", "*.scn", "*.glb") var plate_scene_path: String = "res://Models/LandCarrier/carrier track plate.glb"
@export var fallback_plate_size: Vector3 = Vector3(5.2, 0.35, 1.35)
@export var auto_fit_plate_length_to_path: bool = true
@export var plate_target_width_m: float = 12.0
@export var plate_gap_m: float = 0.2
@export var plate_local_rotation_degrees: Vector3 = Vector3.ZERO
@export var plate_local_scale: Vector3 = Vector3.ONE
@export var visual_direction_sign: float = 1.0
@export var skip_offscreen_plate_animation: bool = true
@export var visibility_bounds_padding_m: float = 6.0

@export_group("Generated Loop")
@export var auto_build_path: bool = true
@export var path_node_name: StringName = &"TrackPath"
@export var guide_root_name: StringName = &"TrackGuide"
@export_range(0.05, 0.9, 0.01) var curve_handle_ratio: float = 0.42
@export var top_run_length_m: float = 31.0
@export var bottom_run_length_m: float = 31.0
@export var loop_height_m: float = 10.0
@export var front_slope_extension_m: float = 4.0
@export var back_slope_extension_m: float = 4.0
@export var path_vertical_offset_m: float = 6.0
@export var path_side_offset_m: float = -5.2

@export_group("Wheels")
@export var wheel_radius_m: float = 4.0
@export_range(0, 2) var wheel_spin_axis: int = 0
@export var wheel_visual_direction_sign: float = -1.0

@export_group("Audio")
@export var rolling_sound: AudioStream = preload("res://Audio/Carrier/Rolling_tracks_mono.wav")
@export var rolling_sound_bus: String = "Master"
@export var rolling_sound_min_volume_db: float = -16.0
@export var rolling_sound_max_volume_db: float = -7.0
@export var rolling_sound_pitch_min: float = 0.78
@export var rolling_sound_pitch_max: float = 1.18
@export var rolling_sound_silence_db: float = -80.0
@export var rolling_sound_full_speed_mps: float = 8.0
@export var rolling_sound_unit_size_m: float = 48.0
@export var rolling_sound_max_distance_m: float = 300.0

@export_group("Debug")
@export_enum("Final:0", "Path:1", "Spacing:2") var belt_debug_mode: int = 0:
	set(value):
		belt_debug_mode = clampi(value, 0, DEBUG_MODE_NAMES.size() - 1)
		_apply_debug_mode()
@export var belt_debug_freeze_scroll: bool = false

var carrier: Node3D = null

var _path: Path3D = null
var _track_multimesh: MultiMeshInstance3D = null
var _track_mesh: Mesh = null
var _path_length_m: float = 0.0
var _travel_m: float = 0.0
var _scroll_sign: float = 1.0
var _wheel_spin_sign: float = 1.0
var _wheel_roots: Array[Node3D] = []
var _last_carrier_origin: Vector3 = Vector3.ZERO
var _last_carrier_forward: Vector3 = Vector3.FORWARD
var _last_external_update_msec: int = 0
var _rolling_audio_player: AudioStreamPlayer3D = null
var _visibility_notifier: VisibleOnScreenNotifier3D = null
var _track_visuals_on_screen: bool = true
var _track_visual_refresh_required: bool = true
var _visual_budget_enabled: bool = true


func _ready() -> void:
	carrier = get_parent() as Node3D
	if carrier != null and carrier.name != "LandCarrier":
		carrier = carrier.get_parent() as Node3D

	collision_layer = 0
	collision_mask = 0

	setup_tread_offset()
	_last_carrier_origin = carrier.global_position if carrier else global_position
	_last_carrier_forward = _get_carrier_forward()

	var legacy_belt := get_node_or_null("carrier track tread") as Node3D
	if legacy_belt:
		legacy_belt.visible = false

	_collect_wheels()
	_ensure_path()
	_rebuild_track_multimesh()
	_setup_visibility_notifier()
	_setup_rolling_audio()


func set_visual_budget_enabled(enabled: bool) -> void:
	if _visual_budget_enabled == enabled:
		return
	_visual_budget_enabled = enabled
	set_physics_process(enabled)
	if _track_multimesh != null:
		_track_multimesh.visible = enabled
	for wheel in _wheel_roots:
		if is_instance_valid(wheel):
			wheel.visible = enabled
	for child in get_children():
		if child.has_method("set_visual_budget_enabled"):
			child.call("set_visual_budget_enabled", enabled)
	if enabled:
		_track_visual_refresh_required = true
		if _rolling_audio_player != null and not _rolling_audio_player.playing:
			_rolling_audio_player.call_deferred("play")
	else:
		if _rolling_audio_player != null:
			_rolling_audio_player.volume_db = rolling_sound_silence_db


func setup_tread_offset() -> void:
	var tread_positions: Array[Vector3] = [
		Vector3(-32, -32, -43),
		Vector3(32, -32, -43),
		Vector3(-32, -32, 0),
		Vector3(32, -32, 0),
		Vector3(32, -32, 43),
		Vector3(-32, -32, 43),
	]
	if tread_index < tread_positions.size():
		carrier_offset = tread_positions[tread_index]

	_scroll_sign = -1.0 if carrier_offset.x > 0.0 else 1.0
	_wheel_spin_sign = -1.0 if carrier_offset.x < 0.0 else 1.0


func set_scroll_speed(speed_mps: float) -> void:
	scroll_speed = speed_mps


func set_track_speed(speed_mps: float) -> void:
	set_scroll_speed(speed_mps)


func get_plate_spacing_m() -> float:
	if _path_length_m > 0.001:
		return _path_length_m / float(maxi(plate_count, 1))
	return maxf(fallback_plate_size.z + maxf(plate_gap_m, 0.0), 0.05)


func get_plate_length_m() -> float:
	return _plate_length_for_spacing(get_plate_spacing_m())


func get_plate_width_m() -> float:
	return maxf(plate_target_width_m, fallback_plate_size.x)


func update_scroll_speed(delta: float, speed_mps: float) -> void:
	_last_external_update_msec = Time.get_ticks_msec()
	_apply_scroll_speed(delta, speed_mps)


func update_from_carrier(delta: float, signed_travel_m: float) -> void:
	_last_external_update_msec = Time.get_ticks_msec()
	var speed_mps := signed_travel_m / delta if delta > 0.0 else 0.0
	_apply_scroll_speed(delta, speed_mps)


func _physics_process(delta: float) -> void:
	var recent_external_update := Time.get_ticks_msec() - _last_external_update_msec <= 100
	if recent_external_update:
		return

	var signed_travel := _compute_signed_travel()
	if absf(signed_travel) > 20.0:
		signed_travel = 0.0
	var speed_mps := signed_travel / delta if delta > 0.0 else 0.0
	_apply_scroll_speed(delta, speed_mps)


func update_position() -> void:
	if carrier:
		var tread_position := carrier.global_position + carrier_offset
		tread_position.y = carrier.global_position.y - 32.0
		global_position = tread_position


func set_belt_debug_mode(mode: int) -> void:
	belt_debug_mode = mode


func cycle_belt_debug_mode(step: int = 1) -> void:
	var count := DEBUG_MODE_NAMES.size()
	set_belt_debug_mode(posmod(belt_debug_mode + step, count))


func toggle_belt_debug_freeze() -> void:
	belt_debug_freeze_scroll = not belt_debug_freeze_scroll
	print("[CarrierTread] Scroll freeze %s" % ("ON" if belt_debug_freeze_scroll else "OFF"))


func get_belt_debug_mode_name() -> String:
	return DEBUG_MODE_NAMES[clampi(belt_debug_mode, 0, DEBUG_MODE_NAMES.size() - 1)]


func _ensure_path() -> void:
	_path = get_node_or_null(NodePath(path_node_name)) as Path3D
	if _path == null:
		_path = Path3D.new()
		_path.name = path_node_name
		add_child(_path)

	if auto_build_path or _path.curve == null or _path.curve.point_count < 4:
		var guide_curve := _build_curve_from_guide_markers()
		_path.curve = guide_curve if guide_curve != null else _build_default_curve()

	_refresh_path_length()


func _build_curve_from_guide_markers() -> Curve3D:
	var guide_root := get_node_or_null(NodePath(guide_root_name)) as Node3D
	if guide_root == null:
		return null

	var starts: Array[Vector3] = []
	var ends: Array[Vector3] = []
	for i in range(1, 5):
		var start_marker := _find_curve_marker(guide_root, "curve_start_%d" % i, "curve_start%d" % i)
		var end_marker := _find_curve_marker(guide_root, "curve_end_%d" % i, "curve_end%d" % i)
		if start_marker == null or end_marker == null:
			return null
		starts.append(to_local(start_marker.global_position))
		ends.append(to_local(end_marker.global_position))

	var curve := Curve3D.new()
	curve.bake_interval = 0.12
	for i in range(4):
		var prev_end: Vector3 = ends[posmod(i - 1, 4)]
		var start: Vector3 = starts[i]
		var end: Vector3 = ends[i]
		var next_start: Vector3 = starts[(i + 1) % 4]

		var incoming := start - prev_end
		var outgoing := next_start - end
		var curve_span := start.distance_to(end)
		var handle_len := curve_span * curve_handle_ratio
		if incoming.length_squared() > 0.0001:
			handle_len = minf(handle_len, incoming.length() * 0.5)
		if outgoing.length_squared() > 0.0001:
			handle_len = minf(handle_len, outgoing.length() * 0.5)

		var out_handle := incoming.normalized() * handle_len if incoming.length_squared() > 0.0001 else Vector3.ZERO
		var in_handle := -outgoing.normalized() * handle_len if outgoing.length_squared() > 0.0001 else Vector3.ZERO
		curve.add_point(start, Vector3.ZERO, out_handle)
		curve.add_point(end, in_handle, Vector3.ZERO)

	curve.add_point(starts[0])
	return curve


func _find_curve_marker(root: Node, primary_name: String, fallback_name: String) -> Node3D:
	var node := root.get_node_or_null(primary_name) as Node3D
	if node:
		return node
	return root.get_node_or_null(fallback_name) as Node3D


func _build_default_curve() -> Curve3D:
	var curve := Curve3D.new()
	curve.bake_interval = 0.2

	var top_half := top_run_length_m * 0.5
	var bottom_half := bottom_run_length_m * 0.5
	var top_y := path_vertical_offset_m
	var bottom_y := path_vertical_offset_m - loop_height_m
	var x := path_side_offset_m

	var back_top := Vector3(x, top_y, -top_half)
	var front_top := Vector3(x, top_y, top_half)
	var front_bottom := Vector3(x, bottom_y, bottom_half + front_slope_extension_m)
	var back_bottom := Vector3(x, bottom_y, -bottom_half - back_slope_extension_m)

	for point in [back_top, front_top, front_bottom, back_bottom, back_top]:
		curve.add_point(point)

	return curve


func _refresh_path_length() -> void:
	if _path == null or _path.curve == null:
		_path_length_m = 0.0
		return
	_path_length_m = _path.curve.get_baked_length()


func _rebuild_track_multimesh() -> void:
	_ensure_path()
	_clear_path_follow_plates()

	if _path == null or _path_length_m <= 0.001:
		return

	var spacing := _path_length_m / float(maxi(plate_count, 1))
	_track_mesh = _resolve_plate_mesh(spacing)
	if _track_mesh == null:
		return

	_track_multimesh = get_node_or_null("TrackPlates") as MultiMeshInstance3D
	if _track_multimesh == null:
		_track_multimesh = MultiMeshInstance3D.new()
		_track_multimesh.name = "TrackPlates"
		add_child(_track_multimesh)

	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = _track_mesh
	multimesh.instance_count = plate_count
	_track_multimesh.multimesh = multimesh
	_update_multimesh_transforms()
	_update_visibility_notifier_bounds()

	_apply_debug_mode()


func _resolve_plate_scene() -> PackedScene:
	if plate_scene != null:
		return plate_scene
	if plate_scene_path != "" and ResourceLoader.exists(plate_scene_path):
		return load(plate_scene_path) as PackedScene
	return null


func _resolve_plate_mesh(spacing_m: float) -> Mesh:
	var scene := _resolve_plate_scene()
	if scene != null:
		var inst := scene.instantiate()
		if inst is Node3D:
			var mesh_node := _find_first_mesh_instance(inst)
			if mesh_node != null and mesh_node.mesh != null:
				var mesh := mesh_node.mesh
				inst.queue_free()
				return mesh
		inst.queue_free()
	return _make_fallback_plate_mesh(spacing_m)


func _make_fallback_plate_mesh(spacing_m: float) -> Mesh:
	var box := BoxMesh.new()
	var fitted_size := fallback_plate_size
	fitted_size.x = plate_target_width_m
	if auto_fit_plate_length_to_path:
		fitted_size.z = _plate_length_for_spacing(spacing_m)
	box.size = fitted_size

	var material := StandardMaterial3D.new()
	material.albedo_color = DEFAULT_PLATE_MATERIAL_COLOR
	material.roughness = 0.92
	box.material = material
	return box


func _plate_length_for_spacing(spacing_m: float) -> float:
	return maxf(spacing_m - maxf(plate_gap_m, 0.0), 0.05)


func _find_first_mesh_instance(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node as MeshInstance3D
	for child in node.get_children():
		var found := _find_first_mesh_instance(child)
		if found:
			return found
	return null


func _clear_path_follow_plates() -> void:
	if _path == null:
		return
	for child in _path.get_children():
		if child is PathFollow3D:
			child.queue_free()


func _advance_tracks(signed_travel_m: float) -> void:
	if not _visual_budget_enabled:
		return
	if _path_length_m <= 0.001:
		return
	if belt_debug_freeze_scroll:
		if _should_update_track_visuals():
			_rotate_wheels(signed_travel_m)
		return

	_travel_m = _wrap_distance(_travel_m + signed_travel_m * _scroll_sign * visual_direction_sign)
	if _should_update_track_visuals():
		_update_multimesh_transforms()
		_rotate_wheels(signed_travel_m)


func _should_update_track_visuals() -> bool:
	if not skip_offscreen_plate_animation:
		_track_visual_refresh_required = false
		return true
	if _visibility_notifier == null or not is_instance_valid(_visibility_notifier) or not _visibility_notifier.is_inside_tree():
		_track_visual_refresh_required = false
		return true
	var visible_to_camera := _visibility_notifier.is_on_screen()
	if visible_to_camera:
		_track_visuals_on_screen = true
	if visible_to_camera or _track_visual_refresh_required:
		_track_visual_refresh_required = false
		return true
	_track_visuals_on_screen = false
	return false


func _setup_visibility_notifier() -> void:
	_visibility_notifier = get_node_or_null("TrackVisibility") as VisibleOnScreenNotifier3D
	if _visibility_notifier == null:
		_visibility_notifier = VisibleOnScreenNotifier3D.new()
		_visibility_notifier.name = "TrackVisibility"
		add_child(_visibility_notifier)
	_update_visibility_notifier_bounds()
	if not _visibility_notifier.screen_entered.is_connected(_on_track_screen_entered):
		_visibility_notifier.screen_entered.connect(_on_track_screen_entered)
	if not _visibility_notifier.screen_exited.is_connected(_on_track_screen_exited):
		_visibility_notifier.screen_exited.connect(_on_track_screen_exited)
	_track_visuals_on_screen = _visibility_notifier.is_on_screen()
	_track_visual_refresh_required = true


func _update_visibility_notifier_bounds() -> void:
	if _visibility_notifier == null:
		return
	var padding := maxf(visibility_bounds_padding_m, 0.0)
	var half_width := maxf(plate_target_width_m, fallback_plate_size.x) * 0.5 + padding
	var half_length := maxf(top_run_length_m, bottom_run_length_m) * 0.5 + maxf(front_slope_extension_m, back_slope_extension_m) + padding
	var half_height := maxf(loop_height_m, fallback_plate_size.y) * 0.5 + padding
	var center := Vector3(path_side_offset_m, path_vertical_offset_m - loop_height_m * 0.5, 0.0)
	var size := Vector3(half_width * 2.0, half_height * 2.0, half_length * 2.0)
	_visibility_notifier.aabb = AABB(center - size * 0.5, size)


func _on_track_screen_entered() -> void:
	_track_visuals_on_screen = true
	_track_visual_refresh_required = true


func _on_track_screen_exited() -> void:
	_track_visuals_on_screen = false


func _apply_scroll_speed(delta: float, speed_mps: float) -> void:
	scroll_speed = speed_mps
	if not _visual_budget_enabled:
		return
	_update_rolling_audio(delta, absf(scroll_speed))
	_advance_tracks(scroll_speed * delta)


func _wrap_distance(value: float) -> float:
	if _path_length_m <= 0.001:
		return 0.0
	return wrapf(value, 0.0, _path_length_m)


func _rotate_wheels(signed_travel_m: float) -> void:
	if absf(signed_travel_m) < 0.0001:
		return
	var angle := signed_travel_m / maxf(wheel_radius_m, 0.001) * _wheel_spin_sign * wheel_visual_direction_sign
	for wheel in _wheel_roots:
		match wheel_spin_axis:
			0:
				wheel.rotate_x(angle)
			1:
				wheel.rotate_y(angle)
			2:
				wheel.rotate_z(angle)


func _update_multimesh_transforms() -> void:
	if _track_multimesh == null or _track_multimesh.multimesh == null or _path == null or _path.curve == null:
		return
	if _track_mesh == null or _path_length_m <= 0.001:
		return

	var spacing := _path_length_m / float(maxi(plate_count, 1))
	var target_length := _plate_length_for_spacing(spacing)
	var source_size := _track_mesh.get_aabb().size
	var scale := plate_local_scale
	if source_size.x > 0.001 and plate_target_width_m > 0.001:
		scale.x *= plate_target_width_m / source_size.x
	if auto_fit_plate_length_to_path and source_size.z > 0.001 and target_length > 0.001:
		scale.z *= target_length / source_size.z

	for i in range(plate_count):
		if belt_debug_mode == 2 and i % 2 != 0:
			_track_multimesh.multimesh.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO))
			continue
		var progress := _wrap_distance(_travel_m + spacing * float(i))
		_track_multimesh.multimesh.set_instance_transform(i, _sample_track_transform(progress, scale))


func _sample_track_transform(progress_m: float, scale: Vector3) -> Transform3D:
	var curve := _path.curve
	var origin := curve.sample_baked(progress_m, true)
	var epsilon := minf(0.2, _path_length_m * 0.01)
	var prev := curve.sample_baked(_wrap_distance(progress_m - epsilon), true)
	var next := curve.sample_baked(_wrap_distance(progress_m + epsilon), true)
	var tangent := next - prev
	if tangent.length_squared() < 0.0001:
		tangent = Vector3.FORWARD

	var z_axis := tangent.normalized()
	var x_axis := Vector3.RIGHT - z_axis * Vector3.RIGHT.dot(z_axis)
	if x_axis.length_squared() < 0.0001:
		x_axis = Vector3.UP.cross(z_axis)
	x_axis = x_axis.normalized()
	var y_axis := z_axis.cross(x_axis).normalized()

	var basis := Basis(x_axis, y_axis, z_axis)
	var local_rotation := Vector3(
		deg_to_rad(plate_local_rotation_degrees.x),
		deg_to_rad(plate_local_rotation_degrees.y),
		deg_to_rad(plate_local_rotation_degrees.z)
	)
	basis = basis * Basis.from_euler(local_rotation)
	basis = basis.scaled(scale)
	return Transform3D(basis, origin)


func _collect_wheels() -> void:
	_wheel_roots.clear()
	var wheel_names := [
		"carrier track wheel",
		"carrier track wheel2",
		"carrier track wheel3",
		"carrier track wheel4",
		"carrier track wheel5",
	]
	for wname in wheel_names:
		var node := get_node_or_null(wname) as Node3D
		if node:
			_wheel_roots.append(node)


func _apply_debug_mode() -> void:
	if _track_multimesh:
		_track_multimesh.visible = _visual_budget_enabled
		_update_multimesh_transforms()


func _get_carrier_forward() -> Vector3:
	if carrier == null:
		return Vector3.FORWARD
	var forward := carrier.global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		return Vector3.FORWARD
	return forward.normalized()


func _compute_signed_travel() -> float:
	if carrier == null:
		return 0.0

	var current_origin := carrier.global_position
	var current_forward := _get_carrier_forward()
	var origin_delta := current_origin - _last_carrier_origin
	var forward_delta := origin_delta.dot(_last_carrier_forward)
	var yaw_delta := _last_carrier_forward.signed_angle_to(current_forward, Vector3.UP)
	var turn_delta := -carrier_offset.x * yaw_delta

	_last_carrier_origin = current_origin
	_last_carrier_forward = current_forward

	return forward_delta + turn_delta


func _setup_rolling_audio() -> void:
	if rolling_sound == null:
		return

	if rolling_sound is AudioStreamWAV:
		rolling_sound.loop_mode = AudioStreamWAV.LOOP_FORWARD

	_rolling_audio_player = AudioStreamPlayer3D.new()
	_rolling_audio_player.name = "RollingTracksAudio"
	_rolling_audio_player.stream = rolling_sound
	_rolling_audio_player.bus = rolling_sound_bus
	_rolling_audio_player.max_distance = rolling_sound_max_distance_m
	_rolling_audio_player.unit_size = rolling_sound_unit_size_m
	_rolling_audio_player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_SQUARE_DISTANCE
	_rolling_audio_player.volume_db = rolling_sound_silence_db
	_rolling_audio_player.pitch_scale = rolling_sound_pitch_min
	_rolling_audio_player.add_to_group("3d_audio")
	add_child(_rolling_audio_player)
	_rolling_audio_player.call_deferred("play")


func _update_rolling_audio(delta: float, tread_speed_mps: float) -> void:
	if _rolling_audio_player == null:
		return

	var speed_factor := clampf(tread_speed_mps / maxf(rolling_sound_full_speed_mps, 0.01), 0.0, 1.0)
	speed_factor = speed_factor * speed_factor * (3.0 - 2.0 * speed_factor)
	var target_volume := rolling_sound_silence_db if tread_speed_mps < 0.05 else lerpf(rolling_sound_min_volume_db, rolling_sound_max_volume_db, speed_factor)
	var target_pitch := lerpf(rolling_sound_pitch_min, rolling_sound_pitch_max, speed_factor)
	var blend := clampf(delta * 5.0, 0.0, 1.0)
	_rolling_audio_player.volume_db = lerpf(_rolling_audio_player.volume_db, target_volume, blend)
	_rolling_audio_player.pitch_scale = lerpf(_rolling_audio_player.pitch_scale, target_pitch, blend)
	if not _rolling_audio_player.playing:
		_rolling_audio_player.call_deferred("play")
