extends "res://Tests/TacticalInputSmoketest.gd"

class Target extends Node3D:
	var health := 100.0
	func get_team() -> int: return 2

func _target(position: Vector3) -> Target:
	var target := Target.new()
	root.add_child(target)
	target.position = position
	target.add_to_group("enemies")
	target.add_to_group("ground_vehicles")
	return target

func _run() -> void:
	await process_frame
	var ops := root.get_node("AirOpsManager")
	ops.set_process(false)
	var flight = ops.get_flight(ops.get_flight_names()[0])
	flight.set_physics_process(false)
	flight.mission = flight.Mission.NONE
	var craft := RigidBody3D.new()
	craft.freeze = true
	root.add_child(craft)
	craft.add_to_group("friendlies")
	var pilot = load("res://Tests/Fixtures/AttackOrderPilot.gd").new()
	pilot.name = "AIPilot"
	craft.add_child(pilot)
	pilot.set_physics_process(false)
	pilot.aircraft = craft
	pilot._terrain_height_callable = func(_position: Vector3) -> float: return 0.0
	pilot.current_state = pilot.State.SEARCH
	flight.register(craft)
	var center := Vector3(720, 0, 380)
	var target := _target(center + Vector3(20, 0, 0))
	var second := _target(center + Vector3(100, 0, 0))
	var outside := _target(center + Vector3(-100.1, 0, 0))
	for item in [target, second, outside]:
		ops.report_contact(craft, item)
		pilot.known_enemies.append(item)
	_expect(ops.order_attack(flight.flight_name, center), "area order must be accepted")
	_expect(flight.mission == flight.Mission.ATTACK and flight.mission_source == "player", "Attack preserves player ownership")
	_expect(not ops._flight_can_take_tactical_order(flight), "allocator must not steal Attack")
	_expect(ops._loadout_profile_for_scramble_reason("attack") == "strike", "Attack uses ground loadout")
	_expect(pilot.current_air_task.get_target() == target, "first in-circle target must be assigned")
	_expect(not pilot._is_valid_ground_attack_target(outside), "target just outside 100m must be excluded")
	_expect(pilot._is_valid_ground_attack_target(second), "target at 100m boundary remains eligible")
	_expect(flight.get_mission_map_points()[0] == center, "area center must be fixed")
	target.position.x += 200
	_expect(pilot._find_ground_attack_target() == null, "pilot must not chase a target outside the circle")
	pilot.current_state = pilot.State.SEARCH
	flight._update_attack_assignment(1.0)
	_expect(pilot.current_air_task.get_target() == second, "next in-circle target must replace departed one")
	second.health = 0
	pilot.current_state = pilot.State.ATTACK_BREAK_OFF
	flight._update_attack_assignment(20.0)
	_expect(flight.mission == flight.Mission.ATTACK, "area clear must not cancel pull-out")
	pilot.current_state = pilot.State.SEARCH
	flight._update_attack_assignment(20.0)
	_expect(flight.mission == flight.Mission.ATTACK, "distant area must be visited before declaring clear")
	_expect(not pilot.waypoints.is_empty(), "empty area needs a real search route")
	craft.position = center + Vector3(0, 500, 0)
	flight._update_attack_assignment(9.0)
	_expect(flight.mission == flight.Mission.ATTACK, "allow time for sensor search")
	flight._update_attack_assignment(1.0)
	_expect(flight.mission == flight.Mission.RTB, "clear area returns after search")
	second.health = 100
	pilot.current_state = pilot.State.LAUNCHING
	var before: int = pilot.assignments
	ops.order_attack(flight.flight_name, center)
	_expect(pilot.assignments == before, "launch must not be interrupted")
	pilot.current_state = pilot.State.SEARCH
	flight._apply_pending_mission_updates()
	_expect(pilot.current_air_task.get_target() == second, "area task applies after launch")
	var offset := Vector3(500, 0, 250)
	flight.apply_origin_shift(offset)
	pilot.apply_origin_shift(offset)
	second.position -= offset
	_expect(pilot._is_valid_ground_attack_target(second), "origin shift preserves circle membership")
	flight.apply_origin_shift(-offset)
	pilot.apply_origin_shift(-offset)
	second.position += offset
	ops.order_rtb(flight.flight_name)
	_expect(not pilot.current_air_task.metadata.get("attack_area", false), "recall releases area restriction")
	var grid := root.get_node("TerrainNavGrid")
	grid.set_process(false)
	grid.set("_cols", 101)
	grid.set("_rows", 101)
	grid.set("cell_size_m", 10.0)
	grid.set("_is_baked", true)
	var heights := PackedFloat32Array()
	heights.resize(10201)
	grid.set("_heights", heights)
	var fog := root.get_node("MapFogOfWar")
	fog.call("_initialize_from_navgrid")
	fog.reveal_circle(center, 250.0)
	var console := root.get_node("CarrierConsole")
	var tactical := root.get_node("WorldMapOverlay")
	console.show_page("tactical", true)
	await process_frame
	await process_frame
	for entry in tactical.get("_asset_buttons"):
		if entry.name == flight.flight_name:
			_click(entry.button.get_global_rect().get_center())
			break
	await process_frame
	for entry in tactical.get("_mission_buttons"):
		if entry.id == "ATTACK":
			_click(entry.button.get_global_rect().get_center())
			break
	_expect(not tactical.call("_can_confirm_draft"), "Attack requires an area center")
	var map_input: Control = tactical.get("_map_input")
	var point: Vector2 = tactical.call("_world_to_map_local", center)
	_click(map_input.get_global_transform() * point)
	_expect(tactical.call("_can_confirm_draft"), "empty explored terrain accepts Attack circle")
	var symbols = tactical.get("_symbol_layer")
	_expect(symbols._attack_draft_center.distance_to(center) < 1.0 and symbols._attack_draft_radius_m == 100, "draft shows chosen 100m circle")
	if DisplayServer.get_name() != "headless":
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://logs/flight_attack_area_draft.png")
	pilot.current_state = pilot.State.SEARCH
	tactical.call("_confirm_draft")
	_expect(flight.mission == flight.Mission.ATTACK, "UI confirmation issues Attack")
	_expect(symbols._attack_area_radius_m == 100 and symbols._attack_draft_center == Vector3.INF, "confirmed circle remains on map")
	tactical.call("_begin_mission_draft", "ATTACK")
	tactical.call("_cancel_draft")
	_expect(symbols._attack_draft_center == Vector3.INF, "cancel clears draft circle")
	# A platoon click tracks membership, including vehicles outside a 100m circle.
	var platoon = load("res://GroundVehicle/ground_vehicle_platoon.gd").new()
	platoon.team = 2
	root.add_child(platoon)
	platoon.set_physics_process(false)
	platoon.set("_contact_world_position", center)
	target.position = center + Vector3(5, 0, 0)
	second.position = center + Vector3(250, 0, 0)
	platoon.register_vehicle(target)
	platoon.register_vehicle(second)
	outside.position = center + Vector3(10, 0, 0)
	tactical.call("_begin_mission_draft", "ATTACK")
	_click(map_input.get_global_transform() * point)
	_expect(tactical.get("_draft_attack_platoon") == platoon, "platoon click must stage a unit order")
	_expect(symbols._attack_draft_center == Vector3.INF and symbols._attack_draft_platoon_center == center, "platoon marker must replace area circle")
	_expect(symbols._attack_area_radius_m == 0, "old area circle must not obscure a new platoon draft")
	if DisplayServer.get_name() != "headless":
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://logs/flight_attack_platoon_draft.png")
	pilot.current_state = pilot.State.SEARCH
	tactical.call("_confirm_draft")
	_expect(flight._attack_tracks_platoon, "platoon order must retain identity")
	_expect(pilot._is_valid_ground_attack_target(second), "spread-out platoon member stays eligible")
	_expect(not pilot._is_valid_ground_attack_target(outside), "nearby non-member must be excluded")
	var moved := center + Vector3(600, 0, 500)
	platoon.set("_contact_world_position", moved)
	target.position += moved - center
	second.position += moved - center
	flight._update_attack_assignment(1.0)
	_expect(flight.get_mission_map_points()[0] == moved, "platoon attack follows movement")
	_expect(pilot._find_ground_attack_target() == target, "moving target must retain attack ownership")
	target.health = 0
	pilot.current_state = pilot.State.SEARCH
	flight._update_attack_assignment(1.0)
	_expect(pilot.current_air_task.get_target() == second, "platoon attack continues with surviving member")
	second.health = 0
	pilot.current_state = pilot.State.ATTACK_BREAK_OFF
	flight._update_attack_assignment(20.0)
	_expect(flight.mission == flight.Mission.ATTACK, "platoon destruction must preserve egress")
	pilot.current_state = pilot.State.SEARCH
	flight._update_attack_assignment(10.0)
	_expect(flight.mission == flight.Mission.RTB, "destroyed platoon must complete mission")
	# Virtual formations retain their identity until real vehicles materialize.
	var virtual = load("res://Enemies/EnemyVirtualPlatoon.gd").new()
	root.add_child(virtual)
	virtual.position = center
	virtual.vehicle_count = 2
	pilot.current_state = pilot.State.SEARCH
	ops.order_attack(flight.flight_name, center, 100, virtual)
	flight._update_attack_assignment(20.0)
	_expect(flight.mission == flight.Mission.ATTACK, "virtual platoon must not be mistaken for an empty area")
	second.health = 100
	second.position = center + Vector3(250, 0, 0)
	virtual._active_vehicles.append(second)
	flight._update_attack_assignment(1.0)
	_expect(pilot.current_air_task.get_target() == second, "materialized member must become the target")
	virtual.free()
	pilot.current_state = pilot.State.SEARCH
	flight._update_attack_assignment(10.0)
	_expect(flight.mission == flight.Mission.RTB, "removed formation must complete safely")
	platoon.free()
	target.health = 100
	target.position = center + Vector3(220, 0, 0)
	second.position = center + Vector3(100, 0, 0)
	outside.position = center + Vector3(-100.1, 0, 0)
	# Exercise the real task-to-attack-route and empty-area search boundaries.
	var real_craft = load("res://Aircraft/Aircraft_5.tscn").instantiate()
	real_craft.freeze = true
	real_craft.position = Vector3(0, 1000, 0)
	root.add_child(real_craft)
	var real_pilot = real_craft.get_node("AIPilot")
	real_pilot.set_physics_process(false)
	real_pilot.current_state = real_pilot.State.SEARCH
	real_pilot._terrain_height_callable = func(_position: Vector3) -> float: return 0.0
	real_craft.linear_velocity = Vector3(0, 0, 90)
	flight.unregister(craft)
	flight.mission = flight.Mission.NONE
	flight.register(real_craft)
	_expect(ops.order_attack(flight.flight_name, center), "real aircraft accepts area Attack")
	_expect(real_pilot.current_air_task.get_target() == second and real_pilot.current_state == real_pilot.State.ATTACK_POSITIONING, "real pilot plans in-circle attack")
	second.free()
	real_pilot.current_state = real_pilot.State.SEARCH
	flight._update_attack_assignment(1.0)
	_expect(real_pilot.current_state == real_pilot.State.SEARCH and not real_pilot.waypoints.is_empty(), "real pilot searches area after target loss")
	flight.unregister(real_craft)
	real_craft.free()
	console.set_open(false)
	craft.free()
	target.free()
	outside.free()
	for failure in failures: push_error(failure)
	print("FLIGHT_ATTACK_AREA_%s failures=%s" % ["PASS" if failures.is_empty() else "FAIL", failures])
	quit(0 if failures.is_empty() else 1)
