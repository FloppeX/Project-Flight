extends Control

const WorldMapTextureBuilder = preload("res://UI/WorldMapTextureBuilder.gd")
const TERRAIN_MAP_EDGE_INSET_PX: float = 2.0
const POI_ACTIVE_COLOR: Color = Color(1.0, 0.92, 0.28, 1.0)
const POI_USED_COLOR: Color = Color(0.52, 0.56, 0.52, 0.95)

var provider: Node = null
var debug_enabled: bool = false
@export var show_terrain_map: bool = true
@export var terrain_map_opacity: float = 0.72
@export var terrain_map_range_m: float = 3500.0
@export var refresh_interval_s: float = 0.05

var _terrain_bounds_xz: Rect2 = Rect2()
var _terrain_map_texture: ImageTexture = null
var _terrain_map_ready: bool = false
var _refresh_timer_s: float = 0.0

# Cached contact lists — rebuilt periodically, not every draw call
var _cached_air_contacts: Array = []
var _cached_ground_enemy_contacts: Array = []
var _cached_ground_friendly_contacts: Array = []
var _cached_ground_enemies: Array = []  # Static enemies (EnemyBox etc.)
var _cached_enemies: Array = []
var _contact_cache_timer_s: float = 0.0
const CONTACT_CACHE_INTERVAL_S: float = 0.2

func _ready() -> void:
	add_to_group("origin_shifter")

func apply_origin_shift(_offset: Vector3) -> void:
	# TerrainNavGrid owns map-origin shifting. The radar samples that live origin
	# directly so it stays aligned with the tactical M map after floating-origin shifts.
	pass

func set_provider(p: Node) -> void:
	provider = p
	queue_redraw()

func _process(_delta: float) -> void:
	if not visible:
		return
	_contact_cache_timer_s -= _delta
	if _contact_cache_timer_s <= 0.0:
		_contact_cache_timer_s = CONTACT_CACHE_INTERVAL_S
		_rebuild_contact_cache()
	_refresh_timer_s -= _delta
	if _refresh_timer_s > 0.0:
		return
	_refresh_timer_s = maxf(refresh_interval_s, 0.01)
	queue_redraw()

