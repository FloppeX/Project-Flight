extends Node
## Persistent flight composition. Aircraft identity lives in stored/live metadata,
## while the flight owns its single model, loadout and launch permission.
const CATALOG = preload("res://UI/TechnicalIndexCatalog.gd")
const OUTLINES = preload("res://UI/OperationalUnitsPage.gd")
const MAX_SIZE := 4
const REPAIR_SECONDS := 120.0
const PRESETS := {"gun_only": "GUNS", "rocket_strike": "ROCKETS + GUNS", "bomb_strike": "BOMBS + GUNS"}
var plans: Dictionary = {}
var _models: Dictionary = {}
var _service_elapsed := 0.0

func deck() -> Node:
	return get_tree().get_first_node_in_group("flight_deck_manager")

func _process(delta: float) -> void:
	_service_elapsed += delta
	if _service_elapsed < 0.5:
		return
	var elapsed := _service_elapsed
	_service_elapsed = 0.0
	var fdm := deck()
	if fdm != null and fdm.call("_damage_control_allows", ["hangar"]):
		service_hangar(fdm, elapsed)

static func ensure_id(data: Dictionary) -> String:
	if not data.get("metadata") is Dictionary:
		data["metadata"] = {}
	if str(data.metadata.get("airframe_id", "")).is_empty():
		data.metadata["airframe_id"] = ResourceUID.id_to_text(ResourceUID.create_id()).trim_prefix("uid://")
	return str(data.metadata.airframe_id)

func model_info(path: String) -> Dictionary:
	if _models.has(path):
		return _models[path]
	var info := {"name": path.get_file().get_basename(), "outline": OUTLINES.aircraft_outline_path_for_reference(path), "max_health": 100.0, "presets": [], "helicopter": false, "fuel_tanks": {}}
	for category in ["AIRPLANES", "HELICOPTERS"]:
		for entry in CATALOG.entries_for(category):
			if str(entry.get("scene", "")) == path:
				info.name = entry.name
				info.helicopter = category == "HELICOPTERS"
				info["role"] = str(entry.get("stats", {}).get("ROLE", "ROTARY-WING" if info.helicopter else "FIXED-WING"))
	# Inspect once, outside the tree: no flight physics or weapon _ready calls.
	var scene := load(path) as PackedScene if ResourceLoader.exists(path) else null
	var aircraft := scene.instantiate() if scene != null else null
	if aircraft != null:
		for node in aircraft.find_children("*", "", true, false):
			if node.get("EnergyType") == "fuel" and node.get("MaxCapacity") != null:
				info.fuel_tanks[str(aircraft.get_path_to(node))] = float(node.get("MaxCapacity"))
		if aircraft.get("max_health") != null:
			info.max_health = float(aircraft.get("max_health"))
		var stations: Array[Node] = []
		_collect_stations(aircraft, stations)
		for profile in PRESETS:
			var allowed := not stations.is_empty()
			var external := 0
			var reserved_gun := false
			for station in stations:
				reserved_gun = reserved_gun or bool(station.get("gun_only"))
			for i in range(stations.size()):
				var station := stations[i]
				var weapon_path := ""
				if station.get("gun_only") or (profile == "gun_only" and not reserved_gun and i == 0):
					var current: PackedScene = station.get("mounted_weapon")
					weapon_path = current.resource_path if current != null and "/Guns/" in current.resource_path else "res://Weapons/Guns/Hardpoint/20mm_autocannon_hardpoint.tscn"
				elif profile != "gun_only":
					weapon_path = "res://Weapons/RocketPod/rocket_pod.tscn" if profile == "rocket_strike" else "res://Weapons/Bomb/bomb_rack.tscn"
					if external >= 2:
						weapon_path = "res://Weapons/Guns/Hardpoint/20mm_autocannon_hardpoint.tscn"
					external += 1
				if weapon_path.is_empty():
					continue
				var weapon_scene := load(weapon_path) as PackedScene if ResourceLoader.exists(weapon_path) else null
				var weapon := weapon_scene.instantiate() if weapon_scene != null else null
				allowed = allowed and weapon != null
				if weapon != null:
					allowed = allowed and bool(station.call("_is_weapon_allowed", weapon_scene, weapon))
					weapon.free()
			if profile != "gun_only" and external == 0:
				allowed = false
			if allowed:
				info.presets.append(profile)
		aircraft.free()
	_models[path] = info
	return info

func _collect_stations(node: Node, result: Array[Node]) -> void:
	if node is Hardpoint:
		result.append(node)
	for child in node.get_children():
		_collect_stations(child, result)

