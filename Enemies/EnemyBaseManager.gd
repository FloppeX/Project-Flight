extends Node

## Enemy Base Manager -- autoload singleton.
##
## Tracks all active enemy bases, manages per-base resource limits, maintains
## patrols, and dispatches reinforcements when active patrols make contact.

const DEFAULT_TOTAL_AIRCRAFT: int = 12
const DEFAULT_TOTAL_VEHICLES: int = 24
const DEFAULT_MAX_ACTIVE_AIRCRAFT: int = 6
const DEFAULT_MAX_ACTIVE_VEHICLES: int = 12
const DEFAULT_PATROL_FLIGHT_SIZE: int = 2
const DEFAULT_PATROL_PLATOON_SIZE: int = 4
const DEFAULT_RESPONSE_FLIGHT_SIZE: int = 2
const DEFAULT_RESPONSE_PLATOON_SIZE: int = 4
const AIR_CONTACT_STATES: Array = [
	AIPilot.State.DOGFIGHT,
	AIPilot.State.ATTACK_POSITIONING,
	AIPilot.State.ATTACK_INBOUND,
	AIPilot.State.ATTACK_DIVE,
	AIPilot.State.ATTACK_BREAK_OFF,
	AIPilot.State.ENGAGE,
]

@export var debug_print: bool = true
@export var auto_manage_bases: bool = true
@export_range(0.1, 10.0, 0.1) var decision_interval_s: float = 1.0
@export_range(1.0, 120.0, 0.5) var contact_memory_s: float = 25.0
@export_range(0.5, 60.0, 0.5) var air_dispatch_cooldown_s: float = 8.0
@export_range(0.5, 60.0, 0.5) var ground_dispatch_cooldown_s: float = 12.0

var bases: Dictionary = {}  # name -> Node3D
var _base_states: Dictionary = {}  # name -> Dictionary
var _enemy_spawner: Node = null
var _decision_timer_s: float = 0.0

func _ready() -> void:
	set_process(true)
	_decision_timer_s = randf() * maxf(decision_interval_s, 0.1)
	call_deferred("_register_existing_bases")

func _process(delta: float) -> void:
	if not auto_manage_bases:
		return
	_decision_timer_s -= maxf(delta, 0.0)
	if _decision_timer_s > 0.0:
		return
	_decision_timer_s = maxf(decision_interval_s, 0.1)
	_manage_all_bases()

func register_base(base: Node3D) -> void:
	if base == null or not is_instance_valid(base):
		return
	bases[base.name] = base
	if not _base_states.has(base.name):
		_base_states[base.name] = _make_base_state(base)
	else:
		var existing_state: Dictionary = _base_states.get(base.name, {})
		var limits: Dictionary = _get_base_limits(base)
		existing_state["aircraft_remaining"] = clampi(
			int(existing_state.get("aircraft_remaining", 0)),
			0,
			int(limits.get("total_aircraft_inventory", DEFAULT_TOTAL_AIRCRAFT))
		)
		existing_state["vehicle_remaining"] = clampi(
			int(existing_state.get("vehicle_remaining", 0)),
			0,
			int(limits.get("total_vehicle_inventory", DEFAULT_TOTAL_VEHICLES))
		)
		_base_states[base.name] = existing_state
	if debug_print:
		print("[EnemyBaseManager] Registered base: %s" % base.name)

func unregister_base(base: Node3D) -> void:
	if base == null:
		return
	if bases.get(base.name, null) == base:
		bases.erase(base.name)
	elif bases.has(base.name):
		bases.erase(base.name)
	_base_states.erase(base.name)
	if debug_print:
		print("[EnemyBaseManager] Unregistered base: %s" % base.name)

func get_base(base_name: String) -> Node3D:
	var base := bases.get(base_name, null) as Node3D
	if base != null and is_instance_valid(base):
		return base
	if bases.has(base_name):
		bases.erase(base_name)
	return null

