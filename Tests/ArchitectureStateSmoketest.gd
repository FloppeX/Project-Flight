extends Node

const RuntimeState = preload("res://Aircraft/AircraftRuntimeState.gd")
const AirTaskModel = preload("res://AI/AirTask.gd")

class RejectingRecoveryPilot:
	extends AIPilot
	func _ready() -> void: pass
	func _physics_process(_delta: float) -> void: pass
	func _process(_delta: float) -> void: pass
	func _find_approach_waypoints() -> bool: return false

var errors: Array[String] = []


func _ready() -> void:
	if not has_meta("runner"):
		# A separate driver survives the real SceneTree transition under test.
		var runner := get_script().new() as Node
		runner.set_meta("runner", true)
		get_tree().root.add_child.call_deferred(runner)
		return
	_run.call_deferred()


func _run() -> void:
	await get_tree().process_frame
	for service in [AirOpsManager, GroundOpsManager, OperationsCoordinator, EnemyOpsManager, SaveGameManager]:
		service.set_process(false)
		service.set_physics_process(false)
	_test_rejected_command()
	await _test_virtual_aircraft()
	_test_cancelled_materialization()
	_test_invalid_enemy_restore()
	await _test_scene_reset()
	for message in errors:
		push_error(message)
	print("[ArchitectureStateSmoketest] %s rejection+virtualization+restore+scene_reset" % ("PASS" if errors.is_empty() else "FAIL"))
	get_tree().quit(0 if errors.is_empty() else 1)


func _test_rejected_command() -> void:
	var pilot := RejectingRecoveryPilot.new()
	add_child(pilot)
	var original := AirTaskModel.patrol(Vector3(300, 800, 400))
	pilot.current_air_task = original
	pilot.current_state = AIPilot.State.SEARCH
	pilot._air_task_return_active = true
	pilot._recovery_go_around_attempt_count = 3
	var rejected := AirTaskModel.recover()
	rejected.requested_speed_mps = 150.0
	rejected.requested_altitude_m = 2500.0
	_check(not pilot.assign_air_task(rejected), "missing approach rejects recovery")
	_check(pilot.current_air_task == original and pilot._air_task_return_active, "rejected recovery preserves prior task")
	_check(pilot.current_state == AIPilot.State.SEARCH and pilot._recovery_go_around_attempt_count == 3, "rejected recovery preserves state and attempt count")
	pilot.free()


func _test_virtual_aircraft() -> void:
	var flight := EnemyVirtualFlight.new()
	get_tree().current_scene.add_child(flight)
	var scenes: Array[PackedScene] = [load("res://Aircraft/Aircraft_1.tscn")]
	var loadouts: Array[String] = ["guns"]
	flight.setup(Vector3.ZERO, scenes, loadouts)
	flight.mission = EnemyVirtualFlight.Mission.INTERCEPT
	flight._begin_materialize()
	flight._tick_materialize_step()
	_check(flight.active_aircraft.size() == 1, "enemy aircraft materializes")
	if flight.active_aircraft.is_empty():
		flight.queue_free()
		return
	var aircraft: Node3D = flight.active_aircraft[0]
	aircraft.process_mode = Node.PROCESS_MODE_DISABLED
	aircraft.set("freeze", true)
	await get_tree().process_frame
	aircraft.set("current_health", 63.0)
	var fuel_found := false
	var weapon_found := false
	for node in aircraft.find_children("*", "", true, false):
		if "EnergyType" in node and str(node.get("EnergyType")) == "fuel":
			node.set("current_level", 17.0)
			fuel_found = true
		if node is Hardpoint and is_instance_valid(node.weapon_instance):
			node.weapon_instance.ammo_count = 7
			weapon_found = true
	var damage := aircraft.find_child("PartDamageModel", true, false) as AircraftPartDamageModel
	_check(damage != null and fuel_found and weapon_found, "fixture has damage, fuel and weapon systems")
	if damage != null:
		damage.damage_zone(AircraftPartDamageModel.ZONE_HORIZONTAL_STABILIZER, 100000.0)
	var before := RuntimeState.capture(aircraft)
	flight.dematerialize()
	_check(flight.mission == EnemyVirtualFlight.Mission.INTERCEPT, "virtualization preserves mission")
	var saved := flight.capture_save_state()
	var legacy := saved.duplicate(true)
	legacy.erase("runtime_slots")
	_check(EnemyVirtualFlight.validate_save_state(legacy), "older enemy checkpoints without combat snapshots remain valid")
	# This fixture has no investigation/intercept target; avoid legacy infinity
	# sentinels obscuring the combat-state round trip with JSON parser warnings.
	saved.intercept_position = Vector3.ZERO
	saved.investigation_position = Vector3.ZERO
	# Exercise the same encode/decode boundary used by campaign checkpoints.
	saved = SaveGameManager._decode_json_value(JSON.parse_string(JSON.stringify(SaveGameManager._encode_json_value(saved))))
	await get_tree().process_frame
	_check(flight.restore_save_state(saved), "virtual combat state restores through checkpoint encoding")
	flight._begin_materialize()
	flight._tick_materialize_step()
	var restored: Node3D = flight.active_aircraft[0]
	restored.process_mode = Node.PROCESS_MODE_DISABLED
	restored.set("freeze", true)
	await get_tree().process_frame
	var after := RuntimeState.capture(restored)
	_check(before == after, "health, ammunition, fuel and part damage survive rematerialization")
	flight.dematerialize()
	flight.queue_free()
	await get_tree().process_frame


