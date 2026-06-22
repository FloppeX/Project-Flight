extends Control

const PIXEL_FONT: FontFile = preload("res://UI/Pixel.ttf")
const TRACKED_TEAMS: PackedStringArray = ["friendlies", "enemies"]
const GRID_DIVISIONS: int = 8
const GRID_COLOR: Color = Color(0.24, 0.60, 0.28, 0.20)
const MAJOR_GRID_COLOR: Color = Color(0.48, 1.0, 0.56, 0.26)
const BORDER_COLOR: Color = Color(0.68, 1.0, 0.74, 0.88)
const SCANLINE_COLOR: Color = Color(0.0, 0.0, 0.0, 0.16)
const CENTER_RETICLE_COLOR: Color = Color(0.48, 1.0, 0.56, 0.34)
const SCANLINE_STEP_PX: float = 4.0
const CORNER_BRACKET_LEN_PX: float = 18.0
const CORNER_BRACKET_INSET_PX: float = 7.0
const POI_ACTIVE_COLOR: Color = Color(1.0, 0.92, 0.28, 1.0)
const POI_USED_COLOR: Color = Color(0.52, 0.56, 0.52, 0.95)

@export var player_color: Color = Color(1.0, 1.0, 0.40, 1.0)
@export var friendly_color: Color = Color(0.58, 1.0, 0.64, 1.0)
@export var enemy_color: Color = Color(1.0, 0.38, 0.38, 1.0)
@export var enemy_platoon_color: Color = Color(1.0, 0.12, 0.72, 1.0)
@export var carrier_color: Color = Color(0.72, 1.0, 0.78, 1.0)
@export var building_color: Color = Color(0.64, 0.96, 0.70, 1.0)
@export var ground_marker_size_px: float = 5.0
@export var building_marker_size_px: float = 8.5
@export var platoon_marker_size_px: float = 10.0
@export var aircraft_marker_size_px: float = 13.0
@export var carrier_marker_length_px: float = 18.0
@export var carrier_marker_width_px: float = 12.0
@export var platoon_reveal_observer_height_m: float = 12.0
@export var platoon_reveal_target_height_m: float = 10.0
@export var platoon_reveal_sample_step_m: float = 80.0
@export var platoon_reveal_terrain_clearance_m: float = 4.0
@export var platoon_reveal_max_range_m: float = 5000.0
@export var carrier_waypoint_color: Color = Color(0.72, 1.0, 0.78, 0.9)
@export var helicopter_waypoint_color: Color = Color(0.44, 0.86, 1.0, 0.9)
@export var platoon_waypoint_color: Color = Color(1.0, 0.24, 0.78, 0.9)
@export var waypoint_line_width_px: float = 1.6
@export var waypoint_dot_size_px: float = 4.0
@export var route_display_simplify_enabled: bool = true
@export var aircraft_route_display_simplify_enabled: bool = false
@export var route_display_simplify_turn_deg: float = 8.0
@export var route_display_simplify_line_error_px: float = 5.0
@export var route_display_simplify_altitude_error_m: float = 35.0
@export var draft_waypoint_color: Color = Color(1.0, 0.82, 0.32, 0.95)
@export var selection_color: Color = Color(0.94, 1.0, 0.64, 1.0)
@export var selection_marker_radius_px: float = 10.0
@export var counter_margin_px: float = 12.0
@export var counter_font_size_px: int = 14
@export var show_contact_counters: bool = true

var _counts_label: Label
var _selection_world_pos: Vector3 = Vector3.INF
var _selection_world_color: Color = selection_color
var _selection_route_origin_world: Vector3 = Vector3.INF
var _selection_route_points: Array[Vector3] = []
var _selection_route_color: Color = selection_color
var _selection_route_closed_loop: bool = false
var _draft_origin_world: Vector3 = Vector3.INF
var _draft_points: Array[Vector3] = []
var _draft_color: Color = draft_waypoint_color
var _draft_closed_loop: bool = false

