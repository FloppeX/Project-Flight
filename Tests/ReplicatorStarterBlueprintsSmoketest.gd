extends Node
const CATALOG := preload("res://LandCarrier/ReplicatorCatalog.gd")
const DECK := preload("res://LandCarrier/FlightDeckManager.gd")
const STORES := preload("res://LandCarrier/CarrierManager.gd")

class TestDeck extends DECK:
	func _ready() -> void:
		add_to_group("flight_deck_manager")
	func _physics_process(_delta: float) -> void:
		pass

class TestBay extends Node:
	var stored_vehicles := 14
	var stored_harvesters := 0
	var max_bay_capacity := 16

var failures: Array[String] = []

func _ready() -> void:
	_run.call_deferred()

func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("REPLICATOR_STARTERS_FAIL: " + message)

func _run() -> void:
	await get_tree().process_frame
	var ops := get_tree().root.get_node("AirOpsManager")
	ops.set_process(false)
	ops.assembly.set_process(false)
	var carrier := Node3D.new()
	add_child(carrier)
	var stores := STORES.new()
	carrier.add_child(stores)
	var bay := TestBay.new()
	bay.name = "VehicleBayManager"
	carrier.add_child(bay)
	var deck := TestDeck.new()
	deck.name = "FlightDeckManager"
	carrier.add_child(deck)
	deck.carrier_manager = stores
	deck.max_hangar_capacity = 12
	for index in range(10):
		deck.stored_aircraft.append({"name": "Existing Kestrel", "scene_file": "res://Aircraft/Aircraft_5.tscn", "metadata": {"airframe_id": "seed_%d" % index}})
	var manager: Node = stores.get_replicator()
	manager.set_process(false)
	_expect(manager.known_blueprints == CATALOG.STARTER_IDS, "all eight starter blueprints granted on creation")
	# Returning and preparing aircraft still own their hangar slots.
	var airborne := RigidBody3D.new()
	airborne.freeze = true
	airborne.scene_file_path = "res://Aircraft/Aircraft_5.tscn"
	airborne.set_meta("airframe_id", "airborne")
	carrier.add_child(airborne)
	airborne.add_to_group("friendlies")
	_expect(not manager.order_blocker("aircraft_5", 2).is_empty(), "returning aircraft reserve hangar capacity")
	airborne.free()
	deck._parallel_launch_jobs[1] = {"aircraft_data": {"scene_file": "res://Aircraft/Aircraft_5.tscn", "metadata": {"airframe_id": "preparing"}}}
	_expect(not manager.order_blocker("aircraft_11", 2).is_empty(), "parallel preparation reserves hangar capacity")
	deck._parallel_launch_jobs.clear()
	var expected_plasteel := 1000
	var expected_corium := 1000
	for id in CATALOG.STARTER_IDS:
		var recipe := CATALOG.recipe(id)
		_expect(manager.place_order(id, 1).is_empty(), "starter can be queued: " + id)
		expected_plasteel -= int(recipe.plasteel)
		expected_corium -= int(recipe.corium)
	_expect(stores.plasteel_units == expected_plasteel and stores.corium_units == expected_corium, "mixed queue spends each recipe's real costs")
	_expect(manager.queue.size() == 8, "mixed fabrication queue keeps all eight jobs")
	_expect(manager.inventory_snapshot().reserved == 2, "both vehicle types reserve vehicle slots")
	_expect(manager.airframe_inventory().reserved == 2, "both aircraft recipes reserve shared hangar capacity")
	_expect(not manager.place_order("aircraft_5", 1).is_empty(), "queued airframes cannot overbook hangar")
	# Upgrade a save made before the starter catalogue existed.
	var saved: Dictionary = stores.capture_save_state()
	saved.replicator.known_blueprints = ["light_combat_vehicle"]
	stores.restore_save_state(saved)
	_expect(manager.known_blueprints.has("kmv_explorer") and manager.known_blueprints.has("light_combat_vehicle") and manager.known_blueprints.size() == 9 and manager.queue.size() == 8, "old saves gain Explorer while preserving unlocked Sabretooth and mixed queue")
	var console := get_tree().root.get_node("CarrierConsole")
	console.show_page("replicator", true)
	await get_tree().process_frame
	var page: Control = console.get("_replicator_page")
	var chamber: Node3D = page.get("_chamber")
	var delivered_airframes: Array[String] = []
	for id in CATALOG.STARTER_IDS:
		var recipe := CATALOG.recipe(id)
		manager.advance(0.01)
		manager.advance(2.0)
		manager.advance(float(recipe.duration_s) * 0.5)
		var halfway: Dictionary = manager.chamber_snapshot()
		_expect(halfway.recipe == id and is_equal_approx(float(halfway.progress), 0.5), "recipe-specific duration and camera state: " + id)
		if "--rendered" in OS.get_cmdline_user_args():
			await _capture(page, id, "building")
		var mid_save: Dictionary = manager.capture_save_state()
		manager.restore_save_state(mid_save)
		_expect(is_equal_approx(float(manager.chamber_snapshot().progress), 0.5), "mixed job progress survives restore: " + id)
		manager.advance(float(recipe.duration_s) * 0.5)
		manager.advance(5.0)
		manager.advance(2.0)
		# These state probes skip simulation time; resume the feed just as opening
		# the tab after off-camera fabrication does. Continuous welding is covered
		# by ReplicatorAssemblySmoketest and the --preweld rendered probe.
		chamber.resume_feed()
		chamber.set_feed_state(manager.chamber_snapshot(), false)
		chamber._process(0.016)
		var visual: Dictionary = chamber.get_debug_snapshot()
		_expect(visual.recipe == id and visual.piece_count > 0 and visual.visible_pieces == visual.piece_count, "finished visual matches recipe: " + id)
		var counts: Array[int] = []
		for stage in range(5):
			var visual_state: Dictionary = manager.chamber_snapshot()
			visual_state.stage = stage
			visual_state.progress = (stage + 0.5) / 5.0
			chamber.resume_feed()
			chamber.set_feed_state(visual_state, false)
			chamber._process(0.016)
			counts.append(int(chamber.get_debug_snapshot().visible_pieces))
		var increases := 0
		for stage in range(1, 5):
			increases += 1 if counts[stage] > counts[stage - 1] else 0
		_expect(counts[0] > 0 and increases == 4, "five distinct visible assembly stages: " + id)
		print("REPLICATOR_STARTER_STAGES %s %s" % [id, str(counts)])
		if "--rendered" in OS.get_cmdline_user_args():
			await _capture(page, id, "ready")
		_expect(manager.phase == "rollout", "recipe transfers automatically: " + id)
		manager.advance(3.0)
		manager.advance(3.0)
		if str(recipe.category) == "AIRFRAMES":
			var entry: Dictionary = deck.stored_aircraft.back()
			_expect(str(entry.scene_file) == str(recipe.scene) and entry.metadata.fabricated, "correct aircraft scene delivered to actual hangar: " + id)
			_expect(entry.metadata.has("airframe_id") and not entry.metadata.has("assembly_flight") and not entry.metadata.has("assembly_pilot_id"), "new hull stays unassigned: " + id)
			if id == "aircraft_11":
				_expect(deck._stored_aircraft_is_helicopter(entry) and deck._count_stored_aircraft_for_kind("helicopter", "Aircraft_11") == 1, "fabricated Hummingbird is available to helicopter operations")
			delivered_airframes.append(str(entry.metadata.airframe_id))
		elif str(recipe.category) == "ORDNANCE":
			_expect(int(manager.ordnance_stores[id]) == int(recipe.output_count), "batch credits correct units: " + id)
	_expect(bay.stored_vehicles == 15 and bay.stored_harvesters == 1 and deck.stored_aircraft.size() == 12, "both destinations filled without overbooking and harvester stored separately")
	_expect(delivered_airframes[0] != delivered_airframes[1], "manufactured hulls have unique identities")
	_expect(ops.assembly.assign(delivered_airframes[0], "Archer").is_empty(), "fabricated Kestrel is usable by flight assembly")
	# A full vehicle bay/hangar must not prevent ammunition fabrication.
	_expect(manager.place_order("bullets", 1).is_empty(), "ammunition works with full bays")
	var paid_plasteel := stores.plasteel_units
	var paid_corium := stores.corium_units
	manager.advance(0.01)
	manager.advance(2.0)
	manager.advance(10.0)
	_expect(manager.cancel_order(int(manager.queue[0].id)), "ammunition job can cancel halfway")
	_expect(stores.plasteel_units == paid_plasteel + 6 and stores.corium_units == paid_corium + 1, "partial refund uses ammunition's own costs and duration")
	manager.advance(2.0)
	var campaign_stock: Dictionary = stores.capture_save_state()
	manager.ordnance_stores.bullets = 0
	stores.restore_save_state(campaign_stock)
	_expect(manager.ordnance_stores.bullets == 200 and manager.ordnance_stores.rockets == 6 and manager.ordnance_stores.gun_10mm == 1, "finished stores survive carrier save restore")
	page._refresh_all()
	_expect(page.get_debug_snapshot().blueprint_count == 9, "page lists eight starters plus the non-starter Sabretooth")
	console.set_open(false)
	carrier.free()
	if failures.is_empty():
		print("REPLICATOR_STARTERS_PASS eight_recipes+destinations+stages+capacity+save_upgrade+ordnance_batches+flight_assembly")
	get_tree().quit(0 if failures.is_empty() else 1)

func _capture(page: Control, recipe_id: String, state: String) -> void:
	page._on_blueprint_pressed(recipe_id)
	var chamber: Node3D = page.get("_chamber")
	chamber.resume_feed()
	if state == "building":
		for attempt in range(60):
			await get_tree().create_timer(0.15).timeout
			if int(page.get_debug_snapshot().chamber.welding_contacts) == 4:
				break
	else:
		await get_tree().create_timer(0.35).timeout
	await RenderingServer.frame_post_draw
	var capture := get_tree().root.get_texture().get_image()
	var path := ProjectSettings.globalize_path("user://replicator_starter_%s_%s.png" % [recipe_id, state])
	_expect(capture != null and capture.save_png(path) == OK, "rendered starter frame: " + recipe_id)
	print("REPLICATOR_STARTER_FRAME " + path)
