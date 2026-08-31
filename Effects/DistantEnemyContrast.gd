extends RefCounted

## Applies a restrained, neutral overlay to distant enemy geometry. The cue
## never changes geometry or depth testing: it darkens targets likely seen
## against sky and slightly lifts targets likely seen against terrain.

const PLAYER_TEAM_ID: int = 1
const ENEMY_TEAM_ID: int = 2
const EXCLUDED_BRANCH_NAMES: Array[StringName] = [
	&"CameraController",
	&"AudioManager3D",
	&"CameraCockpit",
	&"CameraTarget",
	&"CameraChase",
	&"CameraCinematic",
	&"HeadsUpDisplay",
	&"InstrumentPanel",
]
const OVERLAY_SHADER_CODE: String = """
shader_type spatial;
render_mode blend_mix, unshaded, depth_draw_never, cull_back, shadows_disabled;

uniform vec3 contrast_color : source_color = vec3(0.04, 0.045, 0.05);
uniform float contrast_strength : hint_range(0.0, 0.3) = 0.0;

void fragment() {
	ALBEDO = contrast_color;
	ALPHA = contrast_strength;
}
"""

var contrast_start_distance_m: float = 1800.0
var contrast_full_distance_m: float = 5200.0
var max_contrast_strength: float = 0.18
var sky_contrast_color: Color = Color(0.025, 0.03, 0.035, 1.0)
var terrain_contrast_color: Color = Color(0.78, 0.80, 0.76, 1.0)
var terrain_angle_deg: float = -5.0
var sky_angle_deg: float = 1.0

static var _shared_shader: Shader = null

var _target_ref: WeakRef = null
var _overlay_material: ShaderMaterial = null
var _eligible_geometry_refs: Array[WeakRef] = []
var _geometry_collected: bool = false
var _enabled: bool = true
var _overlay_active: bool = false


func _init(target: Node3D = null) -> void:
	bind_target(target)


func bind_target(target: Node3D) -> void:
	_set_overlay_active(false)
	_target_ref = weakref(target) if target != null and is_instance_valid(target) else null
	_eligible_geometry_refs.clear()
	_geometry_collected = false
	if target != null and is_instance_valid(target):
		_collect_eligible_geometry(target, target)
		_geometry_collected = true


func set_enabled(value: bool) -> void:
	_enabled = value
	if not _enabled:
		_set_overlay_active(false)


func configure(
		start_distance_m: float,
		full_distance_m: float,
		strength: float,
		sky_color: Color,
		terrain_color: Color,
		terrain_threshold_deg: float,
		sky_threshold_deg: float) -> void:
	contrast_start_distance_m = start_distance_m
	contrast_full_distance_m = full_distance_m
	max_contrast_strength = strength
	sky_contrast_color = sky_color
	terrain_contrast_color = terrain_color
	terrain_angle_deg = terrain_threshold_deg
	sky_angle_deg = sky_threshold_deg


func refresh_for_camera(camera: Camera3D) -> void:
	var target := _get_target()
	if not _enabled or target == null or not _is_enemy(target) or camera == null or not is_instance_valid(camera):
		_set_overlay_active(false)
		return

	var distance_m := camera.global_position.distance_to(target.global_position)
	var distance_fade := _distance_fade(
		distance_m,
		contrast_start_distance_m,
		contrast_full_distance_m
	)
	if distance_fade <= 0.001 or max_contrast_strength <= 0.001:
		_set_overlay_active(false)
		return

	if not _geometry_collected:
		_collect_eligible_geometry(target, target)
		_geometry_collected = true
	if _eligible_geometry_refs.is_empty():
		return
	_ensure_overlay_material()

	var to_target := target.global_position - camera.global_position
	var elevation_sine := 0.0
	if to_target.length_squared() > 0.000001:
		elevation_sine = to_target.normalized().y
	var color := _contrast_color_for_elevation_sine(elevation_sine)
	_overlay_material.set_shader_parameter("contrast_color", Vector3(color.r, color.g, color.b))
	_overlay_material.set_shader_parameter(
		"contrast_strength",
		clampf(max_contrast_strength * distance_fade, 0.0, 0.3)
	)
	_set_overlay_active(true)


func dispose() -> void:
	_set_overlay_active(false)
	_eligible_geometry_refs.clear()
	_geometry_collected = false
	_target_ref = null


func is_active() -> bool:
	return _overlay_active


func get_eligible_geometry_count() -> int:
	var count := 0
	for ref in _eligible_geometry_refs:
		var geometry: Object = ref.get_ref() if ref != null else null
		if geometry != null and is_instance_valid(geometry):
			count += 1
	return count


func _get_target() -> Node3D:
	if _target_ref == null:
		return null
	var target := _target_ref.get_ref() as Node3D
	return target if target != null and is_instance_valid(target) else null


func _is_enemy(target: Node3D) -> bool:
	var team_id := _resolve_team_id(target)
	if team_id == PLAYER_TEAM_ID:
		return false
	return target.is_in_group("enemies") or team_id == ENEMY_TEAM_ID


func _resolve_team_id(target: Node3D) -> int:
	if target.has_method("get_team"):
		return int(target.call("get_team"))
	var team_value: Variant = target.get("team")
	if typeof(team_value) in [TYPE_INT, TYPE_FLOAT]:
		return int(team_value)
	return 0


func _ensure_overlay_material() -> void:
	if _overlay_material != null:
		return
	if _shared_shader == null:
		_shared_shader = Shader.new()
		_shared_shader.code = OVERLAY_SHADER_CODE
	_overlay_material = ShaderMaterial.new()
	_overlay_material.resource_name = "Distant Enemy Contrast"
	_overlay_material.shader = _shared_shader


func _collect_eligible_geometry(node: Node, target: Node3D) -> void:
	if node != target and node.name in EXCLUDED_BRANCH_NAMES:
		return
	if node is MeshInstance3D or node is MultiMeshInstance3D:
		var geometry := node as GeometryInstance3D
		if geometry.material_overlay == null or geometry.material_overlay == _overlay_material:
			_eligible_geometry_refs.append(weakref(geometry))
	for child: Node in node.get_children():
		_collect_eligible_geometry(child, target)


func _set_overlay_active(active: bool) -> void:
	_overlay_active = active and _overlay_material != null
	for ref in _eligible_geometry_refs:
		var geometry := ref.get_ref() as GeometryInstance3D if ref != null else null
		if geometry == null or not is_instance_valid(geometry):
			continue
		if _overlay_active:
			if geometry.material_overlay == null:
				geometry.material_overlay = _overlay_material
		elif geometry.material_overlay == _overlay_material:
			geometry.material_overlay = null


func _contrast_color_for_elevation_sine(elevation_sine: float) -> Color:
	var terrain_threshold := sin(deg_to_rad(terrain_angle_deg))
	var sky_threshold := sin(deg_to_rad(sky_angle_deg))
	var sky_likelihood := smoothstep(
		minf(terrain_threshold, sky_threshold),
		maxf(terrain_threshold, sky_threshold),
		elevation_sine
	)
	return terrain_contrast_color.lerp(sky_contrast_color, sky_likelihood)


static func _distance_fade(distance_m: float, start_distance_m: float, full_distance_m: float) -> float:
	var start_m := maxf(start_distance_m, 0.0)
	var full_m := maxf(full_distance_m, start_m + 1.0)
	return smoothstep(start_m, full_m, distance_m)