func _ready() -> void:
	add_to_group("origin_shifter")
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(true)
	_counts_label = Label.new()
	_counts_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_counts_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_counts_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_counts_label.add_theme_font_override("font", PIXEL_FONT)
	_counts_label.add_theme_color_override("font_color", BORDER_COLOR)
	_counts_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 1.0))
	_counts_label.add_theme_constant_override("outline_size", 1)
	_counts_label.add_theme_font_size_override("font_size", counter_font_size_px)
	add_child(_counts_label)
	resized.connect(_layout_counts_label)
	_layout_counts_label()

func _process(_delta: float) -> void:
	if visible:
		if show_contact_counters:
			_update_counts_label()
		elif _counts_label != null:
			_counts_label.visible = false
		queue_redraw()

func apply_origin_shift(offset: Vector3) -> void:
	if _selection_world_pos != Vector3.INF:
		_selection_world_pos -= offset
	if _selection_route_origin_world != Vector3.INF:
		_selection_route_origin_world -= offset
	for i in range(_selection_route_points.size()):
		_selection_route_points[i] -= offset
	if _draft_origin_world != Vector3.INF:
		_draft_origin_world -= offset
	for i in range(_draft_points.size()):
		_draft_points[i] -= offset

func _draw() -> void:
	if not TerrainNavGrid.is_ready():
		return
	_draw_vector_decor()
	var carrier := get_tree().get_first_node_in_group("carrier") as Node3D
	if carrier and is_instance_valid(carrier):
		_draw_route_from_points(carrier.global_position, _get_active_route_points(carrier), carrier_waypoint_color, true)
		_draw_carrier_marker(carrier)

	for group_name: String in TRACKED_TEAMS:
		for node in get_tree().get_nodes_in_group(group_name):
			if not (node is Node3D) or not is_instance_valid(node):
				continue
			var node_3d := node as Node3D
			if not node_3d.is_inside_tree():
				continue
			if node_3d == carrier:
				continue
			if node_3d.is_in_group("ground_vehicles") or node_3d is Building or node_3d.is_in_group("buildings"):
				_draw_ground_marker(node_3d)
			else:
				var air_route := _get_active_route_points(node_3d)
				if not air_route.is_empty():
					_draw_route_from_points(node_3d.global_position, air_route, helicopter_waypoint_color, true, false, aircraft_route_display_simplify_enabled)
				_draw_air_marker(node_3d)

	for node in get_tree().get_nodes_in_group("ground_vehicle_platoons"):
		if not (node is GroundVehiclePlatoon) or not is_instance_valid(node):
			continue
		var platoon := node as GroundVehiclePlatoon
		if platoon.team != 2:
			continue
		if not platoon.has_members():
			continue
		var platoon_pos: Vector3 = platoon.get_contact_position()
		if not _is_world_in_map_bounds(platoon_pos):
			continue
		var platoon_color := _nearest_base_color(platoon_pos)
		_draw_route_from_points(platoon_pos, _get_active_route_points(platoon), platoon_color, false)
		var map_pos: Vector2 = _world_to_map(platoon_pos)
		_draw_square_marker(map_pos, platoon_marker_size_px, platoon_color, true)
	_draw_enemy_bases()
	_draw_enemy_virtual_platoons()
	_draw_poi_markers()
	_draw_selection_route()
	_draw_command_draft()
	_draw_selection_focus()

func _layout_counts_label() -> void:
	if _counts_label == null:
		return
	_counts_label.visible = show_contact_counters
	var label_width: float = clampf(size.x * 0.34, 170.0, 220.0)
	_counts_label.position = Vector2(size.x - counter_margin_px - label_width, counter_margin_px)
	_counts_label.size = Vector2(label_width, 56.0)

func _update_counts_label() -> void:
	if _counts_label == null:
		return
	_counts_label.text = "Enemy platoons: %d\nEnemy vehicles: %d" % [
		_count_visible_enemy_platoons(),
		_count_visible_enemy_ground_vehicles(),
	]

func _count_visible_enemy_platoons() -> int:
	var count: int = 0
	for node in get_tree().get_nodes_in_group("ground_vehicle_platoons"):
		if not (node is GroundVehiclePlatoon) or not is_instance_valid(node):
			continue
		var platoon := node as GroundVehiclePlatoon
		if platoon.team != 2:
			continue
		if not platoon.has_members():
			continue
		var platoon_pos: Vector3 = platoon.get_contact_position()
		if not _is_world_in_map_bounds(platoon_pos):
			continue
		count += 1
	return count