func _draw() -> void:
	if provider == null or not is_instance_valid(provider):
		return
	# Expect provider to expose aircraft and EnemyRegistry singleton
	var size: Vector2 = get_size()
	var center: Vector2 = size * 0.5
	var radius: float = min(size.x, size.y) * 0.48
	var aircraft = provider.aircraft if ("aircraft" in provider) else null
	var radar_bg: Color = Color(0.02, 0.06, 0.02)
	draw_rect(Rect2(Vector2.ZERO, size), radar_bg)
	if show_terrain_map:
		_ensure_terrain_map_cache()
	if aircraft == null or not is_instance_valid(aircraft):
		draw_circle(center, radius, radar_bg)
		return
	var team_id: int = aircraft.get_team() if aircraft.has_method("get_team") else 1
	var enemies: Array = _cached_enemies
	if debug_enabled:
		draw_string(get_theme_default_font(), Vector2(6, 14), "Enemies:" + str(enemies.size()), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.8, 1, 0.8))
	var origin: Vector3 = aircraft.global_position
	# Use flat (top-down) axes so radar does not roll/pitch with aircraft
	var flat_forward: Vector3 = Vector3(aircraft.global_transform.basis.z.x, 0.0, aircraft.global_transform.basis.z.z)
	if flat_forward.length() < 0.001:
		flat_forward = Vector3(0, 0, 1)
	else:
		flat_forward = flat_forward.normalized()
	var flat_right: Vector3 = flat_forward.cross(Vector3.UP).normalized()
	var range_m: float = terrain_map_range_m

	# Background / terrain map
	_draw_terrain_map(center, radius, origin, flat_forward, range_m)

	# Use cached contact lists (rebuilt every CONTACT_CACHE_INTERVAL_S)
	var air_contacts: Array = _cached_air_contacts
	var ground_enemy_contacts: Array = _cached_ground_enemy_contacts
	var ground_friendly_contacts: Array = _cached_ground_friendly_contacts
	var ground_enemies: Array = _cached_ground_enemies

	var has_contacts: bool = air_contacts.size() > 0 or ground_enemies.size() > 0 or ground_enemy_contacts.size() > 0 or ground_friendly_contacts.size() > 0
	var carrier_nodes: Array = get_tree().get_nodes_in_group("carrier")
	var has_carrier: bool = carrier_nodes.size() > 0

	if not has_contacts and not has_carrier:
		var bars: Array = [Color.WHITE, Color(1,1,0), Color(0,1,1), Color(0,1,0), Color(1,0,1), Color(1,0,0), Color(0,0,1), Color.BLACK]
		var bar_w: float = (radius * 2.0) / float(bars.size())
		for i in range(bars.size()):
			var x0: float = center.x - radius + i * bar_w
			draw_rect(Rect2(Vector2(x0, center.y - radius), Vector2(bar_w, radius * 2.0)), bars[i])
		draw_arc(center, radius, 0, TAU, 64, Color(0.0, 0.6, 0.0), 2)
		return

	draw_arc(center, radius, 0, TAU, 64, Color(0.0, 0.6, 0.0), 2)

	# Draw carrier as oriented rectangle (matches tactical map color)
	var carrier_hud_color: Color = Livery.get_team_hud_color(Livery.PLAYER_TEAM_ID)
	if has_carrier:
		var carrier: Node3D = carrier_nodes[0] as Node3D
		if carrier and is_instance_valid(carrier):
			var rel_c: Vector3 = carrier.global_position - origin
			var cx: float = rel_c.dot(flat_right)
			var cz: float = rel_c.dot(flat_forward)
			var cdist: float = sqrt(cx*cx + cz*cz)
			if cdist <= range_m:
				var cpx: float = center.x + (cx / range_m) * radius
				var cpy: float = center.y - (cz / range_m) * radius
				var dot_r: float = 3.0
				var rect_w: float = dot_r * 4.0
				var rect_h: float = dot_r * 2.0
				var carrier_flat_forward: Vector3 = Vector3(carrier.global_transform.basis.z.x, 0.0, carrier.global_transform.basis.z.z)
				if carrier_flat_forward.length() < 0.001:
					carrier_flat_forward = Vector3(0, 0, 1)
				else:
					carrier_flat_forward = carrier_flat_forward.normalized()
				var dir2d: Vector2 = Vector2(
					carrier_flat_forward.dot(flat_right),
					-carrier_flat_forward.dot(flat_forward)
				)
				if dir2d.length() < 0.001:
					dir2d = Vector2(0, -1)
				else:
					dir2d = dir2d.normalized()
				dir2d = Vector2(-dir2d.y, dir2d.x)
				var right2d: Vector2 = Vector2(dir2d.y, -dir2d.x)
				var half_w: float = rect_w * 0.5
				var half_h: float = rect_h * 0.5
				var center_pt: Vector2 = Vector2(cpx, cpy)
				var p0: Vector2 = center_pt + (-right2d * half_w) + (-dir2d * half_h)
				var p1: Vector2 = center_pt + ( right2d * half_w) + (-dir2d * half_h)
				var p2: Vector2 = center_pt + ( right2d * half_w) + ( dir2d * half_h)
				var p3: Vector2 = center_pt + (-right2d * half_w) + ( dir2d * half_h)
				draw_polygon(PackedVector2Array([p0, p1, p2, p3]), PackedColorArray([carrier_hud_color]))
				draw_polyline(PackedVector2Array([p0, p1, p2, p3, p0]), Color(0.92, 0.98, 1.0, 1.0), 1.5)

	_draw_poi_markers(center, radius, origin, flat_right, flat_forward, range_m)

	# FOV cone lines
	var fov_cone_deg: float = 60.0
	if aircraft.has_method("find_child"):
		var targeting_module = aircraft.find_child("ControlTargeting", true, false)
		if targeting_module and "fov_cone_deg" in targeting_module:
			fov_cone_deg = targeting_module.fov_cone_deg
	var half_fov_rad: float = deg_to_rad(fov_cone_deg * 0.5)
	var cone_length: float = radius
	var left_angle: float = -half_fov_rad
	var left_end: Vector2 = center + Vector2(sin(left_angle), -cos(left_angle)) * cone_length
	draw_line(center, left_end, Color(0.0, 0.8, 0.0), 1)
	var right_angle: float = half_fov_rad
	var right_end: Vector2 = center + Vector2(sin(right_angle), -cos(right_angle)) * cone_length
	draw_line(center, right_end, Color(0.0, 0.8, 0.0), 1)

	var current_target: Node3D = null
	if aircraft.has_method("find_child"):
		var targeting_module = aircraft.find_child("ControlTargeting", true, false)
		if targeting_module and "current_target" in targeting_module:
			var raw_target = targeting_module.current_target
			if raw_target != null and is_instance_valid(raw_target) and not raw_target.is_queued_for_deletion():
				current_target = raw_target
			elif raw_target != null:
				targeting_module.current_target = null

	# Shared colors matching the tactical map (WorldMapSymbolLayer)
	var friendly_hud_color: Color = Livery.get_team_hud_color(Livery.PLAYER_TEAM_ID)
	var enemy_hud_color: Color = Livery.get_team_hud_color(2)

	# Draw aircraft contacts as heading-pointing triangles
	for ac in air_contacts:
		if not is_instance_valid(ac):
			continue
		var rel: Vector3 = ac.global_position - origin
		var bx: float = rel.dot(flat_right)
		var bz: float = rel.dot(flat_forward)
		var bdist: float = sqrt(bx * bx + bz * bz)
		if bdist > range_m:
			continue
		var bpx: float = center.x + (bx / range_m) * radius
		var bpy: float = center.y - (bz / range_m) * radius
		var blip_pos: Vector2 = Vector2(bpx, bpy)
		# Compute heading direction on radar
		var ac_flat_fwd: Vector3 = Vector3(ac.global_transform.basis.z.x, 0.0, ac.global_transform.basis.z.z)
		if ac_flat_fwd.length() < 0.001:
			ac_flat_fwd = Vector3(0, 0, 1)
		else:
			ac_flat_fwd = ac_flat_fwd.normalized()
		var heading_2d: Vector2 = Vector2(
			ac_flat_fwd.dot(flat_right),
			-ac_flat_fwd.dot(flat_forward)
		).normalized()
		var ac_team: int = int(ac.get_team()) if ac.has_method("get_team") else -1
		var tri_color: Color = enemy_hud_color if ac_team != team_id else friendly_hud_color
		_draw_heading_triangle(blip_pos, heading_2d, tri_color)
		if ac == current_target:
			draw_arc(blip_pos, 8, 0, TAU, 16, Color.WHITE, 2)

	# Draw ground contacts as coloured dots (buildings as filled squares)
	for e in ground_enemies + ground_enemy_contacts:
		if not is_instance_valid(e):
			continue
		var rel: Vector3 = e.global_position - origin
		var ex: float = rel.dot(flat_right)
		var ez: float = rel.dot(flat_forward)
		if sqrt(ex * ex + ez * ez) > range_m:
			continue
		var epx: float = center.x + (ex / range_m) * radius
		var epy: float = center.y - (ez / range_m) * radius
		if e is Building or e.is_in_group("buildings"):
			draw_rect(Rect2(epx - 4, epy - 4, 8, 8), enemy_hud_color)
		else:
			draw_circle(Vector2(epx, epy), 3, enemy_hud_color)
		if e == current_target:
			draw_arc(Vector2(epx, epy), 8, 0, TAU, 16, Color.WHITE, 2)

	for e in ground_friendly_contacts:
		if not is_instance_valid(e):
			continue
		var rel: Vector3 = e.global_position - origin
		var ex: float = rel.dot(flat_right)
		var ez: float = rel.dot(flat_forward)
		if sqrt(ex * ex + ez * ez) > range_m:
			continue
		var epx: float = center.x + (ex / range_m) * radius
		var epy: float = center.y - (ez / range_m) * radius
		draw_circle(Vector2(epx, epy), 3, friendly_hud_color)
		if e == current_target:
			draw_arc(Vector2(epx, epy), 8, 0, TAU, 16, Color.WHITE, 2)

	# Draw flight route (waypoints from HelicopterPilot or AIPilot)
	_draw_flight_route(center, radius, origin, flat_right, flat_forward, range_m)

	# Draw own aircraft at center, always pointing up (heading-up display).
	var own_color: Color = Livery.get_team_hud_color(team_id)
	_draw_heading_triangle(center, Vector2(0.0, -1.0), own_color)

