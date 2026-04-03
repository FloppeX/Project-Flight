extends StaticBody3D
class_name CarrierTread

const TRACK_PATH_SCENE_PATH := "res://Models/LandCarrier/track_path_export.glb"
const PATH_RESAMPLE_COUNT := 160
const PATH_CLUSTER_RADIUS_SCALE := 2.5

static var _cached_baked_belt_mesh: Mesh = null
static var _cached_path_info: Dictionary = {}

@export var tread_index: int = 0
@export var carrier_offset: Vector3 = Vector3.ZERO

## Approximate wheel radius in metres - controls wheel rotation speed.
@export var wheel_radius_m: float = 4.0
## Axis the wheel cylinders spin on: 0=X, 1=Y, 2=Z.
@export_range(0, 2) var wheel_spin_axis: int = 0
## How many tread-link groups repeat across the baked loop coordinate.
@export var belt_band_scale: float = 28.0
## UV scroll per metre of signed tread travel.
@export var belt_uv_scale: float = 0.10
## Which local mesh axis the belt travels along: 0=X, 1=Y, 2=Z.
@export_range(0, 2) var belt_axis: int = 2
## Which local mesh axis spans across the visible belt face.
@export_range(0, 2) var belt_cross_axis: int = 0
@export var rolling_sound: AudioStream = preload("res://Rolling_tracks_mono.wav")
@export var rolling_sound_bus: String = "Master"
@export var rolling_sound_min_volume_db: float = -16.0
@export var rolling_sound_max_volume_db: float = -7.0
@export var rolling_sound_pitch_min: float = 0.78
@export var rolling_sound_pitch_max: float = 1.18
@export var rolling_sound_silence_db: float = -80.0
@export var rolling_sound_full_speed_mps: float = 8.0
@export var rolling_sound_unit_size_m: float = 48.0
@export var rolling_sound_max_distance_m: float = 300.0
## 0=final shading, 1=path-coordinate debug, 2=cross-width debug,
## 3=direction arrows, 4=loop contours + seam highlight.
@export_enum("Final:0", "Path UV:1", "Cross UV:2", "Direction:3", "Loop Contours:4") var belt_debug_mode: int = 0
## Freeze belt scroll while inspecting the baked mapping.
@export var belt_debug_freeze_scroll: bool = false

const DEBUG_MODE_NAMES := [
	"Final",
	"Path UV",
	"Cross UV",
	"Direction",
	"Loop Contours",
]

var carrier: Node3D = null
var _belt_shader_mat: ShaderMaterial = null
var _wheel_roots: Array[Node3D] = []
var _uv_accum: float = 0.0
var _scroll_sign: float = 1.0
var _wheel_spin_sign: float = 1.0
var _last_carrier_origin: Vector3
var _last_carrier_forward: Vector3 = Vector3.FORWARD
var _rolling_audio_player: AudioStreamPlayer3D

