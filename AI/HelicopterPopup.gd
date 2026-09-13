extends RefCounted

const Escape = preload("res://AI/HelicopterEscape.gd")
enum Phase { APPROACH, RISE, FIRE, DESCEND, RELOCATE }
var phase := Phase.APPROACH
var elapsed := 0.0
var plan: Dictionary = {}
var reason := ""

func begin(value: Dictionary) -> void:
	plan = value
	reason = ""
	set_phase(Phase.APPROACH)

func set_phase(value: Phase) -> void:
	phase = value
	elapsed = 0.0

func shift(offset: Vector3) -> void:
	for key in ["hide", "fire", "relocate", "target"]:
		if plan.has(key): plan[key] -= offset

## Terrain footprint and visibility tests are separate. Low points must hide
## the rotor/top of the aircraft, not merely its origin. NaNs fail closed.
static func footprint_floor(point: Vector3, height: Callable) -> float:
	var highest := -INF
	for offset in [Vector3.ZERO, Vector3(20,0,0), Vector3(-20,0,0), Vector3(0,0,20), Vector3(0,0,-20)]:
		var ground := float(height.call(point + offset))
		if not is_finite(ground): return INF
		highest = maxf(highest, ground)
	return highest

static func firing_line_clear(from: Vector3, target: Vector3, height: Callable) -> bool:
	# Leave a short terminal allowance for a target resting on the ground. Real
	# weapon CCIP remains the release authority, not this geometric sightline.
	var steps := maxi(2, int(ceil(from.distance_to(target) / 15.0)))
	for i in range(steps):
		var p := from.lerp(target, float(i) / steps)
		var ground := float(height.call(p))
		if not is_finite(ground) or ground + 2.0 >= p.y: return false
	return true

static func hidden(point: Vector3, target: Vector3, height: Callable) -> bool:
	return Escape.terrain_occludes(target + Vector3.UP * 4, point + Vector3.UP * 12, height)

static func concealed_route(a: Vector3, b: Vector3, target: Vector3, height: Callable) -> bool:
	for i in range(9):
		var p := a.lerp(b, float(i) / 8)
		if footprint_floor(p, height) + 30 > p.y or not hidden(p, target, height): return false
	return true

static func choose(current: Vector3, target: Vector3, range_m: float, low_agl: float,
		max_rise: float, height: Callable, last_site: Vector3 = Vector3.INF) -> Dictionary:
	var dir := Vector3(target.x-current.x, 0, target.z-current.z).normalized()
	if dir.length_squared() < 0.5: return {}
	var right := Vector3.UP.cross(dir)
	var best: Dictionary = {}
	var score_best := INF
	# Local search only; no large orbit to manufacture a pop-up opportunity.
	for lateral in [0.0, -180.0, 180.0, -360.0, 360.0]:
		var hide: Vector3 = current + right * float(lateral)
		var ground := footprint_floor(hide, height)
		if not is_finite(ground): continue
		hide.y = ground + maxf(low_agl, 50.0)
		if last_site != Vector3.INF and Vector2(hide.x-last_site.x, hide.z-last_site.z).length() < 120: continue
		if hide.distance_to(target) > range_m * 0.9 or hide.distance_to(target) < 250: continue
		if not hidden(hide, target, height): continue
		var fire := Vector3.INF
		for rise in range(16, int(max_rise) + 1, 8):
			var candidate := hide + Vector3.UP * rise
			if candidate.distance_to(target) > range_m: break
			if firing_line_clear(candidate, target, height):
				fire = candidate
				break
		if fire == Vector3.INF: continue
		var relocate := Vector3.INF
		for side in [-1.0, 1.0]:
			var next: Vector3 = hide + right * float(side) * 180.0
			next.y = footprint_floor(next, height) + maxf(low_agl, 50.0)
			if is_finite(next.y) and concealed_route(hide, next, target, height):
				relocate = next
				break
		if relocate == Vector3.INF: continue
		var score := current.distance_to(hide) + (fire.y-hide.y) * 2
		if score < score_best:
			score_best = score
			best = {"hide": hide, "fire": fire, "relocate": relocate, "target": target}
	return best
