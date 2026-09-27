extends Control
## Cached, terrain-tested coverage. The overview shares the main map's cache.
const RESOLUTION := 48
const FRAME_BUDGET_US := 2000
const RED := Color(0.95, 0.24, 0.19, 0.32)
var overview := false
var coverage_source: Control
var selected_outpost: EnemyOutpost
var view_uv := Rect2(Vector2.ZERO, Vector2.ONE)
var _coverage: Dictionary = {}
var _stations: Array[EnemyOutpost] = []
var _refresh_s := 0.0
var _carrier_offset_m := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	TerrainNavGrid.bake_complete.connect(invalidate)

func invalidate() -> void:
	_coverage.clear()
	_refresh_s = 0.0
	queue_redraw()

func set_map_view(rect: Rect2) -> void:
	view_uv = rect
	queue_redraw()

func world_to_map(point: Vector3) -> Vector2:
	var span := Vector2(TerrainNavGrid._cols - 1, TerrainNavGrid._rows - 1) * TerrainNavGrid.cell_size_m
	return ((Vector2(point.x - TerrainNavGrid._origin_x, point.z - TerrainNavGrid._origin_z) / span - view_uv.position) / view_uv.size) * size

func _process(delta: float) -> void:
	if not is_visible_in_tree(): return
	if is_instance_valid(coverage_source):
		queue_redraw()
		return
	_refresh_s -= delta
	if _refresh_s <= 0.0:
		_refresh_s = 0.5
		_refresh_stations()
	_build_slice()
	queue_redraw()

func _refresh_stations() -> void:
	_stations.clear()
	for station in get_tree().get_nodes_in_group("enemy_outposts"):
		if station is EnemyOutpost and MapFogOfWar.is_world_explored(station.global_position):
			_stations.append(station)
	for id in _coverage.keys():
		if not is_instance_valid(instance_from_id(id)):
			_coverage.erase(id)
	var carrier := get_tree().get_first_node_in_group("carrier") as Node3D
	if is_instance_valid(carrier):
		var height := EnemyOutpost.sample_terrain_height(carrier.global_position.x, carrier.global_position.z)
		if is_finite(height) and height > TerrainNavGrid.IMPASSABLE * 0.5:
			var offset := snappedf(maxf(carrier.global_position.y - height, 0.0), 5.0)
			if absf(offset - _carrier_offset_m) >= 5.0:
				_carrier_offset_m = offset
				_coverage.clear()

func _build_slice() -> void:
	var started := Time.get_ticks_usec()
	for station in _stations:
		if not is_instance_valid(station) or station.is_destroyed: continue
		var id := station.get_instance_id()
		var radius := station.observation_radius_m
		if not _coverage.has(id) or not is_equal_approx(float(_coverage[id].radius), radius):
			var image := Image.create(RESOLUTION, RESOLUTION, false, Image.FORMAT_RGBA8)
			image.fill(Color.TRANSPARENT)
			_coverage[id] = {"image": image, "texture": ImageTexture.create_from_image(image), "cursor": 0, "radius": radius}
		var entry: Dictionary = _coverage[id]
		var changed := false
		while int(entry.cursor) < RESOLUTION * RESOLUTION:
			var index := int(entry.cursor)
			var x := index % RESOLUTION
			var y := index / RESOLUTION
			var offset := (Vector2(x + 0.5, y + 0.5) / RESOLUTION * 2.0 - Vector2.ONE) * radius
			if offset.length_squared() <= radius * radius:
				var point := station.global_position + Vector3(offset.x, 0, offset.y)
				var height := station._terrain_height(point.x, point.z)
				if is_finite(height) and height > TerrainNavGrid.IMPASSABLE * 0.5:
					point.y = height + _carrier_offset_m
					if station.can_observe(point): entry.image.set_pixel(x, y, RED)
			entry.cursor = index + 1
			changed = true
			if Time.get_ticks_usec() - started >= FRAME_BUDGET_US: break
		if changed: entry.texture.update(entry.image)
		if Time.get_ticks_usec() - started >= FRAME_BUDGET_US: return

func is_building_coverage() -> bool:
	var source: Control = coverage_source if is_instance_valid(coverage_source) else self
	for station: EnemyOutpost in source._stations:
		if is_instance_valid(station) and not station.is_destroyed:
			var entry: Dictionary = source._coverage.get(station.get_instance_id(), {})
			if entry.is_empty() or int(entry.cursor) < RESOLUTION * RESOLUTION: return true
	return false

