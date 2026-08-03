extends Node3D

## Focused carrier ground-defense scenario.
##
## Four normal EnemyVirtualPlatoon instances materialize on parallel approach
## lanes and attack the carrier. GroundOpsManager deploys two real friendly
## platoons from the carrier vehicle bay and gives them pursue orders. The test
## owns only scenario setup, observation, and completion reporting; movement,
## pathfinding, targeting, damage, and bay deployment remain gameplay systems.

const ENEMY_BUGGY_SCENE: PackedScene = preload("res://GroundVehicle/vehicle_enemy_buggy.tscn")
const ENEMY_PICKUP_SCENE: PackedScene = preload("res://GroundVehicle/vehicle_enemy_pickup.tscn")
const ENEMY_BATTLE_BUS_SCENE: PackedScene = preload("res://GroundVehicle/vehicle_enemy_battle_bus.tscn")
const OpsOrderModel: Script = preload("res://Operations/OpsOrder.gd")
const SUPPORT_AIRCRAFT_SCENE_PATH := "res://Aircraft/Aircraft_12.tscn"
const SUPPORT_AIRCRAFT_MODEL_LABEL := "Aircraft_13"
const SUPPORT_AIRCRAFT_HANGAR_NAME := "Aircraft_13_GroundSupport"
const REPORT_PATH := "user://ground_combat_test_report.log"
const BATCH_REPORT_PREFIX := "user://ground_combat_test_"
const FRIENDLY_PLATOON_NAMES: Array[String] = ["Ember", "Ferret"]

@export_range(1, 8, 1) var enemy_platoon_count: int = 4
@export_range(1, 8, 1) var enemy_vehicles_per_platoon: int = 4
@export var enemy_approach_range_m: float = 2300.0
@export var enemy_outer_lane_offset_m: float = 720.0
@export var enemy_inner_lane_offset_m: float = 240.0
@export var friendly_pursuit_range_m: float = 6000.0
@export var battle_timeout_s: float = 600.0
@export var summary_interval_s: float = 5.0
@export var virtual_platoon_tick_interval_s: float = 0.75
@export var support_retask_interval_s: float = 1.0
@export var camera_height_m: float = 720.0
@export var camera_trailing_distance_m: float = 950.0
@export var setup_navigation_timeout_s: float = 120.0

var _play_area_center: Vector3 = Vector3.ZERO
var _carrier: Node3D = null
var _terrain: Node = null
var _ground_ops: Node = null
var _fdm: Node = null
var _enemy_platoons: Array[EnemyVirtualPlatoon] = []
var _selected_spawn_sites: Array[Vector3] = []
var _battle_camera: Camera3D = null
var _status_label: Label = null
var _elapsed_s: float = 0.0
var _summary_timer_s: float = 0.0
var _virtual_tick_timer_s: float = 0.0
var _started: bool = false
var _completed: bool = false
var _setup_only: bool = false
var _quit_on_complete: bool = false
var _test_time_scale: float = 1.0
var _test_run_id: String = ""
var _report_path: String = REPORT_PATH
var _initial_enemy_count: int = 0
var _enemy_shots_fired: int = 0
var _enemy_air_shots_fired: int = 0
var _enemy_ground_shots_fired: int = 0
var _enemy_other_shots_fired: int = 0
var _support_aircraft: RigidBody3D = null
var _support_pilot: Node = null
var _support_launch_queued: bool = false
var _support_launched: bool = false
var _support_loss_logged: bool = false
var _support_retask_timer_s: float = 0.0
var _support_target_id: int = 0
var _friendly_peak_by_name: Dictionary = {}
var _friendly_platoons_seen: Dictionary = {}
var _frame_times_ms: PackedFloat64Array = PackedFloat64Array()
var _captured_frame_time_ms: float = 0.0
var _capture_start_ticks_usec: int = 0
var _last_frame_ticks_usec: int = 0


func configure(play_area_center: Vector3) -> void:
	_play_area_center = play_area_center


func _ready() -> void:
	_configure_from_cli()
	Engine.time_scale = _test_time_scale
	_reset_report()
	_log("START requested: four enemy platoons attack the carrier; GroundOps deploys Ember and Ferret; carrier launches one Aircraft_13 attack helicopter for ground support")
	_suppress_unrelated_ops()
	call_deferred("_setup_scenario")


func _configure_from_cli() -> void:
	_setup_only = OS.get_cmdline_user_args().has("--ground-test-setup-only")
	_quit_on_complete = OS.get_cmdline_user_args().has("--quit-on-test-complete") or _setup_only
	var scale_text := _get_cmdline_option("--ground-test-time-scale=")
	if scale_text.is_valid_float():
		_test_time_scale = clampf(float(scale_text), 0.25, 12.0)
	var run_id := _sanitize_run_id(_get_cmdline_option("--test-run-id="))
	if not run_id.is_empty():
		_test_run_id = run_id
		_report_path = BATCH_REPORT_PREFIX + run_id + ".log"


