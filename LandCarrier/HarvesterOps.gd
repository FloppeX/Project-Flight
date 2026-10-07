extends Node
## One collection mission at a time, sharing the physical vehicle bay with platoons.
const PARKING_DISTANCE := 8.0
const SALVAGE_PARKING_DISTANCE := 6.75
const ALIGNMENT_RUN_IN := 12.0
const AUTO_HARVEST_RADIUS_M := 3000.0
var vehicle: Node3D
var mission := "HOLD"
var move_target := Vector3.ZERO
var source_id := -1
var phase := "stored"
var repeat_collection := true
var notice := "Choose a deposit or salvage site."
var _restore_pending: Dictionary = {}
var _retry := 0.0
var _auto_retry := 0.0
var _auto_blocked_sources: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	add_to_group("origin_shifter")

func apply_origin_shift(offset: Vector3) -> void:
	move_target -= offset
	if _restore_pending.get("position") is Vector3:
		_restore_pending.position -= offset
	if _restore_pending.get("transform") is Transform3D:
		var saved: Transform3D = _restore_pending.transform
		saved.origin -= offset
		_restore_pending.transform = saved

func _bay() -> Node:
	var carrier := get_tree().get_first_node_in_group("carrier")
	return carrier.get("vehicle_bay") if is_instance_valid(carrier) else null

func _field() -> Node:
	return get_tree().root.get_node("POIManager").get_resource_field()

func _set_waypoint(at := Vector3.INF) -> void:
	var points: Array[Vector3] = []
	if at != Vector3.INF:
		points.append(at)
	vehicle.set_patrol_waypoints(points)
	if vehicle.get("navigation_status") != null: vehicle.set("navigation_status", "idle")

func collect(id: int, repeat_run := true) -> String:
	var source: Dictionary = _field().get_source(id)
	if source.is_empty() or not bool(source.discovered) or _field().remaining(source) <= 0.01:
		return "This source is unavailable or depleted."
	var error := _command_error()
	if not error.is_empty(): return error
	mission = "HARVEST"
	source_id = id
	repeat_collection = repeat_run
	notice = "Collecting from %s" % str(source.label)
	if phase == "deploying" or (is_instance_valid(vehicle) and vehicle.deploy_mode):
		phase = "deploying"
		return "" # Finish clearing the ramp before applying the new mission.
	if is_instance_valid(vehicle):
		vehicle.collecting = false
		_set_waypoint()
		phase = "redirecting"
	else:
		if not _source_collectable(_field(), source):
			if not repeat_collection:
				notice = "This seep is dormant. Repeat trips will wait for the next seep."
				phase = "stored"
				return ""
			phase = "waiting_stored"
			notice = "Harvester stored; waiting for the next corium seep."
		else:
			phase = "queued"
		_retry = 0.0
	return ""

func _command_error() -> String:
	if phase == "retrieving" or (is_instance_valid(vehicle) and vehicle.retrieve_mode):
		return "The harvester is on its return approach. Wait for unloading."
	var bay := _bay()
	if not is_instance_valid(bay) or (not is_instance_valid(vehicle) and int(bay.stored_harvesters) <= 0 and phase != "deploying"):
		return "No harvester in the vehicle bay. Build one in the Replicator."
	return ""

func order_move(target: Vector3) -> String:
	if not target.is_finite() or not MapFogOfWar.is_initialized() or not MapFogOfWar.is_world_explored(target):
		return "Area unknown. Scout it before moving the harvester."
	if TerrainNavGrid.is_ready() and not TerrainNavGrid.is_low_clear_position(target.x, target.z, 6.0):
		return "Choose passable ground for the harvester."
	var error := _command_error()
	if not error.is_empty(): return error
	mission = "MOVE"
	move_target = target
	source_id = -1
	repeat_collection = false
	notice = "Moving to the ordered position, then holding."
	_stage_mission()
	return ""

func order_auto_harvest() -> String:
	var error := _command_error()
	if not error.is_empty(): return error
	mission = "AUTO_HARVEST"
	source_id = -1
	repeat_collection = false
	_auto_retry = 0.0
	_auto_blocked_sources.clear()
	notice = "Harvesting known resources within 3 km of the carrier."
	_stage_mission()
	return ""

