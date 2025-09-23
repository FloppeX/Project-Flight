extends Node3D

@export var start_marker_path: NodePath
@export var end_marker_path: NodePath
@export var spacing_m: float = 6.0
@export var centerline_color: Color = Color(0.2, 0.8, 1.0)
@export var edge_color: Color = Color(0.8, 0.8, 0.6)
@export var light_energy: float = 2.0
@export var light_range: float = 18.0
@export var include_edges: bool = true
@export var edge_offset_m: float = 5.0
@export var billboard_size: float = 0.18
@export var use_mesh_markers: bool = true

var _start: Node3D
var _end: Node3D

func _ready():
	_start = get_node_or_null(start_marker_path) as Node3D
	_end = get_node_or_null(end_marker_path) as Node3D
	if not (_start and _end):
		push_warning("DeckLights: assign start/end markers")
		return
	_build_lights()

func _build_lights():
	# Clear previous
	for c in get_children():
		if c is OmniLight3D or c is MeshInstance3D:
			c.queue_free()
	var A: Vector3 = _start.global_position
	var B: Vector3 = _end.global_position
	var dir: Vector3 = (B - A)
	var len: float = dir.length()
	if len < 0.1:
		return
	dir /= len
	var right: Vector3 = dir.cross(Vector3.UP).normalized()
	var count: int = int(floor(len / max(0.5, spacing_m))) + 1
	for i in range(count):
		var t: float = clamp(float(i) / float(max(1, count - 1)), 0.0, 1.0)
		var p: Vector3 = A + dir * (t * len)
		_add_light(p, centerline_color)
		if include_edges:
			_add_light(p + right * edge_offset_m, edge_color)
			_add_light(p - right * edge_offset_m, edge_color)

func _add_light(pos: Vector3, col: Color):
	var o := OmniLight3D.new()
	o.light_color = col
	o.light_energy = light_energy
	o.omni_range = light_range
	o.shadow_enabled = false
	add_child(o)
	o.global_position = pos + Vector3(0, 0.2, 0)
	if use_mesh_markers:
		var mi := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(billboard_size, billboard_size)
		mi.mesh = quad
		var mat := StandardMaterial3D.new()
		mat.unshaded = true
		mat.vertex_color_use_as_albedo = true
		mat.albedo_color = col
		mat.emission_enabled = true
		mat.emission = col * 4.0
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		mi.material_override = mat
		add_child(mi)
		mi.global_position = o.global_position