func service_hangar(fdm: Node, delta: float) -> void:
	for data: Dictionary in fdm.get("stored_aircraft"):
		ensure_id(data)
		var maximum := float(data.get("max_health", model_info(str(data.get("scene_file", ""))).max_health))
		data["max_health"] = maximum
		if data.get("current_health") == null:
			data["current_health"] = maximum
		var health := float(data.current_health)
		if health > 0.0 and health < maximum and not _stored_locked(fdm, data):
			data.current_health = minf(maximum, health + maximum * delta / REPAIR_SECONDS)

func _stored_locked(fdm: Node, data: Dictionary) -> bool:
	var ids: Array = fdm.get("_pending_ai_airframe_ids")
	if ids.has(ensure_id(data)):
		return true
	var staged: Node = fdm.get("deck_aircraft")
	if is_instance_valid(staged) and str(staged.get_meta("airframe_id", "")) == ensure_id(data): return true
	if int(fdm.get("current_state")) == int(fdm.DeckState.RETRIEVING_FROM_HANGAR):
		var index := int(fdm.call("_select_hangar_launch_index"))
		var stock: Array = fdm.get("stored_aircraft")
		return index >= 0 and index < stock.size() and ensure_id(stock[index]) == ensure_id(data)
	return false

func inventory() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var fdm := deck()
	if fdm == null:
		return result
	var by_id: Dictionary = {}
	for data: Dictionary in fdm.get("stored_aircraft"):
		var record := _stored_record(fdm, data)
		by_id[record.id] = record
	for job: Dictionary in fdm.get("_parallel_launch_jobs").values():
		var data: Dictionary = job.get("aircraft_data", {})
		if not data.is_empty():
			var record := _stored_record(fdm, data)
			record.state = "PREPARING"
			record.editable = false
			by_id[record.id] = record
	var live_aircraft: Array[Node] = []
	live_aircraft.assign(get_tree().get_nodes_in_group("friendlies"))
	for flight in get_parent().get("flights"):
		for aircraft in flight.get_members():
			if not live_aircraft.has(aircraft): live_aircraft.append(aircraft)
	for candidate in [fdm.get("deck_aircraft"), fdm.get("_pending_store_aircraft")]:
		if is_instance_valid(candidate) and not live_aircraft.has(candidate): live_aircraft.append(candidate)
	for aircraft in live_aircraft:
		if not aircraft is RigidBody3D or not aircraft.is_inside_tree():
			continue
		var flight: Variant = get_parent().call("get_flight_of", aircraft)
		var path: String = aircraft.scene_file_path
		if not "/Aircraft" in path:
			continue
		if not aircraft.has_meta("airframe_id"):
			aircraft.set_meta("airframe_id", ResourceUID.id_to_text(ResourceUID.create_id()).trim_prefix("uid://"))
		var id := str(aircraft.get_meta("airframe_id"))
		var state := "DEPLOYED"
		var pilot := aircraft.find_child("AIPilot", true, false)
		if pilot != null and pilot.get("current_state") != null:
			var value := int(pilot.get("current_state"))
			if value >= 0 and value < OUTLINES.AIR_STATE_NAMES.size():
				state = OUTLINES.map_air_activity(OUTLINES.AIR_STATE_NAMES[value])
		if by_id.has(id) or aircraft == fdm.get("deck_aircraft") or bool(aircraft.get_meta("launch_sequence_active", false)):
			state = "PREPARING"
		if aircraft == fdm.get("_pending_store_aircraft"): state = "RECOVERING"
		by_id[id] = {"id": id, "scene": path, "model": model_info(path), "state": state, "editable": false, "health": float(aircraft.get("current_health")) if aircraft.get("current_health") != null else 0.0, "flight": flight.flight_name if flight != null else str(aircraft.get_meta("assembly_flight", "")), "pilot_id": str(aircraft.get_meta("pilot_roster_id", "")), "seconds": 0, "loadout": str(aircraft.get_meta("assembly_loadout", ""))}
		by_id[id]["max_health"] = float(aircraft.get("max_health")) if aircraft.get("max_health") != null else float(by_id[id].model.max_health)
		by_id[id]["fuel_fraction"] = _live_fuel_fraction(aircraft)
		by_id[id]["payload"] = _payload_summary(fdm.call("_capture_aircraft_loadout_state", aircraft))
	for record: Dictionary in by_id.values():
		result.append(record)
	# Keep a lost slot visible until the player replaces it; never silently
	# substitute an aircraft or let a missing ID make a flight look ready.
	for flight in plans:
		for id in plans[flight].ids:
			if not by_id.has(id):
				result.append({"id": id, "scene": plans[flight].scene, "model": model_info(plans[flight].scene), "state": "LOST", "editable": false, "health": 0.0, "flight": flight, "pilot_id": "", "seconds": 0, "loadout": plans[flight].loadout})
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.id) < str(b.id))
	return result

