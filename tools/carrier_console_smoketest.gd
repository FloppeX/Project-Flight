extends SceneTree

const OPERATIONAL_UNITS_PAGE: Script = preload("res://UI/OperationalUnitsPage.gd")

class MockWeapon:
	extends Node
	var weapon_name: String = "20mm Autocannon"

class MockHardpoint:
	extends Node
	var weapon_instance: Node = null
	var mounted_weapon: PackedScene = null

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	var console := root.get_node_or_null("CarrierConsole")
	var tactical := root.get_node_or_null("WorldMapOverlay")
	var personnel := root.get_node_or_null("PilotRosterOverlay")

	_expect(console != null, "CarrierConsole autoload is available")
	_expect(tactical != null, "WorldMapOverlay autoload is available")
	_expect(personnel != null, "PilotRosterOverlay autoload is available")
	var pilot_roster := root.get_node_or_null("PilotRoster")
	_expect(pilot_roster != null, "PilotRoster autoload is available")
	if console == null or tactical == null or personnel == null:
		_finish()
		return

	_expect(not bool(console.call("is_open")), "console starts closed")
	if pilot_roster != null:
		var roster: Array = pilot_roster.call("get_carrier_roster")
		var used_portraits: Dictionary = {}
		_expect(not roster.is_empty(), "pilot roster contains pilots")
		for pilot_variant in roster:
			var pilot: Dictionary = pilot_variant
			var portrait_path := str(pilot.get("portrait_path", ""))
			var pilot_name := str(pilot.get("name", "Pilot"))
			_expect(portrait_path != "", "%s has a portrait" % str(pilot.get("name", "Pilot")))
			_expect(ResourceLoader.exists(portrait_path), "%s portrait exists" % str(pilot.get("name", "Pilot")))
			_expect(not used_portraits.has(portrait_path), "%s portrait is unique" % str(pilot.get("name", "Pilot")))
			_expect(is_zero_approx(float(pilot.get("air_kills", -1.0))), "%s starts with zero air kills" % pilot_name)
			_expect(is_zero_approx(float(pilot.get("ground_kills", -1.0))), "%s starts with zero ground kills" % pilot_name)
			_expect(is_zero_approx(float(pilot.get("mission_time_s", -1.0))), "%s starts with zero flight time" % pilot_name)
			_expect(int(pilot.get("sorties_flown", -1)) == 0, "%s starts with zero sorties" % pilot_name)
			used_portraits[portrait_path] = true

	var toggle_event := InputEventAction.new()
	toggle_event.action = &"map_toggle"
	toggle_event.pressed = true
	Input.parse_input_event(toggle_event)
	await process_frame
	_expect(bool(console.call("is_open")), "map_toggle opens the console")
	_expect(str(console.call("get_current_page")) == "tactical", "tactical is the default page")
	_expect(bool(tactical.call("is_console_visible")), "tactical page is visible")
	_expect(not bool(personnel.call("is_console_visible")), "personnel page is hidden")
	var mobility_rect := tactical.get("_mobility_rect") as TextureRect
	var mobility_material := tactical.get("_mobility_material") as ShaderMaterial
	_expect(mobility_rect != null, "tactical page has a mobility texture layer")
	_expect(mobility_material != null, "mobility layer has its classification shader")
	if mobility_material != null:
		tactical.set("_selected_asset_kind", 2) # WorldMapOverlay.AssetKind.PLATOON
		tactical.call("_refresh_mobility_display")
		_expect(float(mobility_material.get_shader_parameter("vehicle_strength")) >= 0.9, "platoon selection emphasizes vehicle mobility")
		tactical.set("_selected_asset_kind", 3) # WorldMapOverlay.AssetKind.CARRIER
		tactical.call("_refresh_mobility_display")
		_expect(float(mobility_material.get_shader_parameter("carrier_strength")) >= 0.99, "carrier selection emphasizes carrier corridors")
		_expect(float(mobility_material.get_shader_parameter("vehicle_strength")) <= 0.11, "carrier selection subdues vehicle-only corridors")
		tactical.set("_selected_asset_kind", 0) # WorldMapOverlay.AssetKind.NONE
		tactical.call("_refresh_mobility_display")
	var fog_toggle_event := InputEventKey.new()
	fog_toggle_event.keycode = KEY_H
	fog_toggle_event.pressed = true
	Input.parse_input_event(fog_toggle_event)
	await process_frame
	_expect(bool(tactical.call("is_fog_mask_suppressed")), "H suppresses the tactical fog mask")
	Input.parse_input_event(fog_toggle_event)
	await process_frame
	_expect(not bool(tactical.call("is_fog_mask_suppressed")), "a second H reapplies the tactical fog mask")
	var order_bar := tactical.get("_order_bar") as Control
	var mission_popup := tactical.get("_mission_popup") as Control
	_expect(order_bar != null and not order_bar.visible, "confirmation bar stays hidden before an order is ready")
	var asset_entries_variant = tactical.get("_asset_buttons")
	var asset_entries: Array = asset_entries_variant if asset_entries_variant is Array else []
	_expect(not asset_entries.is_empty(), "tactical page has selectable assets")
	if not asset_entries.is_empty():
		var asset_button := asset_entries[0].get("button") as Button
		asset_button.emit_signal("pressed")
		await process_frame
		_expect(mission_popup != null and mission_popup.visible, "asset selection opens the adjacent mission menu")
		_expect(order_bar != null and not order_bar.visible, "confirmation bar stays hidden while choosing a mission")
		tactical.call("_begin_mission_draft", "CAP")
		await process_frame
		_expect(mission_popup != null and not mission_popup.visible, "choosing a mission closes the mission menu")
		_expect(order_bar != null and not order_bar.visible, "confirmation bar waits for the required map target")
		var preview_points: Array[Vector3] = [Vector3(0.0, 800.0, 0.0)]
		tactical.set("_draft_points", preview_points)
		tactical.call("_refresh_ui")
		await process_frame
		_expect(order_bar != null and order_bar.visible, "confirmation bar appears when the order is ready")
		tactical.call("_cancel_draft")
		await process_frame
		_expect(order_bar != null and not order_bar.visible, "cancelling hides the confirmation bar")

	console.call("show_page", "personnel")
	await process_frame
	_expect(not bool(tactical.call("is_console_visible")), "tactical page hides after navigation")
	_expect(bool(personnel.call("is_console_visible")), "personnel page is visible")

	console.call("show_page", "air_wing")
	await process_frame
	_expect(not bool(tactical.call("is_console_visible")), "tactical page stays hidden on the flights page")
	_expect(not bool(personnel.call("is_console_visible")), "personnel page hides on the flights page")
	var flights_page := console.get("_air_wing_page") as Control
	var platoons_page := console.get("_ground_page") as Control
	_expect(flights_page != null and flights_page.visible, "active flights page is visible")
	_expect(platoons_page != null and not platoons_page.visible, "active platoons page remains hidden")
	var flight_snapshot: Dictionary = console.call("get_page_debug_snapshot", "air_wing")
	_expect(str(flight_snapshot.get("kind", "")) == "flights", "flights page reports its data kind")
	_expect(str(flight_snapshot.get("layout", "")) == "all_flights", "flights page uses the all-flights board layout")
	_expect(int(flight_snapshot.get("unit_count", 0)) == 4, "flights page lists all four persistent flight groups")
	var flight_rows := flights_page.get("_flight_rows") as VBoxContainer
	_expect(flight_rows != null and flight_rows.get_child_count() == 4, "all four flight rows render simultaneously")
	var flight_filters: Dictionary = flights_page.get("_filter_buttons")
	_expect(flight_filters.is_empty(), "flights board no longer uses roster filters")
	_expect(OPERATIONAL_UNITS_PAGE.map_air_activity("DOGFIGHT") == "ATTACKING", "dogfighting aircraft report attacking")
	_expect(OPERATIONAL_UNITS_PAGE.map_air_activity("TRANSIT", true) == "EVADING", "defensive manoeuvres override transit with evading")
	_expect(OPERATIONAL_UNITS_PAGE.map_air_activity("IDLE", false, true) == "DESTROYED", "lost aircraft report destroyed")
	_expect(str(flights_page.call("_catalog_display_name", "res://Aircraft/Aircraft_1.tscn")) == "SNA AS-20 Sand Sprite", "aircraft cards use the catalog plane type")
	var aircraft_1_outline_path := str(OPERATIONAL_UNITS_PAGE.aircraft_outline_path_for_reference("res://Aircraft/Aircraft_1.tscn"))
	_expect(aircraft_1_outline_path == "res://Images/Aircraft Outlines/aircraft_1.png", "aircraft scene paths map to top-down outlines")
	_expect(ResourceLoader.exists(aircraft_1_outline_path), "Aircraft 1 top-down outline is importable")
	if pilot_roster != null:
		var pilots: Array = pilot_roster.call("get_carrier_roster")
		if not pilots.is_empty():
			var mock_aircraft := Node3D.new()
			mock_aircraft.name = "Aircraft_1"
			mock_aircraft.set_meta("pilot_display_name", "LT TEST PILOT")
			mock_aircraft.set_meta("pilot_identity", pilots[0])
			var mock_hardpoint := MockHardpoint.new()
			var mock_weapon := MockWeapon.new()
			mock_hardpoint.weapon_instance = mock_weapon
			mock_hardpoint.add_child(mock_weapon)
			mock_aircraft.add_child(mock_hardpoint)
			var card_data: Dictionary = flights_page.call("_aircraft_member_summary", mock_aircraft, 0)
			_expect(str(card_data.get("portrait_path", "")) == str((pilots[0] as Dictionary).get("portrait_path", "")), "aircraft card uses the assigned pilot portrait")
			_expect(str(card_data.get("outline_path", "")) == aircraft_1_outline_path, "aircraft card uses its top-down outline")
			_expect(str(card_data.get("loadout", "")) == "20MM AUTOCANNON", "aircraft card reads its mounted loadout")
			var card_host := HBoxContainer.new()
			flights_page.add_child(card_host)
			flights_page.call("_add_aircraft_card", card_host, card_data)
			var outline_rect := card_host.find_child("AircraftOutline", true, false) as TextureRect
			_expect(outline_rect != null and outline_rect.texture != null, "flight card renders the aircraft outline texture")
			card_host.queue_free()
			mock_aircraft.free()

	console.call("show_page", "ground_bay")
	await process_frame
	_expect(flights_page != null and not flights_page.visible, "active flights page hides after navigation")
	_expect(platoons_page != null and platoons_page.visible, "active platoons page is visible")
	var platoon_snapshot: Dictionary = console.call("get_page_debug_snapshot", "ground_bay")
	_expect(str(platoon_snapshot.get("kind", "")) == "platoons", "platoons page reports its data kind")
	_expect(int(platoon_snapshot.get("unit_count", 0)) == 4, "platoons page lists all four persistent platoons")
	_expect(OPERATIONAL_UNITS_PAGE.map_ground_activity("ATTACK_POSITION", true) == "ATTACKING", "engaged vehicles report attacking")
	_expect(OPERATIONAL_UNITS_PAGE.map_ground_activity("RETURN_TO_BASE") == "RETURNING", "retrieving vehicles report returning")
	_expect(OPERATIONAL_UNITS_PAGE.map_ground_activity("NONE", false, false, false, false, true) == "DESTROYED", "lost vehicles report destroyed")

	console.call("show_page", "carrier")
	var carrier_load_deadline := Time.get_ticks_msec() + 10000
	while Time.get_ticks_msec() < carrier_load_deadline:
		var pending_snapshot: Dictionary = console.call("get_page_debug_snapshot", "carrier")
		var pending_wireframe: Dictionary = pending_snapshot.get("wireframe", {})
		if bool(pending_wireframe.get("model_loaded", false)) \
				or not bool(pending_wireframe.get("load_requested", true)):
			break
		await create_timer(0.02).timeout
	await process_frame
	var carrier_page := console.get("_carrier_page") as Control
	_expect(platoons_page != null and not platoons_page.visible, "active platoons page hides on the carrier page")
	_expect(carrier_page != null and carrier_page.visible, "carrier schematic page is visible")
	var carrier_snapshot: Dictionary = console.call("get_page_debug_snapshot", "carrier")
	var wireframe_snapshot: Dictionary = carrier_snapshot.get("wireframe", {})
	_expect(str(carrier_snapshot.get("kind", "")) == "carrier", "carrier page reports its data kind")
	_expect(str(carrier_snapshot.get("mode", "")) == "interactive_mockup", "carrier page reports its interactive mockup mode")
	_expect(bool(carrier_snapshot.get("mock_data", false)), "carrier page labels its fictional scenario data as mock data")
	_expect(not bool(carrier_snapshot.get("telemetry_connected", true)), "carrier page does not claim unimplemented live telemetry")
	_expect(int(carrier_snapshot.get("system_count", 0)) == 10, "carrier mockup exposes all ten proposed subsystem targets")
	_expect(str(carrier_snapshot.get("selected_system", "")) == "defenses", "carrier mockup opens on its degraded defense exception")
	_expect(str(wireframe_snapshot.get("scene_path", "")) == "res://LandCarrier/LandCarrier2.tscn", "carrier schematic resolves the Technical Index carrier scene")
	_expect(bool(wireframe_snapshot.get("model_loaded", false)), "carrier schematic instantiates the catalog model")
	_expect(str(wireframe_snapshot.get("edge_mode", "")) == "crease_filtered", "carrier schematic uses crease-filtered feature edges")
	_expect(is_equal_approx(float(wireframe_snapshot.get("crease_angle_degrees", 0.0)), 25.0), "carrier schematic reports its crease threshold")
	_expect(int(wireframe_snapshot.get("wire_geometry_count", 0)) > 0, "carrier schematic applies wireframe overrides to visible geometry")
	_expect(int(wireframe_snapshot.get("wire_segment_count", 0)) > 0, "carrier schematic generates visible feature segments")
	_expect(int(wireframe_snapshot.get("source_triangle_count", 0)) > int(wireframe_snapshot.get("wire_segment_count", 0)), "crease filtering reduces the displayed carrier topology")
	_expect(bool(wireframe_snapshot.get("presentation_only", false)), "carrier schematic identifies itself as presentation-only")
	_expect(str(wireframe_snapshot.get("selected_region", "")) == "defenses", "default defense selection reaches the 3D schematic")
	_expect(bool(wireframe_snapshot.get("highlight_warning", false)), "degraded defense selection uses warning highlighting")
	_expect(int(wireframe_snapshot.get("highlighted_geometry_count", 0)) > 0, "defense selection highlights carrier geometry")
	carrier_page.call("_select_system", "elevators")
	carrier_snapshot = console.call("get_page_debug_snapshot", "carrier")
	wireframe_snapshot = carrier_snapshot.get("wireframe", {})
	_expect(str(carrier_snapshot.get("selected_system", "")) == "elevators", "carrier mockup changes selected system")
	_expect(str(wireframe_snapshot.get("selected_region", "")) == "elevators", "system selection changes the 3D highlighted region")
	_expect(not bool(wireframe_snapshot.get("highlight_warning", true)), "nominal system selection uses cyan highlighting")
	carrier_page.call("_cycle_repair_priority")
	carrier_page.call("_cycle_defense_posture")
	carrier_snapshot = console.call("get_page_debug_snapshot", "carrier")
	_expect(str(carrier_snapshot.get("repair_priority", "")) == "DEFENSES FIRST", "mock repair priority control cycles")
	_expect(str(carrier_snapshot.get("defense_posture", "")) == "CONSERVE", "mock defense posture control cycles")
	carrier_page.call("_select_system", "defenses")

	console.call("show_page", "replicator")
	await process_frame
	var replicator_page := console.get("_replicator_page") as Control
	_expect(carrier_page != null and not carrier_page.visible, "carrier schematic page hides on the replicator page")
	_expect(replicator_page != null and replicator_page.visible, "replicator concept page is visible")
	var replicator_snapshot: Dictionary = console.call("get_page_debug_snapshot", "replicator")
	_expect(str(replicator_snapshot.get("kind", "")) == "replicator", "replicator page reports its data kind")
	_expect(str(replicator_snapshot.get("mode", "")) == "concept_preview", "replicator page labels its data as a concept preview")
	_expect(int(replicator_snapshot.get("blueprint_count", 0)) == 5, "replicator concept lists the five starter blueprints")
	_expect(int(replicator_snapshot.get("queue_count", 0)) == 2, "replicator concept starts with two illustrative queue rows")
	replicator_page.call("_on_blueprint_pressed", "light_combat_vehicle")
	replicator_page.call("_change_quantity", 1)
	replicator_page.call("_on_add_to_queue_pressed")
	replicator_snapshot = console.call("get_page_debug_snapshot", "replicator")
	_expect(int(replicator_snapshot.get("queue_count", 0)) == 3, "replicator preview can add an illustrative order")
	_expect(int(replicator_snapshot.get("plasteel", 0)) == 840, "preview order updates the displayed plasteel balance only")
	_expect(int(replicator_snapshot.get("corium", 0)) == 976, "preview order updates the displayed corium balance only")
	replicator_page.call("_on_cancel_order_pressed", 2)
	replicator_snapshot = console.call("get_page_debug_snapshot", "replicator")
	_expect(int(replicator_snapshot.get("queue_count", 0)) == 2, "replicator preview can cancel the illustrative order")
	_expect(int(replicator_snapshot.get("plasteel", 0)) == 1000, "cancelling restores the preview plasteel balance")
	_expect(int(replicator_snapshot.get("corium", 0)) == 1000, "cancelling restores the preview corium balance")

	console.call("set_open", false)
	await process_frame
	_expect(not bool(console.call("is_open")), "console closes")
	_expect(not bool(tactical.call("is_console_visible")), "tactical page closes with the console")
	_expect(not bool(personnel.call("is_console_visible")), "personnel page closes with the console")
	_expect(flights_page != null and not flights_page.visible, "flights page closes with the console")
	_expect(platoons_page != null and not platoons_page.visible, "platoons page closes with the console")
	_expect(carrier_page != null and not carrier_page.visible, "carrier page closes with the console")
	_expect(replicator_page != null and not replicator_page.visible, "replicator page closes with the console")
	_finish()


func _expect(condition: bool, description: String) -> void:
	if condition:
		return
	_failures.append(description)
	push_error("[CarrierConsoleSmokeTest] FAIL: %s" % description)


func _finish() -> void:
	if _failures.is_empty():
		print("[CarrierConsoleSmokeTest] PASS")
		quit(0)
		return
	print("[CarrierConsoleSmokeTest] %d failure(s)" % _failures.size())
	quit(1)