func _draw_heading_triangle(pos: Vector2, heading: Vector2, color: Color) -> void:
	var tri_size: float = 8.0
	if heading.length() < 0.001:
		heading = Vector2(0, -1)
	else:
		heading = heading.normalized()
	var perp: Vector2 = Vector2(heading.y, -heading.x)
	var tip: Vector2 = pos + heading * tri_size
	var bl: Vector2 = pos - heading * tri_size * 0.5 + perp * tri_size * 0.52
	var br: Vector2 = pos - heading * tri_size * 0.5 - perp * tri_size * 0.52
	draw_polygon(PackedVector2Array([tip, bl, br]), PackedColorArray([color]))
	draw_polyline(PackedVector2Array([tip, bl, br, tip]), Color(1.0, 1.0, 1.0, 0.75), 1.0)

func _draw_poi_markers(center: Vector2, radius: float, origin: Vector3, flat_right: Vector3, flat_forward: Vector3, range_m: float) -> void:
	if not is_instance_valid(POIManager):
		return
	for marker: Dictionary in POIManager.get_discovered_map_markers():
		var poi_world: Vector3 = marker.get("position", Vector3.INF)
		if not is_finite(poi_world.x) or not is_finite(poi_world.y) or not is_finite(poi_world.z):
			continue
		var rel: Vector3 = poi_world - origin
		var px: float = rel.dot(flat_right)
		var pz: float = rel.dot(flat_forward)
		if sqrt(px * px + pz * pz) > range_m:
			continue
		var map_pos := Vector2(
			center.x + (px / range_m) * radius,
			center.y - (pz / range_m) * radius
		)
		var color := POI_USED_COLOR if bool(marker.get("revealed", false)) else POI_ACTIVE_COLOR
		_draw_poi_star(map_pos, 5.5, color)