func _stored_record(fdm: Node, data: Dictionary) -> Dictionary:
	var id := ensure_id(data)
	var path := str(data.get("scene_file", ""))
	var info := model_info(path)
	var maximum := float(data.get("max_health", info.max_health))
	var health := float(data.current_health) if data.get("current_health") != null else maximum
	var pilot_id := str(data.metadata.get("assembly_pilot_id", ""))
	var locked := _stored_locked(fdm, data)
	var state := "READY"
	if health <= 0.0:
		state = "UNSERVICEABLE"
	elif health < maximum - 0.01:
		state = "REPAIRING" if fdm.call("_damage_control_allows", ["hangar"]) else "REPAIR PAUSED"
	elif not pilot_id.is_empty() and not PilotRoster.can_reserve_for_airframe(pilot_id, id):
		state = "NEEDS PILOT"
	elif not str(data.metadata.get("assembly_flight", "")).is_empty() and pilot_id.is_empty():
		state = "NEEDS PILOT"
	if locked:
		state = "PREPARING"
	return {"id": id, "scene": path, "model": info, "state": state, "editable": not locked, "health": health, "max_health": maximum, "fuel_fraction": _stored_fuel_fraction(data, info), "flight": str(data.metadata.get("assembly_flight", "")), "pilot_id": pilot_id, "seconds": ceili(maxf(maximum - health, 0.0) / maxf(maximum, 1.0) * REPAIR_SECONDS), "loadout": str(data.metadata.get("assembly_loadout", ""))}

static func _live_fuel_fraction(aircraft: Node) -> float:
	var containers: Variant = aircraft.get("energy_containers_by_type")
	if not containers is Dictionary:
		return -1.0
	var current := 0.0
	var capacity := 0.0
	for tank in containers.get("fuel", []):
		if not is_instance_valid(tank) or not bool(tank.get("ContainerActive")):
			continue
		capacity += float(tank.get("MaxCapacity"))
		current += float(tank.get("current_level"))
	return clampf(current / capacity, 0.0, 1.0) if capacity > 0.0 else -1.0

static func _payload_summary(loadout: Dictionary) -> Dictionary:
	var counts := {"guns": 0, "bombs": 0, "rockets": 0}
	var known := false
	for entry: Dictionary in loadout.get("hardpoints", []):
		var scene := str(entry.get("weapon_scene", ""))
		if scene.is_empty(): continue
		var category := ""
		if "/Guns/" in scene or "/Autocannon/" in scene: category = "guns"
		elif "/Bomb/" in scene: category = "bombs"
		elif "/RocketPod/" in scene: category = "rockets"
		if category.is_empty(): continue
		known = true
		var amount := int(entry.get("ammo_count", -1))
		counts[category] = -1 if amount < 0 or counts[category] < 0 else counts[category] + amount
	return counts if known else {}

static func _stored_fuel_fraction(data: Dictionary, info: Dictionary) -> float:
	var current := 0.0
	var capacity := 0.0
	var saved_tanks := {}
	for entry: Dictionary in data.get("energy_state", []):
		if entry.get("energy_type", "") == "fuel":
			saved_tanks[str(entry.get("path", ""))] = entry
	for path in info.fuel_tanks:
		var saved: Dictionary = saved_tanks.get(path, {})
		if not bool(saved.get("active", true)):
			continue
		var maximum := float(info.fuel_tanks[path])
		capacity += maximum
		# New stock starts full; recovery stores the serviced fuel level.
		current += float(saved.get("current_level", maximum))
	return clampf(current / capacity, 0.0, 1.0) if capacity > 0.0 else -1.0

func stored(id: String) -> Dictionary:
	var fdm := deck()
	if fdm != null:
		for data: Dictionary in fdm.get("stored_aircraft"):
			if ensure_id(data) == id:
				return data
	return {}

func plan(flight: String) -> Dictionary:
	return plans.get(flight, {"ids": [], "scene": "", "loadout": "gun_only", "hold": false})

func _manage(flight: String) -> void:
	if not plans.has(flight):
		plans[flight] = {"ids": [], "scene": "", "loadout": "gun_only", "hold": true}

func can_assign(id: String, flight: String) -> String:
	if get_parent().call("get_flight", flight) == null:
		return "Unknown flight."
	var data := stored(id)
	if data.is_empty() or _stored_locked(deck(), data):
		return "Aircraft must be in the hangar."
	var info := model_info(str(data.scene_file))
	if info.helicopter:
		return "Helicopters remain available to rescue operations."
	var p := plan(flight)
	if get_parent().call("get_flight", flight).strength() > 0 or get_parent().get("_scrambling_flight") == get_parent().call("get_flight", flight):
		return "Wait for this flight to return to the hangar."
	if str(data.metadata.get("assembly_flight", "")) == flight:
		return "Already assigned to this flight."
	if p.ids.size() >= MAX_SIZE:
		return "Flight is full."
	if not str(p.scene).is_empty() and str(p.scene) != str(data.scene_file):
		return "This flight uses one aircraft type."
	if not info.presets.has(p.loadout):
		return "Aircraft cannot carry this flight's loadout."
	return ""

