extends SceneTree

var failures: Array[String] = []
var ops: Node
var service: Node
var scene: Node3D

func _initialize() -> void: call_deferred("_run")

func _run() -> void:
	for child in root.get_children(): child.process_mode = Node.PROCESS_MODE_DISABLED
	ops = root.get_node("GroundOpsManager")
	service = ops.rescue_service
	var air := root.get_node("AirOpsManager")
	air.set("mission_tasking_enabled", false)
	var grid := root.get_node("TerrainNavGrid")
	var graph := root.get_node("NavGraph")
	var heights := PackedFloat32Array()
	heights.resize(41 * 41)
	heights.fill(0.0)
	grid.set("_cols", 41)
	grid.set("_rows", 41)
	grid.set("cell_size_m", 40.0)
	grid.set("_origin_x", -800.0)
	grid.set("_origin_z", -800.0)
	grid.set("_heights", heights)
	grid.set("_h_min_passable", 0.0)
	grid.set("_is_baked", true)
	graph.call("_reset_graph")
	graph.call("_build")
	graph.call("_build_spatial_index")
	graph.set("_is_ready", true)
	var scheduler := root.get_node("NavPathScheduler")
	scheduler.process_mode = Node.PROCESS_MODE_ALWAYS
	scheduler.set("min_job_start_interval_s", 0.0)
	scheduler.set("start_jitter_s", 0.0)
	scene = Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var carrier := Node3D.new()
	scene.add_child(carrier)
	ops._carrier = carrier
	var bay: Node = load("res://Tests/Fixtures/GroundRescueTestBay.gd").new()
	scene.add_child(bay)
	bay.stored_vehicles = 0
	ops._vehicle_bay = bay
	var p: Node = ops.get_platoon("Ember")
	var vehicle := _vehicle()
	vehicle.assign_platoon(p)
	vehicle.global_position = Vector3(0, 1, 0)
	var survivor := _survivor(Vector3(100, 0, 0))
	var roster := root.get_node("PilotRoster")
	roster.assign_aircraft_to_callsign(survivor, "RescueTest")
	var identity: String = survivor.get_meta("pilot_roster_id", "")
	_expect(not identity.is_empty(), "pilot identity was not assigned")
	air._downed_pilots.append(survivor)
	_expect(service.consider(survivor, null), "idle nearby platoon not considered")
	await _wait_route(survivor)
	_expect(service.jobs.has(survivor) and not service.jobs[survivor].planning, "reachable route not assigned")
	_expect(p.get_objective_name() == "RESCUE", "rescue objective missing")
	_expect(str(survivor.get_meta("air_ops_rescue_status", "")) == "ground_assigned", "ground status missing")
	_expect(ops.order_rescue("Ember", survivor), "repeating the same assignment should be harmless")
	var competing := _survivor(Vector3(120, 0, 0))
	_expect(not ops.order_rescue("Ember", competing), "platoon accepted two competing rescue objectives")
	competing.queue_free()
	# Production movement controls must aim inside pickup radius, not scatter.
	service._process(0.5)
	_expect(vehicle.waypoint_reach_distance == 6.0, "driver retained 25 m arrival tolerance")
	_expect(p.get_destination_for(vehicle).distance_to(survivor.global_position) < 1.0, "pickup vehicle has formation offset")
	# Exercise real boarding, not only the dispatch bookkeeping.
	vehicle.global_position = Vector3(96, 1, 0)
	vehicle.velocity = Vector3.ZERO
	survivor.approach_ground_transport(vehicle)
	_expect(survivor._ground_transport == vehicle, "stopped vehicle was not boardable")
	bay.state = 1 # DEPLOYING: rescue must not interrupt an occupied vehicle bay.
	survivor._board_ground_transport()
	_expect(vehicle.get_passenger_count() == 1 and survivor.get_parent() == vehicle, "survivor did not become vehicle passenger")
	_expect(survivor.get_meta("pilot_roster_id") == identity, "passenger identity lost")
	_expect(not air.get_tracked_downed_pilots().has(survivor), "boarded survivor still awaits rescue")
	_expect(bay.returned.is_empty() and service.returning.has("Ember"), "rescue interrupted busy bay")
	bay.state = 0
	service._process(0.5)
	_expect(bay.returned.has(vehicle), "pickup did not request carrier retrieval")
	_expect(vehicle.waypoint_reach_distance == 25.0, "driver arrival tolerance was not restored")
	_expect(_roster_status(roster, identity) == "passenger", "passenger became available before returning")
	vehicle.disembark_passengers()
	_expect(vehicle.get_passenger_count() == 0 and _roster_status(roster, identity) == "available", "carrier unload failed to release pilot")
	await process_frame
	# A helicopter already near a distant survivor should beat the ground route.
	var distant := _survivor(Vector3(-650, 0, 650))
	var nearby_heli := Node3D.new()
	scene.add_child(nearby_heli)
	nearby_heli.global_position = distant.global_position
	p.objective_type = 0
	service.consider(distant, nearby_heli)
	await _wait_route(distant)
	_expect(not service.jobs.has(distant), "slower ground route displaced nearby helicopter")
	distant.queue_free()
	nearby_heli.queue_free()
	# Speed, capacity, route failure and changing orders.
	var other := _survivor(Vector3(100, 0, 0))
	vehicle.velocity = Vector3(8, 0, 0)
	other.approach_ground_transport(vehicle)
	_expect(other._ground_transport == null, "pilot boards moving vehicle")
	vehicle.velocity = Vector3.ZERO
	vehicle.passenger_capacity = 0
	_expect(not vehicle.can_accept_passenger(), "zero capacity accepted passenger")
	vehicle.passenger_capacity = 2
	p.objective_type = 7 # ATTACK_POSITION
	_expect(not service.consider(other, null), "automatic rescue stole combat platoon")
	p.objective_type = 0
	_expect(ops.order_rescue("Ember", other), "manual rescue rejected")
	ops.order_hold("Ember")
	service._process(0.5)
	_expect(not service.jobs.has(other), "changed order left rescue reservation")
	await process_frame
	service.retry_after.clear()
	var cliff_pilot := _survivor(Vector3(100, 90, 0))
	_expect(ops.order_rescue("Ember", cliff_pilot), "cliff route check was not started")
	await _wait_route(cliff_pilot)
	_expect(not service.jobs.has(cliff_pilot), "wrong-level graph endpoint accepted")
	# The real passenger node survives a destroyed transport and requests rescue again.
	_expect(vehicle.add_passenger(other), "passenger fixture boarding failed")
	other._phase = 3
	vehicle._release_surviving_passengers()
	_expect(other.get_parent() == scene and other.visible, "destroyed transport lost survivor")
	_expect(air.get_tracked_downed_pilots().has(other), "survivor from destroyed transport not re-registered")
	service._cancel(other, "test cleanup")
	# Stale node references must be pruned without typed casts.
	service.retry_after.clear()
	p.objective_type = 0
	var stale := _survivor(Vector3(110, 0, 0))
	ops.order_rescue("Ember", stale)
	stale.free()
	service._process(0.5)
	_expect(service.jobs.is_empty(), "freed survivor left a rescue job")
	await _test_physical_pickup(p, vehicle, bay)
	var overlay := load("res://UI/WorldMapOverlay.gd")
	_expect(overlay != null and overlay.can_instantiate(), "map UI script does not compile")
	print("[GroundRescueSmoketest] %s failures=%s" % ["PASS" if failures.is_empty() else "FAIL", failures])
	quit(0 if failures.is_empty() else 1)

