extends Control

var provider: Node = null
var debug_enabled: bool = false

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
	# Background
	draw_circle(center, radius, Color(0.02, 0.06, 0.02))
	var aircraft = provider.aircraft if ("aircraft" in provider) else null
	if aircraft == null or not is_instance_valid(aircraft):
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
	var range_m: float = 5000.0

	# Collect airborne contacts (any aircraft that isn't the player)
	var air_contacts: Array = []
	for node in get_tree().get_nodes_in_group("aircraft"):
		if node and is_instance_valid(node) and node != aircraft and node is RigidBody3D:
			air_contacts.append(node)
	for node in get_tree().get_nodes_in_group("enemies"):
		if node and is_instance_valid(node) and node != aircraft and node is RigidBody3D:
			if node not in air_contacts:
				air_contacts.append(node)

	# Collect ground enemies (non-aircraft from enemies list)
	var ground_enemies: Array = []
	for e in enemies:
		if e and is_instance_valid(e) and not (e is RigidBody3D):
			ground_enemies.append(e)

	var has_contacts: bool = air_contacts.size() > 0 or ground_enemies.size() > 0
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

	# Draw aircraft contacts as blue heading-pointing triangles
	var tri_color: Color = Color(0.3, 0.6, 1.0)
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
		_draw_heading_triangle(blip_pos, heading_2d, tri_color)
		if ac == current_target:
			draw_arc(blip_pos, 8, 0, TAU, 16, Color.WHITE, 2)

	# Draw ground enemies as red dots
	for e in ground_enemies:
		if not is_instance_valid(e):
			continue
		var rel: Vector3 = e.global_position - origin
		var ex: float = rel.dot(flat_right)
		var ez: float = rel.dot(flat_forward)
		var edist: float = sqrt(ex * ex + ez * ez)
		if edist > range_m:
			continue
		var epx: float = center.x + (ex / range_m) * radius
		var epy: float = center.y - (ez / range_m) * radius
		draw_circle(Vector2(epx, epy), 3, Color.RED)
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
