extends Control

var provider: Node = null
var debug_enabled: bool = false
@export var show_terrain_map: bool = true
@export var terrain_map_resolution: int = 192
@export var terrain_map_opacity: float = 0.72
@export var terrain_map_range_m: float = 5000.0
@export var terrain_map_cliff_threshold_m: float = 10.0
@export var terrain_map_cliff_edge_strength: float = 0.95

var _terrain_node: Node3D = null
var _terrain_bounds_xz: Rect2 = Rect2()
var _terrain_map_texture: ImageTexture = null
var _terrain_map_ready: bool = false

func set_provider(p: Node) -> void:
	provider = p
	queue_redraw()

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	if provider == null or not is_instance_valid(provider):
		return
	# Expect provider to expose aircraft and EnemyRegistry singleton
	var size: Vector2 = get_size()
	var center: Vector2 = size * 0.5
	var radius: float = min(size.x, size.y) * 0.48
	var aircraft = provider.aircraft if ("aircraft" in provider) else null
	if show_terrain_map:
		_ensure_terrain_map_cache()
	if aircraft == null or not is_instance_valid(aircraft):
		draw_circle(center, radius, Color(0.02, 0.06, 0.02))
		return
	var team_id: int = aircraft.get_team() if aircraft.has_method("get_team") else 1
	var enemies: Array = []
	var registry: Node = get_node_or_null("/root/EnemyRegistry")
	if registry and registry.has_method("get_enemies_for_team"):
		enemies = registry.get_enemies_for_team(1 if team_id != 1 else 2)
	# Fallback to scene group if registry is missing/empty
	if enemies.size() == 0:
		var group_nodes: Array = get_tree().get_nodes_in_group("enemies")
		for e in group_nodes:
			if e and is_instance_valid(e) and e != aircraft:
				if e.has_method("get_team"):
					if int(e.get_team()) != team_id:
						enemies.append(e)
				else:
					# If no team method, assume hostile
					enemies.append(e)
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
	var radar_bg: Color = Color(0.02, 0.06, 0.02)
	draw_circle(center, radius, radar_bg)
	_draw_terrain_map(center, radius, origin, flat_forward, range_m)
	_draw_outside_circle_mask(center, radius, radar_bg)

	# Collect airborne contacts (aircraft only, not ground vehicles)
	var air_contacts: Array = []
	for group_name in ["aircraft", "ai_aircraft", "enemies"]:
		for node in get_tree().get_nodes_in_group(group_name):
			if node and is_instance_valid(node) and node != aircraft and node is RigidBody3D and not node.is_in_group("ground_vehicles"):
				if node not in air_contacts:
					air_contacts.append(node)

	# Collect ground vehicle contacts by team
	var ground_enemy_contacts: Array = []
	var ground_friendly_contacts: Array = []
	for node in get_tree().get_nodes_in_group("ground_vehicles"):
		if not node or not is_instance_valid(node) or not (node is Node3D):
			continue
		if not node.has_method("get_team"):
			continue
		if int(node.get_team()) == team_id:
			ground_friendly_contacts.append(node)
		else:
			ground_enemy_contacts.append(node)

	# Static ground enemies (non-RigidBody3D, e.g. legacy EnemyBox)
	var ground_enemies: Array = []
	for e in enemies:
		if e and is_instance_valid(e) and not (e is RigidBody3D):
			ground_enemies.append(e)

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

	# Draw carrier as oriented blue rectangle
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
				draw_polygon(PackedVector2Array([p0, p1, p2, p3]), PackedColorArray([Color(0.2, 0.4, 1.0)]))
				draw_polyline(PackedVector2Array([p0, p1, p2, p3, p0]), Color(0.5, 0.7, 1.0), 1.0)

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

	# Draw aircraft contacts as heading-pointing triangles (blue=friendly, red=enemy)
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
		var tri_color: Color = Color(1.0, 0.2, 0.2) if ac_team != team_id else Color(0.3, 0.6, 1.0)
		_draw_heading_triangle(blip_pos, heading_2d, tri_color)
		if ac == current_target:
			draw_arc(blip_pos, 8, 0, TAU, 16, Color.WHITE, 2)

	# Draw ground contacts as coloured dots
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
		draw_circle(Vector2(epx, epy), 3, Color.RED)
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
		draw_circle(Vector2(epx, epy), 3, Color(0.3, 0.6, 1.0))
		if e == current_target:
			draw_arc(Vector2(epx, epy), 8, 0, TAU, 16, Color.WHITE, 2)