func assign(id: String, flight: String) -> String:
	var error := can_assign(id, flight)
	if not error.is_empty():
		return error
	var data := stored(id)
	var previous := str(data.metadata.get("assembly_flight", ""))
	if not previous.is_empty():
		error = unassign(id)
		if not error.is_empty(): return error
	_manage(flight)
	var p: Dictionary = plans[flight]
	p.hold = true
	p.scene = str(data.scene_file)
	p.ids.append(id)
	data.metadata.assembly_flight = flight
	data.metadata.assembly_loadout = p.loadout
	data["requested_ai_loadout_profile"] = p.loadout
	return ""

func unassign(id: String) -> String:
	var data := stored(id)
	if data.is_empty():
		for item in inventory():
			if item.id == id and item.state == "LOST":
				plans[item.flight].ids.erase(id)
				plans[item.flight].hold = true
				if plans[item.flight].ids.is_empty():
					plans[item.flight].scene = ""
					plans[item.flight].loadout = "gun_only"
				PilotRoster.release_airframe_reservation(id)
				return ""
	if data.is_empty() or _stored_locked(deck(), data):
		return "Wait for the aircraft to return."
	var flight := str(data.metadata.get("assembly_flight", ""))
	if not flight.is_empty() and get_parent().call("get_flight", flight).strength() > 0:
		return "Wait for the whole flight to return."
	if plans.has(flight):
		plans[flight].ids.erase(id)
		plans[flight].hold = true
		if plans[flight].ids.is_empty():
			plans[flight].scene = ""
			plans[flight].loadout = "gun_only"
	data.metadata.erase("assembly_flight")
	return ""

func configure_loadout(flight: String, profile: String) -> String:
	if not plans.has(flight) or str(plans[flight].scene).is_empty():
		return "Assign an aircraft first."
	var p: Dictionary = plans[flight]
	if not model_info(p.scene).presets.has(profile):
		return "Loadout is incompatible with this aircraft type."
	for id in p.ids:
		var data := stored(id)
		if data.is_empty() or _stored_locked(deck(), data):
			return "All aircraft must be in the hangar to change loadout."
	for id in p.ids:
		var data := stored(id)
		data.metadata.assembly_loadout = profile
		data["requested_ai_loadout_profile"] = profile
	p.loadout = profile
	p.hold = true
	return ""

func assign_pilot(id: String, pilot_id: String) -> String:
	var data := stored(id)
	if data.is_empty() or _stored_locked(deck(), data):
		return "Pilot changes require an aircraft in the hangar."
	if not PilotRoster.reserve_for_airframe(pilot_id, id):
		return "Pilot is already assigned or unavailable."
	data.metadata.assembly_pilot_id = pilot_id
	var flight := str(data.metadata.get("assembly_flight", ""))
	if plans.has(flight): plans[flight].hold = true
	return ""

func auto_assign_pilots(flight: String) -> String:
	for id in plan(flight).ids:
		var data := stored(id)
		if data.is_empty() or _stored_locked(deck(), data): continue
		var current := str(data.metadata.get("assembly_pilot_id", ""))
		if not current.is_empty() and PilotRoster.can_reserve_for_airframe(current, id): continue
		for pilot in PilotRoster.get_carrier_roster():
			if PilotRoster.can_reserve_for_airframe(str(pilot.id), id):
				assign_pilot(id, str(pilot.id))
				break
	return ""

func set_hold(flight: String, hold: bool) -> String:
	if not plans.has(flight):
		return "Assign aircraft before changing flight readiness."
	if get_parent().get("_scrambling_flight") == get_parent().call("get_flight", flight) or get_parent().call("get_flight", flight).strength() > 0:
		return "Flight is already deployed."
	plans[flight].hold = hold
	if not hold:
		get_parent().call("release_to_automatic", flight)
	return ""

func can_launch(flight: String) -> bool:
	if not plans.has(flight): return true
	var p: Dictionary = plans[flight]
	if p.hold or p.ids.is_empty(): return false
	for id in p.ids:
		var data := stored(id)
		if data.is_empty(): return false
		var record := _stored_record(deck(), data)
		if record.state != "READY" or record.pilot_id.is_empty(): return false
	return true

func capture_save_state() -> Dictionary:
	return plans.duplicate(true)

func restore_save_state(saved: Dictionary) -> void:
	plans = saved.duplicate(true)
