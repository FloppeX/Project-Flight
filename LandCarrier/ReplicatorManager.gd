extends Node
## Authoritative fabrication state. Owned by CarrierManager, independent of UI.
const CATALOG := preload("res://LandCarrier/ReplicatorCatalog.gd")
const MAX_QUEUE := 8
const SHIELD_SECONDS := 2.0
const ROLLOUT_SECONDS := 3.0
const STOW_SECONDS := 5.0

var queue: Array[Dictionary] = []
var known_blueprints: Array[String] = CATALOG.STARTER_IDS.duplicate()
var ordnance_stores: Dictionary = {"bombs": 0, "rockets": 0, "bullets": 0, "gun_10mm": 0}
var phase := "idle"
var phase_time := 0.0
var _next_id := 1

func _process(delta: float) -> void:
	advance(delta)

func get_bay() -> Node:
	var carrier := get_parent().get_parent()
	return carrier.get_node_or_null("VehicleBayManager") if carrier != null else null

func get_deck() -> Node:
	var carrier := get_parent().get_parent()
	return carrier.get_node_or_null("FlightDeckManager") if carrier != null else null

func _reserved(category: String) -> int:
	var count := 0
	for order in queue:
		if str(CATALOG.recipe(str(order.recipe)).get("category", "")) == category:
			count += 1
	return count

func airframe_inventory() -> Dictionary:
	var deck := get_deck()
	var airframes: Dictionary = {}
	var stored_count := 0
	if deck != null:
		for data: Dictionary in deck.get("stored_aircraft"):
			var id := str(data.get("metadata", {}).get("airframe_id", "stored_%d" % stored_count))
			airframes[id] = {"scene": str(data.get("scene_file", "")), "stored": true}
			stored_count += 1
		# Parallel launch jobs temporarily remove records from hangar storage.
		var launch_jobs: Variant = deck.get("_parallel_launch_jobs")
		if launch_jobs is Dictionary:
			for job: Dictionary in launch_jobs.values():
				var data: Dictionary = job.get("aircraft_data", {})
				if not data.is_empty():
					var id := str(data.get("metadata", {}).get("airframe_id", "job_%s" % str(job.get("id", ""))))
					airframes[id] = {"scene": str(data.get("scene_file", "")), "stored": false}
	var live: Array[Node] = []
	live.assign(get_tree().get_nodes_in_group("friendlies"))
	if deck != null:
		for property in ["deck_aircraft", "_pending_store_aircraft"]:
			var candidate: Variant = deck.get(property)
			if is_instance_valid(candidate) and not live.has(candidate):
				live.append(candidate)
	for aircraft in live:
		if not aircraft is RigidBody3D or aircraft.is_queued_for_deletion() or not aircraft.scene_file_path.begins_with("res://Aircraft/"):
			continue
		var id := str(aircraft.get_meta("airframe_id", "live_%d" % aircraft.get_instance_id()))
		airframes[id] = {"scene": aircraft.scene_file_path, "stored": false}
	return {"stored": stored_count, "total": airframes.size(), "reserved": _reserved("AIRFRAMES"),
		"capacity": int(deck.get("max_hangar_capacity")) if deck != null else 0, "airframes": airframes}

func production_rate() -> float:
	var carrier := get_parent().get_parent()
	if carrier != null and carrier.has_method("get_system_capability"):
		return clampf(minf(float(carrier.call("get_system_capability", "replicator")),
			float(carrier.call("get_system_capability", "reactor"))), 0.0, 1.0)
	return 1.0

func inventory_snapshot() -> Dictionary:
	var bay := get_bay()
	var stored := int(bay.get("stored_vehicles")) if bay != null else 0
	var harvesters := int(bay.get("stored_harvesters")) if bay != null and "stored_harvesters" in bay else 0
	stored += harvesters
	var deployed := 0
	for vehicle in get_tree().get_nodes_in_group("ground_vehicles"):
		if vehicle.is_in_group("friendlies") and not vehicle.is_queued_for_deletion():
			deployed += 1
	return {"stored": stored, "deployed": deployed, "reserved": _reserved("VEHICLES"),
		"harvesters": harvesters,
		"capacity": int(bay.get("max_bay_capacity")) if bay != null else 0,
		"airframes": airframe_inventory(), "ordnance": ordnance_stores.duplicate()}