func _draw_poi_star(center: Vector2, radius: float, color: Color) -> void:
	var points := PackedVector2Array()
	var inner := radius * 0.42
	for i in range(10):
		var angle := -PI * 0.5 + float(i) * (PI / 5.0)
		var r := radius if i % 2 == 0 else inner
		points.append(center + Vector2(cos(angle), sin(angle)) * r)
	draw_colored_polygon(points, color)
	draw_polyline(PackedVector2Array([
		points[0], points[1], points[2], points[3], points[4],
		points[5], points[6], points[7], points[8], points[9], points[0]
	]), Color(1.0, 1.0, 1.0, 0.35), 1.0)

func _rebuild_contact_cache() -> void:
	if provider == null or not is_instance_valid(provider):
		return
	var aircraft = provider.aircraft if ("aircraft" in provider) else null
	if aircraft == null or not is_instance_valid(aircraft):
		return
	var team_id: int = aircraft.get_team() if aircraft.has_method("get_team") else 1

	# Enemies from registry
	_cached_enemies.clear()
	var registry: Node = get_node_or_null("/root/EnemyRegistry")
	if registry and registry.has_method("get_enemies_for_team"):
		_cached_enemies = registry.get_enemies_for_team(1 if team_id != 1 else 2)
	if _cached_enemies.size() == 0:
		for e in get_tree().get_nodes_in_group("enemies"):
			if e and is_instance_valid(e) and e != aircraft:
				if e.has_method("get_team"):
					if int(e.get_team()) != team_id:
						_cached_enemies.append(e)
				else:
					_cached_enemies.append(e)

	# Air contacts
	_cached_air_contacts.clear()
	for group_name in ["aircraft", "ai_aircraft", "enemies"]:
		for node in get_tree().get_nodes_in_group(group_name):
			if node and is_instance_valid(node) and node != aircraft and node is RigidBody3D and not node.is_in_group("ground_vehicles"):
				if node not in _cached_air_contacts:
					_cached_air_contacts.append(node)

	# Ground contacts by team
	_cached_ground_enemy_contacts.clear()
	_cached_ground_friendly_contacts.clear()
	for node in get_tree().get_nodes_in_group("ground_vehicles"):
		if not node or not is_instance_valid(node) or not (node is Node3D):
			continue
		if not node.has_method("get_team"):
			continue
		if int(node.get_team()) == team_id:
			_cached_ground_friendly_contacts.append(node)
		else:
			_cached_ground_enemy_contacts.append(node)

	# Static ground enemies
	_cached_ground_enemies.clear()
	for e in _cached_enemies:
		if e and is_instance_valid(e) and not (e is RigidBody3D):
			_cached_ground_enemies.append(e)

