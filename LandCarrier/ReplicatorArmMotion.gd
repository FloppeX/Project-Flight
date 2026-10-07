extends RefCounted
## Four independent welders with separate work areas and latched seam passes.
const SPEED := 3.3
const ACCELERATION := 12.0
const REST_SECONDS := 0.3
const CLEARANCE := 0.14
const SECTOR_MARGIN := 0.72
const PREWELD_SECONDS := 0.18
var poses: Array[Dictionary] = []
var jobs: Array[Dictionary] = []
var passes := 0
var _completed: Dictionary = {}
var _pass_scale := 1.0

func _init() -> void:
	for index in range(4):
		poses.append(_pose(index, park(index)))
		jobs.append({"mode": "rest", "piece_index": -1, "edge": [], "target": Vector3.ZERO,
			"fraction": 0.0, "weld_time": 0.0, "delay": 0.2 + index * 0.47, "path": [], "passes": 0, "key": "", "speed": 0.0})

static func shoulder(index: int) -> Vector3:
	var angle := index * TAU / 4.0 + PI / 4.0
	return Vector3(cos(angle) * 4.45, 6.1, sin(angle) * 4.45)

static func park(index: int) -> Vector3:
	var mount := shoulder(index)
	return Vector3(mount.x * 0.92, 5.0, mount.z * 0.92)

static func _pose(index: int, wrist: Vector3) -> Dictionary:
	var mount := shoulder(index)
	var outward := Vector3(mount.x, 0, mount.z).normalized()
	return {"shoulder": mount, "elbow": mount.lerp(wrist, 0.48) + outward * 0.6 + Vector3(0, -0.45, 0), "wrist": wrist}

static func segments(pose: Dictionary) -> Array:
	return [[pose.shoulder, pose.elbow, 0.43], [pose.elbow, pose.wrist, 0.32], [pose.elbow, pose.elbow, 0.55], [pose.wrist, pose.wrist, 0.56]]

static func clearance_between(a: Dictionary, b: Dictionary) -> float:
	var clearance := INF
	for left in segments(a):
		for right in segments(b):
			var points := Geometry3D.get_closest_points_between_segments(left[0], left[1], right[0], right[1])
			clearance = minf(clearance, points[0].distance_to(points[1]) - float(left[2]) - float(right[2]))
	return clearance

func _clear(index: int, candidate: Dictionary) -> bool:
	for other in range(poses.size()):
		if other != index and clearance_between(candidate, poses[other]) < CLEARANCE:
			return false
	return true

func _owns_edge(index: int, seam: Array) -> bool:
	var mount := shoulder(index)
	for point: Vector3 in seam:
		if point.x * signf(mount.x) < -0.015 or point.z * signf(mount.z) < -0.015:
			return false
	return true

func _wrist(index: int, point: Vector3) -> Vector3:
	var mount := shoulder(index)
	var wrist := point + (mount - point).normalized() * 0.7
	# The welding beam reaches the seam while the tool body stays in its area.
	wrist.x = signf(mount.x) * maxf(SECTOR_MARGIN, wrist.x * signf(mount.x))
	wrist.z = signf(mount.z) * maxf(SECTOR_MARGIN, wrist.z * signf(mount.z))
	return wrist

func all_stowed() -> bool:
	for index in range(jobs.size()):
		if poses[index].wrist.distance_to(park(index)) > 0.001:
			return false
	return true

func reset_job() -> void:
	_completed.clear()
	for index in range(jobs.size()):
		if jobs[index].mode != "retract":
			_retract(index)

func _retract(index: int) -> void:
	var job := jobs[index]
	if poses[index].wrist.distance_to(park(index)) < 0.001:
		job.mode = "rest"
		job.piece_index = -1
		job.delay = 0.2 + index * 0.47
		return
	job.mode = "retract"
	job.speed = 0.0
	var wrist: Vector3 = poses[index].wrist
	job.path = [Vector3(wrist.x, maxf(4.8, wrist.y), wrist.z), park(index)]

func advance(delta: float, working: bool, pieces: Array[Dictionary], last_available: int, pass_scale: float = 1.0) -> void:
	_pass_scale = pass_scale
	var remaining := maxf(delta, 0.0)
	# Bound travel between collision checks even when several arms approach.
	while remaining > 0.00001:
		var step := minf(remaining, 0.015)
		for index in range(jobs.size()):
			_step(index, step, working, pieces, last_available)
		remaining -= step

