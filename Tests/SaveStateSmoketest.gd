extends Node

const MAIN_SCENE: PackedScene = preload("res://Main_Scene.tscn")


class PendingLoadRunner:
	extends Node

	var expected_carrier_position := Vector3.ZERO
	var expected_terrain_position := Vector3.ZERO
	var expected_hangar_count := 0
	var expected_aircraft_health := 0.0
	var expected_vehicle_health := 0.0
	var started_ms := 0
	var next_progress_ms := 0
	var restored_settle_frames := 0
	var observed_pending_carrier := false

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		started_ms = Time.get_ticks_msec()
		next_progress_ms = started_ms + 15000

	func _process(_delta: float) -> void:
		var now_ms := Time.get_ticks_msec()
		if now_ms >= next_progress_ms:
			print("[SaveStateSmoketest] Waiting for pending-load world initialization (%ds)" % int((now_ms - started_ms) / 1000))
			next_progress_ms += 15000
		if now_ms - started_ms > 180000:
			_fail_pending("pending-load initialization timed out")
			return
		var scene := get_tree().current_scene
		if scene == null or scene.scene_file_path != "res://Main_Scene.tscn":
			restored_settle_frames = 0
			return
		if GameSession.has_pending_save_state():
			var pending_carrier := get_tree().get_first_node_in_group("carrier") as Node3D
			if pending_carrier != null \
			and pending_carrier.has_method("is_initial_placement_complete") \
			and bool(pending_carrier.call("is_initial_placement_complete")):
				var pending_xz := Vector2(
					pending_carrier.global_position.x,
					pending_carrier.global_position.z
				)
				var expected_pending_xz := Vector2(
					expected_carrier_position.x,
					expected_carrier_position.z
				)
				if pending_xz.distance_to(expected_pending_xz) > 0.1:
					_fail_pending("carrier used a temporary startup position before restore")
					return
				observed_pending_carrier = true
			restored_settle_frames = 0
			return
		restored_settle_frames += 1
		if restored_settle_frames < 3:
			return
		var carrier := get_tree().get_first_node_in_group("carrier") as Node3D
		var carrier_manager := get_tree().get_first_node_in_group("carrier_manager")
		var flight_deck := get_tree().get_first_node_in_group("flight_deck_manager")
		var terrain := get_tree().get_first_node_in_group("terrain_provider") as Node3D
		if carrier == null or carrier_manager == null or flight_deck == null or terrain == null:
			return
		var vehicle_bay := carrier.get("vehicle_bay") as Node
		if not is_equal_approx(float(carrier_manager.get("corium_units")), 321.5):
			_fail_pending("pending load did not restore carrier resources")
			return
		if vehicle_bay == null or int(vehicle_bay.get("stored_vehicles")) != 3:
			_fail_pending("pending load did not restore vehicle inventory")
			return
		var hangar_state := flight_deck.call("get_hangar_status") as Dictionary
		if int(hangar_state.get("stored_count", -1)) != expected_hangar_count:
			_fail_pending("pending load did not restore hangar inventory")
			return
		var restored_xz := Vector2(carrier.global_position.x, carrier.global_position.z)
		var expected_xz := Vector2(expected_carrier_position.x, expected_carrier_position.z)
		if restored_xz.distance_to(expected_xz) > 0.1:
			_fail_pending("pending load did not restore carrier strategic position: expected=%s actual=%s" % [expected_xz, restored_xz])
			return
		if terrain.position.distance_to(expected_terrain_position) > 0.1:
			_fail_pending("pending load did not restore floating-origin terrain position")
			return
		if not _check_restored_friendlies():
			return
		if not observed_pending_carrier:
			_fail_pending("pending carrier placement was not observed before full restore")
			return
		print("[SaveStateSmoketest] PASS pending_load=valid pre_restore_carrier=stable hangar=%d friendlies=air+ground backup=valid codec=valid" % expected_hangar_count)
		get_tree().quit(0)

	func _check_restored_friendlies() -> bool:
		var flight := AirOpsManager.get_flight("Archer")
		if flight == null or flight.strength() != 1:
			_fail_pending("pending load did not restore Archer flight")
			return false
		var aircraft := flight.get_members()[0]
		if aircraft.name != "SaveFlightAircraft" \
		or not is_equal_approx(float(aircraft.get("current_health")), expected_aircraft_health):
			_fail_pending("pending load did not restore deployed aircraft state")
			return false
		var platoon := GroundOpsManager.get_platoon("Ember")
		if platoon == null or platoon.get_members().size() != 1:
			_fail_pending("pending load did not restore Ember platoon")
			return false
		var vehicle := platoon.get_members()[0]
		if vehicle.name != "SaveGroundVehicle" \
		or not is_equal_approx(float(vehicle.get("current_health")), expected_vehicle_health):
			_fail_pending("pending load did not restore deployed ground vehicle state")
			return false
		return true

	func _fail_pending(message: String) -> void:
		push_error("[SaveStateSmoketest] FAIL %s" % message)
		get_tree().quit(1)


