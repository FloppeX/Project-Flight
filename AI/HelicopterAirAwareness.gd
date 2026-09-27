extends RefCounted
## Local visual observations and short defensive breaks, independent of orders.
const Track = preload("res://AI/VisualContactTrack.gd")
const Escape = preload("res://AI/HelicopterEscape.gd")
var clock_s := 0.0
var scan_s := 0.0
var contacts: Dictionary = {}
var break_s := 0.0
var cooldown_s := 0.0
var evidence_s := 0.0
var damage_age_s := INF
var break_direction := Vector3.ZERO
var episodes := 0

func reset() -> void:
	contacts.clear()
	scan_s = 0.0
	break_s = 0.0
	cooldown_s = 0.0
	evidence_s = 0.0
	damage_age_s = INF

func report_damage(amount: float, source: StringName) -> void:
	if amount > 0 and source == &"projectile": damage_age_s = 0.0

static func is_helicopter(node: Node) -> bool:
	return is_instance_valid(node) and (node.get_meta("is_helicopter", false) == true \
		or str(node.get_meta("aircraft_role", "")).contains("helicopter") \
		or node.get_node_or_null("HelicopterFlight") != null)

func shift_origin(offset: Vector3) -> void:
	for entry in contacts.values(): entry.track.shift_origin(offset)

func update_observations(delta: float, craft: RigidBody3D, height: Callable) -> void:
	clock_s += delta
	damage_age_s += delta
	scan_s -= delta
	if scan_s > 0: return
	scan_s = 0.2
	for id in contacts.keys():
		var entry: Dictionary = contacts[id]
		entry.track.visible = false
		if not is_instance_valid(entry.node.get_ref()) or clock_s - entry.track.observed_at > 5.0:
			contacts.erase(id)
	var seen := {}
	for group in ["aircraft", "ai_aircraft"]:
		for target in craft.get_tree().get_nodes_in_group(group):
			if not target is Node3D or target == craft or not target.has_method("get_team"): continue
			if target.get_team() == craft.get_team() or target.get("is_destroyed") == true: continue
			var id: int = target.get_instance_id()
			if seen.has(id): continue
			seen[id] = true
			var offset: Vector3 = target.global_position - craft.global_position
			if offset.length() > 2500.0 or offset.length() < 1.0: continue
			var local: Vector3 = craft.global_basis.inverse() * offset.normalized()
			var visible: bool = Track.in_visual_sector(local)
			# A shoulder check can reacquire a remembered aircraft, never an unknown one.
			if not visible and contacts.has(id) and fmod(clock_s, 2.5) < 0.4:
				var prior: Dictionary = contacts[id].track.sample(clock_s, 5.0)
				var bearing: Vector3 = craft.global_basis.inverse() * (prior.position - craft.global_position).normalized()
				visible = Track.in_search_sector(local, bearing)
			if not visible: continue
			var eye := craft.global_position + craft.global_basis.y * 1.5
			if Escape.terrain_occludes(eye, target.global_position, height): continue
			var ray := PhysicsRayQueryParameters3D.create(eye, target.global_position)
			ray.exclude = [craft.get_rid()]
			var hit := craft.get_world_3d().direct_space_state.intersect_ray(ray)
			if not hit.is_empty() and hit.collider != target and not target.is_ancestor_of(hit.collider): continue
			if not contacts.has(id): contacts[id] = {"node": weakref(target), "track": Track.new(), "forward": Vector3.ZERO}
			var velocity_value: Variant = target.get("linear_velocity")
			var velocity: Vector3 = velocity_value if velocity_value is Vector3 else Vector3.ZERO
			contacts[id].track.observe(target.global_position, velocity, clock_s)
			contacts[id].forward = target.global_basis.z.normalized()

func observation(target: Node) -> Dictionary:
	if not is_instance_valid(target) or not contacts.has(target.get_instance_id()): return {}
	var entry: Dictionary = contacts[target.get_instance_id()]
	var sample: Dictionary = entry.track.sample(clock_s, 5.0)
	if sample.is_empty() or not sample.visible or sample.expired: return {}
	sample["forward"] = entry.forward
	return sample

func visible_helicopters() -> Array:
	var result := []
	for entry in contacts.values():
		var node: Node = entry.node.get_ref()
		if is_helicopter(node) and not observation(node).is_empty(): result.append(node)
	return result

func defensive_waypoint(delta: float, craft: RigidBody3D, goal: Vector3, height: Callable, clearance: float) -> Vector3:
	cooldown_s = maxf(0, cooldown_s - delta)
	var incoming := Vector3.ZERO
	var credible := false
	for entry in contacts.values():
		var sample := observation(entry.node.get_ref())
		if sample.is_empty(): continue
		var to_us: Vector3 = craft.global_position - sample.position
		if to_us.length() < 1000.0 and to_us.length() > 40.0 \
			and sample.forward.dot(to_us.normalized()) > 0.94:
			incoming = sample.forward
			credible = true
			break
	if break_s <= 0.0:
		evidence_s = evidence_s + delta if credible or damage_age_s < 1.0 else 0.0
		if cooldown_s > 0.0 or evidence_s < 0.4: return Vector3.INF
		var progress := Vector3(goal.x - craft.global_position.x, 0, goal.z - craft.global_position.z).normalized()
		if progress.length_squared() < 0.5: progress = Vector3(craft.global_basis.z.x, 0, craft.global_basis.z.z).normalized()
		var side := Vector3(incoming.z, 0, -incoming.x).normalized() if credible else Vector3(progress.z, 0, -progress.x)
		if side.dot(progress) < 0: side = -side
		break_direction = (side + progress * 0.65).normalized()
		break_s = 3.0
		evidence_s = 0.0
		damage_age_s = INF
		episodes += 1
	break_s -= delta
	if break_s <= 0: cooldown_s = 5.0
	# Keep the mission destination untouched; validate a short lateral chord.
	for sign_value in [1.0, -1.0]:
		var point: Vector3 = craft.global_position + break_direction * float(sign_value) * 250.0
		point.y = craft.global_position.y
		if Escape.segment_clear(craft.global_position, point, clearance, height): return point
	return Vector3.INF
