extends RefCounted

## Bounded shoot-and-scoot candidate search, not a dynamic flight predictor.
## Both the escape chord and target exclusion are checked. Cover means terrain
## interrupts the sightline from THIS target; other threats may still see us.
static func choose(start: Vector3, target: Vector3, attack_dir: Vector3, distance_m: float,
		clearance: float, height: Callable) -> Dictionary:
	var dir := Vector3(attack_dir.x, 0, attack_dir.z).normalized()
	if dir.length_squared() < 0.5: return {}
	var right := Vector3.UP.cross(dir)
	var best := {}
	var best_score := -INF
	for side in [-1.0, 1.0]:
		for back in [0.0, 0.5, 1.0]:
			var end: Vector3 = start + (right * float(side) - dir * float(back)).normalized() * distance_m
			var ground := float(height.call(end))
			if not is_finite(ground): continue
			end.y = ground + clearance + 15.0
			if not segment_clear(start, end, clearance, height): continue
			# Reject a chord that cuts through/over the target even if its endpoint
			# happens to be behind a useful hill.
			if closest_range(start, end, target) < 120.0: continue
			var covered := terrain_occludes(target + Vector3.UP * 4.0, end, height)
			var score: float = (2000.0 if covered else 0.0) + end.distance_to(target) * 0.1 - absf(end.y - start.y)
			if score > best_score:
				best_score = score
				best = {"position": end, "covered": covered}
	return best

static func closest_range(a: Vector3, b: Vector3, target: Vector3) -> float:
	var ab := Vector2(b.x - a.x, b.z - a.z)
	var at := Vector2(target.x - a.x, target.z - a.z)
	var t := clampf(at.dot(ab) / maxf(ab.length_squared(), 0.001), 0, 1)
	return (at - ab * t).length()

static func segment_clear(a: Vector3, b: Vector3, clearance: float, height: Callable) -> bool:
	var steps := maxi(2, int(ceil(a.distance_to(b) / 30.0)))
	for i in range(steps + 1):
		var point := a.lerp(b, float(i) / steps)
		var ground := float(height.call(point))
		if not is_finite(ground) or point.y < ground + clearance: return false
	return true

static func terrain_occludes(a: Vector3, b: Vector3, height: Callable) -> bool:
	var steps := maxi(2, int(ceil(a.distance_to(b) / 30.0)))
	for i in range(1, steps):
		var point := a.lerp(b, float(i) / steps)
		var ground := float(height.call(point))
		if not is_finite(ground): return false
		if ground > point.y + 3.0: return true
	return false