func _stage_mission() -> void:
	_retry = 0.0
	if phase == "deploying" or (is_instance_valid(vehicle) and vehicle.deploy_mode):
		phase = "deploying"
		return
	if is_instance_valid(vehicle):
		vehicle.collecting = false
		_set_waypoint()
		phase = "redirecting"
	else:
		phase = "auto_wait" if mission == "AUTO_HARVEST" else "queued"

func _execute_mission() -> void:
	match mission:
		"MOVE":
			_set_waypoint(move_target)
			phase = "moving"
		"AUTO_HARVEST":
			if source_id < 0:
				phase = "auto_wait"
				_auto_retry = 0.0
			else:
				_travel_to_source()
		"RTB":
			_return_to_carrier()
		_:
			_travel_to_source()

func _find_auto_source() -> int:
	var carrier := get_tree().get_first_node_in_group("carrier") as Node3D
	if not is_instance_valid(carrier): return -1
	var origin := vehicle.global_position if is_instance_valid(vehicle) else carrier.global_position
	var best := -1
	var best_distance := INF
	for source in _field().discovered_sources():
		if not _source_collectable(_field(), source): continue
		if int(_auto_blocked_sources.get(int(source.id), 0)) > Time.get_ticks_msec(): continue
		if _flat_distance(carrier.global_position, source.position) > AUTO_HARVEST_RADIUS_M: continue
		var distance := _flat_distance(origin, source.position)
		if distance < best_distance:
			best = int(source.id)
			best_distance = distance
	return best

func _try_auto_harvest() -> void:
	if is_instance_valid(vehicle) and vehicle.cargo_total() >= vehicle.CAPACITY - 0.01:
		_return_to_carrier()
		return
	source_id = _find_auto_source()
	if source_id >= 0:
		if is_instance_valid(vehicle): _travel_to_source()
		else: phase = "queued"
	elif is_instance_valid(vehicle):
		_return_to_carrier()
	else:
		notice = "Waiting for known, active resources within 3 km of the carrier."

func _skip_auto_source() -> void:
	_auto_blocked_sources[source_id] = Time.get_ticks_msec() + 30000
	source_id = -1
	vehicle.collecting = false
	_set_waypoint()
	phase = "redirecting"

func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func recall() -> void:
	mission = "RTB"
	repeat_collection = false
	_return_to_carrier()

func _return_to_carrier() -> void:
	if not is_instance_valid(vehicle) and phase != "deploying":
		phase = "stored"
		source_id = -1
		if mission == "AUTO_HARVEST": phase = "auto_wait"
	elif phase == "deploying":
		phase = "folding" # Finish clearing the ramp, then return immediately.
	elif is_instance_valid(vehicle) and not vehicle.retrieve_mode:
		vehicle.collecting = false
		_set_waypoint()
		phase = "folding"
	notice = "Returning to carrier."

