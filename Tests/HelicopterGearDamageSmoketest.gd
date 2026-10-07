extends "res://Tests/HelicopterDamageSmoketest.gd"

const FLEET := [9, 10, 11, 12, 13, 15]
const RUNTIME := preload("res://Aircraft/AircraftRuntimeState.gd")

class Deck extends CharacterBody3D:
	func _physics_process(delta: float) -> void:
		move_and_collide(velocity * delta)

func _run() -> void:
	get_tree().create_timer(180.0).timeout.connect(func():
		push_error("HELICOPTER_GEAR_DAMAGE_TIMEOUT")
		get_tree().quit(1))
	for singleton in ["AirOpsManager", "GroundOpsManager", "OperationsCoordinator", "FlightDirector", "EnemyVisualBudget"]:
		get_node("/root/" + singleton).process_mode = Node.PROCESS_MODE_DISABLED
	host = Node3D.new()
	add_child(host)
	for number in FLEET: await geometry_and_save(number)
	for deck in [false, true]:
		for heavy in [false, true]: await landing_cases(deck, heavy)
	for number in [9, 10]: await deck_edge_case(number)
	for failure in failures: push_error(failure)
	print("HELICOPTER_GEAR_DAMAGE_", "PASS" if failures.is_empty() else "FAIL", " fleet=6 landings=24 deck_edge=2 geometry+save=true failures=", failures)
	get_tree().quit(0 if failures.is_empty() else 1)

func geometry_and_save(number: int) -> void:
	var craft := spawn(number)
	while not craft.runtime_initialized: await get_tree().process_frame
	var gear: AircraftModule_LandingGear = craft.get_node("LandingGear")
	var roots := gear.get_damage_visual_roots()
	check(not roots.is_empty(), "%d has no breakaway gear visuals" % number)
	for visual in roots:
		check(is_instance_valid(visual) and visual.is_visible_in_tree(), "%d missing gear visual" % number)
	gear.shear_from_damage()
	await get_tree().physics_frame
	await get_tree().physics_frame
	var debris_count := 0
	for node in host.get_children():
		if node.get_meta("damage_debris_zone", &"") == &"landing_gear": debris_count += 1
	check(debris_count == roots.size(), "%d gear debris count %d != %d" % [number, debris_count, roots.size()])
	for visual in roots: check(not visual.is_visible_in_tree(), "%d gear still visible" % number)
	for collider in gear.gear_collision_shapes + gear.auxiliary_safe_collision_shapes:
		check(collider.disabled and collider.get_meta("damage_detached", false), "%d lost gear still collides" % number)
	var count := host.get_child_count()
	gear.shear_from_damage()
	check(host.get_child_count() == count, "%d repeated gear debris" % number)
	var saved := RUNTIME.capture(craft)
	check(RUNTIME.validate(saved), "%d gear save invalid" % number)
	var restored := spawn(number)
	restored.position.x += 100
	while not restored.runtime_initialized: await get_tree().process_frame
	count = host.get_child_count()
	RUNTIME.restore(restored, saved)
	check(host.get_child_count() == count, "%d save replayed debris" % number)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var restored_gear: AircraftModule_LandingGear = restored.get_node("LandingGear")
	check(restored_gear.damage_collapsed, "%d save restored suspension" % number)
	for visual in restored_gear.get_damage_visual_roots(): check(not visual.is_visible_in_tree(), "%d save restored gear visual" % number)
	for collider in restored_gear.gear_collision_shapes + restored_gear.auxiliary_safe_collision_shapes:
		check(collider.disabled, "%d save restored skid collision" % number)
	print("HELICOPTER_GEAR_GEOMETRY id=", number, " debris=", debris_count)
	await clear_case()

