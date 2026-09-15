extends Node
## World-space, visual-only tracking. Never steers a bomb or alters its damage.
signal finished

const TRAIL_M := 8.0
const CLEARANCE_M := 40.0
const AFTERMATH_S := 3.0
enum State { OFF, WAITING, FOLLOWING, HOLDING, AFTERMATH }
var state := State.OFF
var subject: Node3D
var bomb: RigidBody3D
var pose := Transform3D.IDENTITY
var _previous_pose := Transform3D.IDENTITY
var impact := Vector3.ZERO
var has_prediction := false
var _prediction_timer := 0.0
var _visual_remaining := 0.0
var _visuals_done := false
var _explosion: Node
var _hold_locked := false
var _has_pose := false
var _terrain: Node

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	set_physics_process(false)

func begin(aircraft: Node3D) -> void:
	stop()
	subject = aircraft
	_terrain = TerrainReference.get_terrain_node()
	state = State.WAITING
	set_physics_process(true)

func stop() -> void:
	if is_instance_valid(bomb) and bomb.detonated.is_connected(_on_detonated): bomb.detonated.disconnect(_on_detonated)
	if is_instance_valid(_explosion):
		if _explosion.visual_tail_started.is_connected(_on_visual_tail): _explosion.visual_tail_started.disconnect(_on_visual_tail)
		if _explosion.visuals_scheduled.is_connected(_on_visuals_done): _explosion.visuals_scheduled.disconnect(_on_visuals_done)
		if _explosion.tree_exiting.is_connected(_on_visuals_done): _explosion.tree_exiting.disconnect(_on_visuals_done)
	bomb = null
	_explosion = null
	_terrain = null
	subject = null
	state = State.OFF
	_hold_locked = false
	_has_pose = false
	has_prediction = false
	_visual_remaining = 0.0
	_visuals_done = false
	_prediction_timer = 0.0
	set_physics_process(false)

func _physics_process(delta: float) -> void:
	if not is_inside_tree() or get_tree().paused: return
	if state == State.WAITING:
		for candidate in get_tree().get_nodes_in_group("live_bombs"):
			if candidate is BombProjectile and not candidate.is_queued_for_deletion() and not candidate.has_impacted and candidate.shooter == subject:
				bomb = candidate
				bomb.detonated.connect(_on_detonated)
				state = State.FOLLOWING
				break
		if state == State.WAITING: return
	if state == State.AFTERMATH:
		_visual_remaining = maxf(0.0, _visual_remaining - delta)
		if _visuals_done and _visual_remaining <= 0.0:
			stop()
			finished.emit()
		return
	if not is_instance_valid(bomb) or not bomb.is_inside_tree() or bomb.is_queued_for_deletion():
		# Dud/lifetime expiry is not an explosion. Keep a brief ending, then return.
		state = State.AFTERMATH
		_visuals_done = true
		_visual_remaining = AFTERMATH_S
		return
	_previous_pose = pose
	if _hold_locked: return
	_prediction_timer -= delta
	if _prediction_timer <= 0.0:
		var prediction := _predict_impact()
		if prediction.is_finite():
			impact = prediction
			has_prediction = true
		_prediction_timer = 0.2
	if not has_prediction: return
	var direction := bomb.linear_velocity.normalized()
	if direction.is_zero_approx(): direction = Vector3.DOWN
	var candidate: Vector3 = bomb.global_position - direction * TRAIL_M
	var ground := _ground_height(candidate)
	if is_finite(ground) and candidate.y - ground <= CLEARANCE_M:
		# Intersect the last camera segment with the 40 m clearance surface.
		# This prevents a fast bomb from dragging the camera below the stop height.
		var safe := pose.origin
		if _has_pose and safe.y - _ground_height(safe) > CLEARANCE_M:
			var low := 0.0
			var high := 1.0
			for iteration in 14:
				var weight := (low + high) * 0.5
				var point := safe.lerp(candidate, weight)
				if point.y - _ground_height(point) > CLEARANCE_M: low = weight
				else: high = weight
			candidate = safe.lerp(candidate, low)
		else:
			candidate.y = ground + CLEARANCE_M
		_hold_locked = true
		state = State.HOLDING
	_set_pose(candidate)