func _ready() -> void:
	SaveGameManager.autosave_enabled = false
	GameSession.configure_new_game(
		"Save State Smoketest",
		Color(0.2, 0.3, 0.4, 1.0),
		Color(0.8, 0.7, 0.2, 1.0),
		1,
		0,
		GameSession.MAP_OPEN_CANYONS
	)
	var world := MAIN_SCENE.instantiate()
	add_child(world)
	# Use an inexpensive nested scene for capture/codec checks first. The test then
	# changes to a real Main_Scene and waits for the pending-load lifecycle.
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	await _run_checks()


func _run_checks() -> void:
	var deck := get_tree().get_first_node_in_group("flight_deck_manager")
	if deck == null:
		_fail("flight deck missing")
		return
	deck.set("_active_test_scenario", 0)
	var probe_result := await _spawn_deployed_friendly_probes(deck)
	if not bool(probe_result.get("ok", false)):
		_fail(str(probe_result.get("message", "could not create deployed friendly probes")))
		return
	var expected_aircraft_health := float(probe_result.get("aircraft_health", 0.0))
	var expected_vehicle_health := float(probe_result.get("vehicle_health", 0.0))
	var campaign: Dictionary = SaveGameManager.call("_capture_campaign_state")
	if campaign.is_empty():
		_fail("campaign capture was empty")
		return
	for required_key in [
		"session", "world", "carrier", "carrier_manager", "pilot_roster",
		"flight_deck", "vehicle_bay", "friendly_air_ops", "friendly_ground_ops",
		"map_fog", "pois", "enemy_bases", "enemy_ops",
	]:
		if not campaign.has(required_key):
			_fail("missing campaign section: %s" % required_key)
			return
	var world_state := campaign.get("world", {}) as Dictionary
	if not (world_state.get("terrain_bake_center") is Vector3) \
	or not (world_state.get("terrain_position") is Vector3):
		_fail("floating-origin terrain state was not captured")
		return
	var unsupported_path := _find_unsupported_value(campaign)
	if not unsupported_path.is_empty():
		_fail("campaign contains an unsupported JSON value at %s" % unsupported_path)
		return
	var deck_state: Dictionary = campaign.get("flight_deck", {})
	var stored_variant: Variant = deck_state.get("stored_aircraft", [])
	if not (stored_variant is Array) or stored_variant.is_empty():
		_fail("hangar aircraft were not captured")
		return
	var probe_bytes := PackedByteArray([0, 1, 127, 255])
	var probe := {
		"position": Vector3(12.0, -3.0, 40.5),
		"color": Color(0.1, 0.2, 0.3, 0.4),
		"bytes": probe_bytes,
	}
	var encoded: Variant = SaveGameManager.call("_encode_json_value", probe)
	var parsed: Variant = JSON.parse_string(JSON.stringify(encoded))
	var decoded: Variant = SaveGameManager.call("_decode_json_value", parsed)
	if not (decoded is Dictionary) \
	or not ((decoded as Dictionary).get("position") is Vector3) \
	or not ((decoded as Dictionary).get("color") is Color) \
	or (decoded as Dictionary).get("bytes", PackedByteArray()) != probe_bytes:
		_fail("JSON value round trip failed")
		return
	var virtual_flight := EnemyVirtualFlight.new()
	add_child(virtual_flight)
	virtual_flight.restore_save_state({
		"flight_name": "Flight Mackerel",
		"pending_reports": [{"kind": "smoke"}],
	})
	var virtual_platoon := EnemyVirtualPlatoon.new()
	add_child(virtual_platoon)
	virtual_platoon.restore_save_state({
		"platoon_name": "Platoon Haddock",
		"pending_reports": [{"kind": "smoke"}],
	})
	if (virtual_flight.capture_save_state().get("pending_reports", []) as Array).size() != 1 \
	or (virtual_platoon.capture_save_state().get("pending_reports", []) as Array).size() != 1:
		_fail("virtual enemy reports did not restore")
		return
	virtual_flight.queue_free()
	virtual_platoon.queue_free()
	var wrapped := {
		"format_version": SaveGameManager.SAVE_FORMAT_VERSION,
		"metadata": {"carrier_name": "Save State Smoketest", "generation": 1},
		"campaign": campaign,
	}
	var test_save_path := "user://saves/save_state_smoketest.json"
	var test_temp_path := "user://saves/save_state_smoketest.tmp"
	var test_backup_path := "user://saves/save_state_smoketest.bak"
	var json_text := JSON.stringify(SaveGameManager.call("_encode_json_value", wrapped), "  ")
	var write_result: Dictionary = SaveGameManager.call(
		"_write_with_backup_at_paths",
		json_text,
		test_save_path,
		test_temp_path,
		test_backup_path
	)
	if not bool(write_result.get("ok", false)):
		_fail("validated save write failed: %s" % str(write_result.get("message", "unknown")))
		return
	var carrier_manager_state := campaign.get("carrier_manager", {}) as Dictionary
	carrier_manager_state["corium_units"] = 321.5
	var vehicle_bay_state := campaign.get("vehicle_bay", {}) as Dictionary
	vehicle_bay_state["stored_vehicles"] = 3
	(wrapped["metadata"] as Dictionary)["generation"] = 2
	json_text = JSON.stringify(SaveGameManager.call("_encode_json_value", wrapped), "  ")
	write_result = SaveGameManager.call(
		"_write_with_backup_at_paths",
		json_text,
		test_save_path,
		test_temp_path,
		test_backup_path
	)
	if not bool(write_result.get("ok", false)):
		_fail("second validated save write failed: %s" % str(write_result.get("message", "unknown")))
		return
	var loaded: Dictionary = SaveGameManager.call("_read_valid_save", test_save_path)
	var backup: Dictionary = SaveGameManager.call("_read_valid_save", test_backup_path)
	for path in [test_save_path, test_temp_path, test_backup_path]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if loaded.is_empty() or not GameSession.prepare_loaded_game(loaded):
		_fail("validated save read failed")
		return
	if backup.is_empty() or int((backup.get("metadata", {}) as Dictionary).get("generation", 0)) != 1:
		_fail("previous save was not retained as a valid backup")
		return
	if GameSession.carrier_name != "Save State Smoketest":
		_fail("session identity did not restore")
		return
	await _clear_deployed_friendlies()
	SaveGameManager.call("_restore_pending_campaign")
	if GameSession.has_pending_save_state():
		_fail("pending campaign state was not consumed")
		return
	var carrier_manager := get_tree().get_first_node_in_group("carrier_manager")
	var carrier := get_tree().get_first_node_in_group("carrier")
	var vehicle_bay: Node = carrier.get("vehicle_bay") as Node if carrier != null else null
	if carrier_manager == null or not is_equal_approx(float(carrier_manager.get("corium_units")), 321.5):
		_fail("carrier resources did not restore")
		return
	if vehicle_bay == null or int(vehicle_bay.get("stored_vehicles")) != 3:
		_fail("vehicle bay inventory did not restore")
		return
	await get_tree().process_frame
	await get_tree().process_frame
	if not _restored_friendlies_match(expected_aircraft_health, expected_vehicle_health):
		_fail("direct restore did not preserve deployed friendly formations")
		return
	print("[SaveStateSmoketest] DIRECT_RESTORE PASS sections=%d hangar=%d friendlies=air+ground bytes=%d backup=valid" % [
		campaign.size(),
		(stored_variant as Array).size(),
		probe_bytes.size(),
	])
	SaveGameManager.clear_cached_runtime_state()
	# Keep the real scene-transition lifecycle while avoiding the full 50 km bake
	# in a focused test. Campaign saves are geometry-tagged, so the empty fog state
	# captured above remains valid for this initialization check.
	TerrainNavGrid.cell_size_m = 60.0
	TerrainNavGrid.bake_half_extent_m = 1500.0
	TerrainNavGrid.query_cell_size_m = 48.0
	TerrainNavGrid.rows_per_frame = 12
	TerrainNavGrid.call("_reset_bake_state")
	if NavGraph.has_method("reset_until_navgrid_bakes"):
		NavGraph.call("reset_until_navgrid_bakes")
	if not GameSession.prepare_loaded_game(loaded):
		_fail("could not prepare pending-load lifecycle check")
		return
	var runner := PendingLoadRunner.new()
	runner.expected_carrier_position = (campaign.get("carrier", {}) as Dictionary).get("position", Vector3.ZERO) as Vector3
	runner.expected_terrain_position = world_state.get("terrain_position", Vector3.ZERO) as Vector3
	runner.expected_hangar_count = (stored_variant as Array).size()
	runner.expected_aircraft_health = expected_aircraft_health
	runner.expected_vehicle_health = expected_vehicle_health
	get_tree().root.add_child(runner)
	var scene_change_error := get_tree().change_scene_to_packed(MAIN_SCENE)
	if scene_change_error != OK:
		_fail("pending-load scene change failed: %s" % error_string(scene_change_error))