const _BELT_SHADER := """
shader_type spatial;

uniform sampler2D albedo_tex : source_color, repeat_enable;
uniform float uv_scroll = 0.0;
uniform float band_scale = 28.0;
uniform int debug_mode = 0;

void fragment() {
	float path_uv = UV2.x;
	float cross_uv = clamp(UV2.y, 0.0, 1.0);

	if (debug_mode == 1) {
		float loop_frac = fract(path_uv);
		float seam_mask = 1.0 - smoothstep(0.0, 0.020, min(loop_frac, 1.0 - loop_frac));
		float contour = 1.0 - smoothstep(0.46, 0.50, abs(fract(path_uv * 12.0) - 0.5));
		vec3 base = vec3(loop_frac, 0.25, 1.0 - loop_frac);
		vec3 contour_tint = mix(base, vec3(1.0), contour * 0.55);
		ALBEDO = mix(contour_tint, vec3(1.0, 0.15, 0.1), seam_mask);
	} else if (debug_mode == 2) {
		ALBEDO = vec3(cross_uv, 1.0 - cross_uv, 0.0);
	} else if (debug_mode == 3) {
		// Sawtooth ramp: dark-to-bright shows UV increasing direction.
		// 4 ramps around the loop so the direction is visible on each run.
		float ramp = fract(path_uv * 4.0);
		ALBEDO = vec3(ramp);
	} else if (debug_mode == 4) {
		float loop_frac = fract(path_uv);
		float major_line = 1.0 - smoothstep(0.47, 0.50, abs(fract(path_uv * 8.0) - 0.5));
		float minor_line = 1.0 - smoothstep(0.485, 0.50, abs(fract(path_uv * 32.0) - 0.5));
		float seam_mask = 1.0 - smoothstep(0.0, 0.020, min(loop_frac, 1.0 - loop_frac));
		vec3 base = vec3(0.06, 0.07, 0.08);
		vec3 band = mix(base, vec3(0.15, 0.55, 1.0), major_line);
		band = mix(band, vec3(1.0), minor_line * 0.45);
		ALBEDO = mix(band, vec3(1.0, 0.15, 0.1), seam_mask);
	} else {
		vec3 base = vec3(0.18, 0.19, 0.20);
		float loop_pos = fract(path_uv * band_scale + uv_scroll);
		float dist_to_edge = min(loop_pos, 1.0 - loop_pos);
		float seam_shadow = 1.0 - smoothstep(0.025, 0.075, dist_to_edge);
		float plate_mask = smoothstep(0.035, 0.10, dist_to_edge);
		float grouser = 1.0 - smoothstep(0.11, 0.22, abs(loop_pos - 0.5));
		float inner_rib = 1.0 - smoothstep(0.025, 0.055, abs(loop_pos - 0.5));
		float inner_mask = smoothstep(0.10, 0.24, cross_uv) * (1.0 - smoothstep(0.76, 0.90, cross_uv));
		float edge_shadow = 1.0 - smoothstep(0.0, 0.16, min(cross_uv, 1.0 - cross_uv));
		float highlight = (grouser * 0.65 + inner_rib * 0.35) * inner_mask;
		float cavity = seam_shadow * 1.05 + (1.0 - plate_mask) * inner_mask * 0.25 + edge_shadow * 0.40;
		vec3 tread = base * (0.76 - cavity * 0.28) + vec3(0.12, 0.13, 0.14) * highlight;
		ALBEDO = tread;
	}
	ROUGHNESS = 0.9;
}
"""


func _ready() -> void:
	carrier = get_parent()
	if carrier != null and carrier.name != "LandCarrier":
		carrier = carrier.get_parent() as Node3D

	# Treads are visual only - disable collision to prevent physics fighting
	# with terrain (carrier uses TerrainNavGrid for height, not physics).
	collision_layer = 0
	collision_mask = 0

	setup_tread_offset()
	_last_carrier_origin = carrier.global_position if carrier else global_position
	_last_carrier_forward = _get_carrier_forward()

	var belt_root := get_node_or_null("carrier track tread")
	if belt_root:
		var belt_mesh := _find_mesh_recursive(belt_root)
		if belt_mesh:
			var baked_mesh := _get_or_bake_belt_mesh(belt_mesh)
			if baked_mesh:
				belt_mesh.mesh = baked_mesh
			_build_belt_material(belt_mesh)

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
	_setup_rolling_audio()


func _build_belt_material(belt_mesh: MeshInstance3D) -> void:
	var shader := Shader.new()
	shader.code = _BELT_SHADER
	_belt_shader_mat = ShaderMaterial.new()
	_belt_shader_mat.shader = shader

	var tex := load("res://Models/LandCarrier/carrier_track_texture.png") as Texture2D
	if tex:
		_belt_shader_mat.set_shader_parameter("albedo_tex", tex)

	_apply_shader_params()
	var surface_count := belt_mesh.mesh.get_surface_count() if belt_mesh.mesh else 0
	for surface_idx in range(surface_count):
		belt_mesh.set_surface_override_material(surface_idx, _belt_shader_mat)


func _apply_shader_params() -> void:
	if _belt_shader_mat == null:
		return
	_belt_shader_mat.set_shader_parameter("band_scale", belt_band_scale)
	_belt_shader_mat.set_shader_parameter("debug_mode", belt_debug_mode)
	_belt_shader_mat.set_shader_parameter("uv_scroll", _uv_accum)


func set_belt_debug_mode(mode: int) -> void:
	belt_debug_mode = clampi(mode, 0, DEBUG_MODE_NAMES.size() - 1)
	_apply_shader_params()


