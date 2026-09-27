extends Control
## Weather stays below tactical symbols and never intercepts map input.

var overview := false
var view_uv := Rect2(Vector2.ZERO, Vector2.ONE)
const AMBER := Color(0.96, 0.65, 0.28, 0.8)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func set_map_view(rect: Rect2) -> void:
	view_uv = rect
	queue_redraw()

func world_to_map(world_position: Vector3) -> Vector2:
	var span := Vector2(TerrainNavGrid._cols - 1, TerrainNavGrid._rows - 1) * TerrainNavGrid.cell_size_m
	var uv := (Vector2(world_position.x, world_position.z) - Vector2(TerrainNavGrid._origin_x, TerrainNavGrid._origin_z)) / span
	return (uv - view_uv.position) / view_uv.size * size

func _polygon(front: Node3D, scale_factor: float, future_s: float = 0.0) -> PackedVector2Array:
	var points := PackedVector2Array()
	for point in front.get_footprint(scale_factor, future_s):
		points.append(world_to_map(point))
	return points

func _draw() -> void:
	if not TerrainNavGrid.is_ready():
		return
	_draw_twisters()
	_draw_electrical_storms()
	var front := get_tree().get_first_node_in_group("dust_front") as Node3D
	if front != null and front.enabled and front.initialized and front.strength > 0.01:
		var alpha: float = front.strength
		for band in [1.0, 0.9, 0.8]:
			draw_colored_polygon(_polygon(front, band), Color(0.87, 0.48, 0.12, 0.12 * alpha))
		draw_polyline(_polygon(front, 1.0), Color(0.96, 0.65, 0.28, 0.8 * alpha), 1.0 if overview else 2.0, true)
		if not overview:
			var forecast := _polygon(front, 1.0, 120.0)
			for i in range(0, forecast.size() - 1, 2):
				draw_line(forecast[i], forecast[i + 1], Color(0.96, 0.65, 0.28, 0.4 * alpha), 1.0, true)
	if overview:
		return
	var wind := get_tree().get_first_node_in_group("atmospheric_wind")
	if wind == null:
		return
	var span := Vector2(TerrainNavGrid._cols - 1, TerrainNavGrid._rows - 1) * TerrainNavGrid.cell_size_m
	for row in 5:
		for column in 5:
			var fraction := Vector2(column + 0.5, row + 0.5) / 5.0
			var uv := view_uv.position + fraction * view_uv.size
			var world_pos := Vector3(TerrainNavGrid._origin_x + uv.x * span.x,
				550.0, TerrainNavGrid._origin_z + uv.y * span.y)
			var velocity: Vector3 = wind.get_velocity_at(world_pos)
			var direction := Vector2(velocity.x / span.x, velocity.z / span.y).normalized()
			var center := fraction * size
			var tip := center + direction * clampf(velocity.length(), 4.0, 16.0)
			var in_dust: bool = front != null and front.get_intensity_at(world_pos) > 0.1
			var color := AMBER if in_dust else Color(0.6, 0.82, 0.82, 0.45)
			draw_line(center - direction * 4.0, tip, color, 1.0, true)
			draw_line(tip, tip - direction.rotated(0.6) * 5.0, color, 1.0, true)
			draw_line(tip, tip - direction.rotated(-0.6) * 5.0, color, 1.0, true)

func _draw_electrical_storms() -> void:
	for storm in get_tree().get_nodes_in_group("electrical_storm"):
		if not storm.active:
			continue
		var center := world_to_map(storm.global_position)
		var color := Color(0.43, 0.68, 1.0, 0.9)
		var footprint := _polygon(storm, 1.0)
		draw_colored_polygon(footprint, Color(0.11, 0.18, 0.31, 0.24))
		draw_polyline(footprint, color, 1.0 if overview else 1.5, true)
		draw_arc(center, 5.0 if overview else 7.0, 0.0, TAU, 16, color, 1.5, true)
		if not overview:
			var future := world_to_map(storm.global_position + storm.get_travel_velocity() * 60.0)
			draw_dashed_line(center, future, Color(color, 0.55), 1.0, 4.0)
			draw_string(ThemeDB.fallback_font, center + Vector2(11, -9), "ELECTRICAL", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, color)

func _draw_twisters() -> void:
	for twister in get_tree().get_nodes_in_group("twister"):
		if not twister.enabled or not twister.initialized or twister.strength <= 0.01:
			continue
		var color := Color(1.0, 0.44, 0.22, twister.strength)
		var footprint := _polygon(twister, 1.0)
		draw_colored_polygon(footprint, Color(color, 0.16 * twister.strength))
		draw_polyline(footprint, color, 1.0, true)
		var center := world_to_map(twister.global_position)
		var spiral := PackedVector2Array()
		for i in 49:
			var f := float(i) / 48.0
			spiral.append(center + Vector2.from_angle(f * TAU * 2.0) * lerpf(1.0, 7.0 if overview else 10.0, f))
		draw_polyline(spiral, color, 1.5, true)
		if overview:
			continue
		var tip := world_to_map(twister.global_position + twister.get_travel_velocity() * 60.0)
		draw_dashed_line(center, tip, Color(color, 0.65), 1.0, 4.0)
		draw_arc(tip, 4.0, 0.0, TAU, 16, color, 1.0, true)
		draw_string(ThemeDB.fallback_font, center + Vector2(13, -9), "TWISTER", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, color)