func _draw() -> void:
	if not TerrainNavGrid.is_ready(): return
	var source: Control = coverage_source if is_instance_valid(coverage_source) else self
	for station: EnemyOutpost in source._stations:
		if not is_instance_valid(station) or not MapFogOfWar.is_world_explored(station.global_position): continue
		var selected: bool = source.selected_outpost == station
		# This is an estimated operating area, not live patrol telemetry. Keep it
		# after destruction: patrols already deployed can survive their home.
		_draw_patrol_area(station, selected)
		if station.is_destroyed: continue
		var entry: Dictionary = source._coverage.get(station.get_instance_id(), {})
		if entry.is_empty(): continue
		var radius := station.observation_radius_m
		var corner := world_to_map(station.global_position - Vector3(radius, 0, radius))
		var end := world_to_map(station.global_position + Vector3(radius, 0, radius))
		draw_texture_rect(entry.texture, Rect2(corner, end - corner), false, Color(1, 1, 1, 1.4 if selected else 1.0))
		if selected:
			draw_arc(world_to_map(station.global_position), 15, 0, TAU, 32, Color(1, 0.7, 0.3), 2.0, true)
	var reported := EnemyOpsManager.get_reported_carrier_position()
	if reported != Vector3.INF:
		var point := world_to_map(reported)
		draw_arc(point, 9, 0, TAU, 24, Color(1, 0.65, 0.3), 1.5, true)
		draw_line(point - Vector2(12, 0), point + Vector2(12, 0), Color(1, 0.65, 0.3))
		if not overview:
			draw_string(ThemeDB.fallback_font, point + Vector2(14, -10), "LAST REPORTED CARRIER POSITION", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 0.75, 0.4))

func _draw_patrol_area(station: EnemyOutpost, selected: bool) -> void:
	# Helicopters patrol ~3 km and observe within 4 km; ground patrols also
	# operate here. This broad envelope does not claim terrain visibility.
	var radius := 7000.0
	var center := world_to_map(station.global_position)
	var edge := world_to_map(station.global_position + Vector3(radius, 0, radius)) - center
	var color := Color(0.98, 0.66, 0.42, 0.22 if selected else 0.10)
	for stripe in range(-10, 11):
		var height := float(stripe) / 11.0
		var half_width := sqrt(1.0 - height * height)
		# Diagonal chords of an ellipse; fog above this layer hides unknown land.
		var a := Vector2(-half_width, height).rotated(PI / 4) * edge
		var b := Vector2(half_width, height).rotated(PI / 4) * edge
		draw_line(center + a, center + b, color, 1.0, true)

func get_outpost_description(station: EnemyOutpost) -> String:
	if not is_instance_valid(station): return ""
	var gun_count := 0
	for gun in get_tree().get_nodes_in_group("gun_emplacements"):
		if is_instance_valid(gun) and not gun.is_destroyed and gun.global_position.distance_to(station.global_position) < 250.0:
			gun_count += 1
	var observation := "OFFLINE" if station.is_destroyed else "ACTIVE (~%.1f km)" % (station.observation_radius_m / 1000.0)
	return "%s // OUTPOST\n\nObservation: %s\nPatrol replacements: %s\nNearby guns operational: %d\n\nObservation building: remove fixed coverage.\nVehicle bay: stop replacement patrols.\nGuns: make the approach safer.\n\nDeployed patrols may remain after the compound is disabled." % [station.outpost_id, observation, "ACTIVE" if station.can_support_patrols() else "OFFLINE", gun_count]

func get_exposure_status(point: Vector3) -> String:
	if not MapFogOfWar.is_world_explored(point): return "UNKNOWN"
	var possible_patrol := false
	var calculating := false
	for station in _stations:
		if not is_instance_valid(station): continue
		var offset := Vector2(point.x - station.global_position.x, point.z - station.global_position.z)
		possible_patrol = possible_patrol or offset.length() < 7000.0
		if station.is_destroyed or offset.length() > station.observation_radius_m: continue
		var entry: Dictionary = _coverage.get(station.get_instance_id(), {})
		if entry.is_empty() or int(entry.cursor) < RESOLUTION * RESOLUTION:
			calculating = true
			continue
		var cell := Vector2i((offset / station.observation_radius_m + Vector2.ONE) * 0.5 * RESOLUTION)
		cell = cell.clamp(Vector2i.ZERO, Vector2i.ONE * (RESOLUTION - 1))
		if entry.image.get_pixelv(cell).a > 0.0: return "FIXED OBSERVATION"
	if calculating: return "COVERAGE CALCULATING"
	return "POSSIBLE PATROLS" if possible_patrol else "NO KNOWN COVERAGE"
