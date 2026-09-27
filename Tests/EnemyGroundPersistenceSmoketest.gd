extends Node3D

class FlatPlatoon:
	extends EnemyVirtualPlatoon
	func _find_driveable_position_near(desired: Vector3, _reference: Vector3, _require_nav_anchor: bool = true) -> Vector3:
		return desired
	func _project_to_ground(point: Vector3) -> Vector3:
		return point
	func _scan_for_contacts(_immediate: bool) -> void:
		pass

const BUGGY := "res://GroundVehicle/vehicle_enemy_buggy.tscn"
const PICKUP := "res://GroundVehicle/vehicle_enemy_pickup.tscn"
var failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	await get_tree().process_frame
	AirOpsManager.set_process(false)
	GroundOpsManager.set_process(false)
	EnemyOpsManager.set_physics_process(false)
	SaveGameManager.set_process(false)
	var legacy := {"vehicle_count": 4, "vehicle_scene_paths": [BUGGY, PICKUP]}
	_check(EnemyVirtualPlatoon.validate_save_state(legacy), "legacy count may exceed palette size")
	var platoon := FlatPlatoon.new()
	add_child(platoon)
	_check(platoon.restore_save_state(legacy), "legacy platoon loads")
	await _spawn_all(platoon)
	_check(platoon._active_vehicles.size() == 4, "legacy four-unit platoon materializes")
	var expected: Array[Dictionary] = []
	for index in range(1, 4):
		var vehicle: Node3D = platoon._active_vehicles[index]
		vehicle.set("current_health", 15.0 + index)
		expected.append({"scene_file": vehicle.scene_file_path, "health": 15.0 + index})
	platoon._active_vehicles[0].queue_free()
	platoon.mission = EnemyVirtualPlatoon.Mission.ATTACK_POSITION
	platoon.attack_position = Vector3(400, 0, -200)
	platoon.dematerialize()
	_check(platoon.vehicle_count == 3 and platoon._vehicle_slots == expected, "casualty removed while survivor models and health retained")
	_check(platoon.mission == EnemyVirtualPlatoon.Mission.ATTACK_POSITION, "virtualization retains attack intent")
	var saved := platoon.capture_save_state()
	saved.virtual_path_goal = Vector3.ZERO
	saved = SaveGameManager._decode_json_value(JSON.parse_string(JSON.stringify(SaveGameManager._encode_json_value(saved))))
	await get_tree().process_frame
	_check(platoon.restore_save_state(saved), "survivors reload from JSON checkpoint")
	await _spawn_all(platoon)
	_check(platoon._active_vehicles.size() == 3, "casualty does not respawn")
	for index in range(platoon._active_vehicles.size()):
		var vehicle: Node3D = platoon._active_vehicles[index]
		_check(vehicle.scene_file_path == expected[index].scene_file, "survivor model remains stable")
		_check(is_equal_approx(float(vehicle.get("current_health")), float(expected[index].health)), "survivor damage persists")
	platoon.mission = EnemyVirtualPlatoon.Mission.HOLD
	for vehicle in platoon._active_vehicles:
		var route: Array[Vector3] = [Vector3(500, 0, 500)]
		vehicle.set_patrol_waypoints(route)
	platoon._apply_mission_to_platoon()
	_check(platoon._platoon_node.objective_type == GroundVehiclePlatoon.ObjectiveType.NONE, "HOLD does not resume patrol")
	for vehicle in platoon._active_vehicles:
		_check(vehicle.get("_waypoint_positions").is_empty(), "HOLD clears member navigation")
	for vehicle in platoon._active_vehicles:
		var route: Array[Vector3] = [Vector3(600, 0, 600)]
		vehicle.set_patrol_waypoints(route)
	var adapter := OpsUnitAdapter.create(platoon._platoon_node)
	_check(adapter.accept_order(OpsOrder.hold_position()), "adapter accepts HOLD")
	for vehicle in platoon._active_vehicles:
		_check(vehicle.get("_waypoint_positions").is_empty(), "adapter HOLD clears member navigation")
	platoon.mission = EnemyVirtualPlatoon.Mission.RTB
	platoon.home_position = Vector3(900, 0, 200)
	platoon._apply_mission_to_platoon()
	_check(platoon._platoon_node.objective_position == platoon.home_position, "RTB routes to home rather than patrol waypoint")
	platoon.dematerialize()
	platoon.dematerialize()
	_check(platoon.vehicle_count == 3, "repeated dematerialization is harmless")
	platoon.queue_free()
	await get_tree().process_frame
	await _test_partial_spawn()
	_test_path_request_lifetime()
	for failure in failures:
		push_error(failure)
	print("[EnemyGroundPersistenceSmoketest] %s legacy+casualties+models+health+JSON+missions+partial_spawn+path_lifetime" % ("PASS" if failures.is_empty() else "FAIL"))
	get_tree().quit(0 if failures.is_empty() else 1)