func _setup_scenario() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	_carrier = get_tree().get_first_node_in_group("carrier") as Node3D
	_terrain = get_tree().get_first_node_in_group("terrain_provider")
	_ground_ops = get_node_or_null("/root/GroundOpsManager")
	_fdm = get_tree().get_first_node_in_group("flight_deck_manager")
	if not is_instance_valid(_carrier) or not is_instance_valid(_ground_ops) \
			or not is_instance_valid(_fdm):
		_finish("FAIL", "setup_missing_carrier_ground_ops_or_flight_deck")
		return

	if _carrier.has_method("is_initial_placement_complete") \
			and not bool(_carrier.call("is_initial_placement_complete")):
		_log("WAIT carrier initial route placement")
		await _carrier.initial_placement_completed
	await get_tree().process_frame

	if not await _wait_for_navigation():
		_finish("FAIL", "navigation_not_ready")
		return

	_clear_unrelated_units()
	await get_tree().process_frame
	await get_tree().process_frame
	if _carrier.has_method("set_heli_test_stationary"):
		_carrier.call("set_heli_test_stationary", true)
	_suppress_carrier_defenses()
	_reset_friendly_platoons()
	_create_observation_camera()
	_create_status_overlay()

	if not _spawn_enemy_attack():
		_finish("FAIL", "enemy_platoon_spawn_failed")
		return
	_order_friendly_defense()
	if not _setup_only:
		if not _ensure_support_aircraft_hangar_stock():
			_finish("FAIL", "support_aircraft_hangar_setup_failed")
			return
		_request_support_aircraft_launch()
	_started = true
	_start_performance_capture()
	_summary_timer_s = 0.0
	_update_observer_ui()
	_log("PHASE ground defense active enemy_platoons=%d enemy_vehicles=%d friendly_platoons=%d support_launch_queued=%s" % [
		_enemy_platoons.size(),
		_initial_enemy_count,
		FRIENDLY_PLATOON_NAMES.size(),
		str(_support_launch_queued),
	])

	if _setup_only:
		await get_tree().process_frame
		var queued_count: int = 0
		for platoon_name in FRIENDLY_PLATOON_NAMES:
			var status: Dictionary = _ground_ops.call("get_platoon_status", platoon_name)
			if bool(status.get("queued", false)) or bool(status.get("deployed", false)):
				queued_count += 1
		var setup_ok := _enemy_platoons.size() == enemy_platoon_count \
				and _initial_enemy_count == enemy_platoon_count * enemy_vehicles_per_platoon \
				and queued_count == FRIENDLY_PLATOON_NAMES.size()
		_finish("PASS" if setup_ok else "FAIL", "setup_validation")


func _wait_for_navigation() -> bool:
	var waited_s: float = 0.0
	while waited_s < maxf(setup_navigation_timeout_s, 1.0):
		if TerrainNavGrid.is_ready() and NavGraph.is_ready():
			return true
		await get_tree().create_timer(0.25, true, false, true).timeout
		waited_s += 0.25
	return false


func _suppress_unrelated_ops() -> void:
	var air_ops: Node = get_node_or_null("/root/AirOpsManager")
	if air_ops != null:
		if "mission_tasking_enabled" in air_ops:
			air_ops.set("mission_tasking_enabled", false)
		air_ops.set_process(false)
		air_ops.set_physics_process(false)
	var enemy_ops: Node = get_node_or_null("/root/EnemyOpsManager")
	if enemy_ops != null:
		if enemy_ops.has_method("disable_for_heli_test"):
			enemy_ops.call("disable_for_heli_test")
		else:
			enemy_ops.set_process(false)
			enemy_ops.set_physics_process(false)
	for manager_name in ["EnemyBaseManager", "POIManager"]:
		var manager: Node = get_node_or_null("/root/" + manager_name)
		if manager != null:
			manager.set_process(false)
			manager.set_physics_process(false)
	_ground_ops = get_node_or_null("/root/GroundOpsManager")
	if _ground_ops != null:
		_ground_ops.set("maintain_carrier_escort", false)
		_ground_ops.set("debug_print", true)
		_ground_ops.set_process(true)
	_log("SUPPRESSED unrelated air/base operations; GroundOps retained")


func _clear_unrelated_units() -> void:
	var groups: Array[String] = [
		"aircraft", "ai_aircraft", "buildings", "enemy_bases", "ground_vehicles",
		"gun_emplacements", "wind_turbines", "wind_turbine_proxies",
		"enemy_aircraft_spawner",
	]
	var seen: Dictionary = {}
	var removed: int = 0
	for group_name in groups:
		for node_variant in get_tree().get_nodes_in_group(group_name):
			if not is_instance_valid(node_variant):
				continue
			var node := node_variant as Node
			var id := node.get_instance_id()
			if seen.has(id) or node == _carrier:
				continue
			seen[id] = true
			node.queue_free()
			removed += 1
	_log("SCENE_CLEARED removed=%d unrelated nodes" % removed)


func _reset_friendly_platoons() -> void:
	if not is_instance_valid(_ground_ops):
		return
	var deploy_queue_variant: Variant = _ground_ops.get("_deploy_queue")
	if deploy_queue_variant is Array:
		deploy_queue_variant.clear()
	_ground_ops.set("_deploying_platoon_name", "")
	for platoon_name in _ground_ops.call("get_platoon_names"):
		_ground_ops.call("order_hold", str(platoon_name))
	var bay: Node = _get_vehicle_bay()
	if bay != null:
		var capacity: int = int(bay.get("max_bay_capacity"))
		bay.set("stored_vehicles", capacity)


func _get_vehicle_bay() -> Node:
	if not is_instance_valid(_carrier):
		return null
	var bay_variant: Variant = _carrier.get("vehicle_bay")
	return bay_variant as Node if is_instance_valid(bay_variant) else null


func _suppress_carrier_defenses() -> void:
	var suppressed: int = 0
	for node_variant in _carrier.find_children("*", "TurretController", true, false):
		if not is_instance_valid(node_variant) or not node_variant is TurretController:
			continue
		var controller := node_variant as TurretController
		controller.set_process(false)
		controller.set_physics_process(false)
		controller.current_target = null
		if controller.turret != null and is_instance_valid(controller.turret):
			controller.turret.set_target(null)
		if controller.weapon_instance != null and is_instance_valid(controller.weapon_instance) \
				and controller.weapon_instance.has_method("stop_firing"):
			controller.weapon_instance.stop_firing()
		suppressed += 1
	_log("SUPPRESSED carrier defense turrets=%d" % suppressed)


