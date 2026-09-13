extends SceneTree
## Diagnostic only: real normal scenario, hangar, catapult, player route API and
## flight RTB orders. No repositioning, flight tuning, forced catches or saves.

class LaunchObserver extends Node:
	var runner: SceneTree
	func notify_aircraft_launched(pilot: Node) -> void: runner._on_launch(pilot)

var carrier: Node3D
var deck: Node
var air_ops: Node
var records := {}
var live := {}
var events: FileAccess
var started_ms := 0
var started_physics_frame := 0
var recall_fuel_fraction := -1.0
var placement_seed := 20260911
var label := "five_aircraft_recovery"
var stage := "loading"
var recall_at := -1.0
var route_ordered := false
var route_started_at := -1.0
var last_carrier_position := Vector3.ZERO
var carrier_distance_m := 0.0
var last_status := -100.0
var observer: LaunchObserver

func _initialize() -> void: call_deferred("_run")
func elapsed() -> float:
	return float(Engine.get_physics_frames() - started_physics_frame) / Engine.physics_ticks_per_second

static func fuel_is_exhausted(fuel: Dictionary, physics_hz: float) -> bool:
	# request_energy is all-or-nothing. An engine can stop with a fractional
	# tick's fuel left, so an absolute near-zero amount misses genuine flameouts.
	return bool(fuel.get("valid", false)) \
		and float(fuel.get("current_burn_per_s", INF)) <= 0.0 \
		and float(fuel.get("full_power_endurance_s", INF)) < 1.0 / maxf(physics_hz, 1.0)

func _run() -> void:
	started_ms = Time.get_ticks_msec()
	started_physics_frame = Engine.get_physics_frames()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--label="): label = arg.get_slice("=", 1).validate_filename()
		if arg.begins_with("--recall-fuel-fraction="): recall_fuel_fraction = clampf(float(arg.get_slice("=", 1)), 0.0, 1.0)
		if arg.begins_with("--placement-seed="): placement_seed = int(arg.get_slice("=", 1))
	events = FileAccess.open("user://%s.jsonl" % label, FileAccess.WRITE)
	root.get_node("SaveGameManager").set("autosave_enabled", false)
	air_ops = root.get_node("AirOpsManager")
	# Keep normal recovery supervision; prevent unrelated automatic scrambles or
	# mission replacement from changing the specifically ordered five-aircraft cohort.
	air_ops.set("mission_tasking_enabled", false)
	root.get_node("GameSession").call("configure_new_game", "Five Aircraft Recovery", Color.WHITE, Color.BLACK, 0, 0, "open_canyons")
	var loading := root.get_node("LoadingScreen")
	loading.call("begin_scenario_load")
	var scene = load("res://Main_Scene.tscn").instantiate()
	scene.set("randomize_play_area_each_run", false)
	scene.get_node("LandCarrier").set("startup_placement_seed", placement_seed)
	root.add_child(scene)
	current_scene = scene
	create_timer(1800.0).timeout.connect(func(): _finish("watchdog_timeout"))
	while bool(loading.get("_active")) and elapsed() < 240: await process_frame
	if bool(loading.get("_active")):
		_finish("loading_timeout")
		return
	Engine.max_fps = 0 if DisplayServer.get_name() == "headless" else 60
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	DisplayServer.window_set_title("Five Aircraft — Carrier Launch / Travel / Recall / Recovery")
	carrier = scene.get_node("LandCarrier")
	deck = carrier.find_child("FlightDeckManager", true, false)
	last_carrier_position = carrier.global_position
	carrier.call("hold_position")
	var terrain: Node3D = scene.get_node("LowPolyTerrainPrototype")
	_event("WORLD_FRAME", {"placement_seed": placement_seed, "carrier_position": carrier.global_position,
		"carrier_rotation": carrier.global_rotation, "terrain_position": terrain.global_position, "terrain_seed": terrain.get("seed"),
		"nominal_landing_corridor_clear": deck.call("_landing_path_clear_of_terrain", true),
		"terrain_profile": terrain.get("map_profile_id"), "terrain_properties": {
			"plateau_height_m": terrain.get("plateau_height_m"), "base_height_offset_m": terrain.get("base_height_offset_m")}})
	observer = LaunchObserver.new()
	observer.runner = self
	scene.add_child(observer)
	deck.connect("aircraft_stored", _on_stored)
	for cable in get_nodes_in_group("arresting_cable"):
		cable.connect("cable_engaged", _on_caught.bind(cable))
	if await _run_diagnostic_override():
		return
	stage = "launching"
	var queued: int = deck.call("queue_ai_flight", 5, observer)
	_event("LAUNCH_ORDER", {"requested": 5, "queued": queued, "stock": _stock()})
	if queued != 5:
		_finish("could_not_queue_five")
		return
	# A normal spawn can face a cliff. Give the requested travel order now so
	# launch-corridor repositioning has player navigation authority to proceed.
	route_ordered = _order_route()
	if not route_ordered:
		_finish("no_legal_carrier_waypoint")
		return
	while stage != "complete":
		_sample()
		if stage == "launching" and (records.size() == 5 or elapsed() > 600):
			stage = "travelling"
			route_ordered = _order_route()
			route_started_at = elapsed()
		if stage == "travelling" and elapsed() - route_started_at >= 60.0:
			stage = "recovering"
			recall_at = elapsed()
			if recall_fuel_fraction >= 0.0:
				for ref in live.values():
					var craft: Variant = ref.craft.get_ref()
					if not is_instance_valid(craft): continue
					for tank in craft.energy_containers_by_type.get("fuel", []):
						if is_instance_valid(tank): tank.current_level = tank.MaxCapacity * recall_fuel_fraction
					craft.prepare_energy_system()
				_event("FUEL_TEST_SETUP", {"fraction": recall_fuel_fraction, "reason": "simulate return from full-length sortie; no refill after this point"})
			for flight in air_ops.get("flights"):
				if flight.strength() > 0: air_ops.call("order_rtb", flight.flight_name)
			_event("RECALL_ALL", {"launched": records.size(), "carrier_speed": carrier.velocity.length(), "route_active": carrier.has_active_navigation_order()})
		if stage == "recovering":
			var terminal := 0
			for record in records.values():
				if record.stowed or record.destroyed or record.unavailable: terminal += 1
			if terminal == records.size() or elapsed() - recall_at >= 900:
				_finish("cohort_terminal" if terminal == records.size() else "recovery_timeout")
				return
		await create_timer(1.0).timeout