func cycle_belt_debug_mode(step: int = 1) -> void:
	var count := DEBUG_MODE_NAMES.size()
	set_belt_debug_mode(posmod(belt_debug_mode + step, count))


func toggle_belt_debug_freeze() -> void:
	belt_debug_freeze_scroll = not belt_debug_freeze_scroll
	print("[CarrierTread] Scroll freeze %s" % ("ON" if belt_debug_freeze_scroll else "OFF"))


func get_belt_debug_mode_name() -> String:
	return DEBUG_MODE_NAMES[clampi(belt_debug_mode, 0, DEBUG_MODE_NAMES.size() - 1)]


func _get_or_bake_belt_mesh(belt_mesh: MeshInstance3D) -> Mesh:
	if _cached_baked_belt_mesh != null:
		return _cached_baked_belt_mesh

	if belt_mesh.mesh == null:
		return null

	var path_info := _get_or_build_path_info(belt_mesh)
	if path_info.is_empty():
		return belt_mesh.mesh

	_cached_baked_belt_mesh = _bake_mesh_path_uvs(belt_mesh, path_info)
	return _cached_baked_belt_mesh


func _get_or_build_path_info(belt_mesh: MeshInstance3D) -> Dictionary:
	if not _cached_path_info.is_empty():
		return _cached_path_info

	var path_scene := load(TRACK_PATH_SCENE_PATH) as PackedScene
	if path_scene == null:
		push_warning("CarrierTread: Missing track path export at %s" % TRACK_PATH_SCENE_PATH)
		return {}

	var path_root := path_scene.instantiate()
	var path_mesh := _find_mesh_recursive(path_root)
	if path_mesh == null or path_mesh.mesh == null:
		path_root.free()
		push_warning("CarrierTread: track_path_export.glb did not contain a mesh path.")
		return {}

	var path_points := _extract_ordered_path_points(path_mesh)
	path_root.free()
	if path_points.size() < 4:
		push_warning("CarrierTread: track path export did not yield enough points.")
		return {}

	var belt_aabb := belt_mesh.get_aabb()
	var mapped_points := _map_path_points_to_belt(path_points, belt_aabb)
	_cached_path_info = _build_path_info(mapped_points)
	return _cached_path_info


func _extract_ordered_path_points(path_mesh: MeshInstance3D) -> PackedVector2Array:
	var mesh := path_mesh.mesh
	var aabb := path_mesh.get_aabb()
	var extents := aabb.size
	var thin_axis := 0
	for axis in range(1, 3):
		if _axis_from_vec3(extents, axis) < _axis_from_vec3(extents, thin_axis):
			thin_axis = axis

	var plane_axes: Array[int] = []
	for axis in range(0, 3):
		if axis != thin_axis:
			plane_axes.append(axis)

	var run_axis := plane_axes[0]
	var scroll_axis := plane_axes[1]
	if _axis_from_vec3(extents, scroll_axis) < _axis_from_vec3(extents, run_axis):
		run_axis = plane_axes[1]
		scroll_axis = plane_axes[0]

	var projected_points: Array[Vector2] = []
	for surface_idx in range(mesh.get_surface_count()):
		var arrays := mesh.surface_get_arrays(surface_idx)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for vert in verts:
			var local_vert := path_mesh.transform * vert
			var point := Vector2(_axis_from_vec3(local_vert, run_axis), _axis_from_vec3(local_vert, scroll_axis))
			projected_points.append(point)

	var cluster_radius := maxf(_axis_from_vec3(extents, thin_axis) * PATH_CLUSTER_RADIUS_SCALE, 0.01)
	var points := _collapse_projected_path_points(projected_points, cluster_radius)
	if points.size() < 4:
		return PackedVector2Array()

	var ordered := _sort_loop_points(points)

	return _resample_closed_path(ordered, PATH_RESAMPLE_COUNT)