func _draw_heading_triangle(pos: Vector2, heading: Vector2, color: Color) -> void:
	var tri_size: float = 5.0
	if heading.length() < 0.001:
		heading = Vector2(0, -1)
	else:
		heading = heading.normalized()
	var perp: Vector2 = Vector2(heading.y, -heading.x)
	var tip: Vector2 = pos + heading * tri_size
	var bl: Vector2 = pos - heading * tri_size * 0.5 + perp * tri_size * 0.5
	var br: Vector2 = pos - heading * tri_size * 0.5 - perp * tri_size * 0.5
	draw_polygon(PackedVector2Array([tip, bl, br]), PackedColorArray([color]))

func _ensure_terrain_map_cache() -> void:
	if _terrain_map_ready:
		return
	var terrain := get_tree().get_first_node_in_group("terrain_provider") as Node3D
	if terrain == null or not is_instance_valid(terrain):
		return
	if not terrain.has_method("get_height"):
		return
	var quads_x_value = terrain.get("quads_x")
	var quads_z_value = terrain.get("quads_z")
	var cell_size_value = terrain.get("cell_size_m")
	if typeof(quads_x_value) not in [TYPE_INT, TYPE_FLOAT] or typeof(quads_z_value) not in [TYPE_INT, TYPE_FLOAT] or typeof(cell_size_value) not in [TYPE_INT, TYPE_FLOAT]:
		return
	var quads_x: int = int(quads_x_value)
	var quads_z: int = int(quads_z_value)
	var cell_size_m: float = float(cell_size_value)
	var span_x: float = float(quads_x) * cell_size_m
	var span_z: float = float(quads_z) * cell_size_m
	_terrain_node = terrain
	_terrain_bounds_xz = Rect2(
		Vector2(terrain.global_position.x - span_x * 0.5, terrain.global_position.z - span_z * 0.5),
		Vector2(span_x, span_z)
	)
	_terrain_map_texture = _build_terrain_map_texture(terrain, _terrain_bounds_xz, max(terrain_map_resolution, 32))
	_terrain_map_ready = _terrain_map_texture != null

func _build_terrain_map_texture(terrain: Node3D, bounds_xz: Rect2, resolution: int) -> ImageTexture:
	var heights: PackedFloat32Array = PackedFloat32Array()
	heights.resize(resolution * resolution)
	var min_h: float = INF
	var max_h: float = -INF
	var terrain_y: float = terrain.global_position.y
	for y in range(resolution):
		var vz: float = 1.0 - (float(y) / float(max(resolution - 1, 1)))
		var world_z: float = lerpf(bounds_xz.position.y, bounds_xz.position.y + bounds_xz.size.y, vz)
		for x in range(resolution):
			var ux: float = float(x) / float(max(resolution - 1, 1))
			var world_x: float = lerpf(bounds_xz.position.x, bounds_xz.position.x + bounds_xz.size.x, ux)
			var sample_h: float = float(terrain.call("get_height", Vector3(world_x, terrain_y, world_z)))
			if is_nan(sample_h):
				sample_h = terrain_y
			var idx: int = y * resolution + x
			heights[idx] = sample_h
			min_h = minf(min_h, sample_h)
			max_h = maxf(max_h, sample_h)
	if max_h - min_h < 0.001:
		max_h = min_h + 1.0

	var img := Image.create(resolution, resolution, false, Image.FORMAT_RGBA8)
	for y in range(resolution):
		for x in range(resolution):
			var idx: int = y * resolution + x
			var h01: float = clampf((heights[idx] - min_h) / (max_h - min_h), 0.0, 1.0)
			var shade: float = 0.12 + h01 * 0.52
			var left_h: float = heights[y * resolution + maxi(x - 1, 0)]
			var right_h: float = heights[y * resolution + mini(x + 1, resolution - 1)]
			var up_h: float = heights[maxi(y - 1, 0) * resolution + x]
			var down_h: float = heights[mini(y + 1, resolution - 1) * resolution + x]
			var local_relief_m: float = maxf(absf(right_h - left_h), absf(down_h - up_h))
			var cliff_edge: float = clampf((local_relief_m - terrain_map_cliff_threshold_m) / maxf(terrain_map_cliff_threshold_m, 0.001), 0.0, 1.0)
			var edge_darkening: float = cliff_edge * terrain_map_cliff_edge_strength
			var col := Color(0.02 + shade * 0.20, 0.10 + shade * 0.75, 0.03 + shade * 0.22, 1.0)
			col.r = maxf(col.r - edge_darkening * 0.16, 0.0)
			col.g = maxf(col.g - edge_darkening * 0.42, 0.0)
			col.b = maxf(col.b - edge_darkening * 0.14, 0.0)
			img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)