func _test_cancelled_materialization() -> void:
	var prototype := Node3D.new()
	var packed := PackedScene.new()
	packed.pack(prototype)
	prototype.free()
	var flight := EnemyVirtualFlight.new()
	get_tree().current_scene.add_child(flight)
	var scenes: Array[PackedScene] = [packed, packed]
	var loadouts: Array[String] = ["guns", "guns"]
	flight.setup(Vector3.ZERO, scenes, loadouts)
	flight._begin_materialize()
	flight._tick_materialize_step()
	_check(flight.vstate == EnemyVirtualFlight.VState.MATERIALIZING, "fixture interrupts partial materialization")
	flight.active_aircraft[0].queue_free()
	flight.dematerialize()
	_check(flight.aircraft_count == 1 and flight._aircraft_slots.size() == 1, "partial cancellation keeps unspawned slot without resurrecting loss")
	flight.queue_free()


func _test_invalid_enemy_restore() -> void:
	var base := EnemyBase.new()
	var bases: Array[EnemyBase] = [base]
	var original := {"type": "carrier", "position": Vector3(10, 0, 10), "ttl": 90.0}
	EnemyOpsManager._known_contacts = [original]
	var invalid := {"base_entries": [{"base_index": 0, "flights": [{}], "platoons": []}]}
	_check(not EnemyOpsManager.restore_save_state(invalid, bases), "malformed enemy unit rejects checkpoint")
	_check(EnemyOpsManager._known_contacts == [original], "failed validation preserves existing enemy state")
	_check(not RuntimeState.validate({"modules": ["invalid"]}), "malformed runtime module state rejected")
	_check(EnemyVirtualPlatoon.validate_save_state({"vehicle_count": 1,
		"vehicle_scene_paths": ["res://GroundVehicle/vehicle_friendly_light.tscn", "res://GroundVehicle/vehicle_friendly_light.tscn"]}),
		"ground casualty count can be smaller than original scene palette")
	var valid := {"base_entries": [{"base_index": 0, "flights": [], "platoons": []}]}
	_check(EnemyOpsManager.restore_save_state(valid, bases), "empty valid enemy inventory restores")
	base.free()


func _test_scene_reset() -> void:
	var old_flight: Flight = AirOpsManager.flights[0]
	old_flight.mission_source = "player"
	old_flight.mission = Flight.Mission.RTB
	GroundOpsManager.order_hold("Ember")
	GroundOpsManager._deploy_queue.append("Ember")
	var old_platoon := GroundOpsManager.get_platoon("Ember")
	GroundOpsManager.rescue_service.returning["Ember"] = old_platoon
	EnemyOpsManager._known_contacts = [{"type": "carrier", "ttl": 90.0}]
	GameSession._pending_save_state = {"campaign": {"sentinel": true}}
	GameSession.trailer_camera_presets["reset_test"] = 42
	var next_root := Node3D.new()
	var next_scene := PackedScene.new()
	next_scene.pack(next_root)
	next_root.free()
	_check(get_tree().change_scene_to_packed(next_scene) == OK, "scene transition starts")
	await get_tree().scene_changed
	_check(AirOpsManager.flights[0].mission_source == "automatic", "scene transition clears flight ownership")
	_check(GroundOpsManager._deploy_queue.is_empty() and GroundOpsManager.rescue_service.returning.is_empty(), "scene transition cancels deployment and rescue")
	_check(GroundOpsManager.is_automatically_available(GroundOpsManager.get_platoon("Ember")), "new platoon has no old objective")
	_check(OperationsCoordinator.get_all_statuses().all(func(status): return not status.has("order")), "old coordinator assignments removed")
	_check(EnemyOpsManager._known_contacts.is_empty(), "old enemy intelligence removed")
	_check(GameSession.has_pending_save_state() and GameSession.trailer_camera_presets.reset_test == 42, "checkpoint payload and preferences survive runtime reset")
	GameSession.finish_loaded_game()


func _check(passed: bool, message: String) -> void:
	if not passed:
		errors.append(message)
