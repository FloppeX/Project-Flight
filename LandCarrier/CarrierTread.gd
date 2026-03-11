extends StaticBody3D
class_name CarrierTread

@export var tread_index: int = 0
@export var carrier_offset: Vector3 = Vector3.ZERO

## Approximate wheel radius in metres – controls wheel rotation speed
@export var wheel_radius_m: float = 4.0
## Axis the wheel cylinders spin on: 0=X, 1=Y, 2=Z
@export_range(0, 2) var wheel_spin_axis: int = 0
## How many texture repeats per metre of track length. 0.5 = 1 repeat per 2m.
@export var belt_band_scale: float = 0.5
## Scroll speed multiplier. Tune until motion looks right.
@export var belt_uv_scale: float = 0.03
## Which local axis runs along the track surface: 0=X, 1=Y, 2=Z
@export_range(0, 2) var belt_axis: int = 2
## Show RGB axis gradient to find the right axis (R=X G=Y B=Z)
@export var belt_debug_axes: bool = false

var carrier: Node3D = null
var _belt_shader_mat: ShaderMaterial = null
var _wheel_roots: Array[Node3D] = []
var _uv_accum: float = 0.0
var _scroll_sign: float = 1.0   # -1 for left tracks (180° Y rotation flips local Z)
var _last_pos: Vector3
var _debug_moved := false

const _BELT_SHADER := """
shader_type spatial;

uniform sampler2D albedo_tex : source_color, repeat_enable;
uniform float uv_scroll = 0.0;
uniform float band_scale = 0.5;
// 0 = normal  1 = debug UV.x (red bands)  2 = debug UV.y (green bands)
uniform int debug_mode = 0;

void fragment() {
	if (debug_mode == 1) {
		ALBEDO = vec3(fract(UV.x * band_scale), 0.0, 0.0);
	} else if (debug_mode == 2) {
		ALBEDO = vec3(0.0, fract(UV.y * band_scale), 0.0);
	} else {
		vec2 uv = vec2(UV.x, UV.y * band_scale + uv_scroll);
		ALBEDO = texture(albedo_tex, uv).rgb;
	}
	ROUGHNESS = 0.9;
}
"""


func _ready():
	carrier = get_parent()
	if carrier.name != "LandCarrier":
		carrier = carrier.get_parent()

	setup_tread_offset()
	_last_pos = global_position

	# Belt — shader that maps bands along local Z (track length), ignoring UVs
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
			_belt_shader_mat.set_shader_parameter("band_scale", belt_band_scale)
			_belt_shader_mat.set_shader_parameter("debug_mode", 0)
			# Apply to every surface slot — the mesh likely has separate materials per face type
			for i in belt_mesh.get_surface_override_material_count():
				belt_mesh.set_surface_override_material(i, _belt_shader_mat)
			print("[CarrierTread] belt surfaces: ", belt_mesh.get_surface_override_material_count())

	# Wheels
	var wheel_names := ["carrier track wheel", "carrier track wheel2",
		"carrier track wheel3", "carrier track wheel4", "carrier track wheel5"]
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


func setup_tread_offset():
	var tread_positions := [
		Vector3(-32, -32, -43),
		Vector3(32,  -32, -43),
		Vector3(-32, -32,  0),
		Vector3(32,  -32,  0),
		Vector3(32,  -32,  43),
		Vector3(-32, -32,  43),
	]
	if tread_index < tread_positions.size():
		carrier_offset = tread_positions[tread_index]
	# Right tracks (x > 0) are rotated 180° on Y in the scene, flipping local Z → invert scroll
	_scroll_sign = -1.0 if carrier_offset.x > 0.0 else 1.0


func _process(_delta: float) -> void:
	var moved: float = global_position.distance_to(_last_pos)
	_last_pos = global_position
	if moved < 0.0001 or moved > 50.0:
		return

	if not _debug_moved and tread_index == 0:
		print("[CarrierTread] moving: ", snappedf(moved, 0.001), "m/frame")
		_debug_moved = true

	# Scroll belt — negate for correct forward direction, invert for left tracks
	if _belt_shader_mat:
		_uv_accum -= moved * belt_uv_scale * _scroll_sign
		_belt_shader_mat.set_shader_parameter("uv_scroll", _uv_accum)

	# Rotate wheels
	var angle: float = moved / wheel_radius_m
	for wheel in _wheel_roots:
		match wheel_spin_axis:
			0: wheel.rotate_x(angle)
			1: wheel.rotate_y(angle)
			2: wheel.rotate_z(angle)


func update_position():
	if carrier:
		var tread_position := carrier.global_position + carrier_offset
		tread_position.y = carrier.global_position.y - 32.0
		global_position = tread_position
