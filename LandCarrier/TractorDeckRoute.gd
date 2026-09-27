extends RefCounted

# A small visibility graph for deck robots. Swept discs prevent tunnelling;
# octagonal detours leave clearance even between adjacent graph vertices.
static func segment_clear(start: Vector3, finish: Vector3, obstacles: Array[Vector3]) -> bool:
	var a := Vector2(start.x, start.z)
	var b := Vector2(finish.x, finish.z)
	for obstacle in obstacles:
		var center := Vector2(obstacle.x, obstacle.z)
		var closest := Geometry2D.get_closest_point_to_segment(center, a, b)
		if closest.distance_to(center) < obstacle.y - 0.001:
			# An authored/spawn overlap may only move strictly outward.
			if a.distance_to(center) < obstacle.y and b.distance_to(center) > a.distance_to(center) + 0.00001 and (b - a).dot(a - center) >= 0.0:
				continue
			return false
	return true

static func plan(start: Vector3, finish: Vector3, obstacles: Array[Vector3]) -> Array[Vector3]:
	if segment_clear(start, finish, obstacles): return [finish]
	var points: Array[Vector3] = [start, finish]
	for obstacle in obstacles:
		for index in 8:
			var angle := TAU * float(index) / 8.0
			var radius := (obstacle.y + 0.12) / cos(PI / 8.0)
			var point := Vector3(obstacle.x + cos(angle) * radius, finish.y, obstacle.z + sin(angle) * radius)
			if segment_clear(point, point, obstacles): points.append(point)
	var costs: Array[float] = []
	var previous: Array[int] = []
	var visited: Array[bool] = []
	for point in points:
		costs.append(INF)
		previous.append(-1)
		visited.append(false)
	costs[0] = 0.0
	for iteration in points.size():
		var best := -1
		var cost := INF
		for index in points.size():
			if not visited[index] and costs[index] < cost:
				best = index
				cost = costs[index]
		if best < 0: break
		if best == 1:
			var route: Array[Vector3] = []
			while best != 0:
				route.push_front(points[best])
				best = previous[best]
			return route
		visited[best] = true
		for index in points.size():
			if visited[index]: continue
			var next_cost := cost + points[best].distance_to(points[index])
			if next_cost < costs[index] and segment_clear(points[best], points[index], obstacles):
				costs[index] = next_cost
				previous[index] = best
	return []
