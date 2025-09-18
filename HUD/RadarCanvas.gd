extends Control

var provider: Node = null
var debug_enabled: bool = true

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
	if enemies.size() == 0:
		# Draw color bars test pattern under ring
		var bars: Array = [Color.WHITE, Color(1,1,0), Color(0,1,1), Color(0,1,0), Color(1,0,1), Color(1,0,0), Color(0,0,1), Color.BLACK]
		var bar_w: float = (radius * 2.0) / float(bars.size())
		for i in range(bars.size()):
			var x0: float = center.x - radius + i * bar_w
			draw_rect(Rect2(Vector2(x0, center.y - radius), Vector2(bar_w, radius * 2.0)), bars[i])
		# Ring
		draw_arc(center, radius, 0, TAU, 64, Color(0.0, 0.6, 0.0), 2)
		return
	# Ring
	draw_arc(center, radius, 0, TAU, 64, Color(0.0, 0.6, 0.0), 2)
	
	# Center dot (aircraft position)
	draw_circle(center, 2, Color.WHITE)
	
	# FOV cone lines (get FOV from targeting system)
	var fov_cone_deg: float = 60.0  # Default value
	if aircraft.has_method("find_child"):
		var targeting_module = aircraft.find_child("ControlTargeting", true, false)
		if targeting_module and "fov_cone_deg" in targeting_module:
			fov_cone_deg = targeting_module.fov_cone_deg
	
	# Draw FOV cone lines
	var half_fov_rad: float = deg_to_rad(fov_cone_deg * 0.5)
	var cone_length: float = radius  # Full radius to edge of circle
	
	# Left cone line
	var left_angle: float = -half_fov_rad
	var left_end: Vector2 = center + Vector2(sin(left_angle), -cos(left_angle)) * cone_length
	draw_line(center, left_end, Color(0.0, 0.8, 0.0), 1)
	
	# Right cone line  
	var right_angle: float = half_fov_rad
	var right_end: Vector2 = center + Vector2(sin(right_angle), -cos(right_angle)) * cone_length
	draw_line(center, right_end, Color(0.0, 0.8, 0.0), 1)
	
	# Get current target from targeting system with extra safety
	var current_target: Node3D = null
	if aircraft.has_method("find_child"):
		var targeting_module = aircraft.find_child("ControlTargeting", true, false)
		if targeting_module and "current_target" in targeting_module:
			var raw_target = targeting_module.current_target
			# Multiple safety checks
			if raw_target != null and is_instance_valid(raw_target) and not raw_target.is_queued_for_deletion():
				current_target = raw_target
			elif raw_target != null:
				# Clear invalid target in targeting module
				targeting_module.current_target = null
	
	for e in enemies:
		if e and is_instance_valid(e):
			var rel: Vector3 = e.global_position - origin
			# Project onto horizontal plane using flat axes
			var x: float = rel.dot(flat_right)
			var z: float = rel.dot(flat_forward)
			var dist: float = sqrt(x*x + z*z)
			if dist <= range_m:
				var px: float = center.x + (x / range_m) * radius
				var py: float = center.y - (z / range_m) * radius
				
				# Draw enemy dot
				draw_circle(Vector2(px, py), 3, Color.RED)
				
				# Draw white circle around current target
				if e == current_target:
					draw_arc(Vector2(px, py), 8, 0, TAU, 16, Color.WHITE, 2)