func _spawn_deployed_friendly_probes(deck: Node) -> Dictionary:
	var deck_state := deck.call("capture_save_state") as Dictionary
	var stored_variant: Variant = deck_state.get("stored_aircraft", [])
	if not (stored_variant is Array):
		return {"ok": false, "message": "hangar state unavailable for deployed probe"}
	var source_data: Dictionary = {}
	for entry_variant in stored_variant:
		if not (entry_variant is Dictionary):
			continue
		var entry := entry_variant as Dictionary
		var scene_file := str(entry.get("scene_file", "")).to_lower()
		if not scene_file.contains("aircraft_9") \
		and not scene_file.contains("aircraft_10") \
		and not scene_file.contains("aircraft_11"):
			source_data = entry.duplicate(true)
			break
	if source_data.is_empty():
		return {"ok": false, "message": "no fixed-wing hangar aircraft for deployed probe"}
	var carrier := get_tree().get_first_node_in_group("carrier") as Node3D
	if carrier == null:
		return {"ok": false, "message": "carrier missing for deployed probe"}
	source_data["name"] = "SaveFlightAircraft"
	source_data["position"] = carrier.global_position + Vector3(180.0, 550.0, 220.0)
	source_data["rotation"] = Vector3(0.03, 0.5, -0.08)
	source_data["scale"] = Vector3.ONE
	source_data["linear_velocity"] = Vector3(15.0, 2.0, -78.0)
	source_data["angular_velocity"] = Vector3(0.02, -0.01, 0.03)
	source_data["current_health"] = 73.5
	var aircraft := deck.call("restore_deployed_aircraft_save_state", source_data) as RigidBody3D
	if aircraft == null:
		return {"ok": false, "message": "deployed aircraft probe could not be restored"}
	AirOpsManager.reassign(aircraft, "Archer")
	AirOpsManager.order_cap("Archer", 900.0)

	var vehicle_health := 31.25
	var ground_ok := GroundOpsManager.restore_save_state({
		"platoons": [{
			"platoon_name": "Ember",
			"objective_state": {
				"objective_type": GroundVehiclePlatoon.ObjectiveType.PROTECT_POSITION,
				"objective_position": carrier.global_position + Vector3(300.0, 0.0, -180.0),
				"protect_radius_m": 275.0,
			},
			"vehicles": [{
				"name": "SaveGroundVehicle",
				"scene_file": "res://GroundVehicle/vehicle_friendly_light.tscn",
				"position": carrier.global_position + Vector3(240.0, 3.0, -120.0),
				"rotation": Vector3(0.0, -0.4, 0.0),
				"scale": Vector3.ONE,
				"velocity": Vector3(3.0, 0.0, 4.0),
				"current_health": vehicle_health,
			}],
		}]
	})
	if not ground_ok:
		return {"ok": false, "message": "deployed ground probe could not be restored"}
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	aircraft.set("current_health", 73.5)
	aircraft.linear_velocity = Vector3(15.0, 2.0, -78.0)
	var platoon := GroundOpsManager.get_platoon("Ember")
	if platoon == null or platoon.get_members().is_empty():
		return {"ok": false, "message": "deployed ground probe was not registered"}
	var vehicle := platoon.get_members()[0]
	vehicle.set("current_health", vehicle_health)
	vehicle.set("velocity", Vector3(3.0, 0.0, 4.0))
	var archer := AirOpsManager.get_flight("Archer")
	var archer_blocker := archer.get_campaign_save_blocker() if archer != null else "Archer flight missing"
	if not archer_blocker.is_empty():
		return {"ok": false, "message": "calm CAP flight still blocks campaign saving: %s" % archer_blocker}
	if not GroundOpsManager.get_campaign_save_blocker().is_empty():
		return {"ok": false, "message": "calm protection platoon still blocks campaign saving"}
	return {
		"ok": true,
		"aircraft_health": 73.5,
		"vehicle_health": vehicle_health,
	}