func get_bases() -> Array[Node3D]:
	var result: Array[Node3D] = []
	var invalid_names: Array[String] = []
	for base_name in bases.keys():
		var base := bases[base_name] as Node3D
		if base != null and is_instance_valid(base):
			result.append(base)
		else:
			invalid_names.append(base_name)
	for base_name in invalid_names:
		bases.erase(base_name)
		_base_states.erase(base_name)
	return result

func get_base_names() -> Array[String]:
	var names: Array[String] = []
	for base in get_bases():
		names.append(base.name)
	names.sort()
	return names

func get_base_status(base_name: String) -> Dictionary:
	var base := get_base(base_name)
	if base == null:
		return {}
	var state: Dictionary = _ensure_base_state(base)
	var base_status: Dictionary = {}
	if base.has_method("get_status_summary"):
		var status_variant: Variant = base.call("get_status_summary")
		if status_variant is Dictionary:
			base_status = (status_variant as Dictionary).duplicate(true)

	var limits: Dictionary = _get_base_limits(base)
	var active_aircraft: Array[Node3D] = _get_base_aircraft(base)
	var active_platoons: Array[GroundVehiclePlatoon] = _get_base_platoons(base)
	var active_vehicle_count: int = _count_active_vehicles(active_platoons)
	var last_contact_time_s: float = float(state.get("last_contact_time_s", -1000000.0))
	var contact_active: bool = _has_recent_contact(last_contact_time_s)
	var contact_position: Vector3 = state.get("contact_position", Vector3.INF)

	base_status["remaining_aircraft"] = int(state.get("aircraft_remaining", 0))
	base_status["remaining_vehicles"] = int(state.get("vehicle_remaining", 0))
	base_status["active_aircraft"] = active_aircraft.size()
	base_status["active_vehicles"] = active_vehicle_count
	base_status["available_aircraft_launch_slots"] = maxi(
		int(limits.get("max_active_aircraft", DEFAULT_MAX_ACTIVE_AIRCRAFT)) - active_aircraft.size(),
		0
	)
	base_status["available_vehicle_launch_slots"] = maxi(
		int(limits.get("max_active_vehicles", DEFAULT_MAX_ACTIVE_VEHICLES)) - active_vehicle_count,
		0
	)
	base_status["contact_active"] = contact_active
	if contact_active and _is_valid_world_position(contact_position):
		base_status["contact_position"] = contact_position
	return base_status

func get_all_base_statuses() -> Array[Dictionary]:
	var statuses: Array[Dictionary] = []
	for base_name in get_base_names():
		var status: Dictionary = get_base_status(base_name)
		if not status.is_empty():
			statuses.append(status)
	return statuses

func launch_flight(base_name: String, aircraft_count: int = 2) -> bool:
	var base := get_base(base_name)
	if base == null:
		push_warning("[EnemyBaseManager] Unknown base: %s" % base_name)
		return false
	return _request_air_dispatch(base, maxi(aircraft_count, 1), Vector3.INF)

func launch_platoon(base_name: String, vehicle_count: int = 4) -> bool:
	var base := get_base(base_name)
	if base == null:
		push_warning("[EnemyBaseManager] Unknown base: %s" % base_name)
		return false
	return _request_ground_dispatch(base, maxi(vehicle_count, 1), Vector3.INF)

func _register_existing_bases() -> void:
	for base in get_tree().get_nodes_in_group("enemy_bases"):
		if base is Node3D and is_instance_valid(base):
			register_base(base as Node3D)

func _manage_all_bases() -> void:
	var now_s: float = _now_seconds()
	for base in get_bases():
		_manage_base(base, now_s)

