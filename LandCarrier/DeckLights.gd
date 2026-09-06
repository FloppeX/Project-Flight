extends Node3D

@export var start_marker_path: NodePath
@export var end_marker_path: NodePath
@export var spacing_m: float = 6.0
@export var centerline_color: Color = Color(0.2, 0.8, 1.0)
@export var edge_color: Color = Color(0.8, 0.8, 0.6)
@export var light_energy: float = 2.0
@export var light_range: float = 12.0
@export_range(1, 8, 1) var surface_light_stride: int = 3
@export_range(0.5, 12.0, 0.25) var surface_light_height_m: float = 5.0
@export_range(1.0, 89.0, 1.0) var surface_light_angle_deg: float = 65.0
@export var follow_day_night_cycle: bool = true
@export_range(0.0, 12.0, 0.25) var marker_emission_energy: float = 4.0
@export var include_edges: bool = true
@export var edge_offset_m: float = 5.0
@export var billboard_size: float = 0.18
@export var use_mesh_markers: bool = true
@export var centerline_height_m: float = -0.05
@export var edge_height_m: float = 0.05
@export var edge_front_trim_m: float = 6.0
@export var centerline_front_trim_m: float = 6.0
@export var split_centerline_at_elevator: bool = true
@export var elevator_path: NodePath
@export var elevator_gap_margin_m: float = 0.0
@export var debug_height_step_m: float = 0.01

var debug_height_offset_m: float = 0.0

var _start: Node3D
var _end: Node3D
var _elevator: Node3D
var _deck_up: Vector3 = Vector3.UP
var _height_readout_layer: CanvasLayer
var _height_readout_label: Label
var _height_readout_hide_at_ms: int = 0
var _surface_lights: Array[SpotLight3D] = []
var _day_night_cycle: Node
var _lighting_update_accum_s: float = 0.0

const HEIGHT_READOUT_DURATION_MS := 4000
const LIGHTING_UPDATE_INTERVAL_S := 0.25

func _ready():
	_start = get_node_or_null(start_marker_path) as Node3D
	_end = get_node_or_null(end_marker_path) as Node3D
	_elevator = get_node_or_null(elevator_path) as Node3D
	set_process_unhandled_input(true)
	set_process(true)
	if not (_start and _end):
		push_warning("DeckLights: assign start/end markers")
		return
	_build_lights()
	_update_surface_light_state()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key_event: InputEventKey = event as InputEventKey
		if key_event.keycode == KEY_PAGEDOWN:
			_adjust_debug_height(-debug_height_step_m)
		elif key_event.keycode == KEY_PAGEUP:
			_adjust_debug_height(debug_height_step_m)


func _process(_delta: float) -> void:
	if is_instance_valid(_height_readout_label) \
	and Time.get_ticks_msec() >= _height_readout_hide_at_ms:
		_height_readout_label.visible = false
	_lighting_update_accum_s += _delta
	if _lighting_update_accum_s >= LIGHTING_UPDATE_INTERVAL_S:
		_lighting_update_accum_s = 0.0
		_update_surface_light_state()


func _adjust_debug_height(delta_m: float) -> void:
	debug_height_offset_m = snappedf(debug_height_offset_m + delta_m, 0.001)
	_build_lights()
	_show_height_readout()
	print("[DeckLights] Height offset: %+.3fm" % debug_height_offset_m)


func _show_height_readout() -> void:
	_ensure_height_readout()
	if not is_instance_valid(_height_readout_label):
		return
	_height_readout_label.text = "DECK LIGHT HEIGHT OFFSET  %+.3f m\nPGDN LOWER   •   PGUP RAISE" % debug_height_offset_m
	_height_readout_label.visible = true
	_height_readout_hide_at_ms = Time.get_ticks_msec() + HEIGHT_READOUT_DURATION_MS


func _ensure_height_readout() -> void:
	if is_instance_valid(_height_readout_label):
		return
	_height_readout_layer = CanvasLayer.new()
	_height_readout_layer.layer = 120
	_height_readout_layer.name = "DeckLightHeightDebugOverlay"
	add_child(_height_readout_layer)
	_height_readout_label = Label.new()
	_height_readout_label.name = "Readout"
	_height_readout_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_height_readout_label.offset_left = -260.0
	_height_readout_label.offset_top = 24.0
	_height_readout_label.offset_right = 260.0
	_height_readout_label.offset_bottom = 88.0
	_height_readout_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_height_readout_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_height_readout_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_height_readout_label.add_theme_font_size_override("font_size", 20)
	_height_readout_label.add_theme_color_override("font_color", Color(0.75, 1.0, 0.82, 1.0))
	_height_readout_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.95))
	_height_readout_label.add_theme_constant_override("outline_size", 6)
	_height_readout_layer.add_child(_height_readout_label)