func _count_visible_enemy_ground_vehicles() -> int:
	var count: int = 0
	for node in get_tree().get_nodes_in_group("ground_vehicles"):
		if not (node is Node3D) or not is_instance_valid(node):
			continue
		var node_3d := node as Node3D
		if not node_3d.has_method("get_team") or int(node_3d.call("get_team")) != 2:
			continue
		if not _is_world_in_map_bounds(node_3d.global_position):
			continue
		count += 1
	return count

func _draw_carrier_marker(carrier: Node3D) -> void:
	if not _is_world_in_map_bounds(carrier.global_position):
		return
	var center: Vector2 = _world_to_map(carrier.global_position)
	var forward := _basis_to_map_forward(carrier.global_basis)
	if forward.length() < 0.001:
		forward = Vector2(0.0, -1.0)
	else:
		forward = forward.normalized()
	var right := Vector2(forward.y, -forward.x)
	var half_length := carrier_marker_length_px * 0.5
	var half_width := carrier_marker_width_px * 0.5
	var p0: Vector2 = center - right * half_width - forward * half_length
	var p1: Vector2 = center + right * half_width - forward * half_length
	var p2: Vector2 = center + right * half_width + forward * half_length
	var p3: Vector2 = center - right * half_width + forward * half_length
	var c_color := Livery.get_team_hud_color(Livery.PLAYER_TEAM_ID)
	draw_polygon(PackedVector2Array([p0, p1, p2, p3]), PackedColorArray([c_color]))
	draw_polyline(PackedVector2Array([p0, p1, p2, p3, p0]), Color(0.92, 0.98, 1.0, 1.0), 1.5)

func _draw_air_marker(node_3d: Node3D) -> void:
	if not _is_world_in_map_bounds(node_3d.global_position):
		return
	var map_pos: Vector2 = _world_to_map(node_3d.global_position)
	var team_color := _color_for_team_node(node_3d)
	var heading := _basis_to_map_forward(node_3d.global_basis)
	if heading.length() < 0.001:
		heading = Vector2(0.0, -1.0)
	else:
		heading = heading.normalized()
	var perp := Vector2(heading.y, -heading.x)
	var s := aircraft_marker_size_px * 1.55
	var tip: Vector2 = map_pos + heading * s
	var bl: Vector2 = map_pos - heading * (s * 0.55) + perp * (s * 0.52)
	var br: Vector2 = map_pos - heading * (s * 0.55) - perp * (s * 0.52)
	draw_polygon(PackedVector2Array([tip, bl, br]), PackedColorArray([team_color]))
	draw_polyline(PackedVector2Array([tip, bl, br, tip]), Color(1.0, 1.0, 1.0, 0.85), 1.0)

func _draw_ground_marker(node_3d: Node3D) -> void:
	if not _is_world_in_map_bounds(node_3d.global_position):
		return
	var map_pos: Vector2 = _world_to_map(node_3d.global_position)
	var color := _color_for_team_node(node_3d)
	if node_3d is Building or node_3d.is_in_group("buildings"):
		_draw_square_marker(map_pos, building_marker_size_px, color, false)
	else:
		draw_circle(map_pos, ground_marker_size_px * 0.55, color)

func _draw_square_marker(center: Vector2, size_px: float, color: Color, outline: bool) -> void:
	var rect := Rect2(center - Vector2.ONE * size_px * 0.5, Vector2.ONE * size_px)
	draw_rect(rect, color, true)
	if outline:
		draw_rect(rect.grow(1.0), BORDER_COLOR, false, 1.2)