func _manage_base(base: Node3D, now_s: float) -> void:
	if base == null or not is_instance_valid(base):
		return
	var state: Dictionary = _ensure_base_state(base)
	var limits: Dictionary = _get_base_limits(base)
	var active_aircraft: Array[Node3D] = _get_base_aircraft(base)
	var active_platoons: Array[GroundVehiclePlatoon] = _get_base_platoons(base)
	var active_aircraft_count: int = active_aircraft.size()
	var active_vehicle_count: int = _count_active_vehicles(active_platoons)
	var previous_contact_position: Vector3 = state.get("contact_position", Vector3.INF)
	var had_recent_contact: bool = _has_recent_contact(float(state.get("last_contact_time_s", -1000000.0)))

	var contact: Dictionary = _find_base_contact(base, active_aircraft, active_platoons)
	if bool(contact.get("has_contact", false)):
		var new_contact_position: Vector3 = contact.get("position", Vector3.INF)
		state["last_contact_time_s"] = now_s
		state["contact_position"] = new_contact_position
		if debug_print and (
			not had_recent_contact
			or not _is_valid_world_position(previous_contact_position)
			or previous_contact_position.distance_to(new_contact_position) > 250.0
		):
			print("[EnemyBaseManager] %s contact at %s" % [base.name, str(new_contact_position)])
	elif not _has_recent_contact(float(state.get("last_contact_time_s", -1000000.0))):
		state["contact_position"] = Vector3.INF

	var alert_active: bool = _has_recent_contact(float(state.get("last_contact_time_s", -1000000.0))) \
		and _is_valid_world_position(state.get("contact_position", Vector3.INF))
	var desired_aircraft: int = int(limits.get("patrol_flight_size", DEFAULT_PATROL_FLIGHT_SIZE))
	var desired_vehicles: int = int(limits.get("patrol_platoon_size", DEFAULT_PATROL_PLATOON_SIZE))
	if alert_active:
		desired_aircraft = int(limits.get("max_active_aircraft", DEFAULT_MAX_ACTIVE_AIRCRAFT))
		desired_vehicles = int(limits.get("max_active_vehicles", DEFAULT_MAX_ACTIVE_VEHICLES))
	desired_aircraft = clampi(
		desired_aircraft,
		0,
		int(limits.get("max_active_aircraft", DEFAULT_MAX_ACTIVE_AIRCRAFT))
	)
	desired_vehicles = clampi(
		desired_vehicles,
		0,
		int(limits.get("max_active_vehicles", DEFAULT_MAX_ACTIVE_VEHICLES))
	)

	if active_aircraft_count < desired_aircraft:
		var air_wave_size: int = int(limits.get(
			"response_flight_size" if alert_active else "patrol_flight_size",
			DEFAULT_RESPONSE_FLIGHT_SIZE if alert_active else DEFAULT_PATROL_FLIGHT_SIZE
		))
		var air_to_launch: int = _compute_dispatch_count(
			int(state.get("aircraft_remaining", 0)),
			active_aircraft_count,
			desired_aircraft,
			int(limits.get("max_active_aircraft", DEFAULT_MAX_ACTIVE_AIRCRAFT)),
			air_wave_size
		)
		if air_to_launch > 0:
			_request_air_dispatch(
				base,
				air_to_launch,
				state.get("contact_position", Vector3.INF) if alert_active else Vector3.INF
			)

	if active_vehicle_count < desired_vehicles:
		var ground_wave_size: int = int(limits.get(
			"response_platoon_size" if alert_active else "patrol_platoon_size",
			DEFAULT_RESPONSE_PLATOON_SIZE if alert_active else DEFAULT_PATROL_PLATOON_SIZE
		))
		var vehicles_to_launch: int = _compute_dispatch_count(
			int(state.get("vehicle_remaining", 0)),
			active_vehicle_count,
			desired_vehicles,
			int(limits.get("max_active_vehicles", DEFAULT_MAX_ACTIVE_VEHICLES)),
			ground_wave_size
		)
		if vehicles_to_launch > 0:
			_request_ground_dispatch(
				base,
				vehicles_to_launch,
				state.get("contact_position", Vector3.INF) if alert_active else Vector3.INF
			)

	_base_states[base.name] = state