func _collapse_projected_path_points(points: Array[Vector2], cluster_radius: float) -> Array[Vector2]:
	var remaining := points.duplicate()
	var collapsed: Array[Vector2] = []
	var radius_sq := cluster_radius * cluster_radius

	while not remaining.is_empty():
		var seed: Vector2 = remaining.pop_back()
		var sum := seed
		var count := 1
		for idx in range(remaining.size() - 1, -1, -1):
			var candidate: Vector2 = remaining[idx]
			if seed.distance_squared_to(candidate) <= radius_sq:
				sum += candidate
				count += 1
				remaining.remove_at(idx)
		collapsed.append(sum / float(count))

	return collapsed


func _sort_loop_points(points: Array[Vector2]) -> Array[Vector2]:
	var centroid := Vector2.ZERO
	for point in points:
		centroid += point
	centroid /= float(points.size())

	var ordered := points.duplicate()
	ordered.sort_custom(func(a: Vector2, b: Vector2) -> bool:
		var angle_a := atan2(a.y - centroid.y, a.x - centroid.x)
		var angle_b := atan2(b.y - centroid.y, b.x - centroid.x)
		if is_equal_approx(angle_a, angle_b):
			return a.distance_squared_to(centroid) < b.distance_squared_to(centroid)
		return angle_a < angle_b
	)
	return ordered


func _resample_closed_path(points: Array[Vector2], target_count: int) -> PackedVector2Array:
	if points.size() < 2:
		return PackedVector2Array()

	var cumulative := PackedFloat32Array()
	cumulative.resize(points.size() + 1)
	cumulative[0] = 0.0
	var total_length := 0.0
	for idx in range(points.size()):
		var next_idx := (idx + 1) % points.size()
		total_length += points[idx].distance_to(points[next_idx])
		cumulative[idx + 1] = total_length

	var resampled := PackedVector2Array()
	resampled.resize(target_count)
	for sample_idx in range(target_count):
		var distance := total_length * float(sample_idx) / float(target_count)
		var seg_idx := 0
		while seg_idx < points.size() and cumulative[seg_idx + 1] < distance:
			seg_idx += 1
		var next_idx := (seg_idx + 1) % points.size()
		var seg_start := cumulative[seg_idx]
		var seg_end := cumulative[seg_idx + 1]
		var seg_len := maxf(seg_end - seg_start, 0.0001)
		var t := clampf((distance - seg_start) / seg_len, 0.0, 1.0)
		resampled[sample_idx] = points[seg_idx].lerp(points[next_idx], t)
	return resampled


func _map_path_points_to_belt(path_points: PackedVector2Array, belt_aabb: AABB) -> PackedVector2Array:
	var run_axis := _get_run_axis()
	var belt_run_center := _axis_from_vec3(belt_aabb.position, run_axis) + _axis_from_vec3(belt_aabb.size, run_axis) * 0.5
	var belt_scroll_center := _axis_from_vec3(belt_aabb.position, belt_axis) + _axis_from_vec3(belt_aabb.size, belt_axis) * 0.5
	var belt_scroll_span := maxf(_axis_from_vec3(belt_aabb.size, belt_axis), 0.001)

	var path_min := path_points[0]
	var path_max := path_points[0]
	for point in path_points:
		path_min.x = minf(path_min.x, point.x)
		path_min.y = minf(path_min.y, point.y)
		path_max.x = maxf(path_max.x, point.x)
		path_max.y = maxf(path_max.y, point.y)

	var path_run_span := maxf(path_max.x - path_min.x, 0.001)
	var path_scroll_span := maxf(path_max.y - path_min.y, 0.001)
	var path_run_center := (path_min.x + path_max.x) * 0.5
	var path_scroll_center := (path_min.y + path_max.y) * 0.5

	# Preserve the helper curve's aspect instead of fitting run/scroll
	# independently to the tread mesh AABB. The exported helper path already
	# matches the tread very closely along the travel axis, and forcing its
	# vertical span down to the belt AABB was flattening the turnarounds.
	var uniform_scale := belt_scroll_span / path_scroll_span

	var mapped := PackedVector2Array()
	mapped.resize(path_points.size())
	for idx in range(path_points.size()):
		var point := path_points[idx]
		mapped[idx] = Vector2(
			belt_run_center + (point.x - path_run_center) * uniform_scale,
			belt_scroll_center + (point.y - path_scroll_center) * uniform_scale
		)
	return mapped