func _spawn_enemy_attack() -> bool:
	var forward := _carrier_forward()
	var right := Vector3.UP.cross(forward).normalized()
	var lanes: Array[float] = [
		-enemy_outer_lane_offset_m,
		-enemy_inner_lane_offset_m,
		enemy_inner_lane_offset_m,
		enemy_outer_lane_offset_m,
	]
	var vehicle_scenes: Array[PackedScene] = [
		ENEMY_BUGGY_SCENE,
		ENEMY_PICKUP_SCENE,
		ENEMY_BATTLE_BUS_SCENE,
	]
	for i in range(enemy_platoon_count):
		var lane: float = lanes[i % lanes.size()]
		var stagger_m: float = 180.0 if absf(lane) > enemy_inner_lane_offset_m + 1.0 else 0.0
		var desired := _carrier.global_position + forward * (enemy_approach_range_m + stagger_m) + right * lane
		var site: Vector3 = _find_driveable_attack_site(desired, forward, right)
		if not _valid_world_position(site):
			_log("ERROR no driveable enemy site for lane=%d desired=%s" % [i + 1, _fmt(desired)])
			return false
		_selected_spawn_sites.append(site)

		var platoon := EnemyVirtualPlatoon.new()
		platoon.name = "GroundCombatTest_EnemyVirtual_%02d" % (i + 1)
		platoon.platoon_name = "TEST-P%02d" % (i + 1)
		platoon.vehicle_count = enemy_vehicles_per_platoon
		platoon.patrol_radius = 200.0
		platoon.faction_color = Color(0.85, 0.12, 0.08)
		platoon.setup(site, vehicle_scenes, 0.0)
		platoon.position = site
		platoon.home_position = site
		get_tree().current_scene.add_child(platoon)
		platoon.set_mission_attack_carrier()
		platoon.tick(0.01)
		if platoon.vstate != EnemyVirtualPlatoon.VState.ACTIVE:
			platoon.call("_materialize")
		if platoon.vstate != EnemyVirtualPlatoon.VState.ACTIVE:
			_log("ERROR %s did not materialize" % platoon.platoon_name)
			return false
		_enemy_platoons.append(platoon)
		_configure_spawned_enemy_vehicles(platoon, i + 1)
		_log("SPAWN enemy_platoon=%s vehicles=%d pos=%s range=%.0fm lane=%.0fm mission=attack_carrier" % [
			platoon.platoon_name,
			_count_platoon_alive(platoon),
			_fmt(site),
			_flat_distance(site, _carrier.global_position),
			lane,
		])
	_initial_enemy_count = _count_enemy_alive()
	return _enemy_platoons.size() == enemy_platoon_count \
			and _initial_enemy_count == enemy_platoon_count * enemy_vehicles_per_platoon


func _configure_spawned_enemy_vehicles(platoon: EnemyVirtualPlatoon, platoon_index: int) -> void:
	var vehicles_variant: Variant = platoon.get("_active_vehicles")
	if not vehicles_variant is Array:
		return
	var vehicle_index: int = 0
	for vehicle_variant in vehicles_variant:
		if not is_instance_valid(vehicle_variant) or not vehicle_variant is Node3D:
			continue
		vehicle_index += 1
		var vehicle := vehicle_variant as Node3D
		vehicle.name = "GroundCombatTest_Enemy_%02d_%02d" % [platoon_index, vehicle_index]
		vehicle.set_meta("suppress_enemy_ops_on_destroy", true)
		for turret_variant in vehicle.find_children("*", "Turret", true, false):
			if not turret_variant is Turret:
				continue
			var turret := turret_variant as Turret
			var controller := turret.get_parent() as TurretController
			var callback := Callable(self, "_on_enemy_turret_fired").bind(controller)
			if not turret.fired.is_connected(callback):
				turret.fired.connect(callback)


func _on_enemy_turret_fired(controller: TurretController) -> void:
	_enemy_shots_fired += 1
	if not is_instance_valid(controller):
		_enemy_other_shots_fired += 1
		return
	var target_variant: Variant = controller.current_target
	if not is_instance_valid(target_variant) or not (target_variant is Node3D):
		_enemy_other_shots_fired += 1
		return
	var target := target_variant as Node3D
	if target.is_in_group("aircraft") or target.is_in_group("ai_aircraft"):
		_enemy_air_shots_fired += 1
	elif target.is_in_group("ground_vehicles"):
		_enemy_ground_shots_fired += 1
	else:
		_enemy_other_shots_fired += 1


func _find_driveable_attack_site(desired: Vector3, forward: Vector3, right: Vector3) -> Vector3:
	var offsets: Array[Vector2] = [Vector2.ZERO]
	for radius_m in [120.0, 240.0, 360.0, 520.0, 700.0]:
		for angle_index in range(8):
			var angle: float = float(angle_index) * TAU / 8.0
			offsets.append(Vector2(cos(angle), sin(angle)) * radius_m)
	var carrier_goal := _carrier.global_position + forward * 360.0
	carrier_goal.y = _ground_height(carrier_goal)
	for offset in offsets:
		var candidate := desired + right * offset.x + forward * offset.y
		candidate.y = _ground_height(candidate)
		if not _valid_world_position(candidate) or not _inside_nav_map(candidate, 250.0):
			continue
		var separated := true
		for existing in _selected_spawn_sites:
			if _flat_distance(existing, candidate) < 260.0:
				separated = false
				break
		if not separated or not NavGraph.can_anchor(candidate, 60.0, 220.0):
			continue
		var route: Array[Vector3] = NavGraph.find_path(candidate, carrier_goal, 60.0)
		if route.size() >= 2:
			return candidate
	return Vector3.INF


