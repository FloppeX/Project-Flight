extends "res://Tests/HarvesterSmoketest.gd"

var escort: GroundVehiclePlatoon
var guards: Array[Node3D] = []
var followed_hulls: Array[int] = []
var covered_sites: Array[int] = []
var waited_outside := false
var boarded_without_order := false
var max_guard_travel := 0.0
var checked_busy_return := false

func _test_auto_cycle(bay: Node, at: Vector3) -> void:
	var carrier := get_tree().get_first_node_in_group("carrier") as Node3D
	bay.stored_vehicles -= 2 # Two combat vehicles already deployed in this fixture.
	escort = GroundOpsManager.get_platoon("Ember")
	for i in 2:
		var guard := preload("res://GroundVehicle/ground_vehicle_1.tscn").instantiate()
		guard.position = carrier.to_global(Vector3(110 if i == 0 else -110, 0, -160))
		guard.position.y = 1.5
		world.add_child(guard)
		guard.assign_platoon(escort)
		guards.append(guard)
	_expect(GroundOpsManager.order_escort_harvester("Ember"), "real ground escort order accepted")
	get_tree().physics_frame.connect(_observe_escort)
	await super._test_auto_cycle(bay, at + Vector3(0, 0, -240))
	get_tree().physics_frame.disconnect(_observe_escort)
	_expect(followed_hulls.size() == 2, "same assignment follows both physical harvester hulls")
	_expect(covered_sites.size() == 2, "driving guards reach both working sites")
	_expect(waited_outside and not boarded_without_order, "guards wait on ground through both unloads")
	_expect(max_guard_travel > 150.0 and escort.objective_type == escort.ObjectiveType.ESCORT_HARVESTER, "escort actually travels and remains assigned after final unload")
	print("HARVESTER_ESCORT_CYCLE hulls=%s covered=%s ground_wait=%s travel=%.1f" % [followed_hulls.size(), covered_sites, waited_outside, max_guard_travel])
	_expect(checked_busy_return, "busy bay check ran during harvester unloading")
	GroundOpsManager.order_rtb("Ember")
	var before_stock: int = bay.stored_vehicles
	var deadline := Time.get_ticks_msec() + 45000
	while Time.get_ticks_msec() < deadline:
		OperationsCoordinator._process(6.0 / 60.0)
		await get_tree().physics_frame
		if not escort.has_members() and bay.state == 0: break
	_expect(not escort.has_members() and bay.stored_vehicles == before_stock + 2, "explicit escort RTB boards both vehicles through the ramp")
	print("HARVESTER_ESCORT_RTB members=%d stored=%d" % [escort.get_members().size(), bay.stored_vehicles - before_stock])

func _observe_escort() -> void:
	var reference := escort.get_escort_reference()
	for guard in guards:
		boarded_without_order = boarded_without_order or guard.retrieve_mode or guard.deploy_mode
		max_guard_travel = maxf(max_guard_travel, absf(guard.global_position.z + 160.0))
	if is_instance_valid(ops.vehicle) and reference == ops.vehicle:
		var id: int = ops.vehicle.get_instance_id()
		if not id in followed_hulls: followed_hulls.append(id)
		if ops.phase == "harvesting" and not ops.source_id in covered_sites:
			var all_close := true
			for guard in guards:
				all_close = all_close and guard.global_position.distance_to(ops.vehicle.global_position) < 160.0
			if all_close: covered_sites.append(ops.source_id)
	elif is_instance_valid(ops.vehicle) and ops.vehicle.retrieve_mode:
		if not checked_busy_return:
			checked_busy_return = true
			var before: int = escort.objective_type
			_expect(not OpsUnitAdapter.create(escort).try_begin_ground_retrieval() and escort.objective_type == before, "busy harvester bay refuses boarding without clearing escort intent")
		var clear := true
		for guard in guards:
			var local: Vector3 = reference.to_local(guard.global_position)
			clear = clear and absf(local.x) > 50.0 and guard.global_position.y < 10.0
		waited_outside = waited_outside or clear
