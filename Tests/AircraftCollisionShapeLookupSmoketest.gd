extends SceneTree

var _failures: Array[String] = []
var _cases := 0
var _gear_contacts := 0
var _body_contacts := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene_paths: Array[String] = []
	for number in range(1, 15):
		var path := "res://Aircraft/Aircraft_%d.tscn" % number
		if ResourceLoader.exists(path):
			scene_paths.append(path)
	scene_paths.append("res://Aircraft/CompleteFighterJet.tscn")
	scene_paths.append("res://Enemies/EnemyFighter.tscn")
	for path in scene_paths:
		await _check_aircraft(path, false)
		await _check_aircraft(path, true)
	for failure in _failures:
		push_error(failure)
	print("AIRCRAFT_COLLISION_SHAPE_LOOKUP_SMOKETEST %s models=%d cases=%d gear_contacts=%d body_contacts=%d failures=%d" % [
		"PASS" if _failures.is_empty() else "FAIL", scene_paths.size(), _cases,
		_gear_contacts, _body_contacts, _failures.size()])
	quit(0 if _failures.is_empty() else 1)


func _check_aircraft(path: String, replace_shapes: bool) -> void:
	_cases += 1
	var label := "%s replaced=%s" % [path.get_file(), replace_shapes]
	var host := Node3D.new()
	root.add_child(host)
	current_scene = host
	var carrier := StaticBody3D.new()
	carrier.name = "LandCarrierContactTest"
	host.add_child(carrier)
	var runway := StaticBody3D.new()
	runway.add_to_group("runway_surface")
	host.add_child(runway)
	var other := RigidBody3D.new()
	other.freeze = true
	host.add_child(other)
	var craft := (load(path) as PackedScene).instantiate() as RigidBody3D
	craft.freeze = true
	craft.position.y = 1000.0
	craft.set("touchdown_signal_cooldown_s", 0.0)
	host.add_child(craft)
	for frame in range(3):
		await physics_frame
		await process_frame
	var safe: Array = craft.get("safe_colliders")
	_expect(not safe.is_empty(), "%s has no registered landing gear" % label)
	var body_shapes: Array[CollisionShape3D] = []
	for owner_id in craft.get_shape_owners():
		var collider := craft.shape_owner_get_owner(owner_id) as CollisionShape3D
		if collider != null and not collider.disabled and not safe.has(collider):
			body_shapes.append(collider)
	if replace_shapes:
		# Replacing a resource removes/re-adds its physics shape without changing
		# the owner ID. Exercise the Aircraft 1 trigger on every aircraft model.
		for collider in body_shapes:
			collider.shape = collider.shape.duplicate()
		await physics_frame
		await process_frame
	var touchdowns: Array[Dictionary] = []
	var crashes: Array[float] = []
	craft.connect("touchdown", func(details: Dictionary): touchdowns.append(details))
	craft.connect("crashed", func(speed): crashes.append(float(speed)))
	var initial_health: float = craft.get("current_health")
	for invalid_index in [-1, PhysicsServer3D.body_get_shape_count(craft.get_rid())]:
		craft.call("_on_Aircraft_body_shape_entered", carrier.get_rid(), carrier, 0, invalid_index)
	_expect(touchdowns.is_empty() and crashes.is_empty(), "%s invalid shape index generated contact events" % label)
	for wheel in safe:
		for surface in [carrier, runway, other]:
			var previous_touchdowns := touchdowns.size()
			craft.linear_velocity = Vector3(0.0, -1.0, 45.0)
			craft.call("_on_Aircraft_body_shape_entered", surface.get_rid(), surface, 0, _index_for(craft, wheel))
			_gear_contacts += 1
			_expect(not bool(craft.get("_has_exploded")), "%s %s exploded on %s" % [label, wheel.name, surface.name])
			_expect(touchdowns.size() == previous_touchdowns + 1, "%s %s did not publish a touchdown" % [label, wheel.name])
			_expect(crashes.is_empty(), "%s %s emitted crashed for gentle wheel contact" % [label, wheel.name])
			_expect(is_equal_approx(craft.get("current_health"), initial_health), "%s gentle wheel contact damaged aircraft" % label)
			if bool(craft.get("_has_exploded")):
				host.free()
				await process_frame
				return
			if touchdowns.size() > previous_touchdowns:
				_expect(not bool(touchdowns.back().get("damaging", true)), "%s gentle contact marked damaging" % label)
	# Correct gear classification must still respect the vertical crash threshold.
	if not safe.is_empty():
		var damaging_sink := maxf(craft.get("hard_crash_vertical_speed"), craft.get("max_landing_force")) + 2.0
		var previous_touchdowns := touchdowns.size()
		craft.linear_velocity = Vector3(0.0, -damaging_sink, 45.0)
		craft.call("_on_Aircraft_body_shape_entered", carrier.get_rid(), carrier, 0, _index_for(craft, safe[0]))
		_expect(touchdowns.size() == previous_touchdowns + 1 and bool(touchdowns.back().get("damaging", false)), "%s hard gear impact not marked damaging" % label)
		_expect(crashes.size() == 1 and is_equal_approx(crashes[0], damaging_sink), "%s hard gear impact did not emit vertical crash speed" % label)
	# Every non-wheel shape must still take the body-contact path. Use a slow
	# contact and restore health between independent checks; thresholds stay real.
	for collider in body_shapes:
		var previous_crashes := crashes.size()
		var previous_touchdowns := touchdowns.size()
		craft.set("current_health", initial_health)
		craft.linear_velocity = Vector3(0.0, 0.0, 1.0)
		craft.call("_on_Aircraft_body_shape_entered", carrier.get_rid(), carrier, 0, _index_for(craft, collider))
		_body_contacts += 1
		_expect(crashes.size() == previous_crashes + 1, "%s %s not classified as body contact" % [label, collider.name])
		_expect(touchdowns.size() == previous_touchdowns, "%s %s incorrectly classified as safe wheel" % [label, collider.name])
	# The fix must not make genuinely fast body impacts harmless.
	_expect(not body_shapes.is_empty(), "%s has no active body collider" % label)
	if not body_shapes.is_empty():
		craft.set("current_health", initial_health)
		craft.linear_velocity = Vector3(0.0, -1.0, 45.0)
		craft.call("_on_Aircraft_body_shape_entered", carrier.get_rid(), carrier, 0, _index_for(craft, body_shapes[0]))
		_expect(bool(craft.get("_has_exploded")), "%s fast body impact did not destroy aircraft" % label)
	print("COLLISION_LOOKUP_CASE %s wheels=%d body_shapes=%d" % [label, safe.size(), body_shapes.size()])
	host.free()
	await process_frame


func _index_for(craft: RigidBody3D, collider: CollisionShape3D) -> int:
	for owner_id in craft.get_shape_owners():
		if craft.shape_owner_get_owner(owner_id) == collider:
			return craft.shape_owner_get_shape_index(owner_id, 0)
	_failures.append("Collider has no physics shape: %s" % collider.name)
	return -1


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