func _build_lights():
	# Clear previous
	_surface_lights.clear()
	for c in get_children():
		if c is Light3D or c is MeshInstance3D:
			c.queue_free()
	var A: Vector3 = _start.global_position
	var B: Vector3 = _end.global_position
	_deck_up = global_transform.basis.y.normalized()
	if _deck_up.is_zero_approx():
		_deck_up = Vector3.UP
	var dir: Vector3 = (B - A)
	var len: float = dir.length()
	if len < 0.1:
		return
	dir /= len
	var right: Vector3 = dir.cross(_deck_up).normalized()
	# White edge rows run full deck length.
	if include_edges:
		var edge_end: Vector3 = B - dir * maxf(0.0, edge_front_trim_m)
		_add_lights_along_segment(A + right * edge_offset_m, edge_end + right * edge_offset_m, edge_color, true)
		_add_lights_along_segment(A - right * edge_offset_m, edge_end - right * edge_offset_m, edge_color, true)

	# Keep the final spotlight back from the beveled bow, where its downward cone
	# otherwise catches the front face and reads as a large colored glow.
	var center_end_dist := maxf(len - maxf(0.0, centerline_front_trim_m), 0.0)
	var center_end := A + dir * center_end_dist
	# The centerline can also be split around the elevator opening.
	if split_centerline_at_elevator and is_instance_valid(_elevator):
		var elevator_center: Vector3 = _elevator.global_position
		var center_dist_along: float = (elevator_center - A).dot(dir)
		var half_gap: float = _get_elevator_half_length_along_deck(dir) + maxf(elevator_gap_margin_m, 0.0)
		var seg1_end_dist: float = clampf(center_dist_along - half_gap, 0.0, center_end_dist)
		var seg2_start_dist: float = clampf(center_dist_along + half_gap, 0.0, center_end_dist)
		if seg1_end_dist > 0.05:
			_add_lights_along_segment(A, A + dir * seg1_end_dist, centerline_color, false)
		if seg2_start_dist < center_end_dist - 0.05:
			_add_lights_along_segment(A + dir * seg2_start_dist, center_end, centerline_color, false)
	else:
		_add_lights_along_segment(A, center_end, centerline_color, false)

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
		var casts_surface_light := i % maxi(surface_light_stride, 1) == 0 or i == count - 1
		_add_light(p, col, is_edge, casts_surface_light)

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

func _add_light(pos: Vector3, col: Color, is_edge: bool, casts_surface_light: bool):
	var y_offset: float = edge_height_m if is_edge else centerline_height_m
	var marker_position := pos + _deck_up * (y_offset + debug_height_offset_m + 0.5)
	# Every embedded fixture stays visibly emissive, while only a spaced subset
	# creates a broad, non-shadowed deck wash. This avoids the old all-or-nothing
	# choice between marker-only lights and roughly seventy overlapping spots.
	if casts_surface_light and light_energy > 0.001:
		var spot := SpotLight3D.new()
		spot.name = "DeckSurfaceLight"
		spot.light_color = col
		spot.light_energy = light_energy
		spot.spot_range = light_range
		spot.spot_angle = surface_light_angle_deg
		spot.shadow_enabled = false
		# Point downward onto the deck surface.
		spot.rotation_degrees = Vector3(-90, 0, 0)
		add_child(spot)
		spot.global_position = pos + _deck_up * surface_light_height_m
		_surface_lights.append(spot)
	if use_mesh_markers:
		var mi := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(billboard_size, billboard_size)
		mi.mesh = quad
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.vertex_color_use_as_albedo = true
		mat.albedo_color = col
		mat.emission_enabled = true
		mat.emission = col
		mat.emission_energy_multiplier = marker_emission_energy
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		mi.material_override = mat
		add_child(mi)
		mi.global_position = marker_position


func _update_surface_light_state() -> void:
	var darkness := 1.0
	if follow_day_night_cycle:
		if not is_instance_valid(_day_night_cycle) and get_tree() != null:
			_day_night_cycle = get_tree().get_first_node_in_group("day_night_cycle")
		if is_instance_valid(_day_night_cycle) and _day_night_cycle.has_method("get_ai_darkness_factor"):
			darkness = clampf(float(_day_night_cycle.call("get_ai_darkness_factor")), 0.0, 1.0)
	var night_weight := smoothstep(0.08, 0.62, darkness)
	for light in _surface_lights:
		if not is_instance_valid(light):
			continue
		light.light_energy = light_energy * night_weight
		light.visible = light.light_energy > 0.02