func _request_air_dispatch(base: Node3D, aircraft_count: int, response_position: Vector3) -> bool:
	if base == null or not is_instance_valid(base):
		return false
	var state: Dictionary = _ensure_base_state(base)
	if bool(state.get("air_dispatch_in_progress", false)):
		return false
	var now_s: float = _now_seconds()
	if now_s < float(state.get("next_air_dispatch_time_s", 0.0)):
		return false
	var limits: Dictionary = _get_base_limits(base)
	var active_aircraft_count: int = _get_base_aircraft(base).size()
	var remaining_aircraft: int = int(state.get("aircraft_remaining", 0))
	var clamped_count: int = clampi(
		aircraft_count,
		1,
		min(
			remaining_aircraft,
			maxi(int(limits.get("max_active_aircraft", DEFAULT_MAX_ACTIVE_AIRCRAFT)) - active_aircraft_count, 0)
		)
	)
	if clamped_count <= 0:
		return false
	state["air_dispatch_in_progress"] = true
	_base_states[base.name] = state
	_dispatch_air_from_base(base.name, clamped_count, response_position)
	return true

func _request_ground_dispatch(base: Node3D, vehicle_count: int, response_position: Vector3) -> bool:
	if base == null or not is_instance_valid(base):
		return false
	var state: Dictionary = _ensure_base_state(base)
	if bool(state.get("ground_dispatch_in_progress", false)):
		return false
	var now_s: float = _now_seconds()
	if now_s < float(state.get("next_ground_dispatch_time_s", 0.0)):
		return false
	var limits: Dictionary = _get_base_limits(base)
	var active_vehicle_count: int = _count_active_vehicles(_get_base_platoons(base))
	var remaining_vehicles: int = int(state.get("vehicle_remaining", 0))
	var clamped_count: int = clampi(
		vehicle_count,
		1,
		min(
			remaining_vehicles,
			maxi(int(limits.get("max_active_vehicles", DEFAULT_MAX_ACTIVE_VEHICLES)) - active_vehicle_count, 0)
		)
	)
	if clamped_count <= 0:
		return false
	state["ground_dispatch_in_progress"] = true
	_base_states[base.name] = state
	_dispatch_ground_from_base(base.name, clamped_count, response_position)
	return true

func _dispatch_air_from_base(base_name: String, aircraft_count: int, response_position: Vector3) -> void:
	var base := get_base(base_name)
	var state: Dictionary = _base_states.get(base_name, {})
	if base == null or state.is_empty():
		return
	var spawner := _get_enemy_spawner()
	if spawner == null:
		state["air_dispatch_in_progress"] = false
		state["next_air_dispatch_time_s"] = _now_seconds() + 1.0
		_base_states[base_name] = state
		return

	var spawned_variant: Variant = []
	if _is_valid_world_position(response_position) and spawner.has_method("spawn_enemy_response_flight_from_base"):
		spawned_variant = await spawner.call("spawn_enemy_response_flight_from_base", base, response_position, aircraft_count)
	elif spawner.has_method("spawn_enemy_flight_from_base"):
		spawned_variant = await spawner.call("spawn_enemy_flight_from_base", base, aircraft_count)

	var spawned_count: int = 0
	if spawned_variant is Array:
		for item in spawned_variant:
			if item is Node3D and is_instance_valid(item):
				var spawned_aircraft := item as Node3D
				spawned_aircraft.set_meta("enemy_base_name", base_name)
				spawned_aircraft.set_meta("enemy_base_role", "response" if _is_valid_world_position(response_position) else "patrol")
				spawned_count += 1

	state = _base_states.get(base_name, {})
	if state.is_empty():
		return
	state["air_dispatch_in_progress"] = false
	state["next_air_dispatch_time_s"] = _now_seconds() + air_dispatch_cooldown_s
	state["aircraft_remaining"] = maxi(int(state.get("aircraft_remaining", 0)) - spawned_count, 0)
	if spawned_count > 0 and _is_valid_world_position(response_position):
		state["last_contact_time_s"] = _now_seconds()
		state["contact_position"] = response_position
	if debug_print and spawned_count > 0:
		print("[EnemyBaseManager] %s launched %d aircraft (%d remaining)" % [
			base_name,
			spawned_count,
			int(state.get("aircraft_remaining", 0))
		])
	_base_states[base_name] = state

