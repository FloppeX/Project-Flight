extends SceneTree

var failures: Array[String] = []
var carrier: Node3D
var bots: Array[SimpleTractorBot] = []
var wheels: Array[Node3D] = []
var minimum_separation := INF

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	await process_frame
	for child in root.get_children(): child.process_mode = Node.PROCESS_MODE_DISABLED
	carrier = Node3D.new()
	root.add_child(carrier)
	current_scene = carrier
	var aircraft := RigidBody3D.new()
	aircraft.freeze = true
	carrier.add_child(aircraft)
	aircraft.add_to_group("aircraft")
	for offset in [Vector3(0, 0.5, 4), Vector3(-2, 0.5, -1), Vector3(2, 0.5, -1)]:
		var wheel := CollisionShape3D.new()
		wheel.name = "GearCollider%d" % wheels.size()
		wheel.shape = SphereShape3D.new()
		aircraft.add_child(wheel)
		wheel.position = offset
		wheels.append(wheel)
	for index in 3:
		var bot := SimpleTractorBot.new()
		carrier.add_child(bot)
		bots.append(bot)
	# Opposite-side starts exercise crossings around the landing gear.
	for yaw in [0.0, 0.7]:
		aircraft.rotation.y = yaw
		for index in 3:
			bots[index].position = aircraft.to_global([Vector3(-7, 0.5, 8), Vector3(7, 0.5, -4), Vector3(-7, 0.5, -4)][index])
			bots[index].activate(aircraft, Vector3.ZERO, wheels[index])
		var complete := false
		for tick in 2400:
			await physics_frame
			audit()
			if tick == 40:
				paused = true
				var held := bots[0].global_transform
				for frame in 40: await physics_frame
				check(bots[0].global_transform.is_equal_approx(held), "approach moved during pause")
				paused = false
			if tick == 80:
				carrier.position += Vector3(100, 0, -100)
				carrier.rotate_y(0.2)
			if bots.all(func(bot): return bot.is_positioned):
				complete = true
				break
		check(complete, "all bots must dock, yaw=%s states=%s" % [yaw, bots.map(func(bot): return bot.get_recovery_debug_status())])
		var starts: Array[Vector3] = []
		var retreats: Array[Vector3] = []
		for bot in bots:
			starts.append(bot.position)
			bot.deactivate()
			retreats.append(bot._withdrawal)
		var homes: Array[Vector3] = [Vector3(7, 0.5, 10), Vector3(7, 0.5, -6), Vector3(-7, 0.5, -6)]
		complete = false
		for tick in 2400:
			await physics_frame
			var done := true
			for index in 3:
				var bot := bots[index]
				done = bot.move_deck_transit(homes[index], 4.5, 1.0 / 60.0) and done
				if bot._withdrawal != Vector3.INF:
					var closest := Geometry3D.get_closest_point_to_segment(bot.position, starts[index], retreats[index])
					check(bot.position.distance_to(closest) < 0.01, "departure must reverse along docking line")
			audit()
			if done:
				complete = true
				break
		check(complete, "all bots must return around each other, yaw=%s positions=%s" % [yaw, bots.map(func(bot): return bot.position)])
		carrier.transform = Transform3D.IDENTITY
	# Head-on exchange of occupied slots must yield and finish, without deadlock.
	bots[0].position = Vector3(-6, 0.5, 12)
	bots[1].position = Vector3(6, 0.5, 12)
	bots[2].position = Vector3(0, 0.5, 20)
	var swapped := false
	for tick in 1200:
		var left_done := bots[0].move_deck_transit(Vector3(6, 0.5, 12), 4.5, 1.0 / 60.0)
		var right_done := bots[1].move_deck_transit(Vector3(-6, 0.5, 12), 4.5, 1.0 / 60.0)
		audit()
		if left_done and right_done:
			swapped = true
			break
	check(swapped, "head-on slot exchange deadlocked")
	# Permanently occupied destination must never become a timeout teleport.
	bots[0].position = Vector3(-4, 0.5, 12)
	bots[1].position = Vector3(0, 0.5, 12)
	bots[2].position = Vector3(7, 0.5, 12)
	for tick in 120:
		bots[0].move_deck_transit(bots[1].position, 20.0, 1.0 / 60.0)
		audit()
	check(bots[0].position.distance_to(bots[1].position) >= 2.099, "blocked robot ghosted through peer")
	bots[0].position = Vector3(-6, 0.5, 12)
	bots[1].position = Vector3(0, 0.5, 12)
	bots[2].position = Vector3(7, 0.5, 20)
	check(not bots[0].can_tow_step(Vector3(12, 0, 0), [bots[0]]), "towing swept through a stationary bot")
	bots[1].position.z = 20
	check(bots[0].can_tow_step(Vector3(12, 0, 0), [bots[0]]), "tow did not become clear after blocker left")
	for failure in failures: push_error(failure)
	print("TRACTOR_ROUTING_%s minimum_separation=%.3f" % ["PASS" if failures.is_empty() else "FAIL", minimum_separation])
	carrier.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func audit() -> void:
	for index in bots.size():
		var bot := bots[index]
		for other in bots.slice(index + 1):
			var distance: float = bot.global_position.distance_to(other.global_position)
			minimum_separation = minf(minimum_separation, distance)
			check(not bot._peer_sweep_blocked(other, bot.global_position), "bots overlap")
		for wheel in wheels:
			if wheel == bot.target_wheel_node and (bot.is_positioned or bot._approach_phase == SimpleTractorBot.ApproachPhase.DRIVE_TO_GEAR): continue
			if bot._withdrawal != Vector3.INF and bot._withdraw_wheel != null and bot._withdraw_wheel.get_ref() == wheel: continue
			check(Vector2(bot.global_position.x, bot.global_position.z).distance_to(Vector2(wheel.global_position.x, wheel.global_position.z)) >= 1.245, "bot crossed landing gear")

func check(ok: bool, message: String) -> void:
	if not ok and not failures.has(message): failures.append(message)
