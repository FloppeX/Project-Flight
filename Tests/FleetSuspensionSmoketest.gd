extends SceneTree

var failures: Array[String] = []
var rows: Array[Dictionary] = []
var baseline := false

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)

func _disable_updates(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child in node.get_children():
		_disable_updates(child)

func _run() -> void:
	baseline = OS.get_cmdline_user_args().has("--gear-drop-baseline")
	var paths: Array[String] = []
	for n in range(1, 15):
		var path := "res://Aircraft/Aircraft_%d.tscn" % n
		if ResourceLoader.exists(path):
			paths.append(path)
	paths.append("res://Aircraft/CompleteFighterJet.tscn")
	paths.append("res://Enemies/EnemyFighter.tscn")
	for path in paths:
		await _check_model(path)
	if OS.get_cmdline_user_args().has("--gear-drop-trace"):
		await _drop("res://Aircraft/Aircraft_5.tscn", 2.0)
		await _drop("res://Aircraft/Aircraft_9.tscn", 2.0)
		quit(0)
		return
	for path in paths:
		for sink in [2.0, 4.0, 6.0, 8.0]:
			await _drop(path, sink)
	var report := {"baseline_configuration": baseline, "models": paths.size(),
		"drop_cases": rows, "failures": failures}
	var suffix := "%s_%d" % ["baseline" if baseline else "current", Time.get_unix_time_from_system()]
	var output := "user://fleet_suspension_%s.json" % suffix
	var file := FileAccess.open(output, FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	for failure in failures:
		push_error(failure)
	print("FLEET_SUSPENSION_SMOKETEST %s models=%d drops=%d report=%s" % [
		"PASS" if failures.is_empty() else "FAIL", paths.size(), rows.size(), ProjectSettings.globalize_path(output)])
	quit(0 if failures.is_empty() else 1)

func _spawn(path: String, host: Node3D) -> RigidBody3D:
	var craft := (load(path) as PackedScene).instantiate() as RigidBody3D
	craft.freeze = true
	craft.position.y = 1000.0
	if baseline:
		var gear := craft.get_node("LandingGear")
		gear.set("size_suspension_for_static_load", false)
		gear.set("move_colliders_with_suspension", path.get_file() in [
			"Aircraft_1.tscn", "Aircraft_5.tscn", "Aircraft_9.tscn", "Aircraft_10.tscn",
			"Aircraft_11.tscn", "Aircraft_12.tscn", "Aircraft_14.tscn"])
	host.add_child(craft)
	return craft

func _check_model(path: String) -> void:
	var host := Node3D.new()
	root.add_child(host)
	var craft := _spawn(path, host)
	await process_frame
	await physics_frame
	_disable_updates(craft)
	var gear := craft.get_node("LandingGear")
	gear.call("deploy")
	gear.set("use_accel_lean", false)
	var wheels: Array = gear.get("gear_collision_shapes")
	var loads: Array = gear.call("get_static_load_compressions")
	var maximum := 0.0
	for compression in loads:
		maximum = maxf(maximum, compression)
	if not baseline:
		_check(gear.get("move_colliders_with_suspension"), "%s suspension collider movement disabled" % path)
		_check(maximum <= float(gear.get("max_compression")) * 0.351,
			"%s consumes too much static travel" % path)
		var initial: Array[Vector3] = []
		var compressions: Array[float] = []
		for wheel in wheels:
			initial.append(wheel.position)
			compressions.append(0.1)
		gear.set("gear_compressions", compressions)
		gear.call("_update_suspension_collider_geometry", 1.0)
		gear.call("_update_lean_geometry")
		await physics_frame
		for i in wheels.size():
			_check(wheels[i].position.y > initial[i].y + 0.09, "%s wheel %d did not physically move" % [path, i])
			_check((craft.get("safe_colliders") as Array).has(wheels[i]), "%s moving wheel lost safe classification" % path)
			var found_shape := false
			for owner in craft.get_shape_owners():
				if craft.shape_owner_get_owner(owner) == wheels[i]:
					var index := craft.shape_owner_get_shape_index(owner, 0)
					var physics_shape := PhysicsServer3D.body_get_shape_transform(craft.get_rid(), index)
					_check((craft.global_transform * physics_shape.origin).distance_to(wheels[i].global_position) < 0.001,
						"%s wheel %d scene/physics shape transform mismatch" % [path, i])
					found_shape = true
			_check(found_shape, "%s wheel %d has no actual physics shape" % [path, i])
		var velocity: Vector3 = gear.call("_surface_point_velocity", craft, craft.to_global(craft.center_of_mass))
		_check(velocity.is_equal_approx(craft.linear_velocity), "Velocity at COM must exclude rotation")
	print("GEAR_CONFIG model=%s mass=%.0f wheels=%d k=%.1f c=%.1f static_max=%.3f moving=%s" % [
		path.get_file(), craft.mass, wheels.size(), gear.get("spring_strength"), gear.get("spring_damping"),
		maximum, gear.get("move_colliders_with_suspension")])
	host.queue_free()
	await process_frame

func _drop(path: String, sink: float) -> void:
	var host := Node3D.new()
	root.add_child(host)
	var deck := StaticBody3D.new()
	deck.name = "LandCarrierDropDeck"
	deck.add_to_group("carrier")
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(100, 2, 100)
	shape.shape = box
	shape.position.y = -1.0
	deck.add_child(shape)
	host.add_child(deck)
	var craft := _spawn(path, host)
	await process_frame
	await physics_frame
	_disable_updates(craft)
	var gear := craft.get_node("LandingGear")
	gear.call("deploy")
	gear.set("use_accel_lean", false)
	gear.set("airborne_suspension_budget_enabled", false)
	# Isolate vertical suspension: no pilot, engine, lift, arrestor, or attitude motion.
	craft.lock_rotation = true
	craft.gravity_scale = 1.0
	var bottom := INF
	var wheels: Array = gear.get("gear_collision_shapes")
	for i in wheels.size():
		var wheel := wheels[i] as CollisionShape3D
		var extent := 0.0
		if wheel.shape is SphereShape3D:
			extent = wheel.shape.radius * wheel.global_basis.get_scale().y
		elif wheel.shape is BoxShape3D:
			extent = wheel.shape.size.y * wheel.global_basis.get_scale().y * 0.5
		bottom = minf(bottom, wheel.global_position.y - extent)
		# Start above both the physical tire and unloaded suspension probe. Some
		# authored rest heights exceed tire radius; do not begin those precompressed.
		bottom = minf(bottom, wheel.global_position.y - float(gear.call("get_wheel_rest_height", i)))
	craft.freeze = false
	await physics_frame
	await process_frame
	craft.global_position.y += 0.02 - bottom
	craft.linear_velocity = Vector3(0, -sink, 0)
	craft.sleeping = false
	var max_compression := 0.0
	var peak_force := 0.0
	var peak_decel := 0.0
	var rebound := 0.0
	var previous_vy := -sink
	var bottomed := false
	var destroyed := false
	var final_vy := 0.0
	var part_state: Dictionary = {}
	var touchdowns: Array[Dictionary] = []
	craft.connect("touchdown", func(details: Dictionary): touchdowns.append(details.duplicate(true)))
	for step in range(240):
		if not is_instance_valid(craft) or craft.is_queued_for_deletion():
			destroyed = true
			break
		gear.call("process_physic_frame", 1.0 / 60.0)
		for c in gear.get("gear_compressions"):
			max_compression = maxf(max_compression, c)
			bottomed = bottomed or float(c) >= float(gear.get("max_compression")) * 0.98
		var total_force := 0.0
		for force in gear.get("gear_normal_forces_n"):
			total_force += force
		peak_force = maxf(peak_force, total_force)
		await physics_frame
		await process_frame
		if is_instance_valid(craft):
			final_vy = craft.linear_velocity.y
			peak_decel = maxf(peak_decel, (final_vy - previous_vy) * 60.0)
			rebound = maxf(rebound, final_vy)
			previous_vy = final_vy
			if OS.get_cmdline_user_args().has("--gear-drop-trace") and (step < 12 or step == 239):
				print("DROP_TRACE %s step=%d y=%.3f vy=%.3f freeze=%s sleeping=%s k=%.0f c=%s offsets=%s forces=%s" % [
					path.get_file(), step, craft.position.y, final_vy, craft.freeze, craft.sleeping,
					gear.get("spring_strength"), gear.get("gear_compressions"),
					gear.get("_suspension_collider_compressions"), gear.get("gear_normal_forces_n")])
			part_state = craft.call("get_part_damage_state")
			destroyed = bool(craft.get("_has_exploded")) or bool(craft.get("_critical_damage_active"))
			if destroyed:
				break
	var loss := 0.0
	for zone in part_state.values():
		loss += maxf(float(zone.max_health) - float(zone.health), 0.0)
	var row := {"model": path.get_file(), "initial_sink_mps": sink, "max_compression_m": max_compression,
		"bottomed": bottomed, "peak_suspension_force_n": peak_force, "peak_upward_accel_mps2": peak_decel,
		"max_rebound_mps": rebound, "final_vy_mps": final_vy, "destroyed": destroyed, "part_health_loss": loss,
		"touchdown_count": touchdowns.size()}
	rows.append(row)
	print("GEAR_DROP json=" + JSON.stringify(row))
	_check(not destroyed, "%s drop %.0f destroyed aircraft" % [path, sink])
	if not baseline:
		_check(peak_force > 0.0 and max_compression > 0.02, "%s drop bypassed suspension" % path)
		_check(not touchdowns.is_empty(), "%s compliant touchdown was not reported" % path)
	if sink <= 2.0:
		_check(absf(final_vy) < 0.5, "%s gentle drop did not settle" % path)
		if not baseline:
			_check(not bottomed, "%s gentle drop exhausted travel" % path)
	host.queue_free()
	await process_frame