func _dispatch_ground_from_base(base_name: String, vehicle_count: int, response_position: Vector3) -> void:
	var base := get_base(base_name)
	var state: Dictionary = _base_states.get(base_name, {})
	if base == null or state.is_empty():
		return
	var spawner := _get_enemy_spawner()
	if spawner == null:
		state["ground_dispatch_in_progress"] = false
		state["next_ground_dispatch_time_s"] = _now_seconds() + 1.0
		_base_states[base_name] = state
		return

	var platoon_variant: Variant = null
	if _is_valid_world_position(response_position) and spawner.has_method("spawn_enemy_response_platoon_from_base"):
		platoon_variant = spawner.call("spawn_enemy_response_platoon_from_base", base, response_position, vehicle_count)
	elif spawner.has_method("spawn_enemy_platoon_from_base"):
		platoon_variant = spawner.call("spawn_enemy_platoon_from_base", base, vehicle_count)

	var launched_vehicle_count: int = 0
	if platoon_variant is GroundVehiclePlatoon and is_instance_valid(platoon_variant):
		var spawned_platoon := platoon_variant as GroundVehiclePlatoon
		spawned_platoon.set_meta("enemy_base_name", base_name)
		spawned_platoon.set_meta("enemy_base_role", "response" if _is_valid_world_position(response_position) else "patrol")
		launched_vehicle_count = spawned_platoon.get_members().size()
		if launched_vehicle_count <= 0:
			launched_vehicle_count = vehicle_count

	state = _base_states.get(base_name, {})
	if state.is_empty():
		return
	state["ground_dispatch_in_progress"] = false
	state["next_ground_dispatch_time_s"] = _now_seconds() + ground_dispatch_cooldown_s
	state["vehicle_remaining"] = maxi(int(state.get("vehicle_remaining", 0)) - launched_vehicle_count, 0)
	if launched_vehicle_count > 0 and _is_valid_world_position(response_position):
		state["last_contact_time_s"] = _now_seconds()
		state["contact_position"] = response_position
	if debug_print and launched_vehicle_count > 0:
		print("[EnemyBaseManager] %s launched %d vehicles (%d remaining)" % [
			base_name,
			launched_vehicle_count,
			int(state.get("vehicle_remaining", 0))
		])
	_base_states[base_name] = state

func _find_base_contact(base: Node3D, active_aircraft: Array[Node3D], active_platoons: Array[GroundVehiclePlatoon]) -> Dictionary:
	var best_position: Vector3 = Vector3.INF
	var best_distance: float = INF

	for aircraft in active_aircraft:
		var contact_position: Vector3 = _get_aircraft_contact_position(aircraft)
		if not _is_valid_world_position(contact_position):
			continue
		var distance_to_base: float = base.global_position.distance_to(contact_position)
		if distance_to_base < best_distance:
			best_distance = distance_to_base
			best_position = contact_position

	for platoon in active_platoons:
		var contact_position: Vector3 = _get_platoon_contact_position(platoon)
		if not _is_valid_world_position(contact_position):
			continue
		var distance_to_base: float = base.global_position.distance_to(contact_position)
		if distance_to_base < best_distance:
			best_distance = distance_to_base
			best_position = contact_position

	if not _is_valid_world_position(best_position):
		return {"has_contact": false, "position": Vector3.INF}
	return {"has_contact": true, "position": best_position}