func _order_friendly_defense() -> void:
	for platoon_name in FRIENDLY_PLATOON_NAMES:
		_friendly_peak_by_name[platoon_name] = 0
		_friendly_platoons_seen[platoon_name] = false
		_ground_ops.call("order_pursue", platoon_name, friendly_pursuit_range_m)
		_log("FRIENDLY_ORDER platoon=%s task=pursue range=%.0fm deployment=carrier_vehicle_bay" % [
			platoon_name,
			friendly_pursuit_range_m,
		])


func _ensure_support_aircraft_hangar_stock() -> bool:
	if not is_instance_valid(_fdm):
		return false
	var support_scene := load(SUPPORT_AIRCRAFT_SCENE_PATH) as PackedScene
	if support_scene == null:
		_log("SUPPORT_HANGAR failed model=%s scene=%s" % [
			SUPPORT_AIRCRAFT_MODEL_LABEL,
			SUPPORT_AIRCRAFT_SCENE_PATH,
		])
		return false
	var stored_variant: Variant = _fdm.get("stored_aircraft")
	if not (stored_variant is Array):
		return false
	var stored: Array = stored_variant
	var selected_index := -1
	for i in range(stored.size()):
		if not (stored[i] is Dictionary):
			continue
		var existing := stored[i] as Dictionary
		var existing_name := str(existing.get("name", "")).to_lower()
		var existing_scene := str(existing.get("scene_file", "")).to_lower()
		if existing_name.contains("aircraft_13") \
				or existing_scene.contains("aircraft_12.tscn"):
			selected_index = i
			break
	if selected_index < 0:
		for i in range(stored.size()):
			if not (stored[i] is Dictionary):
				continue
			var candidate := stored[i] as Dictionary
			var is_helicopter := bool(_fdm.call("_stored_aircraft_is_helicopter", candidate)) \
					if _fdm.has_method("_stored_aircraft_is_helicopter") else false
			if not is_helicopter:
				selected_index = i
				break
	if selected_index < 0:
		_log("SUPPORT_HANGAR failed: no convertible hangar slot")
		return false
	var entry := stored[selected_index] as Dictionary
	entry["name"] = SUPPORT_AIRCRAFT_HANGAR_NAME
	entry["scene_file"] = SUPPORT_AIRCRAFT_SCENE_PATH
	entry["scene"] = support_scene
	var metadata: Dictionary = entry.get("metadata", {})
	metadata["aircraft_role"] = "attack_helicopter"
	metadata["is_helicopter"] = true
	entry["metadata"] = metadata
	stored[selected_index] = entry
	_fdm.set("stored_aircraft", stored)
	_log("SUPPORT_HANGAR ready model=%s runtime_scene=%s slot=%d weapons=rockets+15mm" % [
		SUPPORT_AIRCRAFT_MODEL_LABEL,
		SUPPORT_AIRCRAFT_SCENE_PATH,
		selected_index,
	])
	return true


func _request_support_aircraft_launch() -> void:
	if not is_instance_valid(_fdm) or not _fdm.has_method("queue_ai_helicopters"):
		return
	var queued := int(_fdm.call(
		"queue_ai_helicopters",
		1,
		self,
		SUPPORT_AIRCRAFT_HANGAR_NAME
	))
	_support_launch_queued = queued == 1
	_log("SUPPORT_LAUNCH requested=1 queued=%d model=%s deck_path=helicopter" % [
		queued,
		SUPPORT_AIRCRAFT_MODEL_LABEL,
	])


## FlightDeckManager calls this after the real elevator/deck helicopter launch is ready.
func notify_aircraft_launched(pilot: Node) -> void:
	if pilot == null or not is_instance_valid(pilot):
		_log("SUPPORT_LAUNCH callback_invalid_pilot")
		return
	var craft_variant: Variant = pilot.get("aircraft")
	if not is_instance_valid(craft_variant) or not (craft_variant is RigidBody3D):
		_log("SUPPORT_LAUNCH callback_invalid_aircraft")
		return
	_support_aircraft = craft_variant as RigidBody3D
	_support_pilot = pilot
	_support_aircraft.name = SUPPORT_AIRCRAFT_HANGAR_NAME
	if "team" in _support_aircraft:
		_support_aircraft.set("team", 1)
	_support_aircraft.set_meta("ground_combat_support", true)
	if not _support_aircraft.is_in_group("friendlies"):
		_support_aircraft.add_to_group("friendlies")
	if not _support_aircraft.is_in_group("ai_aircraft"):
		_support_aircraft.add_to_group("ai_aircraft")
	if _support_aircraft.is_in_group("enemies"):
		_support_aircraft.remove_from_group("enemies")
	if "combat_enabled" in _support_pilot:
		_support_pilot.set("combat_enabled", true)
	if "atk_enabled" in _support_pilot:
		_support_pilot.set("atk_enabled", true)
	_support_launched = true
	_support_retask_timer_s = 0.0
	_log("SUPPORT_LAUNCHED aircraft=%s model=%s pos=%s" % [
		_support_aircraft.name,
		SUPPORT_AIRCRAFT_MODEL_LABEL,
		str(_support_aircraft.global_position),
	])
	_update_support_aircraft(0.0)


