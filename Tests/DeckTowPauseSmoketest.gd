extends SceneTree

var failures: Array[String] = []
var done := false

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	await process_frame
	for child in root.get_children(): child.process_mode = Node.PROCESS_MODE_DISABLED
	var carrier := Node3D.new()
	root.add_child(carrier)
	current_scene = carrier
	var manager = load("res://Tests/Fixtures/DeckTowSuspensionFixture.gd").new()
	carrier.add_child(manager)
	manager._aircraft_move_speed = 10.0
	var aircraft := RigidBody3D.new()
	aircraft.freeze = true
	carrier.add_child(aircraft)
	var bot := SimpleTractorBot.new()
	carrier.add_child(bot)
	bot.is_active = true
	bot.movement_disabled = true
	var bots: Array[Node3D] = [bot]
	manager.tractor_bots.assign(bots)
	for parallel in [false, true]:
		aircraft.position = Vector3(0, 2, 0)
		bot.position = Vector3(1, 0, 0)
		done = false
		paused = true
		move(manager, aircraft, Vector3(0, 2, 20), bots, parallel)
		for frame in 20: await physics_frame
		check(aircraft.position.is_equal_approx(Vector3(0, 2, 0)), "tow started while already paused")
		check(bot.position.is_equal_approx(Vector3(1, 0, 0)), "tractor started while already paused")
		paused = false
		for frame in 20: await physics_frame
		paused = true
		var held_aircraft := aircraft.global_transform
		var held_bot := bot.global_transform
		for frame in 180: await physics_frame
		check(aircraft.global_transform.is_equal_approx(held_aircraft), "aircraft moved while paused, parallel=%s" % parallel)
		check(bot.global_transform.is_equal_approx(held_bot), "tractor moved while paused, parallel=%s" % parallel)
		check(not done, "tow completed during pause")
		paused = false
		for frame in 3: await physics_frame
		check(aircraft.position.z > held_aircraft.origin.z, "tow must resume")
		check(aircraft.position.z - held_aircraft.origin.z < 2.0, "resume must not fast-forward paused time")
		for frame in 180:
			if done: break
			await physics_frame
		check(done and absf(aircraft.position.z - 20.0) < 0.01, "tow must finish at its destination")
	for failure in failures: push_error(failure)
	print("DECK_TOW_PAUSE_%s" % ("PASS" if failures.is_empty() else "FAIL"))
	carrier.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func move(manager: Node, aircraft: RigidBody3D, target: Vector3, bots: Array[Node3D], parallel: bool) -> void:
	if parallel:
		await manager._move_parallel_aircraft_horizontally(aircraft, target, bots)
	else:
		await manager._move_aircraft_horizontally(aircraft, target)
	done = true

func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