func _draw_terrain_map(center: Vector2, radius: float, origin: Vector3, flat_forward: Vector3, range_m: float) -> void:
	if not show_terrain_map or _terrain_map_texture == null or not _terrain_map_ready:
		return
	if _terrain_bounds_xz.size.x <= 1.0 or _terrain_bounds_xz.size.y <= 1.0:
		return
	var tex_size: Vector2 = Vector2(_terrain_map_texture.get_width(), _terrain_map_texture.get_height())
	var origin_u: float = (origin.x - _terrain_bounds_xz.position.x) / _terrain_bounds_xz.size.x
	var origin_v: float = (origin.z - _terrain_bounds_xz.position.y) / _terrain_bounds_xz.size.y
	var half_u: float = range_m / _terrain_bounds_xz.size.x
	var half_v: float = range_m / _terrain_bounds_xz.size.y
	var region_left: float = clampf(origin_u - half_u, 0.0, 1.0)
	var region_right: float = clampf(origin_u + half_u, 0.0, 1.0)
	var region_top: float = clampf((1.0 - origin_v) - half_v, 0.0, 1.0)
	var region_bottom: float = clampf((1.0 - origin_v) + half_v, 0.0, 1.0)
	var region := Rect2(
		Vector2(region_left * tex_size.x, region_top * tex_size.y),
		Vector2(maxf((region_right - region_left) * tex_size.x, 1.0), maxf((region_bottom - region_top) * tex_size.y, 1.0))
	)
	var heading_rad: float = atan2(flat_forward.x, flat_forward.z)
	# Contacts are projected in a mirrored horizontal basis, so the terrain slice
	# needs the same mirror but the opposite rotation sign to stay heading-up.
	draw_set_transform(center, -heading_rad, Vector2(-1.0, 1.0))
	draw_texture_rect_region(
		_terrain_map_texture,
		Rect2(Vector2(-radius, -radius), Vector2(radius * 2.0, radius * 2.0)),
		region,
		Color(1.0, 1.0, 1.0, terrain_map_opacity)
	)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw_outside_circle_mask(center: Vector2, radius: float, color: Color) -> void:
	var steps: int = 32
	var top_poly: PackedVector2Array = PackedVector2Array()
	top_poly.append(center + Vector2(-radius, -radius))
	top_poly.append(center + Vector2(radius, -radius))
	for i in range(steps, -1, -1):
		var t: float = float(i) / float(steps)
		var angle: float = lerpf(PI, TAU, t)
		top_poly.append(center + Vector2(cos(angle), sin(angle)) * radius)
	draw_colored_polygon(top_poly, color)

	var bottom_poly: PackedVector2Array = PackedVector2Array()
	bottom_poly.append(center + Vector2(radius, radius))
	bottom_poly.append(center + Vector2(-radius, radius))
	for i in range(steps, -1, -1):
		var t: float = float(i) / float(steps)
		var angle: float = lerpf(0.0, PI, t)
		bottom_poly.append(center + Vector2(cos(angle), sin(angle)) * radius)
	draw_colored_polygon(bottom_poly, color)