func _update_support_aircraft(delta: float) -> void:
	if not _support_launched:
		return
	if not is_instance_valid(_support_aircraft) or not is_instance_valid(_support_pilot):
		if not _support_loss_logged:
			_support_loss_logged = true
			_log("SUPPORT_LOST model=%s" % SUPPORT_AIRCRAFT_MODEL_LABEL)
		return
	_support_retask_timer_s -= maxf(delta, 0.0)
	if _support_retask_timer_s > 0.0:
		return
	_support_retask_timer_s = maxf(support_retask_interval_s, 0.25)
	var current_variant: Variant = _support_pilot.get("_commanded_attack_target")
	var current_target: Node3D = null
	if is_instance_valid(current_variant) and current_variant is Node3D:
		current_target = current_variant as Node3D
	if _vehicle_is_alive(current_target):
		_support_target_id = current_target.get_instance_id()
		return
	var next_target := _find_support_target()
	if next_target == null:
		_support_target_id = 0
		return
	var accepted := OperationsCoordinator.issue_order(
		_support_aircraft,
		OpsOrderModel.attack_target(next_target)
	)
	if accepted:
		_support_target_id = next_target.get_instance_id()
	_log("SUPPORT_ORDER aircraft=%s target=%s accepted=%s" % [
		_support_aircraft.name,
		next_target.name,
		str(accepted),
	])


func _find_support_target() -> Node3D:
	if not is_instance_valid(_carrier):
		return null
	var origin := _support_aircraft.global_position \
			if is_instance_valid(_support_aircraft) else _carrier.global_position
	var best: Node3D = null
	var best_score := INF
	for platoon in _enemy_platoons:
		if not is_instance_valid(platoon):
			continue
		var vehicles_variant: Variant = platoon.get("_active_vehicles")
		if not (vehicles_variant is Array):
			continue
		for vehicle_variant in vehicles_variant:
			if not is_instance_valid(vehicle_variant) or not (vehicle_variant is Node3D):
				continue
			var vehicle := vehicle_variant as Node3D
			if not _vehicle_is_alive(vehicle):
				continue
			# Bias toward the vehicle threatening the carrier most, without sending the
			# helicopter all the way across the battlefield for every retask.
			var score := _flat_distance(vehicle.global_position, _carrier.global_position) * 0.65 \
					+ _flat_distance(vehicle.global_position, origin) * 0.35
			if score < best_score:
				best_score = score
				best = vehicle
	return best


func _process(_delta: float) -> void:
	if not _started or _completed:
		return
	var now_usec := Time.get_ticks_usec()
	if _last_frame_ticks_usec > 0:
		var frame_time_ms := float(now_usec - _last_frame_ticks_usec) / 1000.0
		if frame_time_ms > 0.0:
			_frame_times_ms.append(frame_time_ms)
			_captured_frame_time_ms += frame_time_ms
	_last_frame_ticks_usec = now_usec


func _start_performance_capture() -> void:
	_frame_times_ms.clear()
	_captured_frame_time_ms = 0.0
	_capture_start_ticks_usec = Time.get_ticks_usec()
	_last_frame_ticks_usec = _capture_start_ticks_usec
	_log("PERFORMANCE capture_started scope=battle rendered_frames_only")


func _physics_process(delta: float) -> void:
	if is_instance_valid(_battle_camera):
		_update_observation_camera(delta)
	if not _started or _completed:
		return
	_elapsed_s += maxf(delta, 0.0)
	_virtual_tick_timer_s -= delta
	if _virtual_tick_timer_s <= 0.0:
		_virtual_tick_timer_s = maxf(virtual_platoon_tick_interval_s, 0.1)
		for platoon in _enemy_platoons:
			if is_instance_valid(platoon) and platoon.vehicle_count > 0:
				platoon.tick(maxf(virtual_platoon_tick_interval_s, delta))
	_update_support_aircraft(delta)

	_update_friendly_history()
	var enemy_alive: int = _count_enemy_alive()
	var friendly_alive: int = _count_friendly_alive()
	if enemy_alive <= 0:
		_finish("PASS", "all_enemy_platoons_destroyed")
		return
	if _both_friendly_platoons_seen() and friendly_alive <= 0:
		_finish("FAIL", "both_friendly_platoons_destroyed")
		return
	if _elapsed_s >= maxf(battle_timeout_s, 30.0):
		_finish("FAIL", "timeout")
		return

	_summary_timer_s -= delta
	if _summary_timer_s <= 0.0:
		_summary_timer_s = maxf(summary_interval_s, 1.0)
		_log_summary()
	_update_observer_ui()


func _update_friendly_history() -> void:
	for platoon_name in FRIENDLY_PLATOON_NAMES:
		var platoon: GroundVehiclePlatoon = _ground_ops.call("get_platoon", platoon_name)
		var live_count: int = platoon.get_members().size() if is_instance_valid(platoon) else 0
		_friendly_peak_by_name[platoon_name] = maxi(
			int(_friendly_peak_by_name.get(platoon_name, 0)),
			live_count
		)
		if live_count > 0:
			_friendly_platoons_seen[platoon_name] = true


func _both_friendly_platoons_seen() -> bool:
	for platoon_name in FRIENDLY_PLATOON_NAMES:
		if not bool(_friendly_platoons_seen.get(platoon_name, false)):
			return false
	return true


func _count_enemy_alive() -> int:
	var count: int = 0
	for platoon in _enemy_platoons:
		if is_instance_valid(platoon):
			count += _count_platoon_alive(platoon)
	return count


func _count_platoon_alive(platoon: EnemyVirtualPlatoon) -> int:
	var vehicles_variant: Variant = platoon.get("_active_vehicles")
	if not vehicles_variant is Array:
		return maxi(platoon.vehicle_count, 0)
	var count: int = 0
	for vehicle_variant in vehicles_variant:
		if _vehicle_is_alive(vehicle_variant):
			count += 1
	return count