func _spawn_all(platoon: EnemyVirtualPlatoon) -> void:
	platoon._materialize()
	platoon.set_process(false)
	for frame in range(12):
		await get_tree().process_frame
		platoon._process(0.0)
		for vehicle in platoon._active_vehicles:
			vehicle.process_mode = Node.PROCESS_MODE_DISABLED
		if platoon.vstate != EnemyVirtualPlatoon.VState.MATERIALIZING:
			return
	_check(false, "materialization finishes within frame budget")


func _test_partial_spawn() -> void:
	var platoon := FlatPlatoon.new()
	add_child(platoon)
	var saved := {"vehicle_count": 3, "vehicle_scene_paths": [BUGGY, PICKUP],
		"vehicle_slots": [{"scene_file": BUGGY, "health": 12.0},
			{"scene_file": PICKUP, "health": 21.0}, {"scene_file": BUGGY, "health": 33.0}]}
	_check(platoon.restore_save_state(saved), "partial-spawn fixture restores")
	platoon._materialize()
	platoon.set_process(false)
	await get_tree().process_frame
	platoon._process(0.0)
	platoon._active_vehicles[0].queue_free()
	platoon.dematerialize()
	_check(platoon.vehicle_count == 2 and platoon._vehicle_slots == saved.vehicle_slots.slice(1), "cancelled spawn retains untouched slots and excludes casualty")
	await get_tree().process_frame
	await _spawn_all(platoon)
	_check(platoon._active_vehicles.size() == 2, "partial spawn survivors rematerialize")
	platoon.dematerialize()
	platoon.queue_free()
	await get_tree().process_frame


func _test_path_request_lifetime() -> void:
	var platoon := FlatPlatoon.new()
	add_child(platoon)
	var baseline := EnemyVirtualPlatoon._global_virtual_path_jobs
	platoon._is_virtual_pathfinding = true
	EnemyVirtualPlatoon._global_virtual_path_jobs += 1
	platoon._virtual_path_request_serial += 1
	var old_serial := platoon._virtual_path_request_serial
	remove_child(platoon)
	_check(EnemyVirtualPlatoon._global_virtual_path_jobs == baseline, "tree exit releases pending path budget")
	add_child(platoon)
	platoon._is_virtual_pathfinding = true
	EnemyVirtualPlatoon._global_virtual_path_jobs += 1
	platoon._virtual_path_request_serial += 1
	var current_serial := platoon._virtual_path_request_serial
	var empty: Array[Vector3] = []
	platoon._on_virtual_path_computed(empty, Vector3.ZERO, old_serial)
	_check(platoon._is_virtual_pathfinding and EnemyVirtualPlatoon._global_virtual_path_jobs == baseline + 1, "late callback cannot consume newer request")
	platoon._on_virtual_path_computed(empty, Vector3.ZERO, current_serial)
	platoon._on_virtual_path_computed(empty, Vector3.ZERO, current_serial)
	_check(not platoon._is_virtual_pathfinding and EnemyVirtualPlatoon._global_virtual_path_jobs == baseline, "callback releases budget exactly once")
	platoon.free()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