func _process(delta: float) -> void:
	if GameSession.has_pending_save_state():
		return
	if not _restore_pending.is_empty():
		_restore_live_vehicle()
	var bay := _bay()
	if not is_instance_valid(bay):
		return
	if source_id >= 0 and phase in ["queued", "waiting_stored", "deploying", "redirecting", "travelling", "waiting_seep", "harvesting"]:
		var assigned: Dictionary = _field().get_source(source_id)
		if not bool(assigned.get("discovered", false)):
			recall()
			notice = "Assigned site is not discovered; collection cancelled."
			return
	if not bay.vehicle_deployed.is_connected(_on_deployed):
		bay.vehicle_deployed.connect(_on_deployed)
		bay.vehicle_retrieved.connect(_on_retrieved)
		bay.vehicle_spawned.connect(_on_spawned)
	if mission == "AUTO_HARVEST" and phase == "auto_wait":
		_auto_retry -= delta
		if _auto_retry <= 0.0:
			_auto_retry = 2.0
			_try_auto_harvest()
		return
	if phase in ["queued", "waiting_stored"]:
		var field := _field()
		var source: Dictionary = field.get_source(source_id)
		if mission != "MOVE" and (source.is_empty() or field.remaining(source) <= 0.01):
			phase = "stored"
			if mission == "AUTO_HARVEST": phase = "auto_wait"
			repeat_collection = false
			notice = "The assigned resource source is exhausted."
			return
		if mission != "MOVE" and not _source_collectable(field, source):
			if mission == "AUTO_HARVEST":
				phase = "auto_wait"
				return
			phase = "waiting_stored" if repeat_collection else "stored"
			notice = "Harvester stored; waiting for the next corium seep." if repeat_collection else "This seep is dormant."
			return
		phase = "queued"
		_retry -= delta
		if _retry <= 0.0:
			_retry = 1.0
			if bay.deploy_harvester():
				phase = "deploying"
		return
	if not is_instance_valid(vehicle) or vehicle.is_dying:
		return
	if vehicle.deploy_mode:
		return
	match phase:
		"redirecting":
			if vehicle.arm_folded():
				_execute_mission()
		"moving":
			if _flat_distance(vehicle.global_position, move_target) <= 0.75 and Vector2(vehicle.velocity.x, vehicle.velocity.z).length() < 0.5:
				_set_waypoint()
				phase = "holding"
				notice = "At the ordered position. Holding; no automatic harvesting."
			elif vehicle.get("navigation_status") == "blocked":
				notice = "Move route blocked; retrying. Choose another destination or return."
		"travelling":
			var field := _field()
			var source: Dictionary = field.get_source(source_id)
			if vehicle.get("navigation_status") == "blocked":
				if mission == "AUTO_HARVEST":
					_skip_auto_source()
					return
				notice = "No safe route to %s; retrying. You can recall or choose another source." % str(source.get("label", "source"))
			elif vehicle.get("navigation_status") == "travelling":
				notice = "Travelling to %s" % str(source.get("label", "source"))
			if source.is_empty() or field.remaining(source) <= 0.01:
				_return_to_carrier()
			elif not _source_collectable(field, source):
				_pause_collection(field, source)
			elif _at_collection_stop(source):
				_set_waypoint()
				if vehicle.has_method("align_for_collection") and not vehicle.align_for_collection(delta):
					return
				vehicle.collection_target = _collection_intake_target(source)
				vehicle.collecting = true
				phase = "harvesting"
				notice = "Collecting from %s" % str(source.label)
		"waiting_seep":
			var field := _field()
			var source: Dictionary = field.get_source(source_id)
			if source.is_empty() or field.remaining(source) <= 0.01:
				recall()
			elif not repeat_collection:
				_pause_collection(field, source)
			elif _source_collectable(field, source) and vehicle.arm_folded():
				_travel_to_source()
		"harvesting":
			var field := _field()
			var source: Dictionary = field.get_source(source_id)
			if source.is_empty():
				recall()
				return
			if not _source_collectable(field, source):
				_pause_collection(field, source)
				return
			vehicle.collection_target = _collection_intake_target(source)
			field.extract(source_id, vehicle.EXTRACTION_RATE * delta, vehicle)
			if vehicle.cargo_total() >= vehicle.CAPACITY - 0.01 or field.remaining(source) <= 0.01:
				vehicle.collecting = false
				phase = "folding"
				notice = "Load complete; returning to unload." if vehicle.cargo_total() >= vehicle.CAPACITY - 0.01 else "Source exhausted; returning to unload."
			elif not _source_collectable(field, source):
				_pause_collection(field, source)
		"folding":
			if vehicle.arm_folded():
				phase = "returning"
		"returning":
			if bay.can_retrieve_vehicles():
				var vehicles: Array[Node3D] = [vehicle]
				bay.retrieve_vehicles(vehicles)
				phase = "retrieving"
			else:
				_retry -= delta
				if _retry <= 0.0:
					_retry = 5.0
					var carrier := get_tree().get_first_node_in_group("carrier") as Node3D
					if carrier != null:
							_set_waypoint(carrier.to_global(Vector3(0, 0, -190)))

