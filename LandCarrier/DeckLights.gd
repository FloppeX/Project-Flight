extends Node3D

@export var start_marker_path: NodePath
@export var end_marker_path: NodePath
@export var spacing_m: float = 6.0
@export var centerline_color: Color = Color(0.2, 0.8, 1.0)
@export var edge_color: Color = Color(0.8, 0.8, 0.6)
@export var light_energy: float = 2.0
@export var light_range: float = 6.0
@export var include_edges: bool = true
@export var edge_offset_m: float = 5.0
@export var billboard_size: float = 0.18
@export var use_mesh_markers: bool = true
@export var centerline_height_m: float = -0.05
@export var edge_height_m: float = 0.05
@export var edge_front_trim_m: float = 6.0
@export var split_centerline_at_elevator: bool = true
@export var elevator_path: NodePath
@export var elevator_gap_margin_m: float = 0.0

var _start: Node3D
var _end: Node3D
var _elevator: Node3D

func _ready():
	_start = get_node_or_null(start_marker_path) as Node3D
	_end = get_node_or_null(end_marker_path) as Node3D
	_elevator = get_node_or_null(elevator_path) as Node3D
	set_process_unhandled_input(true)
	if not (_start and _end):
		push_warning("DeckLights: assign start/end markers")
		return
	_build_lights()

func _unhandled_input(event: InputEvent) -> void:
	return
	if event is InputEventKey and event.pressed and not event.echo:
		var key_event: InputEventKey = event as InputEventKey
		if key_event.keycode == KEY_COMMA:
			centerline_height_m -= 0.05
			_build_lights()
			print("[DeckLights] Centerline height offset: %.2fm" % centerline_height_m)
		elif key_event.keycode == KEY_PERIOD:
			centerline_height_m += 0.05
			_build_lights()
			print("[DeckLights] Centerline height offset: %.2fm" % centerline_height_m)

func _build_lights():
	# Clear previous
	for c in get_children():
		if c is Light3D or c is MeshInstance3D:
			c.queue_free()
	var A: Vector3 = _start.global_position
	var B: Vector3 = _end.global_position
	var dir: Vector3 = (B - A)
	var len: float = dir.length()
	if len < 0.1:
		return
	dir /= len
	var right: Vector3 = dir.cross(Vector3.UP).normalized()
	# White edge rows run full deck length.
	if include_edges:
		var edge_end: Vector3 = B - dir * maxf(0.0, edge_front_trim_m)
		_add_lights_along_segment(A + right * edge_offset_m, edge_end + right * edge_offset_m, edge_color, true)
		_add_lights_along_segment(A - right * edge_offset_m, edge_end - right * edge_offset_m, edge_color, true)

	# Green centerline can be split around the elevator opening.
	if split_centerline_at_elevator and is_instance_valid(_elevator):
		var elevator_center: Vector3 = _elevator.global_position
		var center_dist_along: float = (elevator_center - A).dot(dir)
		var half_gap: float = _get_elevator_half_length_along_deck(dir) + maxf(elevator_gap_margin_m, 0.0)
		var seg1_end_dist: float = clampf(center_dist_along - half_gap, 0.0, len)
		var seg2_start_dist: float = clampf(center_dist_along + half_gap, 0.0, len)
		if seg1_end_dist > 0.05:
			_add_lights_along_segment(A, A + dir * seg1_end_dist, centerline_color, false)
		if seg2_start_dist < len - 0.05:
			_add_lights_along_segment(A + dir * seg2_start_dist, B, centerline_color, false)
	else:
		_add_lights_along_segment(A, B, centerline_color, false)

func _add_lights_along_segment(from_pos: Vector3, to_pos: Vector3, col: Color, is_edge: bool) -> void:
	var segment: Vector3 = to_pos - from_pos
	var segment_len: float = segment.length()
	if segment_len < 0.1:
		return
	var seg_dir: Vector3 = segment / segment_len
	var count: int = int(floor(segment_len / max(0.5, spacing_m))) + 1
	for i in range(count):
		var t: float = clamp(float(i) / float(max(1, count - 1)), 0.0, 1.0)
		var p: Vector3 = from_pos + seg_dir * (t * segment_len)
		_add_light(p, col, is_edge)

func _get_elevator_half_length_along_deck(deck_dir: Vector3) -> float:
	if not is_instance_valid(_elevator):
		return 0.0
	var half_len: float = 8.0
	if "platform_size" in _elevator:
		var size_val: Variant = _elevator.get("platform_size")
		if typeof(size_val) == TYPE_VECTOR3:
			var psize: Vector3 = size_val
			var world_z_axis: Vector3 = (_elevator.global_transform.basis * Vector3.FORWARD).normalized()
			var world_x_axis: Vector3 = (_elevator.global_transform.basis * Vector3.RIGHT).normalized()
			var dz: float = absf(deck_dir.dot(world_z_axis))
			var dx: float = absf(deck_dir.dot(world_x_axis))
			half_len = (psize.z * 0.5) * dz + (psize.x * 0.5) * dx
	return maxf(half_len, 0.1)

func _add_light(pos: Vector3, col: Color, is_edge: bool):
	var o := SpotLight3D.new()
	o.light_color = col
	o.light_energy = light_energy
	o.spot_range = light_range
	o.spot_angle = 45.0
	o.shadow_enabled = false
	# Point downward onto the deck surface
	o.rotation_degrees = Vector3(-90, 0, 0)
	add_child(o)
	var y_offset: float = edge_height_m if is_edge else centerline_height_m
	o.global_position = pos + Vector3(0, y_offset + 0.5, 0)
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