func _draw_route_from_points(origin_world: Vector3, route_points: Array[Vector3], color: Color, outline: bool, closed_loop: bool = false, simplify_display: bool = true) -> void:
	if route_points.is_empty() or not _is_world_in_map_bounds(origin_world):
		return
	var display_points := _simplify_route_for_display(origin_world, route_points) if simplify_display else route_points
	var map_points := PackedVector2Array()
	map_points.append(_world_to_map(origin_world))
	for world_point in display_points:
		if not _is_world_in_map_bounds(world_point):
			continue
		map_points.append(_world_to_map(world_point))
	if map_points.size() < 2:
		return
	draw_polyline(map_points, color, waypoint_line_width_px, true)
	for i in range(1, map_points.size()):
		_draw_square_marker(map_points[i], waypoint_dot_size_px, color, outline)
	if closed_loop and map_points.size() >= 3:
		draw_line(map_points[map_points.size() - 1], map_points[1], color, waypoint_line_width_px, true)


func _simplify_route_for_display(origin_world: Vector3, route_points: Array[Vector3]) -> Array[Vector3]:
	if not route_display_simplify_enabled or route_points.size() <= 2:
		return route_points

	var full_route: Array[Vector3] = [origin_world]
	for point in route_points:
		full_route.append(point)

	var simplified: Array[Vector3] = [full_route[0]]
	for i in range(1, full_route.size() - 1):
		var previous: Vector3 = simplified[simplified.size() - 1]
		var middle: Vector3 = full_route[i]
		var next_point: Vector3 = full_route[i + 1]
		if _can_skip_display_route_point(previous, middle, next_point):
			continue
		simplified.append(middle)
	simplified.append(full_route[full_route.size() - 1])

	var result: Array[Vector3] = []
	for i in range(1, simplified.size()):
		result.append(simplified[i])
	return result


func _can_skip_display_route_point(previous: Vector3, middle: Vector3, next_point: Vector3) -> bool:
	var prev_map := _world_to_map(previous)
	var mid_map := _world_to_map(middle)
	var next_map := _world_to_map(next_point)
	var segment := next_map - prev_map
	var segment_len_sq := segment.length_squared()
	if segment_len_sq <= 1.0:
		return true

	var prev_to_mid := mid_map - prev_map
	var mid_to_next := next_map - mid_map
	if prev_to_mid.length_squared() > 1.0 and mid_to_next.length_squared() > 1.0:
		var turn_angle := absf(prev_to_mid.normalized().angle_to(mid_to_next.normalized()))
		if turn_angle > deg_to_rad(maxf(route_display_simplify_turn_deg, 0.0)):
			return false

	var line_t := clampf(prev_to_mid.dot(segment) / segment_len_sq, 0.0, 1.0)
	var closest := prev_map + segment * line_t
	if mid_map.distance_to(closest) > maxf(route_display_simplify_line_error_px, 0.0):
		return false

	var altitude_t := clampf(_flat_distance_world(previous, middle) / maxf(_flat_distance_world(previous, next_point), 1.0), 0.0, 1.0)
	var expected_altitude := lerpf(previous.y, next_point.y, altitude_t)
	if absf(middle.y - expected_altitude) > maxf(route_display_simplify_altitude_error_m, 0.0):
		return false

	return true


