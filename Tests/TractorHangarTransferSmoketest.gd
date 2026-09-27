extends Node

var completed := false
var destroyed_prepare_completed := false
var failures: Array[String] = []

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	var carrier := Node3D.new()
	add_child(carrier)
	var manager = load("res://Tests/Fixtures/DeckTowSuspensionFixture.gd").new()
	carrier.add_child(manager)
	var marker := Marker3D.new()
	carrier.add_child(marker)
	marker.position = Vector3(8, 0, -10)
	manager.elevator_pickup_marker = marker
	manager.recovery_elevator_pickup_marker = marker
	# A recovery aircraft may be destroyed while another elevator transfer blocks prep.
	var destroyed_aircraft := RigidBody3D.new()
	carrier.add_child(destroyed_aircraft)
	manager._tractor_elevator_transfer_in_progress = true
	prepare_destroyed(manager, destroyed_aircraft)
	await get_tree().physics_frame
	destroyed_aircraft.free()
	manager._tractor_elevator_transfer_in_progress = false
	for tick in 3:
		await get_tree().physics_frame
	check(destroyed_prepare_completed, "prep did not finish after aircraft was freed during transfer wait")
	check(manager._current_job_tractor_bots.is_empty(), "freed aircraft reserved tractor bots")
	var elevator := CarrierElevator.new()
	carrier.add_child(elevator)
	elevator.position = marker.position
	manager.elevator = elevator
	manager.recovery_elevator = elevator
	var bots: Array[Node3D] = []
	for z in [-15.5, -12.0, -8.0, -4.5]:
		var bot := SimpleTractorBot.new()
		carrier.add_child(bot)
		bot.position = Vector3(4.5, -9.5, z)
		bots.append(bot)
		manager.tractor_bots.append(bot)
		manager._tractor_home_transforms_local[bot.get_instance_id()] = bot.transform
	var heli = load("res://Aircraft/Aircraft_11.tscn").instantiate()
	# Only the authored transforms and landing gear are needed here.
	strip_scripts(heli)
	carrier.add_child(heli)
	heli.freeze = true
	heli.position = Vector3(8, -9.5, -10)
	var wheels: Array[Node3D] = manager._get_launch_wheel_nodes(heli)
	for i in 2:
		bots[i].activate(heli, Vector3.ZERO, wheels[i])
		bots[i].finish_hangar_docking()
		bots[i].position.y = -9.5
		manager._set_cleanup_idle_for_tractor_bot(bots[i])
	# The third bot's home blocks the helicopter bot's mandatory reverse leg.
	for tick in 120:
		bots[1].move_deck_transit(Vector3(4.5, -9.5, -12), 4.5, 1.0 / 60.0)
	var held_position := bots[1].position
	bots[1].move_deck_transit(Vector3(4.5, -9.5, -12), 4.5, 1.0 / 60.0)
	check(bots[1].position.is_equal_approx(held_position), "live gear departure crossed the idle bot")
	check(bots[1]._withdrawal != Vector3.INF, "live gear lost its reverse departure")
	heli.free()
	var aircraft = load("res://Aircraft/Aircraft_5.tscn").instantiate()
	strip_scripts(aircraft)
	carrier.add_child(aircraft)
	aircraft.freeze = true
	aircraft.position = Vector3(0, 0, -50)
	manager._tractorbots_in_hangar = true
	prepare(manager, aircraft)
	for tick in 2400:
		await get_tree().physics_frame
		if completed: break
	check(completed, "hangar fetch stalled after helicopter storage: %s" % [bots.map(func(b): return b.position)])
	check(not manager._tractor_elevator_transfer_in_progress, "transfer flag stayed set")
	check(not manager._tractorbots_in_hangar, "recovery bots remained in hangar")
	check(manager._current_job_tractor_bots.size() == 3, "fixed wing did not receive three bots")
	var slots: Array[Vector3] = manager._get_primary_elevator_slots_local(3, manager._get_elevator_platform_top_local_y())
	for i in 3:
		check(bots[i].position.distance_to(slots[i]) < 0.05, "bot %d did not reach the raised elevator slot" % i)
		check(bots[i]._withdrawal == Vector3.INF, "bot retained a departure from deleted gear")
	for failure in failures: push_error(failure)
	print("TRACTOR_HANGAR_TRANSFER_%s" % ("PASS" if failures.is_empty() else "FAIL"))
	carrier.queue_free()
	await get_tree().process_frame
	get_tree().quit(0 if failures.is_empty() else 1)

func prepare(manager, aircraft) -> void:
	await manager._prepare_tractorbots_for_recovery_job(aircraft)
	completed = true

func prepare_destroyed(manager, aircraft) -> void:
	await manager._prepare_tractorbots_for_recovery_job(aircraft)
	destroyed_prepare_completed = true

func strip_scripts(node: Node) -> void:
	for child in node.get_children(): strip_scripts(child)
	node.set_script(null)

func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