func _get_aircraft_contact_position(aircraft: Node3D) -> Vector3:
	if aircraft == null or not is_instance_valid(aircraft):
		return Vector3.INF
	var ai_pilot := aircraft.find_child("AIPilot", true, false) as AIPilot
	if ai_pilot == null:
		return Vector3.INF
	if ai_pilot.combat_target != null and is_instance_valid(ai_pilot.combat_target):
		return ai_pilot.combat_target.global_position
	if ai_pilot.current_state in AIR_CONTACT_STATES:
		return aircraft.global_position
	return Vector3.INF

func _get_platoon_contact_position(platoon: GroundVehiclePlatoon) -> Vector3:
	if platoon == null or not is_instance_valid(platoon):
		return Vector3.INF
	if not platoon.has_any_member_in_combat():
		return Vector3.INF
	for member in platoon.get_members():
		var target_value: Variant = member.get("current_target")
		if target_value is Node3D and is_instance_valid(target_value):
			return (target_value as Node3D).global_position
	var contact_position: Vector3 = platoon.get_contact_position()
	return contact_position if _is_valid_world_position(contact_position) else Vector3.INF

func _get_base_aircraft(base: Node3D) -> Array[Node3D]:
	var result: Array[Node3D] = []
	if base == null or not is_instance_valid(base):
		return result
	if base.has_method("get_flight_count"):
		base.call("get_flight_count")
	var flights_value: Variant = base.get("spawned_flights")
	if flights_value is Array:
		for item in flights_value:
			if item is Node3D and is_instance_valid(item):
				result.append(item as Node3D)
	return result

func _get_base_platoons(base: Node3D) -> Array[GroundVehiclePlatoon]:
	var result: Array[GroundVehiclePlatoon] = []
	if base == null or not is_instance_valid(base):
		return result
	if base.has_method("get_platoon_count"):
		base.call("get_platoon_count")
	var platoons_value: Variant = base.get("spawned_platoons")
	if platoons_value is Array:
		for item in platoons_value:
			if item is GroundVehiclePlatoon and is_instance_valid(item):
				result.append(item as GroundVehiclePlatoon)
	return result

func _count_active_vehicles(active_platoons: Array[GroundVehiclePlatoon]) -> int:
	var total: int = 0
	for platoon in active_platoons:
		if platoon == null or not is_instance_valid(platoon):
			continue
		total += platoon.get_members().size()
	return total

func _get_base_limits(base: Node3D) -> Dictionary:
	var limits := {
		"total_aircraft_inventory": DEFAULT_TOTAL_AIRCRAFT,
		"total_vehicle_inventory": DEFAULT_TOTAL_VEHICLES,
		"max_active_aircraft": DEFAULT_MAX_ACTIVE_AIRCRAFT,
		"max_active_vehicles": DEFAULT_MAX_ACTIVE_VEHICLES,
		"patrol_flight_size": DEFAULT_PATROL_FLIGHT_SIZE,
		"patrol_platoon_size": DEFAULT_PATROL_PLATOON_SIZE,
		"response_flight_size": DEFAULT_RESPONSE_FLIGHT_SIZE,
		"response_platoon_size": DEFAULT_RESPONSE_PLATOON_SIZE,
	}
	if base != null and is_instance_valid(base) and base.has_method("get_resource_limits"):
		var limit_variant: Variant = base.call("get_resource_limits")
		if limit_variant is Dictionary:
			var limit_dict := limit_variant as Dictionary
			for key in limit_dict.keys():
				limits[key] = limit_dict[key]

	limits["total_aircraft_inventory"] = maxi(int(limits.get("total_aircraft_inventory", DEFAULT_TOTAL_AIRCRAFT)), 1)
	limits["total_vehicle_inventory"] = maxi(int(limits.get("total_vehicle_inventory", DEFAULT_TOTAL_VEHICLES)), 1)
	limits["max_active_aircraft"] = clampi(
		int(limits.get("max_active_aircraft", DEFAULT_MAX_ACTIVE_AIRCRAFT)),
		1,
		int(limits.get("total_aircraft_inventory", DEFAULT_TOTAL_AIRCRAFT))
	)
	limits["max_active_vehicles"] = clampi(
		int(limits.get("max_active_vehicles", DEFAULT_MAX_ACTIVE_VEHICLES)),
		1,
		int(limits.get("total_vehicle_inventory", DEFAULT_TOTAL_VEHICLES))
	)
	limits["patrol_flight_size"] = clampi(
		int(limits.get("patrol_flight_size", DEFAULT_PATROL_FLIGHT_SIZE)),
		1,
		int(limits.get("max_active_aircraft", DEFAULT_MAX_ACTIVE_AIRCRAFT))
	)
	limits["patrol_platoon_size"] = clampi(
		int(limits.get("patrol_platoon_size", DEFAULT_PATROL_PLATOON_SIZE)),
		1,
		int(limits.get("max_active_vehicles", DEFAULT_MAX_ACTIVE_VEHICLES))
	)
	limits["response_flight_size"] = clampi(
		int(limits.get("response_flight_size", DEFAULT_RESPONSE_FLIGHT_SIZE)),
		1,
		int(limits.get("max_active_aircraft", DEFAULT_MAX_ACTIVE_AIRCRAFT))
	)
	limits["response_platoon_size"] = clampi(
		int(limits.get("response_platoon_size", DEFAULT_RESPONSE_PLATOON_SIZE)),
		1,
		int(limits.get("max_active_vehicles", DEFAULT_MAX_ACTIVE_VEHICLES))
	)
	return limits