func deck_edge_case(number: int) -> void:
	var craft := spawn(number)
	while not craft.runtime_initialized: await get_tree().process_frame
	craft.position = Vector3(0, 1400, 0)
	craft.get_node("Engine").engine_stop()
	craft.get_node("SimpleAero").set_physics_process(false)
	craft.gravity_scale = 0.0
	var gear: AircraftModule_LandingGear = craft.get_node("LandingGear")
	var collider: CollisionShape3D = gear.gear_collision_shapes[1]
	obstacle(collider.global_position + Vector3(0, 0, 1.2), Vector3(0.6, 0.4, 0.12), "carrier")
	craft.freeze = false
	craft.linear_velocity = Vector3(0, 0, 12)
	for frame in 45: await get_tree().physics_frame
	check(is_instance_valid(craft) and craft.get_meta("gear_sheared", false), "%d horizontal deck edge did not shear gear" % number)
	print("HELICOPTER_GEAR_EDGE id=", number, " sheared=", craft.get_meta("gear_sheared", false) if is_instance_valid(craft) else false)
	await clear_case()

func landing_cases(deck: bool, heavy: bool) -> void:
	var records: Array[Dictionary] = []
	for number in FLEET:
		var floor_body: PhysicsBody3D = Deck.new() if deck else StaticBody3D.new()
		floor_body.add_to_group("carrier" if deck else "terrain")
		if deck:
			floor_body.velocity = Vector3(0, 0, 8)
			floor_body.collision_mask = 0
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(80, 2, 300)
		shape.shape = box
		shape.position.y = -1
		floor_body.add_child(shape)
		host.add_child(floor_body)
		floor_body.position = Vector3(number * 100, 1400, 0)
		floor_body.set_physics_process(false)
		var craft := spawn(number)
		while not craft.runtime_initialized: await get_tree().process_frame
		# Rotor coasting at low RPM models a failed autorotation flare. Retain
		# normal flight, suspension and damage processing throughout the drop.
		prime(craft)
		craft.get_node("PartDamageModel").damage_zone(&"engine", 1000)
		craft.get_node("SimpleAero").rotor_energy.rpm = 0.2
		craft.get_node("Engine").engine_set_power(0.0)
		var gear: AircraftModule_LandingGear = craft.get_node("LandingGear")
		var bottom := 0.0
		for collider in gear.gear_collision_shapes + gear.auxiliary_safe_collision_shapes:
			var bounds: AABB = collider.transform * collider.shape.get_debug_mesh().get_aabb()
			bottom = minf(bottom, bounds.position.y)
		craft.position = floor_body.position + Vector3.UP * (0.7 - bottom)
		var record := {"craft":craft, "floor":floor_body, "number":number, "sheared":false, "belly":false, "exploded":false, "touchdown":{}, "max_speed_after_shear":0.0}
		craft.destroyed.connect(func(): record.exploded = true)
		craft.touchdown.connect(func(details: Dictionary):
			if record.touchdown.is_empty(): record.touchdown = details.duplicate())
		records.append(record)
	for record in records:
		record.floor.set_physics_process(true)
		record.craft.freeze = false
		record.craft.linear_velocity = Vector3(0, -11 if heavy else -2, 6 if heavy else 0) + VelocityFrame.get_node_velocity(record.floor)
	for frame in 600:
		await get_tree().physics_frame
		for record in records:
			if not is_instance_valid(record.craft) or record.exploded: continue
			var craft: Aircraft = record.craft
			record.sheared = record.sheared or craft.get_meta("gear_sheared", false)
			record.belly = record.belly or craft.get_meta("ground_landing_mode", "") == "belly"
			if record.sheared:
				record.max_speed_after_shear = maxf(record.max_speed_after_shear, (craft.linear_velocity - VelocityFrame.get_node_velocity(record.floor)).length())
	for record in records:
		var label := "%d %s %s" % [record.number, "deck" if deck else "terrain", "heavy" if heavy else "gentle"]
		check(record.sheared == heavy, label + " incorrect gear failure")
		var survived: bool = is_instance_valid(record.craft) and not record.exploded and not record.craft.get_meta("pilot_dead", false)
		check(survived, label + " pilot/aircraft did not survive")
		var speed := INF
		if survived:
			var craft: Aircraft = record.craft
			speed = (craft.linear_velocity - VelocityFrame.get_node_velocity(record.floor)).length()
			check(speed < 1.0, label + " did not settle: " + str(speed))
			if heavy: check(record.belly, label + " did not reach belly support")
		print("HELICOPTER_GEAR_LANDING ", label, " sheared=", record.sheared, " belly=", record.belly, " survived=", survived, " speed=", speed, " touchdown=", record.touchdown)
	await clear_case()