func _vehicle() -> CharacterBody3D:
	var v := CharacterBody3D.new()
	scene.add_child(v)
	v.set_script(load("res://GroundVehicle/vehicle_friendly_light.gd"))
	v.process_mode = Node.PROCESS_MODE_DISABLED
	v.current_health = 100.0
	return v

func _test_physical_pickup(p: Node, old_vehicle: Node, bay: Node) -> void:
	# Real vehicle scene, real driver, real survivor walking: no teleport pickup.
	p.unregister_vehicle(old_vehicle)
	old_vehicle.queue_free()
	for pilot in root.get_node("AirOpsManager").get_tracked_downed_pilots():
		root.get_node("AirOpsManager").notify_pilot_rescued(pilot)
		pilot.queue_free()
	service.jobs.clear()
	service.retry_after.clear()
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1600, 2, 1600)
	floor_shape.shape = box
	floor_body.add_child(floor_shape)
	scene.add_child(floor_body)
	floor_body.position.y = -1.0
	var vehicle: Node3D = load("res://GroundVehicle/vehicle_friendly_light.tscn").instantiate()
	scene.add_child(vehicle)
	var doors := vehicle.get_node("RescueDoors")
	_expect(doors._left_hinge != null and doors._right_hinge != null,
		"new friendly vehicle did not bind both authored doors")
	var left_board: Vector3 = vehicle.get_boarding_position_for(vehicle.to_global(Vector3(-10, 0, 0)))
	var right_board: Vector3 = vehicle.get_boarding_position_for(vehicle.to_global(Vector3(10, 0, 0)))
	_expect(vehicle.to_local(left_board).x < -2.0 and vehicle.to_local(right_board).x > 2.0,
		"ground pilot did not select the nearer side doorway")
	vehicle.global_position = Vector3(0, 2, -150)
	vehicle.assign_platoon(p)
	p.objective_type = 0
	p.process_mode = Node.PROCESS_MODE_ALWAYS
	service.process_mode = Node.PROCESS_MODE_ALWAYS
	var pilot: RigidBody3D = load("res://Models/Characters/DownedPilot.tscn").instantiate()
	scene.add_child(pilot)
	var roster := root.get_node("PilotRoster")
	roster.assign_aircraft_to_callsign(pilot, "PhysicalRescueTest")
	var identity: String = pilot.get_meta("pilot_roster_id", "")
	_expect(not identity.is_empty(), "physical pickup pilot identity was not assigned")
	pilot.global_position = Vector3.ZERO
	pilot._phase = 1 # Already waiting at its clearing.
	pilot.process_mode = Node.PROCESS_MODE_ALWAYS
	root.get_node("AirOpsManager")._downed_pilots.append(pilot)
	bay.returned.clear()
	_expect(ops.order_rescue("Ember", pilot), "physical pickup assignment rejected")
	Engine.time_scale = 4.0
	var deadline := Time.get_ticks_msec() + 20000
	var saw_door_open := false
	var saw_pilot_run := false
	while vehicle.get_passenger_count() == 0 and Time.get_ticks_msec() < deadline:
		await physics_frame
		saw_door_open = saw_door_open or doors._open_t >= 0.85
		if is_instance_valid(pilot):
			saw_pilot_run = saw_pilot_run or pilot.global_position.distance_to(Vector3.ZERO) > 2.0
	Engine.time_scale = 1.0
	_expect(saw_door_open, "rescue doors did not open before boarding")
	_expect(saw_pilot_run, "pilot did not run toward ground transport")
	_expect(vehicle.get_passenger_count() == 1, "real driver/pilot did not complete pickup: vehicle=%s pilot=%s status=%s" % [vehicle.global_position, pilot.global_position, pilot.get_meta("air_ops_rescue_status", "")])
	_expect(_roster_status(roster, identity) == "passenger", "physical pickup marked pilot available before vehicle returned")
	_expect(not doors._open_target, "rescue doors stayed commanded open after boarding")
	for i in 70:
		await physics_frame
	_expect(doors._open_t < 0.05, "rescue doors did not close after boarding")
	_expect(bay.returned.has(vehicle), "physical pickup did not start carrier retrieval")
	print("[GroundRescueSmoketest] physical_pickup passengers=%d vehicle=%s" % [vehicle.get_passenger_count(), vehicle.global_position])
	var status_at_stow_signal: Array[String] = []
	vehicle.retrieve_complete.connect(func(_retrieved: Node): status_at_stow_signal.append(_roster_status(roster, identity)))
	vehicle._finish_retrieve()
	_expect(status_at_stow_signal == ["available"], "pilot was not available when vehicle finished stowing in the bay")
	p.process_mode = Node.PROCESS_MODE_DISABLED
	service.process_mode = Node.PROCESS_MODE_DISABLED
	await process_frame

func _survivor(pos: Vector3) -> RigidBody3D:
	var pilot := RigidBody3D.new()
	pilot.freeze = true
	scene.add_child(pilot)
	pilot.set_script(load("res://Models/Characters/DownedPilot.gd"))
	pilot.process_mode = Node.PROCESS_MODE_DISABLED
	pilot.global_position = pos
	pilot.set_meta("pilot_callsign", "RescueTest")
	return pilot

func _wait_route(pilot: Node3D) -> void:
	var deadline := Time.get_ticks_msec() + 5000
	while service.jobs.has(pilot) and service.jobs[pilot].planning and Time.get_ticks_msec() < deadline:
		await process_frame

func _roster_status(roster: Node, id: String) -> String:
	for record in roster.get_carrier_roster():
		if record.id == id: return record.status
	return "missing"

func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)