func _source_collectable(field: Node, source: Dictionary) -> bool:
	return field.available(source) > 0.01 and (str(source.get("kind", "")) != "corium" or str(source.get("seep_phase", "seeping")) == "seeping")

func _at_collection_stop(source: Dictionary) -> bool:
	if vehicle.has_method("at_collection_stop"):
		return vehicle.at_collection_stop()
	return vehicle.global_position.distance_to(source.position) < 9.0 and Vector2(vehicle.velocity.x, vehicle.velocity.z).length() < 0.5

func _collection_intake_target(source: Dictionary) -> Vector3:
	return _intake_target_at(source, vehicle.collection_parking_position) if vehicle.has_method("set_collection_approach") else source.position

func _intake_target_at(source: Dictionary, parking: Vector3) -> Vector3:
	var target: Vector3 = source.position
	if str(source.get("kind", "")) == "corium":
		# Work the near side of the liquid pool, not its mathematical center.
		# Leaves reach margin for parking error, suspension tilt and the intake scan.
		var outward := parking - target
		outward.y = 0.0
		target += outward.normalized() * 1.3
	return target

func _pause_collection(field: Node, source: Dictionary) -> void:
	vehicle.collecting = false
	_set_waypoint()
	if mission == "AUTO_HARVEST" and vehicle.cargo_total() <= 0.01:
		_skip_auto_source()
		return
	if vehicle.cargo_total() > 0.01 or not repeat_collection or field.remaining(source) <= 0.01:
		phase = "folding"
		notice = "Seep paused; returning with collected cargo." if vehicle.cargo_total() > 0.01 else "Seep dormant; returning to carrier."
	else:
		phase = "waiting_seep"
		notice = "Waiting safely with the intake folded for the next corium seep."

func _travel_to_source() -> void:
	var field := _field()
	var source: Dictionary = field.get_source(source_id)
	if source.is_empty() or field.remaining(source) <= 0.01:
		recall()
		return
	if not _source_collectable(field, source):
		_pause_collection(field, source)
		return
	var approach: Vector3 = vehicle.global_position - source.position
	var avoid_wreck := source.get("wreck_position") is Vector3
	if avoid_wreck:
		approach = source.position - source.wreck_position
	approach.y = 0.0
	if approach.length_squared() < 0.01:
		approach = Vector3.FORWARD
		avoid_wreck = false
	var goal := Vector3.ZERO
	var staging := Vector3.ZERO
	var parking_forward := Vector3.ZERO
	var found := false
	# Salvage targets the pile centre. Leave reach margin for suspension,
	# parking tolerance and the intake scan, as corium's near-edge target does.
	var parking_distance := PARKING_DISTANCE if str(source.get("kind", "")) == "corium" else SALVAGE_PARKING_DISTANCE
	var outward_steps: Array[int] = [0, 1, -1, 2, -2]
	for step in range(5 if avoid_wreck else 8):
		# Approach the near/outward side, then finish along a tangent. The source
		# ends up beside the hull instead of under its nose or roof-mounted boom.
		var turn := outward_steps[step] if avoid_wreck else step
		var outward := approach.normalized().rotated(Vector3.UP, float(turn) * TAU / 8.0)
		var candidate: Vector3 = source.position + outward * parking_distance
		var tangent := outward.cross(Vector3.UP).normalized()
		if tangent.dot(vehicle.global_basis.z) < 0.0:
			tangent = -tangent
		for direction in [1.0, -1.0]:
			var forward := tangent * float(direction)
			var run_in := candidate - forward * ALIGNMENT_RUN_IN
			if avoid_wreck and (run_in - source.position).dot(approach.normalized()) < 0.0:
				continue
			if TerrainNavGrid.is_ready():
				if TerrainNavGrid.has_query_grid() and not TerrainNavGrid.is_stable_footprint(candidate.x, candidate.z, 3.0, 2.0, 2.5):
					continue
				if TerrainNavGrid.has_query_grid() and not TerrainNavGrid.is_stable_footprint(run_in.x, run_in.z, 3.0, 2.0, 2.5):
					continue
				candidate.y = TerrainNavGrid.sample_query_height(candidate.x, candidate.z) if TerrainNavGrid.has_query_grid() else TerrainNavGrid.sample_height(candidate.x, candidate.z)
				run_in.y = TerrainNavGrid.sample_query_height(run_in.x, run_in.z) if TerrainNavGrid.has_query_grid() else TerrainNavGrid.sample_height(run_in.x, run_in.z)
			if NavGraph.is_ready() and (not NavGraph.can_anchor(candidate, 6.0) or not NavGraph.can_anchor(run_in, 6.0) or not NavGraph.can_traverse_segment(run_in, candidate, 6.0)):
				continue
			goal = candidate
			staging = run_in
			parking_forward = forward
			found = true
			break
		if found:
			break
	if not found:
		if mission == "AUTO_HARVEST":
			_skip_auto_source()
			return
		phase = "blocked"
		notice = "No safe arm approach to this source. Choose another source or recall."
		return
	if vehicle.has_method("set_collection_approach"):
		vehicle.set_collection_approach(_intake_target_at(source, goal), goal, parking_forward)
	var points: Array[Vector3] = [staging, goal]
	vehicle.set_patrol_waypoints(points)
	if vehicle.get("navigation_status") != null: vehicle.set("navigation_status", "idle")
	phase = "travelling"
	notice = "Travelling to %s" % str(source.label)

