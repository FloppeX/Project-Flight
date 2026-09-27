extends SceneTree

const TERRAIN = preload("res://Environment/LowPolyTerrain.gd")
var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for child in root.get_children():
		child.process_mode = Node.PROCESS_MODE_DISABLED
	for service in ["EnemyBaseManager", "EnemyOpsManager"]:
		root.get_node(service).set("_disabled_for_test", true)
	var grid := root.get_node("TerrainNavGrid")
	var graph := root.get_node("NavGraph")
	grid.process_mode = Node.PROCESS_MODE_INHERIT
	graph.process_mode = Node.PROCESS_MODE_INHERIT
	grid.disk_cache_enabled = false
	grid.bake_half_extent_m = 6000.0
	grid.query_grid_enabled = true
	grid.rows_per_frame = 24
	var terrain := TERRAIN.new()
	terrain.generate_on_ready = false
	terrain.seed = 22551
	terrain.cell_size_m = 36.0
	terrain.plateau_height_m = 500.0
	terrain.base_height_offset_m = 220.0
	terrain.set_map_profile("canyon_highlands")
	root.add_child(terrain)
	terrain.set_process(false)
	terrain.get_surface_color(Vector3.ZERO)
	_expect(terrain._highlands_ramps.size() == 9, "expected one pass in each of nine districts")
	var reports: Array[Dictionary] = []
	for centre in [Vector3.ZERO, Vector3(-12500, 0, -12500), Vector3(12500, 0, -12500), Vector3(-12500, 0, 12500), Vector3(12500, 0, 12500), Vector3(0, 0, -16000), Vector3(0, 0, 16000), Vector3(-16000, 0, 0), Vector3(16000, 0, 0)]:
		grid.rebake_at_center(centre)
		graph.reset_until_navgrid_bakes()
		var started := Time.get_ticks_msec()
		while not graph.is_ready():
			if Time.get_ticks_msec() - started > 90000:
				push_error("Regional navigation timeout")
				quit(1)
				return
			await process_frame
		# Select real natural valley anchors near each district edge, rather than
		# assuming a road at prescribed coordinates.
		var carrier_targets: Array[Vector3] = []
		for side in ["bottom", "top", "left", "right"]:
			var target := Vector3.ZERO
			var best := INF
			for lateral in range(-3200, 3201, 160):
				for inward in [0.0, 320.0, 640.0, 960.0]:
					var offset := Vector3(lateral, 0, 3550.0 - inward)
					if side == "top": offset.z = -offset.z
					if side == "left": offset = Vector3(-offset.z, 0, lateral)
					if side == "right": offset = Vector3(offset.z, 0, lateral)
					var point: Vector3 = centre + offset
					var score: float = absf(lateral) + inward
					if score >= best or not grid.is_low_clear_position(point.x, point.z, 12.0): continue
					if not grid.is_stable_footprint(point.x, point.z, 320.0, 30.0, 30.0): continue
					point.y = terrain.get_height(point)
					if not graph.can_anchor(point, 80.0): continue
					best = score
					target = point
			_expect(target != Vector3.ZERO, "district has no carrier valley at %s edge: %s" % [side, centre])
			if target != Vector3.ZERO:
				carrier_targets.append(target)
				_expect(grid.is_low_clear_position(target.x, target.z, 12.0), "carrier baseline rejected by low-ground filter")
				_expect(grid.is_stable_footprint(target.x, target.z, 320.0, 30.0, 30.0), "carrier valley footprint too narrow")
		for i in range(1, carrier_targets.size()):
			var carrier_path: Array = graph.find_path(carrier_targets[0], carrier_targets[i], 80.0)
			_expect(carrier_path.size() > 2, "carrier cannot cross natural district %s toward side %d" % [centre, i])
		print("HIGHLANDS_CARRIER_DISTRICT ", centre)
		for ramp in terrain._highlands_ramps:
			var a: Vector3 = ramp.start
			var b: Vector3 = ramp.end
			if maxf(absf(a.x - centre.x), absf(a.z - centre.z)) > 3800.0:
				continue
			a.y = terrain.get_height(a)
			b.y = terrain.get_height(b)
			var path_check: Array = graph.find_path(a, b, 0.0)
			var maximum_grade := 0.0
			var previous := a
			for step in range(1, 401):
				var p := a.lerp(b, step / 400.0)
				p.y = terrain.get_height(p)
				maximum_grade = maxf(maximum_grade, rad_to_deg(atan2(absf(p.y - previous.y), Vector2(p.x - previous.x, p.z - previous.z).length())))
				previous = p
			_expect(path_check.size() >= 2, "district pass does not connect its actual endpoints: %s" % centre)
			_expect(maximum_grade <= 20.0, "pass centreline too steep: %s" % centre)
			var middle := a.lerp(b, 0.5)
			middle.y = terrain.get_height(middle)
			_expect(terrain.get_navigation_clearance_cap(middle.x, middle.z) == 40.0, "pass lost carrier exclusion")
			_expect(not graph.can_anchor(middle, 80.0), "carrier can enter a small-vehicle pass")
			print("HIGHLANDS_PASS ", centre, " grade=", maximum_grade, " points=", path_check.size())
		var nodes: PackedVector3Array = graph._nodes
		var starts: PackedInt32Array = graph._edge_starts
		var neighbors: PackedInt32Array = graph._edge_nb
		var visited := PackedByteArray()
		visited.resize(nodes.size())
		var biggest := 0
		var best_climb := 0.0
		var low_index := -1
		var high_index := -1
		for node in nodes.size():
			if visited[node]:
				continue
			var queue := PackedInt32Array([node])
			visited[node] = 1
			var cursor := 0
			var low := node
			var high := node
			while cursor < queue.size():
				var current := queue[cursor]
				cursor += 1
				if nodes[current].y < nodes[low].y:
					low = current
				if nodes[current].y > nodes[high].y:
					high = current
				for edge in range(starts[current], starts[current + 1]):
					var next := neighbors[edge]
					if not visited[next]:
						visited[next] = 1
						queue.append(next)
			var span := nodes[high].y - nodes[low].y
			var starts_on_floor := nodes[low].y - 420.0 - terrain.HighlandsProfile.floor_relief(nodes[low].x, nodes[low].z) < 40.0
			if queue.size() > 40 and starts_on_floor and span > best_climb:
				best_climb = span
				biggest = queue.size()
				low_index = low
				high_index = high
		_expect(low_index >= 0, "region has no ground routes")
		if low_index < 0:
			continue
		var path: Array = graph.find_path(nodes[low_index], nodes[high_index], 0.0)
		var climb := nodes[high_index].y - nodes[low_index].y
		_expect(climb > 140.0 and path.size() >= 2, "region %s has no connected elevated route: %.1f m" % [centre, climb])
		var grade := 0.0
		var steepest_point := Vector3.ZERO
		for i in range(1, path.size()):
			var a: Vector3 = path[i - 1]
			var b: Vector3 = path[i]
			var steps := maxi(1, int(ceil(Vector2(b.x - a.x, b.z - a.z).length() / 12.0)))
			var previous := a
			previous.y = terrain.get_height(previous)
			for j in range(1, steps + 1):
				var p := a.lerp(b, float(j) / steps)
				p.y = terrain.get_height(p)
				var measured := rad_to_deg(atan2(absf(p.y - previous.y), Vector2(p.x - previous.x, p.z - previous.z).length()))
				if measured > grade:
					grade = measured
					steepest_point = p
				previous = p
		_expect(grade <= 20.0, "region %s route crosses excessive actual grade %.2f" % [centre, grade])
		reports.append({"centre": str(centre), "connected_nodes": biggest, "climb_m": climb, "actual_grade": grade, "steepest_point": str(steepest_point), "path_points": path.size()})
		print("HIGHLANDS_REGION_NAV ", JSON.stringify(reports.back()))
	print("HIGHLANDS_REGIONAL_NAVIGATION ", JSON.stringify({"status": "PASS" if failures.is_empty() else "FAIL", "regions": reports, "failures": failures}))
	terrain.queue_free()
	quit(0 if failures.is_empty() else 1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)