func _step(index: int, delta: float, working: bool, pieces: Array[Dictionary], last_available: int) -> void:
	var job := jobs[index]
	if not working and job.mode != "retract":
		_retract(index)
	if job.mode == "rest":
		if not working:
			return
		job.delay = maxf(0.0, float(job.delay) - delta)
		if float(job.delay) <= 0.0:
			_select_pass(index, pieces, last_available)
		return
	if job.mode in ["approach", "retract"]:
		var destination: Vector3 = job.path[0]
		var distance: float = poses[index].wrist.distance_to(destination)
		var desired_speed := minf(SPEED, sqrt(2.0 * ACCELERATION * distance))
		job.speed = move_toward(float(job.speed), desired_speed, ACCELERATION * delta)
		var next: Vector3 = poses[index].wrist.move_toward(destination, float(job.speed) * delta)
		var candidate := _pose(index, next)
		if not _clear(index, candidate):
			job.speed = 0.0
			return
		poses[index] = candidate
		if next.distance_to(destination) < 0.0001:
			job.path.pop_front()
			job.speed = 0.0
			if job.path.is_empty():
				if job.mode == "approach":
					job.mode = "weld"
					job.fraction = 0.0
					job.weld_time = 0.0
				else:
					job.mode = "rest"
					job.piece_index = -1
					job.delay = 0.2 + index * 0.47
		return
	if job.mode == "weld":
		var length: float = (job.edge[0] as Vector3).distance_to(job.edge[1])
		var speed: float = [0.23, 0.28, 0.25, 0.30][index]
		var building := bool(job.get("build_pass", false))
		var duration := maxf(0.4, 1.2 * _pass_scale) if building else maxf(0.55, minf(2.0, maxf(1.7 + index * 0.19, length / speed) * _pass_scale))
		duration = maxf(duration, length / 1.45)
		var next_fraction := minf(1.0, float(job.fraction) + delta / duration)
		var next_target := (job.edge[0] as Vector3).lerp(job.edge[1], next_fraction)
		var candidate := _pose(index, _wrist(index, next_target))
		if not _clear(index, candidate):
			return
		poses[index] = candidate
		job.target = next_target
		job.fraction = next_fraction
		var nozzle: Vector3 = candidate.wrist - (candidate.wrist - next_target).normalized() * 0.5
		if nozzle.distance_to(next_target) < 0.85:
			job.weld_time += delta
			if float(job.weld_time) >= PREWELD_SECONDS:
				# Mesh/material fragments sharing a grid cell form one local section.
				# The beam has already worked here before any of them can appear.
				var cell: Vector3i = pieces[int(job.piece_index)].cell
				for piece in pieces:
					if piece.cell == cell and not bool(piece.get("primed", false)):
						piece.primed = true
						piece.preweld_seconds = job.weld_time
						piece.preweld_target = next_target
						piece.preweld_arm = index
		if next_fraction >= 1.0:
			_completed[job.key] = true
			passes += 1
			job.passes += 1
			# Keep the arm near its part between passes instead of repeatedly
			# swinging all the way up to the ring.
			job.mode = "rest"
			job.delay = 0.12 + index * 0.025 if bool(job.get("build_pass", false)) else REST_SECONDS + index * 0.11 + int(job.passes) % 3 * 0.13

func _claimed(piece: int, owner: int) -> bool:
	for index in range(jobs.size()):
		if index != owner and int(jobs[index].piece_index) == piece:
			return true
	return false

func _select_pass(index: int, pieces: Array[Dictionary], last_available: int) -> void:
	var choice: Dictionary = {}
	var best := INF
	for piece_index in range(last_available, -1, -1):
		if _claimed(piece_index, index):
			continue
		var piece := pieces[piece_index]
		for seam: Array in piece.weld_seams:
			if not _owns_edge(index, seam):
				continue
			var key := str(piece_index) + "/" + str(seam)
			if _completed.has(key):
				continue
			var a: Vector3 = seam[0]
			var b: Vector3 = seam[1]
			if poses[index].wrist.distance_squared_to(_wrist(index, b)) < poses[index].wrist.distance_squared_to(_wrist(index, a)):
				var swap := a
				a = b
				b = swap
			var pending := not bool(piece.get("primed", false))
			var priority: float = piece_index * 0.025 if pending else 1000.0 + (last_available - piece_index) * 0.025
			var score: float = priority + poses[index].wrist.distance_to(_wrist(index, a)) * 0.3
			score -= 0.35 if bool(piece.connected_seam) else 0.0
			score -= minf(a.distance_to(b), 0.8) * 0.15
			if score >= best:
				continue
			if not _clear(index, _pose(index, _wrist(index, a))) or not _clear(index, _pose(index, _wrist(index, b))):
				continue
			best = score
			choice = {"piece": piece_index, "edge": [a, b], "target": a, "key": key, "pending": pending}
	if choice.is_empty():
		jobs[index].delay = 0.3 + index * 0.09
		return
	var job := jobs[index]
	job.piece_index = choice.piece
	job.edge = choice.edge
	job.target = choice.target
	job.key = choice.key
	job.build_pass = choice.pending
	job.mode = "approach"
	job.speed = 0.0
	var start := _wrist(index, choice.target)
	var wrist: Vector3 = poses[index].wrist
	job.path = [start] if wrist.distance_to(start) < 3.0 else [Vector3(start.x, maxf(4.8, start.y), start.z), start]