func _count_friendly_alive() -> int:
	if not is_instance_valid(_ground_ops):
		return 0
	var count: int = 0
	for platoon_name in FRIENDLY_PLATOON_NAMES:
		var platoon: GroundVehiclePlatoon = _ground_ops.call("get_platoon", platoon_name)
		if is_instance_valid(platoon):
			for member in platoon.get_members():
				if _vehicle_is_alive(member):
					count += 1
	return count


func _vehicle_is_alive(vehicle_variant: Variant) -> bool:
	if not is_instance_valid(vehicle_variant) or not vehicle_variant is Node:
		return false
	var vehicle := vehicle_variant as Node
	if "is_dying" in vehicle and bool(vehicle.get("is_dying")):
		return false
	if "current_health" in vehicle and float(vehicle.get("current_health")) <= 0.0:
		return false
	return true


func _friendly_peak_count() -> int:
	var total: int = 0
	for platoon_name in FRIENDLY_PLATOON_NAMES:
		total += int(_friendly_peak_by_name.get(platoon_name, 0))
	return total


func _log_summary() -> void:
	var enemy_alive := _count_enemy_alive()
	var friendly_alive := _count_friendly_alive()
	var statuses: PackedStringArray = []
	for platoon_name in FRIENDLY_PLATOON_NAMES:
		var status: Dictionary = _ground_ops.call("get_platoon_status", platoon_name)
		statuses.append("%s:%s/%d" % [
			platoon_name,
			str(status.get("objective", "UNKNOWN")),
			int(status.get("strength", 0)),
		])
	var attacker_statuses: PackedStringArray = []
	for platoon in _enemy_platoons:
		if not is_instance_valid(platoon):
			continue
		var centroid := _platoon_centroid(platoon)
		var carrier_range_m: float = _flat_distance(centroid, _carrier.global_position) \
				if _valid_world_position(centroid) else -1.0
		var combat_status := _enemy_platoon_combat_status(platoon)
		attacker_statuses.append("%s:%d@%.0fm %s r=%d a=%d tg=%d ta=%d b=%d" % [
			platoon.platoon_name,
			_count_platoon_alive(platoon),
			carrier_range_m,
			str(combat_status.get("objective", "NONE")),
			int(combat_status.get("route_points", 0)),
			int(combat_status.get("armed", 0)),
			int(combat_status.get("ground_targeting", 0)),
			int(combat_status.get("air_targeting", 0)),
			int(combat_status.get("bursting", 0)),
		])
	_log("STATUS t=%.1fs enemy=%d/%d friendly=%d/%d enemy_shots=%d ground=%d air=%d other=%d fps=%.1f avg_fps=%.1f [%s] attackers=[%s]" % [
		_elapsed_s,
		enemy_alive,
		_initial_enemy_count,
		friendly_alive,
		_friendly_peak_count(),
		_enemy_shots_fired,
		_enemy_ground_shots_fired,
		_enemy_air_shots_fired,
		_enemy_other_shots_fired,
		float(Performance.get_monitor(Performance.TIME_FPS)),
		_running_average_fps(),
		", ".join(statuses),
		", ".join(attacker_statuses),
	])
	_log("SUPPORT_STATUS model=%s state=%s target_id=%d" % [
		SUPPORT_AIRCRAFT_MODEL_LABEL,
		_support_status_text(),
		_support_target_id,
	])


func _enemy_platoon_combat_status(platoon: EnemyVirtualPlatoon) -> Dictionary:
	var result := {
		"objective": "MISSING",
		"route_points": 0,
		"armed": 0,
		"targeting": 0,
		"ground_targeting": 0,
		"air_targeting": 0,
		"bursting": 0,
	}
	var real_platoon_variant: Variant = platoon.get("_platoon_node")
	if real_platoon_variant is GroundVehiclePlatoon and is_instance_valid(real_platoon_variant):
		var real_platoon := real_platoon_variant as GroundVehiclePlatoon
		result["objective"] = real_platoon.get_objective_name()
		result["route_points"] = real_platoon.get_active_waypoints().size()
	var vehicles_variant: Variant = platoon.get("_active_vehicles")
	if not vehicles_variant is Array:
		return result
	for vehicle_variant in vehicles_variant:
		if not _vehicle_is_alive(vehicle_variant) or not vehicle_variant is Node3D:
			continue
		for controller_variant in (vehicle_variant as Node3D).find_children("*", "TurretController", true, false):
			if not controller_variant is TurretController:
				continue
			var controller := controller_variant as TurretController
			if controller.weapon_instance != null and is_instance_valid(controller.weapon_instance):
				result["armed"] = int(result["armed"]) + 1
			var target_variant: Variant = controller.current_target
			if is_instance_valid(target_variant) and target_variant is Node3D:
				var target := target_variant as Node3D
				result["targeting"] = int(result["targeting"]) + 1
				if target.is_in_group("aircraft") or target.is_in_group("ai_aircraft"):
					result["air_targeting"] = int(result["air_targeting"]) + 1
				elif target.is_in_group("ground_vehicles"):
					result["ground_targeting"] = int(result["ground_targeting"]) + 1
			if controller.fire_state == TurretController.FireState.BURSTING:
				result["bursting"] = int(result["bursting"]) + 1
	return result


func _platoon_centroid(platoon: EnemyVirtualPlatoon) -> Vector3:
	var vehicles_variant: Variant = platoon.get("_active_vehicles")
	if not vehicles_variant is Array:
		return Vector3.INF
	var sum := Vector3.ZERO
	var count: int = 0
	for vehicle_variant in vehicles_variant:
		if _vehicle_is_alive(vehicle_variant) and vehicle_variant is Node3D:
			sum += (vehicle_variant as Node3D).global_position
			count += 1
	return sum / float(count) if count > 0 else Vector3.INF


