extends SceneTree

class BayStub:
	extends Node
	var stored_vehicles := 14
	var max_bay_capacity := 16

class CarrierStub:
	extends Node3D
	var output := 1.0
	func get_system_capability(_id: String) -> float:
		return output

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("REPLICATOR_FAIL: " + message)

func _run() -> void:
	await process_frame
	var carrier := CarrierStub.new()
	root.add_child(carrier)
	var bay := BayStub.new()
	bay.name = "VehicleBayManager"
	carrier.add_child(bay)
	var stores: Node = load("res://LandCarrier/CarrierManager.gd").new()
	carrier.add_child(stores)
	var manager: Node = stores.get_replicator()
	# This transaction test explicitly unlocks the non-starter Sabretooth recipe.
	manager.known_blueprints.append("light_combat_vehicle")
	manager.set_process(false)
	_expect(manager.place_order("light_combat_vehicle", 2) == "", "two available slots accept two vehicles")
	_expect(stores.plasteel_units == 840 and stores.corium_units == 976, "real materials committed once")
	_expect(manager.place_order("light_combat_vehicle", 1) != "", "queue reserves capacity")
	_expect(manager.place_order("sand_sprite", 1) != "", "uncommissioned recipes cannot spend materials")
	var second_id := int(manager.queue[1].id)
	_expect(manager.cancel_order(second_id), "queued cancellation succeeds")
	_expect(stores.plasteel_units == 920 and stores.corium_units == 988, "queued cancellation fully refunds")
	var returning := Node3D.new()
	root.add_child(returning)
	returning.add_to_group("ground_vehicles")
	returning.add_to_group("friendlies")
	_expect(manager.place_order("light_combat_vehicle", 1) != "", "deployed vehicles retain return capacity")
	returning.free()
	manager.advance(0.01)
	manager.advance(2.0)
	_expect(manager.phase == "fabricating", "shield closes before fabrication")
	manager.advance(45.0)
	var snapshot: Dictionary = manager.chamber_snapshot()
	_expect(is_equal_approx(float(snapshot.progress), 0.5) and float(snapshot.shield) == 1.0, "mid-build shield and stage")
	var saved: Dictionary = stores.capture_save_state()
	manager.advance(45.0)
	manager.advance(5.0)
	manager.advance(2.0)
	_expect(manager.phase == "rollout" and bay.stored_vehicles == 14, "completed item transfers automatically after stow and shield opening")
	_expect(not manager.cancel_order(int(manager.queue[0].id)), "finished item cannot refund materials")
	_expect(stores.restore_save_state(saved), "carrier restores saved state")
	_expect(manager.phase == "fabricating" and is_equal_approx(float(manager.queue[0].elapsed), 45.0), "mid-build restores exact progress")
	manager.advance(45.0)
	manager.advance(5.0)
	manager.advance(2.0)
	_expect(manager.phase == "rollout", "completed item automatically starts transfer")
	var rollout_save: Dictionary = stores.capture_save_state()
	manager.advance(3.0)
	_expect(bay.stored_vehicles == 15 and manager.queue.is_empty(), "rollout delivers once into deployment inventory")
	_expect(manager.phase == "returning", "empty platform returns before next order")
	# Save system restores bay and stores as a pair. Restore the pre-delivery bay.
	bay.stored_vehicles = 14
	stores.restore_save_state(rollout_save)
	manager.advance(3.0)
	manager.advance(3.0)
	_expect(bay.stored_vehicles == 15 and manager.queue.is_empty(), "rollout restore cannot duplicate delivery")
	_expect(manager.place_order("light_combat_vehicle", 1) == "", "new job after delivery")
	manager.advance(0.01)
	manager.advance(2.0)
	manager.advance(45.0)
	_expect(manager.cancel_order(int(manager.queue[0].id)), "active build cancellation")
	_expect(stores.plasteel_units == 880 and stores.corium_units == 982, "half-build refunds only unused half")
	manager.advance(2.0)
	_expect(manager.phase == "idle", "cancel raises shield before next build")
	stores.plasteel_units = 0
	_expect(manager.place_order("light_combat_vehicle", 1) == "INSUFFICIENT MATERIALS", "insufficient stores reject atomically")
	var console := root.get_node("CarrierConsole")
	console.show_page("replicator", true)
	await process_frame
	var page: Control = console.get("_replicator_page")
	var page_snapshot: Dictionary = page.get_debug_snapshot()
	_expect(page_snapshot.mode == "live", "page connects to real manager")
	_expect(int(page_snapshot.chamber.arms) == 4 and int(page_snapshot.chamber.piece_count) > 5, "four arms and actual vehicle mesh pieces")
	var chamber: Node3D = page.get("_chamber")
	var counts: Array[int] = []
	for stage in range(5):
		chamber.resume_feed() # The fixture jumps elapsed time, as reopening the feed does.
		chamber.set_feed_state({"phase": "fabricating", "progress": (stage + 0.5) / 5.0, "stage": stage, "shield": 1.0, "rollout": 0.0}, false)
		chamber._process(0.016)
		var visual: Dictionary = chamber.get_debug_snapshot()
		counts.append(int(visual.visible_pieces))
	_expect(counts[0] > 0, "chassis appears at first stage")
	for stage in range(1, 5):
		_expect(counts[stage] > counts[stage - 1], "each stage adds authored pieces")
	console.set_open(false)
	page_snapshot = page.get_debug_snapshot()
	_expect(int(page_snapshot.camera_update_mode) == SubViewport.UPDATE_DISABLED, "hidden feed stops rendering")
	_expect(not bool(page_snapshot.chamber.hum_playing), "hidden feed stops hum")
	stores.plasteel_units = 1000
	stores.corium_units = 1000
	manager.place_order("light_combat_vehicle", 1)
	manager.advance(0.01)
	manager.advance(2.0)
	manager.set_process(true)
	await create_timer(0.08).timeout
	_expect(float(manager.queue[0].elapsed) > 0.0, "fabrication progresses while console is closed")
	manager.set_process(false)
	var before_pause := float(manager.queue[0].elapsed)
	manager.set_process(true)
	paused = true
	await create_timer(0.05, true).timeout
	_expect(float(manager.queue[0].elapsed) == before_pause, "pause does not fabricate")
	paused = false
	carrier.output = 0.0
	manager.advance(5.0)
	_expect(float(manager.queue[0].elapsed) == before_pause, "replicator or reactor loss suspends fabrication")
	carrier.output = 0.5
	manager.advance(2.0)
	_expect(is_equal_approx(float(manager.queue[0].elapsed), before_pause + 1.0), "damaged systems reduce fabrication rate")
	carrier.output = 1.0
	manager.advance(90.0)
	bay.stored_vehicles = 16
	manager.advance(5.0)
	manager.advance(2.0)
	_expect(manager.phase == "ready", "full destination holds completed item on platform")
	var held_save: Dictionary = manager.capture_save_state()
	manager.advance(20.0)
	_expect(manager.phase == "ready" and not manager.chamber_snapshot().delivery_blocker.is_empty(), "held delivery retries without needing a player click")
	manager.restore_save_state(held_save)
	bay.stored_vehicles = 15
	manager.advance(0.1)
	_expect(manager.phase == "rollout", "restored completed item starts automatically when space opens")
	bay.stored_vehicles = 16
	manager.advance(3.0)
	_expect(manager.phase == "transfer_wait" and float(manager.chamber_snapshot().rollout) == 1.0, "capacity change during transfer holds item at destination")
	var transfer_save: Dictionary = manager.capture_save_state()
	manager.restore_save_state(transfer_save)
	bay.stored_vehicles = 15
	manager.advance(0.1)
	_expect(manager.phase == "returning" and manager.queue.is_empty() and bay.stored_vehicles == 16, "destination retry delivers saved item once automatically")
	manager.advance(3.0)
	manager.advance(3.0)
	_expect(manager.phase == "idle" and bay.stored_vehicles == 16, "returning platform never duplicates delivered inventory")
	carrier.free()
	if failures.is_empty():
		print("REPLICATOR_PASS staged_piece_counts=%s" % str(counts))
		quit(0)
	else:
		quit(1)
