extends "res://Tests/HarvesterMissionsSmoketest.gd"

func _test_map() -> void:
	await super._test_map()
	var platoon := GroundOpsManager.get_platoon("Ember")
	var member := preload("res://GroundVehicle/ground_vehicle_1.tscn").instantiate()
	add_child(member)
	member.set_physics_process(false)
	member.assign_platoon(platoon)
	member.position = Vector3(80, 1, -160)
	check(GroundOpsManager.order_escort_harvester("Ember"), "persistent escort accepted")
	check(not GroundOpsManager.is_automatically_available(platoon), "automatic carrier defense cannot take a player escort")
	harvester.position = Vector3(800, 1, -600)
	ops.phase = "harvesting"
	check(platoon.get_escort_reference() == harvester, "field escort follows actual harvester")
	var destination: Vector3 = platoon.get_destination_for(member)
	check(destination.distance_to(harvester.position) > 50.0 and destination.distance_to(harvester.position) < 110.0, "guard slots stay outside intake and corium hazard")
	check("GUARDING HARVESTER" == platoon.get_harvester_escort_state(), "working site has explicit guard status")
	var route: Array[Vector3] = [member.position, destination]
	harvester.position += Vector3(12, 0, 0)
	member._on_navigation_path_computed(route, destination, 0, 1.0, 1.0)
	check(not member._nav_path_positions.is_empty(), "moving harvester does not invalidate every queued route")
	ops.phase = "retrieving"
	harvester.retrieve_mode = true
	check(platoon.get_escort_reference() == harvester, "escort accompanies the long return approach")
	harvester.position = Vector3(0, 1, -190)
	check(platoon.get_escort_reference() == carrier, "escort peels away before ramp entry")
	for yaw in [0.0, 0.8]:
		carrier.rotation.y = yaw
		member.position = carrier.to_global(Vector3(80, 1, -160))
		var local_slot: Vector3 = carrier.to_local(platoon.get_destination_for(member))
		check(absf(local_slot.x) >= 75.0 and local_slot.z < 0.0, "rotated carrier waiting slot is outside rear ramp corridor")
	carrier.rotation.y = 0.0
	harvester.retrieve_mode = false
	ops._on_retrieved(harvester)
	harvester.free()
	check(platoon.get_escort_reference() == carrier and platoon.has_active_objective(), "unloading and freeing the hull retain assignment")
	var saved: Dictionary = SaveGameManager._decode_json_value(JSON.parse_string(JSON.stringify(SaveGameManager._encode_json_value(GroundOpsManager._capture_platoon_objective(platoon)))))
	platoon.set_hold_objective()
	GroundOpsManager._carrier = carrier
	GroundOpsManager._restore_platoon_objective(platoon, saved)
	check(platoon.objective_type == platoon.ObjectiveType.ESCORT_HARVESTER and platoon.get_escort_reference() == carrier, "JSON checkpoint restores escort while harvester is stored")
	check(OperationsCoordinator.get_unit_status(platoon).order.kind == OpsOrder.Kind.ESCORT_HARVESTER, "restored standing order retains semantic intent")
	harvester = preload("res://GroundVehicle/Harvester.tscn").instantiate()
	add_child(harvester)
	harvester.set_physics_process(false)
	ops.vehicle = harvester
	harvester.position = Vector3(0, 1, -280)
	harvester.deploy_mode = true
	check(platoon.get_escort_reference() == carrier, "escort waits until deployment clears")
	harvester.deploy_mode = false
	ops.phase = "travelling"
	check(platoon.get_escort_reference() == harvester, "same escort rejoins a newly created hull")
	var offset := Vector3(3400, 0, -2300)
	var before: Vector3 = platoon.get_destination_for(member)
	carrier.position -= offset
	harvester.position -= offset
	member.position -= offset
	platoon.apply_origin_shift(offset)
	check(platoon.get_destination_for(member).is_equal_approx(before - offset), "moving origin preserves relative escort formation")
	carrier.position += offset
	harvester.position += offset
	member.position += offset
	platoon.apply_origin_shift(-offset)
	var enemy := Node3D.new()
	add_child(enemy)
	member.position = harvester.position + Vector3(60, 0, 60)
	enemy.position = harvester.position + Vector3(100, 0, 0)
	check(platoon.can_harvester_escort_engage(member, enemy), "nearby threats permit local combat")
	member.current_target = enemy
	check(member._has_combat_target(), "driver engages a live nearby escort threat")
	enemy.position += Vector3(1000, 0, 0)
	check(not platoon.can_harvester_escort_engage(member, enemy), "distant threats cannot pull escort away")
	enemy.free()
	check(not platoon.can_harvester_escort_engage(member, enemy), "freed threat is rejected before typed binding")
	check(not member._has_combat_target() and member.current_target == null, "driver clears a freed combat target before escort checks")
	var route_destination := harvester.position + Vector3(65, 0, 0)
	check(member._select_steering_destination(route_destination) == route_destination, "freed threat leaves escort navigation in control")
	member._update_shoot_and_scoot(0.1)
	check(not member._had_combat_target_last_frame, "freed threat resets combat movement")
	check(not platoon.can_harvester_escort_engage(member, null), "missing threat cannot engage")
	var pending_enemy := Node3D.new()
	add_child(pending_enemy)
	pending_enemy.position = harvester.position + Vector3(100, 0, 0)
	pending_enemy.queue_free()
	check(not platoon.can_harvester_escort_engage(member, pending_enemy), "queued deletion threat cannot engage")
	GroundOpsManager.order_hold("Ember")
	check(platoon.objective_type == platoon.ObjectiveType.NONE, "explicit hold cancels persistent escort")
	GroundOpsManager.order_escort_harvester("Ember")
	GroundOpsManager.order_rtb("Ember")
	check(platoon.objective_type == platoon.ObjectiveType.RETURN_TO_BASE and OperationsCoordinator.get_unit_status(platoon).order.kind == OpsOrder.Kind.RECOVER, "separate RTB cancels escort and requests boarding")
	await _escort_map(platoon)
	member.free()
	print("HARVESTER_ESCORT_%s failures=%s" % ["PASS" if failures.is_empty() else "FAIL", failures])

