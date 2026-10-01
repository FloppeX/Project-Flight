extends "res://Tests/TacticalInputSmoketest.gd"

class Bandit extends RigidBody3D:
	var health := 100.0
	func get_team() -> int: return 2

func _bandit(at: Vector3, label: String) -> Bandit:
	var bandit := Bandit.new()
	bandit.name = label
	bandit.freeze = true
	root.add_child(bandit)
	bandit.position = at
	bandit.add_to_group("enemies")
	bandit.add_to_group("aircraft")
	return bandit

func _run() -> void:
	await process_frame
	var ops := root.get_node("AirOpsManager")
	ops.set_process(false)
	var enemy_ops := root.get_node("EnemyOpsManager")
	enemy_ops.set_process(false)
	var model = load("res://AirOps/InterceptTarget.gd")
	var flight = ops.get_flight(ops.get_flight_names()[0])
	flight.set_physics_process(false)
	flight.mission = flight.Mission.NONE
	var craft := RigidBody3D.new()
	craft.freeze = true
	root.add_child(craft)
	craft.position = Vector3(300, 800, 400)
	craft.add_to_group("friendlies")
	var pilot = load("res://Tests/Fixtures/AttackOrderPilot.gd").new()
	pilot.name = "AIPilot"
	craft.add_child(pilot)
	pilot.set_physics_process(false)
	pilot.aircraft = craft
	pilot._terrain_height_callable = func(_position: Vector3) -> float: return 0.0
	pilot.current_state = pilot.State.SEARCH
	flight.register(craft)
	var first := _bandit(Vector3(650, 900, 350), "BanditOne")
	var second := _bandit(Vector3(850, 900, 350), "BanditTwo")
	var outsider := _bandit(Vector3(750, 900, 650), "OtherFlight")
	var base = load("res://Tests/Fixtures/InterceptOrderBase.gd").new()
	root.add_child(base)
	base.set_physics_process(false)
	var enemy = load("res://Enemies/EnemyVirtualFlight.gd").new()
	root.add_child(enemy)
	enemy.flight_name = "BANDIT 01"
	enemy.position = Vector3(750, 900, 350)
	enemy.aircraft_count = 2
	enemy.active_aircraft.assign([first, second])
	enemy.vstate = enemy.VState.ACTIVE
	enemy_ops._base_flights[base] = [enemy]
	_expect(not ops.order_intercept(flight.flight_name, null), "empty target rejected")
	_expect(not ops.order_intercept(flight.flight_name, craft), "friendly rejected")
	outsider.add_to_group("ground_vehicles")
	_expect(not ops.order_intercept(flight.flight_name, outsider), "ground target rejected")
	outsider.remove_from_group("ground_vehicles")
	_expect(ops.order_intercept(flight.flight_name, first), "aircraft click accepted")
	_expect(flight._intercept_flight == enemy, "individual marker resolves to owning flight")
	_expect(flight.mission_source == "player" and not ops._flight_can_take_tactical_order(flight), "automatic allocator preserves explicit Intercept")
	_expect(pilot.current_air_task.get_target() == first, "nearest flight member assigned")
	_expect(pilot._matches_intercept_flight(second) and not pilot._matches_intercept_flight(outsider), "target selection stays inside designated flight")
	pilot.dogfight_situational_awareness_enabled = false
	pilot.known_enemies.assign([outsider, first, second])
	outsider.position = craft.position + Vector3(0, 0, 5)
	_expect(pilot._find_best_air_target() != outsider and pilot._find_nearest_enemy_aircraft_target() != outsider \
		and pilot._find_alternate_dogfight_target() == second, "automatic retarget choices exclude closer unrelated flight")
	outsider.position = Vector3(750, 900, 650)
	pilot.dogfight_situational_awareness_enabled = true
	var before: int = pilot.assignments
	flight._update_intercept_assignment()
	_expect(pilot.assignments == before, "live dogfight is not reset every update")
	pilot.combat_target = second
	flight._update_intercept_assignment()
	_expect(pilot.current_air_task.get_target() == second and pilot._has_commanded_intercept_track(second), "pilot retarget within formation keeps controller tracking")
	pilot.combat_target = first
	first.health = 0
	flight._update_intercept_assignment()
	_expect(pilot.current_air_task.get_target() == second, "surviving member replaces destroyed aircraft")
	second.position.x += 100
	_expect(flight.get_mission_map_points()[0] == second.position, "map order follows surviving aircraft")
	second.health = 0
	flight._update_intercept_assignment()
	_expect(flight.mission == flight.Mission.RTB, "destroyed flight completes order")
	first.health = 100
	second.health = 100
	pilot.current_state = pilot.State.LAUNCHING
	before = pilot.assignments
	ops.order_intercept(flight.flight_name, enemy)
	_expect(pilot.assignments == before, "launch remains uninterrupted")
	pilot.current_state = pilot.State.SEARCH
	flight._apply_pending_mission_updates()
	_expect(pilot.current_state == pilot.State.DOGFIGHT, "intercept applies after launch")
	pilot.current_state = pilot.State.RECOVERY_APPROACH
	before = pilot.assignments
	ops.order_intercept(flight.flight_name, enemy)
	flight._update_intercept_assignment()
	_expect(pilot.assignments == before, "recovery approach remains uninterrupted")
	pilot.current_state = pilot.State.ATTACK_DIVE
	before = pilot.assignments
	ops.order_intercept(flight.flight_name, enemy)
	_expect(pilot.assignments == before, "committed dive remains uninterrupted")
	pilot.current_state = pilot.State.SEARCH
	flight._apply_pending_mission_updates()
	# Virtual flight interception must navigate, follow movement, and acquire its materialized members.
	enemy.active_aircraft.clear()
	enemy.vstate = enemy.VState.VIRTUAL
	pilot.current_state = pilot.State.SEARCH
	ops.order_intercept(flight.flight_name, enemy)
	_expect(not pilot.waypoints.is_empty() and flight.mission == flight.Mission.INTERCEPT, "virtual target creates pursuit route")
	var previous_center: Vector3 = pilot.current_air_task.metadata.search_route_center
	enemy.position.x += 800
	flight._update_intercept_assignment()
	_expect(pilot.current_air_task.metadata.search_route_center != previous_center, "virtual pursuit route follows movement")
	enemy.active_aircraft.assign([first, second])
	enemy.vstate = enemy.VState.ACTIVE
	flight._update_intercept_assignment()
	_expect(pilot.current_air_task.get_target() == first, "materialized target becomes intercept task")
	ops.order_rtb(flight.flight_name)
	_expect(not pilot._has_flight_intercept_order(), "recall releases flight target scope")
	pilot.current_state = pilot.State.SEARCH
	flight.set_intercept(outsider, null)
	_expect(not flight._intercept_tracks_flight and pilot.current_air_task.get_target() == outsider, "automatic single-aircraft intercept is preserved")
	# Exercise the actual tactical menu, transformed map hit testing, and target lifetime.
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
	fog.reveal_circle(Vector3(500, 0, 500), 2000.0)
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
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://logs/flight_intercept_menu.png")
	for entry in tactical.get("_mission_buttons"):
		if entry.id == "ATTACK":
			_click(entry.button.get_global_rect().get_center())
			break
	_expect(tactical._selected_mission_id == "ATTACK", "Attack menu button opens draft")
	_expect(not tactical._can_confirm_draft(), "targetless Attack cannot confirm")
	var input: Control = tactical._map_input
	var point: Vector2 = tactical._world_to_map_local(Vector3(500, 0, 800))
	_click(input.get_global_transform() * point)
	_expect(tactical._can_confirm_draft() and not tactical._draft_tracks_flight, "terrain click creates area Attack")
	point = tactical._world_to_map_local(first.position)
	_click(input.get_global_transform() * point)
	_expect(tactical._draft_intercept_target == enemy and tactical._can_confirm_draft(), "click on aircraft stages whole flight")
	tactical._map_zoom = 2.0
	tactical._map_view_center_uv = Vector2(0.65, 0.45)
	tactical._apply_map_view()
	point = tactical._world_to_map_local(first.position)
	_click(input.get_global_transform() * point)
	_expect(tactical._draft_intercept_target == enemy, "zoomed aircraft marker retains flight hit testing")
	tactical._map_zoom = 1.0
	tactical._map_view_center_uv = Vector2(0.5, 0.5)
	tactical._apply_map_view()
	first.position.z += 40
	second.position.z += 40
	tactical._refresh_ui()
	_expect(tactical._draft_points[0] == model.position(enemy), "draft follows moving flight")
	var symbols = tactical._symbol_layer
	_expect(symbols._intercept_draft_center == model.position(enemy), "draft has flight target marker")
	if DisplayServer.get_name() != "headless":
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://logs/flight_intercept_draft.png")
	tactical._confirm_draft()
	_expect(flight._intercept_flight == enemy and symbols._intercept_center == model.position(enemy), "confirmation retains moving target marker")
	tactical._begin_mission_draft("ATTACK")
	point = tactical._world_to_map_local(outsider.position)
	_click(input.get_global_transform() * point)
	_expect(tactical._draft_intercept_target == outsider, "standalone enemy aircraft can be selected")
	outsider.free()
	tactical._refresh_ui()
	_expect(not tactical._can_confirm_draft() and tactical._draft_points.is_empty(), "deleted draft target clears safely")
	tactical._cancel_draft()
	_expect(symbols._intercept_draft_center == Vector3.INF, "cancel clears target marker")
	# Real pilot receives an air task, engages beyond CAP bounds, and retains visual fire gating.
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
	first.position = Vector3(22000, 900, 500)
	second.position = Vector3(23000, 900, 500)
	_expect(ops.order_intercept(flight.flight_name, enemy), "real pilot accepts Intercept")
	_expect(real_pilot.current_state == real_pilot.State.DOGFIGHT and real_pilot.combat_target == first, "real pilot starts pursuing assigned member")
	_expect(real_pilot._is_within_engagement_radius(first, 100.0), "explicit intercept is not cancelled by CAP radius")
	var contact: Dictionary = real_pilot._dogfight_target_observation(first)
	_expect(not contact.is_empty() and not contact.get("visible", true), "controller report does not grant visual contact")
	real_pilot._state_dogfight(0.016)
	_expect(real_pilot.current_state == real_pilot.State.DOGFIGHT, "distant reported target remains a pursuit")
	enemy.free()
	flight._update_intercept_assignment()
	_expect(flight.mission == flight.Mission.RTB, "removed flight completes safely")
	flight.unregister(real_craft)
	real_craft.free()
	console.set_open(false)
	enemy_ops._base_flights.erase(base)
	base.free()
	craft.free()
	first.free()
	second.free()
	for failure in failures: push_error(failure)
	print("FLIGHT_INTERCEPT_ORDER_%s failures=%s" % ["PASS" if failures.is_empty() else "FAIL", failures])
	quit(0 if failures.is_empty() else 1)