func order_blocker(recipe_id: String, quantity: int) -> String:
	var recipe := CATALOG.recipe(recipe_id)
	if not known_blueprints.has(recipe_id) or recipe.is_empty():
		return "BLUEPRINT UNAVAILABLE"
	if quantity < 1 or queue.size() + quantity > MAX_QUEUE:
		return "FABRICATION QUEUE IS FULL"
	if production_rate() <= 0.0:
		return "POWER OR REPLICATOR OFFLINE"
	if str(recipe.category) == "VEHICLES":
		if get_bay() == null:
			return "VEHICLE BAY UNAVAILABLE"
		var inventory := inventory_snapshot()
		if inventory.stored + inventory.deployed + inventory.reserved + quantity > inventory.capacity:
			return "BAY CAPACITY RESERVED FOR STORED AND RETURNING VEHICLES"
	elif str(recipe.category) == "AIRFRAMES":
		if get_deck() == null:
			return "FLIGHT HANGAR UNAVAILABLE"
		var inventory := airframe_inventory()
		if inventory.total + inventory.reserved + quantity > inventory.capacity:
			return "HANGAR CAPACITY RESERVED FOR STORED AND RETURNING AIRCRAFT"
	var scene_path := str(recipe.scene)
	if not scene_path.is_empty() and not ResourceLoader.exists(scene_path):
		return "BLUEPRINT ASSET UNAVAILABLE"
	var stores := get_parent()
	if float(stores.get("plasteel_units")) < int(recipe.plasteel) * quantity or float(stores.get("corium_units")) < int(recipe.corium) * quantity:
		return "INSUFFICIENT MATERIALS"
	return ""

func place_order(recipe_id: String, quantity: int) -> String:
	var reason := order_blocker(recipe_id, quantity)
	if not reason.is_empty():
		return reason
	var stores := get_parent()
	var recipe := CATALOG.recipe(recipe_id)
	stores.set("plasteel_units", float(stores.get("plasteel_units")) - int(recipe.plasteel) * quantity)
	stores.set("corium_units", float(stores.get("corium_units")) - int(recipe.corium) * quantity)
	for index in range(quantity):
		queue.append({"id": _next_id, "recipe": recipe_id, "elapsed": 0.0})
		_next_id += 1
	return ""

func cancel_order(order_id: int) -> bool:
	for index in range(queue.size()):
		var order := queue[index]
		if int(order.id) != order_id:
			continue
		if index == 0 and phase in ["stowing", "opening", "ready", "rollout", "transfer_wait"]:
			return false
		# Spent materials stay spent; only the unbuilt portion is refunded.
		var recipe := CATALOG.recipe(str(order.recipe))
		var unbuilt := 1.0 - clampf(float(order.elapsed) / float(recipe.duration_s), 0.0, 1.0)
		var stores := get_parent()
		stores.set("plasteel_units", float(stores.get("plasteel_units")) + floorf(float(recipe.plasteel) * unbuilt))
		stores.set("corium_units", float(stores.get("corium_units")) + floorf(float(recipe.corium) * unbuilt))
		queue.remove_at(index)
		if index == 0 and phase != "returning":
			phase = "clearing"
			phase_time = 0.0
		return true
	return false

func roll_out() -> bool:
	if phase != "ready" or queue.is_empty():
		return false
	if not delivery_blocker(str(queue[0].recipe)).is_empty():
		return false
	phase = "rollout"
	phase_time = 0.0
	return true

func delivery_blocker(recipe_id: String) -> String:
	var recipe := CATALOG.recipe(recipe_id)
	if recipe.is_empty():
		return "BLUEPRINT UNAVAILABLE"
	if str(recipe.category) == "VEHICLES":
		var bay := get_bay()
		if bay == null:
			return "VEHICLE BAY UNAVAILABLE"
		if int(inventory_snapshot().stored) >= int(bay.get("max_bay_capacity")):
			return "VEHICLE BAY FULL / WAITING FOR SPACE"
	elif str(recipe.category) == "AIRFRAMES":
		var deck := get_deck()
		if deck == null or not deck.has_method("accept_fabricated_airframe"):
			return "FLIGHT HANGAR UNAVAILABLE"
		if (deck.get("stored_aircraft") as Array).size() >= int(deck.get("max_hangar_capacity")):
			return "FLIGHT HANGAR FULL / WAITING FOR SPACE"
	return ""

func _deliver(recipe_id: String) -> bool:
	if not delivery_blocker(recipe_id).is_empty():
		return false
	var recipe := CATALOG.recipe(recipe_id)
	match str(recipe.category):
		"VEHICLES":
			var bay := get_bay()
			if bay.has_method("accept_fabricated_vehicle"):
				return bool(bay.call("accept_fabricated_vehicle", str(recipe.scene)))
			var stock := "stored_harvesters" if recipe_id == "harvester" else "stored_vehicles"
			bay.set(stock, int(bay.get(stock)) + 1)
		"AIRFRAMES":
			return bool(get_deck().call("accept_fabricated_airframe", str(recipe.name), str(recipe.scene)))
		"ORDNANCE":
			ordnance_stores[recipe_id] = int(ordnance_stores.get(recipe_id, 0)) + int(recipe.output_count)
	return true

