extends SceneTree

var failures: Array[String] = []
var returned := false
var rendered := false
var captured_aircraft_id := 2

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	await process_frame
	for child in root.get_children(): child.process_mode = Node.PROCESS_MODE_DISABLED
	var carrier := Node3D.new()
	root.add_child(carrier)
	current_scene = carrier
	var marker := Marker3D.new()
	carrier.add_child(marker)
	var manager = load("res://Tests/Fixtures/DeckTowSuspensionFixture.gd").new()
	manager.deck_marker = marker
	carrier.add_child(manager)
	rendered = OS.get_cmdline_user_args().has("--render")
	if rendered:
		var camera := Camera3D.new()
		carrier.add_child(camera)
		camera.position = Vector3(15, 20, 22)
		camera.look_at(Vector3.ZERO)
		camera.current = true
		var sun := DirectionalLight3D.new()
		carrier.add_child(sun)
		sun.rotation_degrees = Vector3(-65, -30, 0)
		var deck := MeshInstance3D.new()
		deck.mesh = BoxMesh.new()
		deck.mesh.size = Vector3(32, 0.2, 36)
		deck.position.y = -0.1
		carrier.add_child(deck)
	var aircraft_ids: Array[int] = [1, 2, 5, 9, 10, 11, 13]
	if rendered: aircraft_ids = [2, 9]
	if OS.get_cmdline_user_args().has("--onlyskids"): aircraft_ids = [10, 11, 13]
	if OS.get_cmdline_user_args().has("--only11"): aircraft_ids = [11]
	for aircraft_id in aircraft_ids:
		var skid_helicopter: bool = aircraft_id in [10, 11, 13]
		captured_aircraft_id = aircraft_id
		var aircraft: RigidBody3D = load("res://Aircraft/Aircraft_%d.tscn" % aircraft_id).instantiate()
		aircraft.freeze = true
		carrier.add_child(aircraft)
		await process_frame
		stop(aircraft)
		aircraft.freeze = true
		aircraft.global_position = Vector3.ZERO
		manager.settle_aircraft_on_landing_deck(aircraft)
		var wheels: Array[Node3D] = manager._get_launch_wheel_nodes(aircraft)
		if skid_helicopter:
			var static_compressions: Array = aircraft.get_node("LandingGear").get_static_load_compressions()
			check(absf(float(static_compressions[0]) - float(static_compressions[2])) < 0.005
				and absf(float(static_compressions[1]) - float(static_compressions[3])) < 0.005,
				"Aircraft %d paired skid contacts received uneven static load" % aircraft_id)
			check(wheels.size() == 4, "Aircraft %d did not expose four skid contacts to tractors" % aircraft_id)
			for wheel in wheels:
				check("skid" in wheel.name.to_lower(), "Aircraft %d tractor target was not a skid contact" % aircraft_id)
		var bots: Array[Node3D] = []
		var homes: Array[Vector3] = []
		var count := mini(wheels.size(), 4)
		for index in count:
			var bot = load("res://LandCarrier/SimpleTractorBot.tscn").instantiate()
			carrier.add_child(bot)
			bot.position = Vector3(-10, 0, -9 + index * 4)
			homes.append(bot.position)
			bots.append(bot)
			if not skid_helicopter:
				bot.activate(aircraft, Vector3.ZERO, wheels[index])
		if skid_helicopter:
			manager.tractor_bots.clear()
			for bot in bots: manager.tractor_bots.append(bot)
			var assigned: Array[Node] = manager._activate_tractor_bots(aircraft)
			check(assigned.size() == 4, "Aircraft %d did not receive four tractor bots" % aircraft_id)
			for index in count:
				check(bots[index].target_wheel_node == wheels[index],
					"Aircraft %d tractor %d received the wrong skid contact" % [aircraft_id, index])
		var done := false
		var minimum := INF
		for tick in 3600:
			await physics_frame
			for i in count:
				for j in range(i + 1, count):
					minimum = minf(minimum, bots[i].global_position.distance_to(bots[j].global_position))
					check(not bots[i]._peer_sweep_blocked(bots[j], bots[i].global_position), "Aircraft %d oriented chassis overlap" % aircraft_id)
			if rendered and tick in [45, 150]: await capture("approach_%d" % tick)
			if bots.all(func(bot): return bot.is_positioned):
				done = true
				break
		check(done, "Aircraft %d docking failed: %s" % [aircraft_id, bots.map(func(bot): return bot.get_recovery_debug_status())])
		check(minimum >= 1.15, "Aircraft %d bots overlapped at %.3f" % [aircraft_id, minimum])
		if skid_helicopter and done:
			for tick in 120:
				aircraft.global_position += Vector3(0, 0, -0.025)
				await physics_frame
			for tick in 60: await physics_frame
			for index in count:
				var target: Vector3 = bots[index]._resolve_wheel_target_position()
				target.y = bots[index].global_position.y
				check(bots[index].global_position.distance_to(target) < 0.2,
					"Aircraft %d tractor %d lost its skid contact during tow: %s" % [aircraft_id, index, bots[index].get_recovery_debug_status()])
		if rendered: await capture("docked")
		for bot in bots: manager._set_cleanup_idle_for_tractor_bot(bot)
		returned = false
		go_home(manager, bots, homes)
		for tick in 3600:
			await physics_frame
			if tick == 10 and aircraft_id == 2:
				paused = true
				var held: Array = bots.map(func(bot): return bot.global_transform)
				for frame in 30: await physics_frame
				for index in bots.size(): check(bots[index].global_transform.is_equal_approx(held[index]), "manager transit moved while paused")
				paused = false
			if rendered and tick in [5, 30, 70]: await capture("departure_%d" % tick)
			if returned: break
		check(returned, "Aircraft %d return failed: %s" % [aircraft_id, bots.map(func(bot): return bot.position)])
		print("TRACTOR_AIRCRAFT id=%d docked=%s returned=%s min_separation=%.3f" % [aircraft_id, done, returned, minimum])
		for bot in bots: bot.free()
		aircraft.free()
	for failure in failures: push_error(failure)
	print("TRACTOR_AIRCRAFT_ROUTING_%s" % ("PASS" if failures.is_empty() else "FAIL"))
	carrier.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func capture(label: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://captures/tractor_a%d_%s.png" % [captured_aircraft_id, label])

func go_home(manager: Node, bots: Array[Node3D], homes: Array[Vector3]) -> void:
	await manager._move_nodes_to_local_targets(bots, homes, 4.5)
	returned = true

func stop(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child in node.get_children(): stop(child)

func check(ok: bool, message: String) -> void:
	if not ok and not failures.has(message): failures.append(message)
