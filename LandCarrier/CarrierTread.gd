extends StaticBody3D
class_name CarrierTread

@export var tread_index: int = 0
@export var carrier_offset: Vector3 = Vector3.ZERO

## Approximate wheel radius in metres - controls wheel rotation speed.
@export var wheel_radius_m: float = 4.0
## Axis the wheel cylinders spin on: 0=X, 1=Y, 2=Z.
@export_range(0, 2) var wheel_spin_axis: int = 0
## How many tread-link groups repeat across the belt unwrap.
@export var belt_band_scale: float = 28.0
## UV scroll per metre of signed tread travel.
@export var belt_uv_scale: float = 0.015
## Which local mesh axis the belt travels along: 0=X, 1=Y, 2=Z.
@export_range(0, 2) var belt_axis: int = 2
## Which local mesh axis spans across the visible belt face.
@export_range(0, 2) var belt_cross_axis: int = 0
## Where the upper/lower run split happens along the derived vertical axis.
@export_range(0.0, 1.0, 0.01) var belt_run_split_center: float = 0.5
## How soft the transition is between the two runs.
@export_range(0.0, 0.25, 0.005) var belt_run_split_softness: float = 0.02
## 0=final shading, 1=RGB axes debug, 2=run-split gradient debug.
@export_enum("Final:0", "Axes RGB:1", "Run Split:2") var belt_debug_mode: int = 0
## Freeze belt scroll while tuning the split in debug mode.
@export var belt_debug_freeze_scroll: bool = false
## Hold PageUp/PageDown or ]/[ to move the run split while debugging.
@export var belt_debug_adjust_speed: float = 0.35

var carrier: Node3D = null
var _belt_shader_mat: ShaderMaterial = null
var _wheel_roots: Array[Node3D] = []
var _uv_accum: float = 0.0
var _scroll_sign: float = 1.0
var _last_carrier_origin: Vector3
var _last_carrier_forward: Vector3 = Vector3.FORWARD