func _create_observation_camera() -> void:
	_battle_camera = Camera3D.new()
	_battle_camera.name = "GroundCombatObservationCamera"
	_battle_camera.fov = 72.0
	_battle_camera.far = 8000.0
	get_tree().current_scene.add_child(_battle_camera)
	_update_observation_camera(1.0)
	_battle_camera.current = true


func _update_observation_camera(delta: float) -> void:
	if not is_instance_valid(_carrier) or not is_instance_valid(_battle_camera):
		return
	var focus := _carrier.global_position + _carrier_forward() * 500.0
	var hostile_centroid := _enemy_centroid()
	if _valid_world_position(hostile_centroid):
		focus = _carrier.global_position.lerp(hostile_centroid, 0.48)
	if is_instance_valid(_support_aircraft):
		var support_focus := _support_aircraft.global_position
		support_focus.y = focus.y
		focus = focus.lerp(support_focus, 0.12)
	var forward := _carrier_forward()
	var desired := focus - forward * camera_trailing_distance_m + Vector3.UP * camera_height_m
	var blend := clampf(maxf(delta, 0.0) * 1.8, 0.0, 1.0)
	_battle_camera.global_position = _battle_camera.global_position.lerp(desired, blend)
	_battle_camera.look_at(focus + Vector3.UP * 15.0, Vector3.UP)


func _enemy_centroid() -> Vector3:
	var sum := Vector3.ZERO
	var count: int = 0
	for platoon in _enemy_platoons:
		if not is_instance_valid(platoon):
			continue
		var vehicles_variant: Variant = platoon.get("_active_vehicles")
		if not vehicles_variant is Array:
			continue
		for vehicle_variant in vehicles_variant:
			if _vehicle_is_alive(vehicle_variant) and vehicle_variant is Node3D:
				sum += (vehicle_variant as Node3D).global_position
				count += 1
	return sum / float(count) if count > 0 else Vector3.INF


func _create_status_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.name = "GroundCombatTestOverlay"
	layer.layer = 100
	get_tree().current_scene.add_child(layer)
	_status_label = Label.new()
	_status_label.position = Vector2(24.0, 24.0)
	_status_label.add_theme_font_size_override("font_size", 22)
	_status_label.add_theme_color_override("font_color", Color.WHITE)
	_status_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_status_label.add_theme_constant_override("outline_size", 5)
	layer.add_child(_status_label)


func _support_status_text() -> String:
	if _support_launched:
		return "ACTIVE" if is_instance_valid(_support_aircraft) else "LOST"
	if _support_launch_queued:
		return "ELEVATOR / DECK LAUNCH"
	return "NOT QUEUED"


func _update_observer_ui() -> void:
	if not is_instance_valid(_status_label):
		return
	var state := "COMPLETE" if _completed else ("ACTIVE" if _started else "SETUP")
	_status_label.text = "GROUND DEFENSE TEST — %s\nEnemy vehicles: %d / %d\nFriendly vehicles: %d / %d\nEmber + Ferret: PURSUE\nAircraft_13 support: %s\nTime: %.0f s  Scale: %.1fx" % [
		state,
		_count_enemy_alive(),
		_initial_enemy_count,
		_count_friendly_alive(),
		_friendly_peak_count(),
		_support_status_text(),
		_elapsed_s,
		_test_time_scale,
	]
	_status_label.text += "\nFPS: %.0f  Running avg: %.1f" % [
		float(Performance.get_monitor(Performance.TIME_FPS)),
		_running_average_fps(),
	]


func _running_average_fps() -> float:
	if _captured_frame_time_ms <= 0.0:
		return 0.0
	return float(_frame_times_ms.size()) * 1000.0 / _captured_frame_time_ms


func _performance_result() -> Dictionary:
	var sample_count := _frame_times_ms.size()
	if sample_count < 30 or _captured_frame_time_ms <= 0.0:
		return {
			"fps_sample_count": sample_count,
			"fps_capture_real_s": _captured_frame_time_ms / 1000.0,
		}
	var sorted_times := Array(_frame_times_ms)
	sorted_times.sort()
	var worst_one_percent_count := maxi(int(ceil(float(sample_count) * 0.01)), 1)
	var worst_one_percent_total_ms := 0.0
	for index in range(sample_count - worst_one_percent_count, sample_count):
		worst_one_percent_total_ms += float(sorted_times[index])
	var worst_one_percent_mean_ms := worst_one_percent_total_ms / float(worst_one_percent_count)
	var below_60_count := 0
	var below_30_count := 0
	var hitch_50ms_count := 0
	for frame_time_ms in _frame_times_ms:
		if frame_time_ms > 1000.0 / 60.0:
			below_60_count += 1
		if frame_time_ms > 1000.0 / 30.0:
			below_30_count += 1
		if frame_time_ms > 50.0:
			hitch_50ms_count += 1
	return {
		"fps_sample_count": sample_count,
		"fps_capture_real_s": _captured_frame_time_ms / 1000.0,
		"fps_average": _running_average_fps(),
		"fps_one_percent_low": 1000.0 / worst_one_percent_mean_ms,
		"frame_time_average_ms": _captured_frame_time_ms / float(sample_count),
		"frame_time_worst_ms": float(sorted_times[sample_count - 1]),
		"frames_below_60_percent": 100.0 * float(below_60_count) / float(sample_count),
		"frames_below_30_percent": 100.0 * float(below_30_count) / float(sample_count),
		"hitch_frames_over_50ms": hitch_50ms_count,
	}


