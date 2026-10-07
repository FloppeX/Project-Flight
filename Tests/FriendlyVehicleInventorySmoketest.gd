extends Node

const CATALOG := preload("res://LandCarrier/ReplicatorCatalog.gd")

class TestCarrier extends "res://LandCarrier/LandCarrier.gd":
	func _ready() -> void: pass
	func _physics_process(_delta: float) -> void: pass
	func get_system_capability(_id: String, _component: Node = null) -> float: return 1.0

class TestRamp extends "res://LandCarrier/VehicleRamp.gd":
	func _ready() -> void: pass
	func _physics_process(_delta: float) -> void: pass
	func is_deployed() -> bool: return true
	func get_bay_spawn_local() -> Vector3: return Vector3(0, 2, 0)
	func get_hinge_local() -> Vector3: return Vector3(0, 2, -5)

var failures: Array[String] = []

func _ready() -> void: _run.call_deferred()

func _run() -> void:
	get_tree().root.get_node("SaveGameManager").set("autosave_enabled", false)
	for child in get_tree().root.get_children():
		if child != self: child.process_mode = Node.PROCESS_MODE_DISABLED
	get_tree().create_timer(30).timeout.connect(func(): get_tree().quit(2))
	var carrier := TestCarrier.new()
	carrier.position.y = 100
	add_child(carrier)
	var ramp := TestRamp.new()
	carrier.add_child(ramp)
	carrier.vehicle_ramp = ramp
	var bay = load("res://LandCarrier/VehicleBayManager.gd").new()
	bay.name = "VehicleBayManager"
	carrier.add_child(bay)
	bay.set_physics_process(false)
	bay._ramp = ramp
	_check(bay.stored_explorers() == 15 and bay.stored_sabretooths == 0 and bay.stored_harvesters == 1, "new-game inventory is Explorer plus existing utility harvester")
	_check(bay.vehicle_scene.resource_path == bay.EXPLORER_SCENE, "new-game default is vehicle 1")
	var stores = load("res://LandCarrier/CarrierManager.gd").new()
	carrier.add_child(stores)
	var manager = stores.get_replicator()
	manager.set_process(false)
	_check(manager.known_blueprints.has("kmv_explorer") and not manager.known_blueprints.has("light_combat_vehicle"), "Explorer starter, Sabretooth locked")
	_check(manager.order_blocker("light_combat_vehicle", 1) == "BLUEPRINT UNAVAILABLE", "cannot build locked Sabretooth")
	var start_save: Dictionary = bay.capture_save_state()
	bay.restore_save_state(start_save)
	_check(bay.stored_explorers() == 15 and bay.stored_sabretooths == 0, "fresh save retains Explorer identity")
	# Exercise the real spawn path, not just the recipe/model dictionary.
	bay._deploy_queue = 1
	bay._spawn_next_vehicle()
	var explorer: Node3D = get_tree().get_nodes_in_group("ground_vehicles").back()
	_check(explorer.get_meta("vehicle_id", "") == "kmv_explorer" and explorer._all_wheel_nodes.size() == 4, "bay deploys actual four-wheel Explorer")
	explorer.set_physics_process(false)
	bay._on_vehicle_retrieved(explorer)
	_check(bay.stored_explorers() == 15 and bay.stored_sabretooths == 0, "returning Explorer stays Explorer")
	explorer.free()
	bay.restore_save_state({"stored_vehicles": 1, "stored_harvesters": 0, "stored_sabretooths": 1})
	bay._deploy_queue = 1
	bay._spawn_next_vehicle()
	var sabre: Node3D = get_tree().get_nodes_in_group("ground_vehicles").back()
	_check(sabre.get_meta("vehicle_id", "") == "kmv_sabretooth" and sabre._all_wheel_nodes.size() == 6, "bay deploys actual six-wheel Sabretooth")
	_check(bay.stored_sabretooths == 0 and bay.stored_vehicles == 0, "deployment consumes correct type")
	sabre.set_physics_process(false)
	bay._on_vehicle_retrieved(sabre)
	_check(bay.stored_sabretooths == 1 and bay.stored_explorers() == 0, "returning Sabretooth stays Sabretooth")
	sabre.free()
	_check(manager._deliver("kmv_explorer"), "fabricated Explorer delivered")
	_check(bay.stored_explorers() == 1 and bay.stored_sabretooths == 1, "fabrication credits correct type in mixed bay")
	_check(manager._deliver("light_combat_vehicle"), "existing completed Sabretooth delivered")
	_check(bay.stored_sabretooths == 2, "Sabretooth fabrication retains type")
	var mixed_save: Dictionary = bay.capture_save_state()
	bay.restore_save_state(mixed_save)
	_check(bay.stored_explorers() == 1 and bay.stored_sabretooths == 2, "mixed inventory round trip")
	bay.restore_save_state({"stored_vehicles": 5, "stored_harvesters": 0})
	_check(bay.stored_sabretooths == 5 and bay.stored_explorers() == 0, "legacy bay counts retain original Sabretooths")
	manager.restore_save_state({"known_blueprints": ["light_combat_vehicle"], "queue": [{"id": 1, "recipe": "light_combat_vehicle", "elapsed": 20}]})
	_check(manager.known_blueprints.has("kmv_explorer") and manager.known_blueprints.has("light_combat_vehicle"), "legacy unlocks retained and Explorer added")
	_check(CATALOG.recipe(manager.queue[0].recipe).scene == bay.SABRETOOTH_SCENE, "legacy queued build remains Sabretooth")
	for legacy in ["vehicle_friendly_light", "vehicle_friendly_2"]:
		var old: Node = load("res://GroundVehicle/%s.tscn" % legacy).instantiate()
		_check(old.get_meta("vehicle_id", "") == ("kmv_sabretooth" if legacy.ends_with("light") else "kmv_explorer"), "old scene path preserves vehicle identity")
		old.free()
	print("FRIENDLY_VEHICLE_INVENTORY_", "PASS" if failures.is_empty() else "FAIL", " failures=", failures)
	carrier.queue_free()
	await get_tree().process_frame
	get_tree().quit(0 if failures.is_empty() else 1)

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)