func _ensure_terrain_map_cache() -> void:
	if _terrain_map_ready:
		return
	if not TerrainNavGrid.is_ready():
		return
	var span_x: float = float(TerrainNavGrid._cols - 1) * TerrainNavGrid.cell_size_m
	var span_z: float = float(TerrainNavGrid._rows - 1) * TerrainNavGrid.cell_size_m
	if span_x <= 1.0 or span_z <= 1.0:
		return
	_terrain_bounds_xz = Rect2(
		Vector2(TerrainNavGrid._origin_x, TerrainNavGrid._origin_z),
		Vector2(span_x, span_z)
	)
	var img := WorldMapTextureBuilder.build_image()
	if img == null:
		return
	_terrain_map_texture = ImageTexture.create_from_image(img)
	_terrain_map_ready = _terrain_map_texture != null

func _draw_terrain_map(center: Vector2, radius: float, origin: Vector3, flat_forward: Vector3, range_m: float) -> void:
	if not show_terrain_map or _terrain_map_texture == null or not _terrain_map_ready:
		return
	if not TerrainNavGrid.is_ready():
		return
	var span_x: float = float(TerrainNavGrid._cols - 1) * TerrainNavGrid.cell_size_m
	var span_z: float = float(TerrainNavGrid._rows - 1) * TerrainNavGrid.cell_size_m
	if span_x <= 1.0 or span_z <= 1.0:
		return
	var draw_radius: float = maxf(radius - TERRAIN_MAP_EDGE_INSET_PX, 1.0)
	var flat_right: Vector3 = flat_forward.cross(Vector3.UP)
	if flat_right.length_squared() < 0.0001:
		flat_right = Vector3.LEFT
	else:
		flat_right = flat_right.normalized()
	_draw_textured_world_circle_region(
		_terrain_map_texture,
		center,
		draw_radius,
		origin,
		flat_forward,
		flat_right,
		range_m,
		span_x,
		span_z,
		Color(1.0, 1.0, 1.0, terrain_map_opacity)
	)

func _draw_textured_world_circle_region(
	texture: Texture2D,
	center: Vector2,
	radius: float,
	origin: Vector3,
	flat_forward: Vector3,
	flat_right: Vector3,
	range_m: float,
	span_x: float,
	span_z: float,
	modulate: Color
) -> void:
	if texture == null:
		return
	var segments: int = 64
	var points: PackedVector2Array = PackedVector2Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	if texture.get_width() <= 0 or texture.get_height() <= 0:
		return
	var center_uv := _terrain_uv_for_radar_point(
		Vector2.ZERO,
		radius,
		origin,
		flat_forward,
		flat_right,
		range_m,
		span_x,
		span_z
	)
	for i in range(segments):
		var angle_a: float = -PI * 0.5 + (TAU * float(i) / float(segments))
		var angle_b: float = -PI * 0.5 + (TAU * float(i + 1) / float(segments))
		var local_a: Vector2 = Vector2(cos(angle_a), sin(angle_a)) * radius
		var local_b: Vector2 = Vector2(cos(angle_b), sin(angle_b)) * radius
		points = PackedVector2Array([center, center + local_a, center + local_b])
		uvs = PackedVector2Array([
			center_uv,
			_terrain_uv_for_radar_point(local_a, radius, origin, flat_forward, flat_right, range_m, span_x, span_z),
			_terrain_uv_for_radar_point(local_b, radius, origin, flat_forward, flat_right, range_m, span_x, span_z),
		])
		draw_colored_polygon(points, modulate, uvs, texture)