func _build_path_info(path_points: PackedVector2Array) -> Dictionary:
	var peak_idx := 0
	var run_min := INF
	var run_max := -INF
	var scroll_min := INF
	var scroll_max := -INF
	for idx in range(path_points.size()):
		var point := path_points[idx]
		run_min = minf(run_min, point.x)
		run_max = maxf(run_max, point.x)
		scroll_min = minf(scroll_min, point.y)
		scroll_max = maxf(scroll_max, point.y)
		if point.y > path_points[peak_idx].y:
			peak_idx = idx

	var left_points := PackedVector2Array()
	left_points.resize(peak_idx + 1)
	for idx in range(peak_idx + 1):
		left_points[idx] = path_points[idx]

	var right_desc_points := PackedVector2Array()
	right_desc_points.resize(path_points.size() - peak_idx + 1)
	for idx in range(peak_idx, path_points.size()):
		right_desc_points[idx - peak_idx] = path_points[idx]
	right_desc_points[right_desc_points.size() - 1] = path_points[0]

	var left_cumulative := _build_polyline_cumulative(left_points)
	var right_desc_cumulative := _build_polyline_cumulative(right_desc_points)
	var left_total := left_cumulative[left_cumulative.size() - 1] if not left_cumulative.is_empty() else 0.0
	var right_total := right_desc_cumulative[right_desc_cumulative.size() - 1] if not right_desc_cumulative.is_empty() else 0.0

	var right_points := PackedVector2Array()
	right_points.resize(right_desc_points.size())
	for idx in range(right_desc_points.size()):
		right_points[idx] = right_desc_points[right_desc_points.size() - 1 - idx]
	var right_cumulative := _build_polyline_cumulative(right_points)
	var closed_cumulative := _build_closed_path_cumulative(path_points)
	var total_length: float = closed_cumulative[closed_cumulative.size() - 1] if not closed_cumulative.is_empty() else maxf(left_total + right_total, 0.001)
	var seam_distance := _find_top_seam_distance(path_points, closed_cumulative, run_min, run_max, scroll_max)

	return {
		"points": path_points,
		"closed_cumulative": closed_cumulative,
		"left_points": left_points,
		"left_cumulative": left_cumulative,
		"left_total": maxf(left_total, 0.001),
		"right_points": right_points,
		"right_cumulative": right_cumulative,
		"right_total": maxf(right_total, 0.001),
		"total_length": maxf(total_length, 0.001),
		"seam_distance": seam_distance,
		"run_min": run_min,
		"run_max": run_max,
		"scroll_min": scroll_min,
		"scroll_max": scroll_max,
	}


func _bake_mesh_path_uvs(belt_mesh: MeshInstance3D, path_info: Dictionary) -> ArrayMesh:
	var source_mesh := belt_mesh.mesh
	var belt_aabb := belt_mesh.get_aabb()
	var cross_min := _axis_from_vec3(belt_aabb.position, belt_cross_axis)
	var cross_span := maxf(_axis_from_vec3(belt_aabb.size, belt_cross_axis), 0.001)
	var run_axis := _get_run_axis()
	var baked_mesh := ArrayMesh.new()

	for surface_idx in range(source_mesh.get_surface_count()):
		var arrays := source_mesh.surface_get_arrays(surface_idx)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		if verts.is_empty():
			continue

		var uv2 := PackedVector2Array()
		uv2.resize(verts.size())
		for vert_idx in range(verts.size()):
			var node_local_vert := belt_mesh.transform * verts[vert_idx]
			var path_point := Vector2(
				_axis_from_vec3(node_local_vert, run_axis),
				_axis_from_vec3(node_local_vert, belt_axis)
			)
			var loop_distance := _project_point_onto_path(path_point, path_info)
			var cross_uv := (_axis_from_vec3(node_local_vert, belt_cross_axis) - cross_min) / cross_span
			uv2[vert_idx] = Vector2(loop_distance / path_info["total_length"], clampf(cross_uv, 0.0, 1.0))

		arrays[Mesh.ARRAY_TEX_UV2] = uv2
		baked_mesh.add_surface_from_arrays(source_mesh.surface_get_primitive_type(surface_idx), arrays)

	return baked_mesh