func _on_spawned(spawned: Node3D) -> void:
	if not spawned.is_in_group("harvesters"):
		return
	vehicle = spawned
	if not vehicle.destroyed.is_connected(_on_destroyed):
		vehicle.destroyed.connect(_on_destroyed, CONNECT_ONE_SHOT)

func _on_deployed(deployed: Node3D) -> void:
	if not deployed.is_in_group("harvesters"):
		return
	vehicle = deployed
	if not vehicle.destroyed.is_connected(_on_destroyed):
		vehicle.destroyed.connect(_on_destroyed, CONNECT_ONE_SHOT)
	if phase == "folding":
		return
	_execute_mission()

func _on_destroyed(_destroyed_vehicle: Node3D) -> void:
	vehicle = null
	phase = "lost"
	mission = "HOLD"
	repeat_collection = false
	notice = "Harvester lost. Its cargo remains at the wreck."

func _on_retrieved(retrieved: Node3D) -> void:
	if retrieved != vehicle:
		return
	vehicle = null
	phase = "stored"
	var source: Dictionary = _field().get_source(source_id)
	notice = "Cargo unloaded into carrier stores."
	if mission == "AUTO_HARVEST":
		phase = "auto_wait"
		_auto_retry = 1.0
	elif repeat_collection and not source.is_empty() and _field().remaining(source) > 0.01:
		phase = "queued" if _source_collectable(_field(), source) else "waiting_stored"
		if phase == "waiting_stored":
			notice = "Cargo unloaded; waiting in the bay for the next corium seep."
		_retry = 1.0
	else:
		mission = "HOLD"

func snapshot() -> Dictionary:
	var bay := _bay()
	var source: Dictionary = _field().get_source(source_id)
	return {"phase": phase, "mission": mission, "stored": int(bay.stored_harvesters) if bay != null else 0,
		"cargo": vehicle.cargo.duplicate() if is_instance_valid(vehicle) else {"corium": 0.0, "plasteel": 0.0},
		"capacity": 160, "source_id": source_id, "source": str(source.get("label", "—")), "notice": notice,
		"remaining": _field().remaining(source), "repeat": repeat_collection,
		"surface": _field().available(source), "reserve": float(source.get("reserve_corium", 0.0)),
		"source_status": _field().source_status(source) if not source.is_empty() else "NO SOURCE",
		"hazard_radius": float(source.get("hazard_radius", 0.0))}