const _BELT_SHADER := """
shader_type spatial;

uniform sampler2D albedo_tex : source_color, repeat_enable;
uniform float uv_scroll = 0.0;
uniform float band_scale = 28.0;
uniform int scroll_axis = 2;
uniform int cross_axis = 0;
uniform vec3 mesh_origin = vec3(0.0);
uniform vec3 mesh_size = vec3(1.0);
uniform vec3 run_split_dir = vec3(0.0, 1.0, 0.0);
uniform float run_split_min = 0.0;
uniform float run_split_span = 1.0;
uniform float run_split_center = 0.5;
uniform float run_split_softness = 0.02;
uniform int debug_mode = 0;

varying vec3 local_pos;

float select_axis(vec3 p, int axis) {
	return axis == 0 ? p.x : (axis == 1 ? p.y : p.z);
}

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	float scroll_size = max(select_axis(mesh_size, scroll_axis), 0.001);
	float cross_size = max(select_axis(mesh_size, cross_axis), 0.001);
	float scroll_uv = (select_axis(local_pos, scroll_axis) - select_axis(mesh_origin, scroll_axis)) / scroll_size;
	float cross_uv = (select_axis(local_pos, cross_axis) - select_axis(mesh_origin, cross_axis)) / cross_size;
	float run_split_uv = (dot(local_pos, run_split_dir) - run_split_min) / max(run_split_span, 0.001);
	cross_uv = clamp(cross_uv, 0.0, 1.0);
	run_split_uv = clamp(run_split_uv, 0.0, 1.0);

	float split_lo = max(run_split_center - run_split_softness, 0.0);
	float split_hi = min(run_split_center + run_split_softness, 1.0);
	float run_blend = smoothstep(split_lo, split_hi, run_split_uv);

	if (debug_mode == 1) {
		ALBEDO = vec3(fract(scroll_uv), fract(cross_uv), fract(run_split_uv));
	} else if (debug_mode == 2) {
		vec3 gradient = mix(vec3(0.10, 0.25, 0.95), vec3(0.95, 0.20, 0.10), run_split_uv);
		float center_line = 1.0 - smoothstep(0.0, 0.015, abs(run_split_uv - run_split_center));
		float band_lo = 1.0 - smoothstep(0.0, 0.01, abs(run_split_uv - split_lo));
		float band_hi = 1.0 - smoothstep(0.0, 0.01, abs(run_split_uv - split_hi));
		ALBEDO = mix(gradient, vec3(1.0), max(center_line, max(band_lo, band_hi)));
	} else {
		vec3 base = texture(albedo_tex, UV).rgb;
		float path_uv = mix(1.0 - scroll_uv, scroll_uv, run_blend);
		float loop_pos = fract((path_uv + uv_scroll) * band_scale);
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
			var shader := Shader.new()
			shader.code = _BELT_SHADER
			_belt_shader_mat = ShaderMaterial.new()
			_belt_shader_mat.shader = shader
			var tex := load("res://Models/LandCarrier/carrier_track_texture.png") as Texture2D
			if tex:
				_belt_shader_mat.set_shader_parameter("albedo_tex", tex)
			var belt_aabb := belt_mesh.get_aabb()
			var run_split := _compute_run_split_data(belt_mesh, belt_aabb)
			_apply_shader_params(belt_aabb, run_split)
			for i in belt_mesh.get_surface_override_material_count():
				belt_mesh.set_surface_override_material(i, _belt_shader_mat)

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


func _find_mesh_recursive(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node as MeshInstance3D
	for child in node.get_children():
		var result := _find_mesh_recursive(child)
		if result:
			return result
	return null


func _compute_run_split_data(belt_mesh: MeshInstance3D, belt_aabb: AABB) -> Dictionary:
	var local_up := (belt_mesh.global_transform.basis.inverse() * Vector3.UP).normalized()
	if local_up.length_squared() < 0.0001:
		local_up = Vector3.UP

	var min_proj := INF
	var max_proj := -INF
	for corner in _get_aabb_corners(belt_aabb):
		var proj := corner.dot(local_up)
		min_proj = minf(min_proj, proj)
		max_proj = maxf(max_proj, proj)

	return {
		"direction": local_up,
		"min_proj": min_proj,
		"span": maxf(max_proj - min_proj, 0.001),
	}


func _apply_shader_params(belt_aabb: AABB, run_split: Dictionary) -> void:
	if _belt_shader_mat == null:
		return
	_belt_shader_mat.set_shader_parameter("band_scale", belt_band_scale)
	_belt_shader_mat.set_shader_parameter("scroll_axis", belt_axis)
	_belt_shader_mat.set_shader_parameter("cross_axis", belt_cross_axis)
	_belt_shader_mat.set_shader_parameter("mesh_origin", belt_aabb.position)
	_belt_shader_mat.set_shader_parameter("mesh_size", belt_aabb.size)
	_belt_shader_mat.set_shader_parameter("run_split_dir", run_split.direction)
	_belt_shader_mat.set_shader_parameter("run_split_min", run_split.min_proj)
	_belt_shader_mat.set_shader_parameter("run_split_span", run_split.span)
	_belt_shader_mat.set_shader_parameter("run_split_center", belt_run_split_center)
	_belt_shader_mat.set_shader_parameter("run_split_softness", belt_run_split_softness)
	_belt_shader_mat.set_shader_parameter("debug_mode", belt_debug_mode)


func _get_aabb_corners(aabb: AABB) -> Array[Vector3]:
	var p := aabb.position
	var s := aabb.size
	return [
		p,
		p + Vector3(s.x, 0.0, 0.0),
		p + Vector3(0.0, s.y, 0.0),
		p + Vector3(0.0, 0.0, s.z),
		p + Vector3(s.x, s.y, 0.0),
		p + Vector3(s.x, 0.0, s.z),
		p + Vector3(0.0, s.y, s.z),
		p + s,
	]


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


func _physics_process(delta: float) -> void:
	if _should_drive_debug_controls():
		_drive_debug_controls(delta)

	if _belt_shader_mat:
		var belt_root := get_node_or_null("carrier track tread")
		if belt_root:
			var belt_mesh := _find_mesh_recursive(belt_root)
			if belt_mesh:
				var belt_aabb := belt_mesh.get_aabb()
				var run_split := _compute_run_split_data(belt_mesh, belt_aabb)
				_apply_shader_params(belt_aabb, run_split)

	var signed_travel := _compute_signed_travel()
	if absf(signed_travel) < 0.0001 or absf(signed_travel) > 20.0:
		return

	if _belt_shader_mat and not belt_debug_freeze_scroll:
		_uv_accum -= signed_travel * belt_uv_scale * _scroll_sign
		_belt_shader_mat.set_shader_parameter("uv_scroll", _uv_accum)

	var angle := signed_travel / maxf(wheel_radius_m, 0.001)
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


func _should_drive_debug_controls() -> bool:
	if carrier == null:
		return false
	if belt_debug_mode != 2:
		return false
	return tread_index == 0


func _drive_debug_controls(delta: float) -> void:
	var input_dir := 0.0
	if Input.is_physical_key_pressed(KEY_PAGEUP) or Input.is_physical_key_pressed(KEY_BRACKETRIGHT):
		input_dir += 1.0
	if Input.is_physical_key_pressed(KEY_PAGEDOWN) or Input.is_physical_key_pressed(KEY_BRACKETLEFT):
		input_dir -= 1.0
	if absf(input_dir) < 0.001:
		return

	var next_center := clampf(
		belt_run_split_center + input_dir * belt_debug_adjust_speed * delta,
		0.0,
		1.0
	)
	if is_equal_approx(next_center, belt_run_split_center):
		return

	for child in carrier.get_children():
		if child is CarrierTread:
			(child as CarrierTread).belt_run_split_center = next_center
	if OS.is_debug_build():
		print("[CarrierTread] belt_run_split_center=", snappedf(next_center, 0.001))