func _project_point_onto_path(point: Vector2, path_info: Dictionary) -> float:
	# Project directly to the nearest point on the closed helper loop.
	# The previous angle-from-centroid partitioning was creating a visible
	# handoff around the lower front/rear turnarounds, where small position
	# changes could flip a vertex into a different angular region even though
	# the geometric nearest point stayed on the same tread run.
	var raw_distance := _project_point_onto_closed_path(
		point,
		path_info["points"],
		path_info["closed_cumulative"]
	)
	var total_length: float = float(path_info["total_length"])
	var seam_distance: float = float(path_info["seam_distance"])
	return fposmod(raw_distance - seam_distance, total_length)


func _build_polyline_cumulative(points: PackedVector2Array) -> PackedFloat32Array:
	var cumulative := PackedFloat32Array()
	cumulative.resize(points.size())
	if points.is_empty():
		return cumulative

	cumulative[0] = 0.0
	for idx in range(1, points.size()):
		cumulative[idx] = cumulative[idx - 1] + points[idx - 1].distance_to(points[idx])
	return cumulative


func _build_closed_path_cumulative(points: PackedVector2Array) -> PackedFloat32Array:
	var cumulative := PackedFloat32Array()
	cumulative.resize(points.size() + 1)
	if points.is_empty():
		return cumulative

	cumulative[0] = 0.0
	for idx in range(points.size()):
		var next_idx := (idx + 1) % points.size()
		cumulative[idx + 1] = cumulative[idx] + points[idx].distance_to(points[next_idx])
	return cumulative


func _find_top_seam_distance(points: PackedVector2Array, cumulative: PackedFloat32Array, run_min: float, run_max: float, scroll_max: float) -> float:
	if points.is_empty() or cumulative.is_empty():
		return 0.0

	var run_mid: float = (run_min + run_max) * 0.5
	var best_idx := 0
	var best_score := INF
	for idx in range(points.size()):
		var point := points[idx]
		var top_penalty: float = absf(scroll_max - point.y) * 8.0
		var center_penalty: float = absf(run_mid - point.x)
		var score: float = top_penalty + center_penalty
		if score < best_score:
			best_score = score
			best_idx = idx
	return cumulative[best_idx]


func _project_point_by_angle(point: Vector2, points: PackedVector2Array, cumulative: PackedFloat32Array) -> float:
	# Two-step projection:
	# 1. Use angle-from-centroid to find the approximate region on the path.
	#    This disambiguates the turnarounds where top/bottom runs are close.
	# 2. Do nearest-point-on-segment within a local window around that region.
	#    This gives geometric precision without cross-path jumping.

	var n := points.size()
	if n < 2:
		return 0.0

	# Step 1: find the closest path point by angle.
	var centroid := Vector2.ZERO
	for p in points:
		centroid += p
	centroid /= float(n)

	var query_angle := atan2(point.y - centroid.y, point.x - centroid.x)

	var best_idx := 0
	var best_angle_diff := INF
	for idx in range(n):
		var pa := atan2(points[idx].y - centroid.y, points[idx].x - centroid.x)
		var diff := absf(query_angle - pa)
		if diff > PI:
			diff = TAU - diff
		if diff < best_angle_diff:
			best_angle_diff = diff
			best_idx = idx

	# Step 2: nearest-point projection within a local window (±window_size).
	var window_size := n / 8  # ~20 points = ~1/8 of the loop
	var best_distance_sq := INF
	var best_loop_distance := cumulative[best_idx]
	for offset in range(-window_size, window_size + 1):
		var idx := posmod(best_idx + offset, n)
		var next_idx := (idx + 1) % n
		var a := points[idx]
		var b := points[next_idx]
		var ab := b - a
		var ab_len_sq := maxf(ab.length_squared(), 0.000001)
		var t := clampf((point - a).dot(ab) / ab_len_sq, 0.0, 1.0)
		var projected := a + ab * t
		var distance_sq := point.distance_squared_to(projected)
		if distance_sq < best_distance_sq:
			best_distance_sq = distance_sq
			best_loop_distance = cumulative[idx] + a.distance_to(b) * t

	return best_loop_distance