func _flat_distance_world(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func set_selection_focus(world_pos: Vector3, color: Color = selection_color) -> void:
	_selection_world_pos = world_pos
	_selection_world_color = color
	queue_redraw()

func clear_selection_focus() -> void:
	_selection_world_pos = Vector3.INF
	queue_redraw()

func set_selection_route(origin_world: Vector3, route_points: Array[Vector3], color: Color = selection_color, closed_loop: bool = false) -> void:
	_selection_route_origin_world = origin_world
	_selection_route_points = route_points.duplicate()
	_selection_route_color = color
	_selection_route_closed_loop = closed_loop
	queue_redraw()

func clear_selection_route() -> void:
	_selection_route_origin_world = Vector3.INF
	_selection_route_points.clear()
	_selection_route_closed_loop = false
	queue_redraw()

func set_command_draft(origin_world: Vector3, route_points: Array[Vector3], color: Color = draft_waypoint_color, closed_loop: bool = false) -> void:
	_draft_origin_world = origin_world
	_draft_points = route_points.duplicate()
	_draft_color = color
	_draft_closed_loop = closed_loop
	queue_redraw()

func clear_command_draft() -> void:
	_draft_origin_world = Vector3.INF
	_draft_points.clear()
	_draft_closed_loop = false
	queue_redraw()

func _get_active_route_points(node: Node) -> Array[Vector3]:
	var route_points: Array[Vector3] = []
	if node == null or not is_instance_valid(node):
		return route_points
	var route_provider: Node = node if node.has_method("get_active_waypoints") else null
	if route_provider == null:
		route_provider = node.find_child("HelicopterPilot", true, false)
	if route_provider == null:
		route_provider = node.find_child("AIPilot", true, false)
	if route_provider == null or not route_provider.has_method("get_active_waypoints"):
		return route_points
	var points_variant = route_provider.call("get_active_waypoints")
	if not (points_variant is Array):
		return route_points
	for point in points_variant:
		if point is Vector3:
			route_points.append(point)
	return route_points

func _is_world_in_map_bounds(world_pos: Vector3) -> bool:
	var span_x: float = float(TerrainNavGrid._cols - 1) * TerrainNavGrid.cell_size_m
	var span_z: float = float(TerrainNavGrid._rows - 1) * TerrainNavGrid.cell_size_m
	if span_x <= 1.0 or span_z <= 1.0:
		return false
	var u: float = (world_pos.x - TerrainNavGrid._origin_x) / span_x
	var v: float = (world_pos.z - TerrainNavGrid._origin_z) / span_z
	return u >= 0.0 and u <= 1.0 and v >= 0.0 and v <= 1.0

func _world_to_map(world_pos: Vector3) -> Vector2:
	var span_x: float = float(TerrainNavGrid._cols - 1) * TerrainNavGrid.cell_size_m
	var span_z: float = float(TerrainNavGrid._rows - 1) * TerrainNavGrid.cell_size_m
	var u: float = (world_pos.x - TerrainNavGrid._origin_x) / span_x
	var v: float = (world_pos.z - TerrainNavGrid._origin_z) / span_z
	return Vector2(u * size.x, v * size.y)

func _basis_to_map_forward(basis: Basis) -> Vector2:
	var forward_3d: Vector3 = basis.z
	return Vector2(forward_3d.x, forward_3d.z)

func _color_for_team_node(node_3d: Node3D) -> Color:
	if node_3d.has_method("get_team") and int(node_3d.call("get_team")) == 2:
		return Livery.get_team_hud_color(2)
	return Livery.get_team_hud_color(Livery.PLAYER_TEAM_ID)


func _nearest_base_color(_pos: Vector3) -> Color:
	return Livery.get_team_hud_color(2)

func _is_enemy_platoon_revealed(target_world_pos: Vector3) -> bool:
	var carrier := get_tree().get_first_node_in_group("carrier") as Node3D
	if carrier and is_instance_valid(carrier) and _has_terrain_line_of_sight(carrier.global_position, target_world_pos):
		return true
	for observer in get_tree().get_nodes_in_group("team_1"):
		if not (observer is Node3D) or not is_instance_valid(observer):
			continue
		var observer_node := observer as Node3D
		if observer_node == carrier:
			continue
		if observer_node.global_position.distance_squared_to(target_world_pos) > platoon_reveal_max_range_m * platoon_reveal_max_range_m:
			continue
		if _has_terrain_line_of_sight(observer_node.global_position, target_world_pos):
			return true
	return false

func _is_enemy_ground_contact_revealed(target_node: Node3D) -> bool:
	return _is_enemy_platoon_revealed(target_node.global_position)

func _has_terrain_line_of_sight(observer_world_pos: Vector3, target_world_pos: Vector3) -> bool:
	var from_pos := observer_world_pos + Vector3.UP * platoon_reveal_observer_height_m
	var to_pos := target_world_pos + Vector3.UP * platoon_reveal_target_height_m
	var planar_distance := Vector2(to_pos.x - from_pos.x, to_pos.z - from_pos.z).length()
	if planar_distance <= 1.0:
		return true
	var max_range_sq := platoon_reveal_max_range_m * platoon_reveal_max_range_m
	if from_pos.distance_squared_to(to_pos) > max_range_sq:
		return false
	var steps: int = maxi(int(ceil(planar_distance / maxf(platoon_reveal_sample_step_m, 10.0))), 1)
	for step_idx in range(1, steps):
		var t: float = float(step_idx) / float(steps)
		var sample_pos := from_pos.lerp(to_pos, t)
		var terrain_y := TerrainNavGrid.sample_height(sample_pos.x, sample_pos.z)
		if terrain_y > TerrainNavGrid.IMPASSABLE * 0.5 and terrain_y + platoon_reveal_terrain_clearance_m > sample_pos.y:
			return false
	return true

func _draw_vector_decor() -> void:
	_draw_scanlines()
	_draw_grid()
	_draw_border_brackets()
	_draw_center_reticle()

func _draw_scanlines() -> void:
	var y: float = 0.0
	while y <= size.y:
		draw_line(Vector2(0.0, y), Vector2(size.x, y), SCANLINE_COLOR, 1.0)
		y += SCANLINE_STEP_PX

func _draw_grid() -> void:
	for i in range(GRID_DIVISIONS + 1):
		var t: float = float(i) / float(GRID_DIVISIONS)
		var x: float = size.x * t
		var y: float = size.y * t
		var color := MAJOR_GRID_COLOR if i == GRID_DIVISIONS / 2 else GRID_COLOR
		draw_line(Vector2(x, 0.0), Vector2(x, size.y), color, 1.0)
		draw_line(Vector2(0.0, y), Vector2(size.x, y), color, 1.0)

func _draw_border_brackets() -> void:
	var min_x := CORNER_BRACKET_INSET_PX
	var min_y := CORNER_BRACKET_INSET_PX
	var max_x := size.x - CORNER_BRACKET_INSET_PX
	var max_y := size.y - CORNER_BRACKET_INSET_PX
	draw_line(Vector2(min_x, min_y), Vector2(min_x + CORNER_BRACKET_LEN_PX, min_y), BORDER_COLOR, 2.0)
	draw_line(Vector2(min_x, min_y), Vector2(min_x, min_y + CORNER_BRACKET_LEN_PX), BORDER_COLOR, 2.0)
	draw_line(Vector2(max_x, min_y), Vector2(max_x - CORNER_BRACKET_LEN_PX, min_y), BORDER_COLOR, 2.0)
	draw_line(Vector2(max_x, min_y), Vector2(max_x, min_y + CORNER_BRACKET_LEN_PX), BORDER_COLOR, 2.0)
	draw_line(Vector2(min_x, max_y), Vector2(min_x + CORNER_BRACKET_LEN_PX, max_y), BORDER_COLOR, 2.0)
	draw_line(Vector2(min_x, max_y), Vector2(min_x, max_y - CORNER_BRACKET_LEN_PX), BORDER_COLOR, 2.0)
	draw_line(Vector2(max_x, max_y), Vector2(max_x - CORNER_BRACKET_LEN_PX, max_y), BORDER_COLOR, 2.0)
	draw_line(Vector2(max_x, max_y), Vector2(max_x, max_y - CORNER_BRACKET_LEN_PX), BORDER_COLOR, 2.0)

func _draw_center_reticle() -> void:
	var center := size * 0.5
	draw_line(center + Vector2(-8.0, 0.0), center + Vector2(8.0, 0.0), CENTER_RETICLE_COLOR, 1.0)
	draw_line(center + Vector2(0.0, -8.0), center + Vector2(0.0, 8.0), CENTER_RETICLE_COLOR, 1.0)

func _draw_enemy_bases() -> void:
	for node in get_tree().get_nodes_in_group("enemy_bases"):
		if not (node is EnemyBase) or not is_instance_valid(node as EnemyBase):
			continue
		var base      := node as EnemyBase
		var base_pos  := base.global_position
		if not _is_world_in_map_bounds(base_pos):
			continue
		var mp    := _world_to_map(base_pos)
		var color := Livery.get_team_hud_color(2)

		# Filled diamond
		var s := 9.0
		var diamond := PackedVector2Array([
			mp + Vector2(0.0, -s), mp + Vector2(s, 0.0),
			mp + Vector2(0.0,  s), mp + Vector2(-s, 0.0),
		])
		draw_colored_polygon(diamond, color)
		draw_polyline(PackedVector2Array([
			diamond[0], diamond[1], diamond[2], diamond[3], diamond[0]
		]), Color(1.0, 1.0, 1.0, 0.55), 1.2)

		# Virtual flight arrow markers
		for flight in base.get_flights():
			if not is_instance_valid(flight):
				continue
			if not _is_world_in_map_bounds(flight.position):
				continue
			var fmp := _world_to_map(flight.position)
			var fh  := Vector2(flight.heading.x, flight.heading.z)
			if fh.length_squared() < 0.001:
				fh = Vector2(0.0, -1.0)
			fh = fh.normalized()
			var perp := Vector2(fh.y, -fh.x)
			var fs   := aircraft_marker_size_px * 1.55
			var tip  := fmp + fh * fs
			var bl   := fmp - fh * (fs * 0.55) + perp * (fs * 0.52)
			var br   := fmp - fh * (fs * 0.55) - perp * (fs * 0.52)
			var alpha := 0.50 if flight.vstate == EnemyVirtualFlight.VState.VIRTUAL else 1.0
			var fc    := Color(color.r, color.g, color.b, alpha)
			draw_colored_polygon(PackedVector2Array([tip, bl, br]), fc)


func _draw_enemy_virtual_platoons() -> void:
	var color := Livery.get_team_hud_color(2)
	for base in EnemyBaseManager.get_all_bases():
		if not is_instance_valid(base):
			continue
		for platoon: EnemyVirtualPlatoon in EnemyOpsManager._get_platoons(base):
			if platoon.vehicle_count <= 0:
				continue
			if not _is_world_in_map_bounds(platoon.position):
				continue
			var mp    := _world_to_map(platoon.position)
			var alpha := 0.50 if platoon.vstate == EnemyVirtualPlatoon.VState.VIRTUAL else 1.0
			var pc    := Color(color.r, color.g, color.b, alpha)
			_draw_square_marker(mp, platoon_marker_size_px, pc, true)


func _draw_poi_markers() -> void:
	for marker: Dictionary in POIManager.get_discovered_map_markers():
		var pos: Vector3 = marker.get("position", Vector3.INF)
		if not _is_world_in_map_bounds(pos):
			continue
		var color := POI_USED_COLOR if bool(marker.get("revealed", false)) else POI_ACTIVE_COLOR
		_draw_star(_world_to_map(pos), 7.0, color)

func _draw_star(center: Vector2, radius: float, color: Color) -> void:
	var pts := PackedVector2Array()
	var inner := radius * 0.42
	for i in range(10):
		var angle := -PI * 0.5 + i * (PI / 5.0)
		var r := radius if i % 2 == 0 else inner
		pts.append(center + Vector2(cos(angle), sin(angle)) * r)
	draw_colored_polygon(pts, color)
	draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[4],
		pts[5], pts[6], pts[7], pts[8], pts[9], pts[0]]),
		Color(1.0, 1.0, 1.0, 0.40), 1.0)