func _escort_map(platoon: GroundVehiclePlatoon) -> void:
	var map := WorldMapOverlay
	CarrierConsole.show_page("tactical", true)
	var button: Button
	for entry in map._asset_buttons:
		if entry.kind == map.AssetKind.PLATOON and entry.name == "Ember": button = entry.button
	map._select_asset(map.AssetKind.PLATOON, "Ember", button)
	map._begin_mission_draft("ESCORT")
	check(not map._can_confirm_draft(), "escort requires an explicit friendly target")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = map._world_to_map_local(Vector3(2000, 0, 2000))
	map._on_map_gui_input(click)
	check(not map._can_confirm_draft(), "arbitrary terrain is not an escort target")
	harvester.position = Vector3(1100, 1, -1200)
	click.position = map._world_to_map_local(harvester.position)
	map._on_map_gui_input(click)
	check(map._draft_escort_target == "harvester" and map._can_confirm_draft(), "map click targets the moving harvester")
	if "--rendered" in OS.get_cmdline_user_args(): await _capture("escort_draft")
	map._confirm_draft()
	check(platoon.objective_type == platoon.ObjectiveType.ESCORT_HARVESTER, "map confirmation dispatches persistent escort")
	check("ESCORT HARVESTER" in map._info_body.text, "selected platoon names the protected unit")
	if "--rendered" in OS.get_cmdline_user_args(): await _capture("escort_active")
	map._begin_mission_draft("ESCORT")
	click.position = map._world_to_map_local(carrier.position)
	map._on_map_gui_input(click)
	map._confirm_draft()
	check(platoon.objective_type == platoon.ObjectiveType.ESCORT_CARRIER, "carrier escort remains selectable")
	ops.vehicle = null
	ops.phase = "stored"
	map._begin_mission_draft("ESCORT")
	map.select_harvester()
	check(map._selected_asset_kind == map.AssetKind.PLATOON and map._draft_escort_target == "harvester" and map._can_confirm_draft(), "stored harvester is an unambiguous target through its sidebar entry")
	map._confirm_draft()
	check(platoon.objective_type == platoon.ObjectiveType.ESCORT_HARVESTER, "stored harvester escort waits persistently at carrier")
	map._begin_mission_draft("ESCORT")
	map.select_harvester()
	carrier.vehicle_bay.stored_harvesters = 0
	check(not map._can_confirm_draft(), "lost target invalidates draft")
	carrier.vehicle_bay.stored_harvesters = 1
	map._cancel_draft()
	ops.vehicle = harvester
	CarrierConsole.set_open(false)