func _finish(status: String, reason: String) -> void:
	if _completed:
		return
	_completed = true
	var enemy_alive := _count_enemy_alive()
	var friendly_alive := _count_friendly_alive()
	var result := {
		"status": status,
		"reason": reason,
		"elapsed_s": _elapsed_s,
		"enemy_initial": _initial_enemy_count,
		"enemy_alive": enemy_alive,
		"enemy_destroyed": maxi(_initial_enemy_count - enemy_alive, 0),
		"enemy_shots_fired": _enemy_shots_fired,
		"enemy_ground_shots_fired": _enemy_ground_shots_fired,
		"enemy_air_shots_fired": _enemy_air_shots_fired,
		"enemy_other_shots_fired": _enemy_other_shots_fired,
		"support_aircraft_model": SUPPORT_AIRCRAFT_MODEL_LABEL,
		"support_launch_queued": _support_launch_queued,
		"support_launched": _support_launched,
		"support_alive": is_instance_valid(_support_aircraft),
		"friendly_deployed_peak": _friendly_peak_count(),
		"friendly_alive": friendly_alive,
		"friendly_lost": maxi(_friendly_peak_count() - friendly_alive, 0),
		"enemy_platoons": _enemy_platoons.size(),
		"friendly_platoons": FRIENDLY_PLATOON_NAMES.size(),
	}
	var performance := _performance_result()
	result.merge(performance)
	if performance.has("fps_average"):
		_log("PERFORMANCE avg_fps=%.1f one_percent_low=%.1f avg_ms=%.2f worst_ms=%.2f below_60=%.1f%% below_30=%.1f%% hitches_over_50ms=%d frames=%d real_s=%.1f" % [
			float(performance["fps_average"]),
			float(performance["fps_one_percent_low"]),
			float(performance["frame_time_average_ms"]),
			float(performance["frame_time_worst_ms"]),
			float(performance["frames_below_60_percent"]),
			float(performance["frames_below_30_percent"]),
			int(performance["hitch_frames_over_50ms"]),
			int(performance["fps_sample_count"]),
			float(performance["fps_capture_real_s"]),
		])
	_log("RUN_RESULT json=%s" % JSON.stringify(result))
	_update_observer_ui()
	if is_instance_valid(_status_label):
		_status_label.text += "\n%s: %s" % [status, reason]
	if _quit_on_complete:
		call_deferred("_quit_after_completion", 0 if status == "PASS" else 1)


func _quit_after_completion(exit_code: int) -> void:
	# Dynamic terrain/vehicle meshes can still have queued renderer notifications in
	# the completion frame. Retire the gameplay scene and give the SceneTree time to
	# drain those notifications before a headless batch run exits.
	var tree := get_tree()
	var scene := tree.current_scene
	# Keep this coroutine alive while its former gameplay scene is retired.
	if get_parent() != tree.root:
		reparent(tree.root)
	if is_instance_valid(scene):
		scene.queue_free()
	for _frame in range(12):
		await tree.process_frame
	tree.quit(exit_code)


func _reset_report() -> void:
	var report := FileAccess.open(_report_path, FileAccess.WRITE)
	if report == null:
		return
	report.store_line("Ground combat test report")
	if not _test_run_id.is_empty():
		report.store_line("run_id=%s" % _test_run_id)
	report.close()


func _log(message: String) -> void:
	var line := "[GroundCombatTest] %s" % message
	print(line)
	var report := FileAccess.open(_report_path, FileAccess.READ_WRITE)
	if report == null:
		return
	report.seek_end()
	report.store_line(line)
	report.close()


func _get_cmdline_option(prefix: String) -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with(prefix):
			return argument.substr(prefix.length())
	return ""


func _sanitize_run_id(value: String) -> String:
	var safe := ""
	for character in value:
		if character.to_lower() in "abcdefghijklmnopqrstuvwxyz0123456789_-":
			safe += character
	return safe.left(80)


func _carrier_forward() -> Vector3:
	if not is_instance_valid(_carrier):
		return Vector3.FORWARD
	var forward := _carrier.global_basis.z
	forward.y = 0.0
	return forward.normalized() if forward.length_squared() > 0.001 else Vector3.FORWARD


func _ground_height(position: Vector3) -> float:
	if TerrainNavGrid.is_ready():
		var grid_height: float = TerrainNavGrid.sample_height(position.x, position.z)
		if grid_height > TerrainNavGrid.IMPASSABLE * 0.5:
			return grid_height
	if is_instance_valid(_terrain) and _terrain.has_method("get_height"):
		var terrain_height := float(_terrain.call("get_height", position))
		if is_finite(terrain_height):
			return terrain_height
	return NAN


func _inside_nav_map(position: Vector3, margin_m: float) -> bool:
	if not TerrainNavGrid.is_ready() or TerrainNavGrid._cols <= 1 or TerrainNavGrid._rows <= 1:
		return false
	var max_x := TerrainNavGrid._origin_x + float(TerrainNavGrid._cols - 1) * TerrainNavGrid.cell_size_m
	var max_z := TerrainNavGrid._origin_z + float(TerrainNavGrid._rows - 1) * TerrainNavGrid.cell_size_m
	return position.x >= TerrainNavGrid._origin_x + margin_m \
			and position.x <= max_x - margin_m \
			and position.z >= TerrainNavGrid._origin_z + margin_m \
			and position.z <= max_z - margin_m


func _valid_world_position(position: Vector3) -> bool:
	return is_finite(position.x) and is_finite(position.y) and is_finite(position.z) \
			and position != Vector3.INF


func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _fmt(position: Vector3) -> String:
	return "(%.0f, %.0f, %.0f)" % [position.x, position.y, position.z]