func _terrain_uv_for_radar_point(
	local_point: Vector2,
	radius: float,
	origin: Vector3,
	flat_forward: Vector3,
	flat_right: Vector3,
	range_m: float,
	span_x: float,
	span_z: float
) -> Vector2:
	var safe_radius: float = maxf(radius, 1.0)
	var world_offset_x: float = (local_point.x / safe_radius) * range_m
	var world_offset_z: float = (-local_point.y / safe_radius) * range_m
	var sample_world: Vector3 = origin + flat_right * world_offset_x + flat_forward * world_offset_z
	var u: float = (sample_world.x - TerrainNavGrid._origin_x) / span_x
	var v: float = (sample_world.z - TerrainNavGrid._origin_z) / span_z
	return Vector2(clampf(u, 0.0, 1.0), clampf(v, 0.0, 1.0))


# --- Flight route drawing ---------------------------------------------------

const ROUTE_COLOR: Color = Color(0.44, 0.86, 1.0, 0.9)  # Light blue, matches tactical map
const ROUTE_LINE_WIDTH: float = 1.6
const ROUTE_DOT_SIZE: float = 4.0
const ROUTE_SIMPLIFY_MIN_PX: float = 4.0  # Skip waypoints closer than this on screen

func _draw_flight_route(center: Vector2, radius: float, origin: Vector3,
		flat_right: Vector3, flat_forward: Vector3, range_m: float) -> void:
	if provider == null or not is_instance_valid(provider):
		return
	var ac = provider.aircraft if ("aircraft" in provider) else null
	if ac == null or not is_instance_valid(ac):
		return
	# Find a waypoint provider: HelicopterPilot first, then AIPilot
	var pilot: Node = ac.find_child("HelicopterPilot", true, false)
	if pilot == null:
		pilot = ac.find_child("AIPilot", true, false)
	if pilot == null or not pilot.has_method("get_active_waypoints"):
		return
	var waypoints: Array = pilot.get_active_waypoints()
	if waypoints.is_empty():
		return

	# Build screen-space polyline: start at own position (center), then each waypoint
	var map_points: PackedVector2Array = PackedVector2Array()
	map_points.append(center)  # Own aircraft is always at center
	for wp in waypoints:
		var screen_pt := _world_to_radar(wp, origin, flat_right, flat_forward, range_m, center, radius)
		# Skip points that are too close to the previous one (route simplification)
		if map_points.size() > 0 and screen_pt.distance_to(map_points[map_points.size() - 1]) < ROUTE_SIMPLIFY_MIN_PX:
			continue
		map_points.append(screen_pt)

	if map_points.size() < 2:
		return

	# Draw route line
	draw_polyline(map_points, ROUTE_COLOR, ROUTE_LINE_WIDTH, true)

	# Draw square markers at each waypoint (skip index 0 which is own position)
	for i in range(1, map_points.size()):
		_draw_square_marker(map_points[i], ROUTE_DOT_SIZE, ROUTE_COLOR)

func _world_to_radar(world_pos: Vector3, origin: Vector3, flat_right: Vector3,
		flat_forward: Vector3, range_m: float, center: Vector2, radius: float) -> Vector2:
	var rel: Vector3 = world_pos - origin
	var rx: float = rel.dot(flat_right)
	var rz: float = rel.dot(flat_forward)
	return Vector2(
		center.x + (rx / range_m) * radius,
		center.y - (rz / range_m) * radius
	)

func _draw_square_marker(pos: Vector2, size_px: float, color: Color) -> void:
	var half: float = size_px * 0.5
	draw_rect(Rect2(pos.x - half, pos.y - half, size_px, size_px), color)
	draw_rect(Rect2(pos.x - half, pos.y - half, size_px, size_px), Color(1.0, 1.0, 1.0, 0.5), false, 1.0)