func _draw_selection_focus() -> void:
	if not _is_world_in_map_bounds(_selection_world_pos):
		return
	var center := _world_to_map(_selection_world_pos)
	var radius := selection_marker_radius_px
	draw_arc(center, radius, 0.0, TAU, 24, _selection_world_color, 1.6, true)
	draw_line(center + Vector2(-radius - 4.0, 0.0), center + Vector2(-radius + 1.0, 0.0), _selection_world_color, 1.4)
	draw_line(center + Vector2(radius - 1.0, 0.0), center + Vector2(radius + 4.0, 0.0), _selection_world_color, 1.4)
	draw_line(center + Vector2(0.0, -radius - 4.0), center + Vector2(0.0, -radius + 1.0), _selection_world_color, 1.4)
	draw_line(center + Vector2(0.0, radius - 1.0), center + Vector2(0.0, radius + 4.0), _selection_world_color, 1.4)

func _draw_selection_route() -> void:
	if _selection_route_points.is_empty():
		return
	_draw_route_from_points(
		_selection_route_origin_world,
		_selection_route_points,
		_selection_route_color,
		true,
		_selection_route_closed_loop,
		false
	)

func _draw_command_draft() -> void:
	if _draft_points.is_empty():
		return
	_draw_route_from_points(_draft_origin_world, _draft_points, _draft_color, true, _draft_closed_loop, false)