func _ensure_base_state(base: Node3D) -> Dictionary:
	if base == null or not is_instance_valid(base):
		return {}
	if not _base_states.has(base.name):
		_base_states[base.name] = _make_base_state(base)
	return _base_states.get(base.name, {})

func _make_base_state(base: Node3D) -> Dictionary:
	var limits: Dictionary = _get_base_limits(base)
	var used_aircraft: int = _get_base_aircraft(base).size()
	var used_vehicles: int = _count_active_vehicles(_get_base_platoons(base))
	return {
		"aircraft_remaining": maxi(int(limits.get("total_aircraft_inventory", DEFAULT_TOTAL_AIRCRAFT)) - used_aircraft, 0),
		"vehicle_remaining": maxi(int(limits.get("total_vehicle_inventory", DEFAULT_TOTAL_VEHICLES)) - used_vehicles, 0),
		"last_contact_time_s": -1000000.0,
		"contact_position": Vector3.INF,
		"next_air_dispatch_time_s": 0.0,
		"next_ground_dispatch_time_s": 0.0,
		"air_dispatch_in_progress": false,
		"ground_dispatch_in_progress": false,
	}

func _compute_dispatch_count(remaining: int, active: int, desired: int, max_active: int, wave_size: int) -> int:
	var missing: int = maxi(desired - active, 0)
	var active_room: int = maxi(max_active - active, 0)
	if remaining <= 0 or missing <= 0 or active_room <= 0:
		return 0
	return clampi(wave_size, 1, min(remaining, min(missing, active_room)))

func _has_recent_contact(last_contact_time_s: float) -> bool:
	return _now_seconds() - last_contact_time_s <= maxf(contact_memory_s, 0.1)

func _is_valid_world_position(value: Variant) -> bool:
	if not (value is Vector3):
		return false
	var world_pos := value as Vector3
	return is_finite(world_pos.x) and is_finite(world_pos.y) and is_finite(world_pos.z)

func _get_enemy_spawner() -> Node:
	if _enemy_spawner != null and is_instance_valid(_enemy_spawner):
		return _enemy_spawner
	var current_scene := get_tree().current_scene
	if current_scene == null:
		return null
	_enemy_spawner = current_scene.find_child("EnemyAircraftSpawner", true, false)
	return _enemy_spawner

func _now_seconds() -> float:
	return float(Time.get_ticks_msec()) / 1000.0