func _project_point_onto_closed_path(point: Vector2, points: PackedVector2Array, cumulative: PackedFloat32Array) -> float:
	if points.is_empty():
		return 0.0
	if points.size() == 1:
		return 0.0

	var best_distance_sq := INF
	var best_loop_distance := 0.0
	for idx in range(points.size()):
		var next_idx := (idx + 1) % points.size()
		var a := points[idx]
		var b := points[next_idx]
		var ab := b - a
		var ab_len_sq := maxf(ab.length_squared(), 0.000001)
		var t: float = clampf((point - a).dot(ab) / ab_len_sq, 0.0, 1.0)
		var projected := a + ab * t
		var distance_sq := point.distance_squared_to(projected)
		if distance_sq < best_distance_sq:
			best_distance_sq = distance_sq
			var segment_start: float = cumulative[idx]
			var segment_length: float = b.distance_to(a)
			best_loop_distance = segment_start + segment_length * t
	return best_loop_distance


func _sample_polyline_at_scroll(points: PackedVector2Array, cumulative: PackedFloat32Array, scroll: float) -> Dictionary:
	if points.is_empty():
		return {"run": 0.0, "distance": 0.0}
	if points.size() == 1:
		return {"run": points[0].x, "distance": 0.0}
	if scroll <= points[0].y:
		return {"run": points[0].x, "distance": cumulative[0]}
	if scroll >= points[points.size() - 1].y:
		return {"run": points[points.size() - 1].x, "distance": cumulative[cumulative.size() - 1]}

	for idx in range(points.size() - 1):
		var a := points[idx]
		var b := points[idx + 1]
		if scroll > b.y:
			continue
		var dy := b.y - a.y
		var t := 0.0 if absf(dy) < 0.00001 else clampf((scroll - a.y) / dy, 0.0, 1.0)
		return {
			"run": lerpf(a.x, b.x, t),
			"distance": lerpf(cumulative[idx], cumulative[idx + 1], t),
		}

	return {
		"run": points[points.size() - 1].x,
		"distance": cumulative[cumulative.size() - 1],
	}




func _find_mesh_recursive(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node as MeshInstance3D
	for child in node.get_children():
		var result := _find_mesh_recursive(child)
		if result:
			return result
	return null


func _axis_from_vec3(value: Vector3, axis: int) -> float:
	match axis:
		0:
			return value.x
		1:
			return value.y
		_:
			return value.z


func _get_run_axis() -> int:
	for axis in range(0, 3):
		if axis != belt_cross_axis and axis != belt_axis:
			return axis
	return 1


func setup_tread_offset() -> void:
	var tread_positions := [
		Vector3(-32, -32, -43),
		Vector3(32, -32, -43),
		Vector3(-32, -32, 0),
		Vector3(32, -32, 0),
		Vector3(32, -32, 43),
		Vector3(-32, -32, 43),
	]
	if tread_index < tread_positions.size():
		carrier_offset = tread_positions[tread_index]

	# Right tracks are mirrored in the scene, so their UV travel direction is flipped.
	_scroll_sign = -1.0 if carrier_offset.x > 0.0 else 1.0
	# Left wheel meshes currently read backward unless their spin is flipped.
	_wheel_spin_sign = -1.0 if carrier_offset.x < 0.0 else 1.0


func _physics_process(delta: float) -> void:
	_apply_shader_params()

	var signed_travel := _compute_signed_travel()
	var tread_speed_mps: float = 0.0
	if delta > 0.0 and absf(signed_travel) <= 20.0:
		tread_speed_mps = absf(signed_travel) / delta
	_update_rolling_audio(delta, tread_speed_mps)
	if absf(signed_travel) < 0.0001 or absf(signed_travel) > 20.0:
		return

	if _belt_shader_mat and not belt_debug_freeze_scroll:
		_uv_accum -= signed_travel * belt_uv_scale * _scroll_sign
		_belt_shader_mat.set_shader_parameter("uv_scroll", _uv_accum)

	var angle := signed_travel / maxf(wheel_radius_m, 0.001) * _wheel_spin_sign
	for wheel in _wheel_roots:
		match wheel_spin_axis:
			0:
				wheel.rotate_x(angle)
			1:
				wheel.rotate_y(angle)
			2:
				wheel.rotate_z(angle)


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


func update_position() -> void:
	if carrier:
		var tread_position := carrier.global_position + carrier_offset
		tread_position.y = carrier.global_position.y - 32.0
		global_position = tread_position

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