func map_status() -> Dictionary:
	var result := snapshot()
	var carrier := get_tree().get_first_node_in_group("carrier") as Node3D
	var at := vehicle.global_position if is_instance_valid(vehicle) else (carrier.global_position if is_instance_valid(carrier) else Vector3.ZERO)
	var points: Array[Vector3] = []
	if is_instance_valid(vehicle) and vehicle.has_method("get_active_waypoints"):
		points = vehicle.get_active_waypoints()
	if points.is_empty() and phase != "holding":
		if phase in ["folding", "returning", "retrieving"] and is_instance_valid(carrier):
			points.append(carrier.global_position)
		elif mission == "MOVE":
			points.append(move_target)
		elif phase not in ["stored", "lost", "auto_wait"]:
			var source: Dictionary = _field().get_source(source_id)
			if not source.is_empty() and bool(source.discovered): points.append(source.position)
	result.merge({"name": "Harvester", "kind": "harvester", "position": at,
		"strength": 1 if is_instance_valid(vehicle) or int(result.stored) > 0 or phase == "deploying" else 0,
		"command_ready": _command_error().is_empty(), "deployed": is_instance_valid(vehicle),
		"active_waypoints": points, "mission_map_points": points, "mission_map_closed_loop": false})
	return result

func capture_save_state() -> Dictionary:
	var result := {"phase": phase, "mission": mission, "move_target": move_target, "source_id": source_id, "repeat": repeat_collection, "notice": notice}
	if is_instance_valid(vehicle) and not vehicle.is_dying:
		# Campaign JSON encodes Vector3, but not Transform3D. Keep the full basis
		# as vectors so a moving harvester survives a real disk checkpoint.
		result["vehicle"] = {"position": vehicle.global_position,
			"basis_x": vehicle.global_basis.x, "basis_y": vehicle.global_basis.y, "basis_z": vehicle.global_basis.z,
			"cargo": vehicle.cargo.duplicate(), "health": vehicle.current_health}
	return result

func restore_save_state(state: Dictionary) -> void:
	if is_instance_valid(vehicle):
		vehicle.queue_free()
	vehicle = null
	source_id = int(state.get("source_id", -1))
	repeat_collection = bool(state.get("repeat", false))
	phase = str(state.get("phase", "stored"))
	mission = str(state.get("mission", "HARVEST" if source_id >= 0 else "HOLD"))
	move_target = state.get("move_target", Vector3.ZERO)
	_auto_blocked_sources.clear()
	_auto_retry = 0.0
	notice = str(state.get("notice", "Choose a deposit or salvage site."))
	_restore_pending = state.get("vehicle", {}).duplicate(true)
	_retry = 0.0

func _restore_live_vehicle() -> void:
	var saved := _restore_pending
	_restore_pending = {}
	vehicle = preload("res://GroundVehicle/Harvester.tscn").instantiate()
	get_tree().current_scene.add_child(vehicle)
	if saved.get("position") is Vector3:
		vehicle.global_transform = Transform3D(Basis(saved.basis_x, saved.basis_y, saved.basis_z), saved.position)
	elif saved.get("transform") is Transform3D:
		vehicle.global_transform = saved.transform # Older in-memory checkpoints.
	else:
		# Older disk saves lost the unsupported transform entirely. Preserve
		# their cargo and recover at the carrier's ground rally point.
		var carrier := get_tree().get_first_node_in_group("carrier") as Node3D
		var rally := carrier.to_global(Vector3(0, 0, -190)) if is_instance_valid(carrier) else Vector3.ZERO
		var ground_y := TerrainNavGrid.sample_height(rally.x, rally.z)
		if ground_y > TerrainNavGrid.IMPASSABLE * 0.5: rally.y = ground_y + 1.0
		vehicle.global_position = rally
		notice = "Saved position unavailable; harvester recovered near the carrier."
	vehicle.current_health = float(saved.get("health", vehicle.max_health))
	for material in ["corium", "plasteel"]:
		vehicle.load_cargo(material, float(saved.get("cargo", {}).get(material, 0)))
	vehicle.destroyed.connect(_on_destroyed, CONNECT_ONE_SHOT)
	# Fold first on restore; never jump an intake or a vehicle across the map.
	if phase in ["folding", "returning", "retrieving"]:
		phase = "returning"
	elif phase == "holding":
		_set_waypoint()
	else:
		phase = "redirecting"