func advance(delta: float) -> void:
	# Damage can slow/stop fabrication without discarding orders or materials.
	delta = maxf(delta, 0.0) * production_rate()
	if delta <= 0.0:
		return
	if phase == "idle":
		if not queue.is_empty():
			phase = "closing"
			phase_time = 0.0
		return
	if phase == "ready":
		# Includes completed jobs restored from saves made with manual rollout.
		roll_out()
		return
	if phase == "transfer_wait":
		if _deliver(str(queue[0].recipe)):
			queue.pop_front()
			phase = "returning"
			phase_time = 0.0
		return
	phase_time += maxf(delta, 0.0)
	match phase:
		"closing":
			if phase_time >= SHIELD_SECONDS:
				phase = "fabricating"
				phase_time = 0.0
		"fabricating":
			if queue.is_empty():
				phase = "clearing"
				phase_time = 0.0
				return
			var duration := float(CATALOG.recipe(str(queue[0].recipe)).duration_s)
			queue[0].elapsed = minf(float(queue[0].elapsed) + delta, duration)
			if float(queue[0].elapsed) >= duration:
				phase = "stowing"
				phase_time = 0.0
		"stowing":
			if phase_time >= STOW_SECONDS:
				phase = "opening"
				phase_time = 0.0
		"opening":
			if phase_time >= SHIELD_SECONDS:
				phase = "ready"
				phase_time = 0.0
				roll_out()
		"rollout":
			if phase_time >= ROLLOUT_SECONDS:
				if not _deliver(str(queue[0].recipe)):
					phase = "transfer_wait"
				else:
					queue.pop_front()
					phase = "returning"
				phase_time = 0.0
		"returning":
			if phase_time >= ROLLOUT_SECONDS:
				phase = "idle"
				phase_time = 0.0
		"clearing":
			if phase_time >= SHIELD_SECONDS:
				phase = "idle"
				phase_time = 0.0

func chamber_snapshot() -> Dictionary:
	var recipe_id := str(queue[0].recipe) if not queue.is_empty() and phase not in ["clearing", "returning"] else ""
	var recipe := CATALOG.recipe(recipe_id)
	var progress := float(queue[0].elapsed) / float(recipe.duration_s) if not recipe.is_empty() else 0.0
	var shield := 0.0
	match phase:
		"closing": shield = clampf(phase_time / SHIELD_SECONDS, 0.0, 1.0)
		"fabricating", "stowing": shield = 1.0
		"opening", "clearing": shield = 1.0 - clampf(phase_time / SHIELD_SECONDS, 0.0, 1.0)
	var transfer := 0.0
	match phase:
		"rollout": transfer = clampf(phase_time / ROLLOUT_SECONDS, 0.0, 1.0)
		"transfer_wait": transfer = 1.0
		"returning": transfer = 1.0 - clampf(phase_time / ROLLOUT_SECONDS, 0.0, 1.0)
	return {"phase": phase, "progress": progress, "shield": shield,
		"job_id": int(queue[0].id) if not recipe_id.is_empty() else -1,
		"delivery_blocker": delivery_blocker(recipe_id) if phase in ["ready", "transfer_wait"] else "",
		"recipe": recipe_id, "stages": recipe.get("stages", CATALOG.VEHICLE_STAGES),
		"powered": production_rate() > 0.0,
		"rollout": transfer,
		"stage": mini(4, int(progress * 5.0)) if progress > 0.0 else -1}

func capture_save_state() -> Dictionary:
	return {"queue": queue.duplicate(true), "known_blueprints": known_blueprints.duplicate(),
		"ordnance_stores": ordnance_stores.duplicate(),
		"phase": phase, "phase_time": phase_time, "next_id": _next_id}

func restore_save_state(data: Dictionary) -> void:
	queue.clear()
	known_blueprints.assign(CATALOG.STARTER_IDS)
	for id in data.get("known_blueprints", []):
		if not known_blueprints.has(str(id)):
			known_blueprints.append(str(id))
	var saved_stores: Dictionary = data.get("ordnance_stores", {})
	for id in ordnance_stores:
		ordnance_stores[id] = maxi(0, int(saved_stores.get(id, 0)))
	for entry in data.get("queue", []):
		if entry is Dictionary:
			var recipe := CATALOG.recipe(str(entry.get("recipe", "")))
			if not recipe.is_empty():
				queue.append({"id": int(entry.get("id", 0)), "recipe": str(recipe.id),
					"elapsed": clampf(float(entry.get("elapsed", 0)), 0.0, float(recipe.duration_s))})
	phase = str(data.get("phase", "idle"))
	if phase not in ["idle", "closing", "fabricating", "stowing", "opening", "ready", "rollout", "transfer_wait", "returning", "clearing"] or (queue.is_empty() and phase not in ["clearing", "returning"]):
		phase = "idle"
	phase_time = maxf(float(data.get("phase_time", 0.0)), 0.0)
	_next_id = maxi(1, int(data.get("next_id", 1)))
	for order in queue:
		_next_id = maxi(_next_id, int(order.id) + 1)