func _set_pose(position: Vector3) -> void:
	var first_pose := not _has_pose
	_has_pose = true
	var direction := impact - position
	if direction.length_squared() < 0.001: direction = Vector3.DOWN
	var up := Vector3.RIGHT if absf(direction.normalized().dot(Vector3.UP)) > 0.999 else Vector3.UP
	pose = Transform3D(Basis.looking_at(direction, up), position)
	if first_pose: _previous_pose = pose

func render_pose() -> Transform3D:
	if state != State.FOLLOWING or get_tree().paused: return pose
	return _previous_pose.interpolate_with(pose, clampf(Engine.get_physics_interpolation_fraction(), 0.0, 1.0))

func _ground_height(point: Vector3) -> float:
	# Use the terrain's precise height API, not the coarse 40 m navigation grid,
	# to enforce local clearance on slopes. Cache the provider only for this shot.
	if is_instance_valid(_terrain) and _terrain.is_inside_tree() and _terrain.has_method("get_height"):
		var height := float(_terrain.call("get_height", point))
		if is_finite(height): return height
	var world_node: Node3D = bomb if is_instance_valid(bomb) and bomb.is_inside_tree() else subject
	if not is_instance_valid(world_node) or not world_node.is_inside_tree(): return NAN
	var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 1000.0, point + Vector3.DOWN * 10000.0)
	query.exclude = _exclusions()
	var hit := world_node.get_world_3d().direct_space_state.intersect_ray(query)
	return float(hit.position.y) if not hit.is_empty() else NAN

func _exclusions() -> Array[RID]:
	var result: Array[RID] = []
	if is_instance_valid(subject) and subject is CollisionObject3D: result.append(subject.get_rid())
	for projectile in get_tree().get_nodes_in_group("live_bombs"):
		if projectile is CollisionObject3D: result.append(projectile.get_rid())
	return result

func _predict_impact() -> Vector3:
	var position := bomb.global_position
	var velocity := bomb.linear_velocity
	var gravity: Vector3 = ProjectSettings.get_setting("physics/3d/default_gravity_vector", Vector3.DOWN)
	gravity *= float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)) * bomb.gravity_scale
	var space := bomb.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.new()
	query.exclude = _exclusions()
	query.collision_mask = 0xFFFFFFFF
	const STEP := 0.2
	for step in 300:
		var next := position + velocity * STEP + gravity * (0.5 * STEP * STEP)
		velocity += gravity * STEP
		query.from = position
		query.to = next
		var hit := space.intersect_ray(query)
		for skip in 8:
			if hit.is_empty() or not hit.get("collider") is ProjectileNew: break
			var excluded := query.exclude
			excluded.append(hit.rid)
			query.exclude = excluded
			hit = space.intersect_ray(query)
		if not hit.is_empty(): return hit.position
		var height: float = TerrainNavGrid.sample_height(next.x, next.z)
		if height > TerrainNavGrid.IMPASSABLE * 0.5 and next.y <= height:
			return Vector3(next.x, height, next.z)
		position = next
	return Vector3.INF

func _on_detonated(_position: Vector3, explosion: Node) -> void:
	# Retain the exact aim point and camera pose selected before impact.
	state = State.AFTERMATH
	_visual_remaining = AFTERMATH_S
	_explosion = explosion
	_visuals_done = not is_instance_valid(explosion)
	if is_instance_valid(explosion):
		explosion.visual_tail_started.connect(_on_visual_tail)
		explosion.visuals_scheduled.connect(_on_visuals_done, CONNECT_ONE_SHOT)
		explosion.tree_exiting.connect(_on_visuals_done, CONNECT_ONE_SHOT)

func _on_visual_tail(duration: float) -> void:
	_visual_remaining = maxf(_visual_remaining, duration + AFTERMATH_S)

func _on_visuals_done() -> void:
	_visuals_done = true

func apply_origin_shift(offset: Vector3) -> void:
	pose.origin -= offset
	_previous_pose.origin -= offset
	impact -= offset