func _run_diagnostic_override() -> bool:
	return false

func _stock() -> Array:
	var stock := []
	for entry in deck.get("stored_aircraft"): stock.append(str(entry.get("scene_file", "")))
	return stock

func _order_route() -> bool:
	var terrain := current_scene.get_node("LowPolyTerrainPrototype")
	var forward := carrier.global_basis.z
	forward.y = 0
	forward = forward.normalized()
	for distance in [4000, 3000, 2000, 1400, 1000, 700]:
		for bearing in [0, 30, -30, 60, -60, 90, -90, 150, -150, 180]:
			var point: Vector3 = carrier.global_position + forward.rotated(Vector3.UP, deg_to_rad(float(bearing))) * distance
			point.y = terrain.get_height(point)
			if not carrier.get_player_route_point_error(point).is_empty(): continue
			var points: Array[Vector3] = [point]
			if carrier.set_player_patrol_waypoints(points):
				_event("CARRIER_WAYPOINT", {"position": point, "distance_m": distance, "bearing_deg": bearing})
				return true
	_event("CARRIER_WAYPOINT_FAILED", {"reason": "no legal explored destination"})
	return false

func _on_launch(pilot: Node) -> void:
	var craft: RigidBody3D = pilot.get("aircraft")
	var id := craft.get_instance_id()
	if records.has(id): return
	var flight_name: String = ["Archer", "Bulldog", "Crimson", "Dingo"][records.size() % 4]
	records[id] = {"name": str(craft.name), "model": craft.scene_file_path.get_file(), "flight": flight_name,
		"launched_at": elapsed(), "caught": false, "stowed": false, "destroyed": false, "unavailable": false,
		"touchdowns": 0, "crash_signals": 0, "state": "", "health": craft.current_health}
	live[id] = {"craft": weakref(craft), "pilot": weakref(pilot)}
	air_ops.call("reassign", craft, flight_name)
	craft.connect("touchdown", func(details):
		records[id].touchdowns += 1
		_event("TOUCHDOWN", {"id": id, "details": details}))
	craft.connect("crashed", func(speed):
		records[id].crash_signals += 1
		_event("CRASH_SIGNAL", {"id": id, "speed": speed}))
	craft.connect("destroyed", func():
		records[id].destroyed = true
		_event("DESTROYED", {"id": id, "health_at_signal": craft.current_health,
			"position": craft.global_position, "velocity": craft.linear_velocity,
			"ground_y": craft.call("_get_ground_height_at_position", craft.global_position),
			"destruction_stack": get_stack(), "metadata": _collision_metadata(craft)}))
	craft.connect("combat_damage_received", func(amount, source):
		_event("COMBAT_DAMAGE", {"id": id, "amount": amount, "source": str(source), "health": craft.current_health}))
	craft.connect("damaged", func(amount, health):
		records[id].health = health
		_event("HEALTH_CHANGE", {"id": id, "amount": amount, "health": health}))
	_event("LAUNCHED", records[id].merged({"id": id}))

func _collision_metadata(craft: Node) -> Dictionary:
	var result := {}
	for key in craft.get_meta_list():
		if str(key).begins_with("last_collision"):
			result[str(key)] = craft.get_meta(key)
	return result

