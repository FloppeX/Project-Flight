extends SceneTree

var failures: Array[String] = []
var tow_done := false

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	await process_frame
	for child in root.get_children():
		child.process_mode = Node.PROCESS_MODE_DISABLED
	var carrier := Node3D.new()
	root.add_child(carrier)
	current_scene = carrier
	carrier.position.y = 100.0
	var marker := Marker3D.new()
	carrier.add_child(marker)
	var deck := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	collision.shape = BoxShape3D.new()
	collision.shape.size = Vector3(200, 1, 200)
	collision.position.y = -0.5
	deck.add_child(collision)
	carrier.add_child(deck)
	var manager: Node = load("res://Tests/Fixtures/DeckTowSuspensionFixture.gd").new()
	manager.set("deck_marker", marker)
	manager.set("_aircraft_move_speed", 20.0)
	carrier.add_child(manager)
	for aircraft_id in [1, 2, 5]:
		var aircraft: RigidBody3D = load("res://Aircraft/Aircraft_%d.tscn" % aircraft_id).instantiate()
		aircraft.freeze = true
		aircraft.position = carrier.position + Vector3(0, 6, 0)
		root.add_child(aircraft)
		await process_frame
		await physics_frame
		stop(aircraft)
		var gear := aircraft.get_node("LandingGear")
		gear.call("deploy")
		for parallel in [false, true]:
			# Elevator top/landing handoff: derive body pose from real static loads,
			# never an aircraft-specific hard-coded clearance.
			aircraft.global_position = carrier.global_position + Vector3.ZERO
			aircraft.global_basis = carrier.global_basis
			check(manager.call("settle_aircraft_on_landing_deck", aircraft), "static supported pose")
			manager.call("_prepare_aircraft_for_movement", aircraft)
			var start_local := carrier.to_local(aircraft.global_position)
			var max_drop := 0.0
			var max_wheel_error := 0.0
			tow_done = false
			# Catapult marker is on the deck, NOT at the aircraft body's height.
			var target := carrier.to_global(Vector3(start_local.x, 0, start_local.z + 20))
			tow(manager, aircraft, target, parallel)
			var ticks := 0
			while not tow_done and ticks < 180:
				await physics_frame
				ticks += 1
				max_drop = maxf(max_drop, absf(carrier.to_local(aircraft.global_position).y - start_local.y))
				var loads: Array = gear.call("get_static_load_compressions")
				for i in loads.size():
					var base: Vector3 = gear.call("get_gear_base_global_position", i)
					var predicted_contact := base.y - float(gear.call("get_wheel_rest_height", i)) + float(loads[i])
					max_wheel_error = maxf(max_wheel_error, absf(predicted_contact - marker.global_position.y))
				if not tow_done:
					carrier.position += Vector3(0.02, 0.001, 0.03)
					carrier.rotate_y(0.001)
					if ticks == 25:
						carrier.position -= Vector3(2048, 0, 2048)
						aircraft.position -= Vector3(2048, 0, 2048)
			check(tow_done, "tow completed")
			check(max_drop < 0.005, "Aircraft %d parallel=%s supported body drift %.4fm" % [aircraft_id, parallel, max_drop])
			check(max_wheel_error < 0.025, "Aircraft %d parallel=%s wheel support error %.4fm" % [aircraft_id, parallel, max_wheel_error])
			var local_end := carrier.to_local(aircraft.global_position)
			check(absf(local_end.z - start_local.z - 20) < 0.01, "tow reached carrier-relative launch position")
			print("DECK_TOW aircraft=%d parallel=%s body_drift=%.4f wheel_error=%.4f" % [aircraft_id, parallel, max_drop, max_wheel_error])
		aircraft.free()
	carrier.queue_free()
	await process_frame
	print("DECK_TOW_SUSPENSION_%s failures=%s" % ["PASS" if failures.is_empty() else "FAIL", failures])
	quit(0 if failures.is_empty() else 1)

func tow(manager: Node, aircraft: RigidBody3D, target: Vector3, parallel: bool) -> void:
	if parallel:
		var bots: Array[Node3D] = []
		await manager.call("_move_parallel_aircraft_horizontally", aircraft, target, bots)
	else:
		await manager.call("_move_aircraft_horizontally", aircraft, target)
	tow_done = true

func stop(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child in node.get_children():
		stop(child)

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