func _clear_deployed_friendlies() -> void:
	for flight in AirOpsManager.flights:
		for aircraft in flight.get_members().duplicate():
			flight.unregister(aircraft)
			aircraft.queue_free()
	for platoon_name in GroundOpsManager.get_platoon_names():
		var platoon := GroundOpsManager.get_platoon(platoon_name)
		if platoon == null:
			continue
		for vehicle in platoon.get_members().duplicate():
			platoon.unregister_vehicle(vehicle)
			vehicle.queue_free()
	await get_tree().process_frame


func _restored_friendlies_match(aircraft_health: float, vehicle_health: float) -> bool:
	var flight := AirOpsManager.get_flight("Archer")
	if flight == null or flight.strength() != 1:
		return false
	var aircraft := flight.get_members()[0]
	if aircraft.name != "SaveFlightAircraft" \
	or not is_equal_approx(float(aircraft.get("current_health")), aircraft_health):
		return false
	var platoon := GroundOpsManager.get_platoon("Ember")
	if platoon == null or platoon.get_members().size() != 1:
		return false
	var vehicle := platoon.get_members()[0]
	return vehicle.name == "SaveGroundVehicle" \
	and is_equal_approx(float(vehicle.get("current_health")), vehicle_health)


func _fail(message: String) -> void:
	push_error("[SaveStateSmoketest] FAIL %s" % message)
	get_tree().quit(1)


func _find_unsupported_value(value: Variant, path: String = "campaign") -> String:
	if value == null or value is bool or value is int or value is float or value is String \
	or value is Vector2 or value is Vector2i or value is Vector3 or value is Color \
	or value is PackedByteArray:
		return ""
	if value is Array:
		for index in range((value as Array).size()):
			var nested := _find_unsupported_value((value as Array)[index], "%s[%d]" % [path, index])
			if not nested.is_empty():
				return nested
		return ""
	if value is Dictionary:
		for key in (value as Dictionary).keys():
			var nested := _find_unsupported_value((value as Dictionary)[key], "%s.%s" % [path, str(key)])
			if not nested.is_empty():
				return nested
		return ""
	return "%s (%s)" % [path, type_string(typeof(value))]