func _on_caught(craft: Variant, cable: Node) -> void:
	if not is_instance_valid(craft) or not records.has(craft.get_instance_id()): return
	var id: int = craft.get_instance_id()
	records[id].caught = true
	records[id].caught_at = elapsed()
	_event("WIRE_CAUGHT", {"id": id, "wire": cable.get_wire_number(), "health": craft.current_health})

func _on_stored(craft: Variant) -> void:
	if not is_instance_valid(craft) or not records.has(craft.get_instance_id()): return
	var id: int = craft.get_instance_id()
	records[id].stowed = true
	records[id].health = craft.current_health
	records[id].stowed_at = elapsed()
	_event("STOWED", {"id": id, "health": craft.current_health, "fuel": deck.get_recovery_fuel_snapshot(craft)})

func _sample() -> void:
	var displacement := carrier.global_position.distance_to(last_carrier_position)
	# Reject origin-rebase jumps, while logging relative positions below.
	if displacement < 100: carrier_distance_m += displacement
	last_carrier_position = carrier.global_position
	var rows := []
	for id in live:
		var record: Dictionary = records[id]
		if record.stowed or record.destroyed: continue
		var craft: Variant = live[id].craft.get_ref()
		var pilot: Variant = live[id].pilot.get_ref()
		if not is_instance_valid(craft) or not is_instance_valid(pilot):
			record.unavailable = true
			continue
		var state_name: String = pilot.State.keys()[pilot.current_state]
		if record.state != state_name:
			record.state = state_name
			_event("STATE", {"id": id, "name": record.name, "state": state_name})
		record.health = craft.current_health
		var fuel: Dictionary = deck.get_recovery_fuel_snapshot(craft)
		record["fuel"] = fuel
		if fuel_is_exhausted(fuel, Engine.physics_ticks_per_second) and not record.get("fuel_exhausted", false):
			record["fuel_exhausted"] = true
			_event("FUEL_EXHAUSTED", {"id": id, "name": record.name, "state": state_name})
		var row := {"id": id, "name": record.name, "state": state_name, "health": craft.current_health,
			"relative_position": carrier.to_local(craft.global_position), "speed": craft.linear_velocity.length(),
			"velocity": craft.linear_velocity, "rotation": craft.global_rotation,
			"angular_velocity": craft.angular_velocity, "terrain_y": craft.call("_get_ground_height_at_position", craft.global_position),
			"controls": {"pitch": pilot.pitch_input, "roll": pilot.roll_input, "yaw": pilot.yaw_input,
				"terrain_vs_floor_mps": pilot.get("_recovery_terrain_vs_floor_mps"),
				"checked_corridor": pilot.call("_is_tracking_checked_recovery_corridor")},
			"clearance": deck.has_landing_clearance(craft), "queue": deck.get_landing_queue_position(craft),
			"approach_slot": deck.has_recovery_approach(craft), "fuel": fuel,
			"recovery_budget_s": deck.get_recovery_fuel_budget_s(craft),
			"nav": pilot.get_recovery_navigation_snapshot(), "sight": pilot.get_landing_sight_snapshot()}
		rows.append(row)
	_event("SAMPLE", {"stage": stage, "carrier_position": carrier.global_position, "carrier_velocity": carrier.velocity,
		"carrier_rotation": carrier.global_rotation, "route_active": carrier.has_active_navigation_order(),
		"terrain_position": current_scene.get_node("LowPolyTerrainPrototype").global_position,
		"nominal_landing_corridor_clear": deck.call("_landing_path_clear_of_terrain", false),
		"deck_state": deck.get("current_state"), "aircraft": rows}, false)
	if elapsed() - last_status >= 10:
		last_status = elapsed()
		_write_status("RUNNING")
		print("RECOVERY_STATUS t=%.0f stage=%s launched=%d carrier_speed=%.1f records=%s" % [elapsed(), stage, records.size(), carrier.velocity.length(), JSON.stringify(records.values())])

func _event(kind: String, data: Dictionary, echo: bool = true) -> void:
	var row := {"t": elapsed(), "wall_s": (Time.get_ticks_msec() - started_ms) / 1000.0, "event": kind, "data": data}
	events.store_line(JSON.stringify(row))
	events.flush()
	if echo: print("RECOVERY_EVENT ", JSON.stringify(row))

func _write_status(status: String, reason: String = "") -> void:
	var file := FileAccess.open("user://%s_status.json" % label, FileAccess.WRITE)
	file.store_string(JSON.stringify({"status": status, "reason": reason, "stage": stage, "elapsed_s": elapsed(),
		"route_ordered": route_ordered, "carrier_distance_m": carrier_distance_m, "recall_at": recall_at, "aircraft": records.values()}))
	file.close()

func _finish(reason: String) -> void:
	if stage == "complete": return
	stage = "complete"
	_event("COMPLETE", {"reason": reason})
	_write_status("COMPLETE", reason)
	if events != null: events.close()
	quit(0)
