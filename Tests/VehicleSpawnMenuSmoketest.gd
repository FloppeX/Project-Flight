extends SceneTree

const MENU_SCRIPT: Script = preload("res://UI/VehicleSpawnMenu.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var menu := MENU_SCRIPT.new() as CanvasLayer
	root.add_child(menu)
	await process_frame
	var entries: Array[Dictionary] = menu.call("get_spawn_entries")
	if entries.size() < 16:
		_fail("spawn catalog has only %d vehicle entries" % entries.size())
		return
	if not _has_scene(entries, "res://Aircraft/Aircraft_1.tscn") \
			or not _has_scene(entries, "res://Aircraft/Aircraft_11.tscn") \
			or not _has_scene(entries, "res://GroundVehicle/vehicle_friendly_light.tscn"):
		_fail("spawn catalog omitted a canonical airplane, helicopter, or ground vehicle")
		return
	if ResourceLoader.exists("res://Aircraft/Aircraft_14.tscn") \
			and not _has_scene(entries, "res://Aircraft/Aircraft_14.tscn"):
		_fail("uncatalogued numbered Aircraft 14 was not discovered")
		return
	var aircraft_13_entry := _entry_for(entries, "res://Aircraft/Aircraft_13.tscn")
	if aircraft_13_entry.is_empty() or str(aircraft_13_entry.get("category", "")) != "HELICOPTERS" \
			or str((aircraft_13_entry.get("stats", {}) as Dictionary).get("CLASS", "")) != "ROTARY-WING":
		_fail("Aircraft 13 is missing or not classified as a helicopter")
		return
	var vulture_entry := _entry_for(entries, "res://Wildlife/CanyonVulture.tscn")
	if vulture_entry.is_empty() \
			or str(vulture_entry.get("category", "")) != "WILDLIFE" \
			or str(vulture_entry.get("spawn_kind", "")) != "wildlife_vulture":
		_fail("canyon vulture wildlife preset is missing or misconfigured")
		return
	var storm_entry := _entry_for(entries, "res://Weather/DustFront.gd")
	if storm_entry.is_empty() or str(storm_entry.get("category", "")) != "ENVIRONMENT" \
			or str(storm_entry.get("spawn_kind", "")) != "dust_storm":
		_fail("environment dust storm preset is missing or misconfigured")
		return
	var electrical_entry := _entry_for(entries, "res://Weather/ElectricalStorm.gd")
	if electrical_entry.is_empty() or str(electrical_entry.get("category", "")) != "ENVIRONMENT" \
			or str(electrical_entry.get("spawn_kind", "")) != "electrical_storm":
		_fail("environment electrical storm preset is missing or misconfigured")
		return
	for expected_preset in [
		{"kind": "enemy_flight", "role": "bomber", "scene": "res://Aircraft/Aircraft_4.tscn"},
		{"kind": "enemy_flight", "role": "fighter", "scene": "res://Aircraft/Aircraft_3.tscn"},
		{"kind": "enemy_flight", "role": "attack", "scene": "res://Aircraft/Aircraft_6.tscn"},
		{"kind": "enemy_platoon", "role": "", "scene": ""},
	]:
		var preset := _enemy_preset_for(
			entries,
			str(expected_preset["kind"]),
			str(expected_preset["role"])
		)
		if preset.is_empty() or str(preset.get("scene", "")) != str(expected_preset["scene"]) \
				or int(preset.get("count", 0)) != 4:
			_fail("enemy formation preset is missing or misconfigured: %s/%s" % [
				expected_preset["kind"], expected_preset["role"],
			])
			return
	var spitewing_entry := _entry_for(entries, "res://Aircraft/Aircraft_14.tscn")
	if not spitewing_entry.is_empty() and (
			str(spitewing_entry.get("name", "")) != "KAW FX-5 Spitewing"
			or str(spitewing_entry.get("description", "")) != "Ultra-compact interceptor/point-defense aircraft; fast roll rate and exceptional climb, but notoriously twitchy controls with almost zero stall margin."
	):
		_fail("Aircraft 14 did not expose the approved Spitewing name and description")
		return
	if _has_scene(entries, "res://LandCarrier/LandCarrier2.tscn"):
		_fail("world-owning land carrier was exposed as an ordinary spawned unit")
		return
	if int(menu.call("get_spawn_button_count")) != entries.size():
		_fail("menu button count does not match the spawn catalog")
		return

	menu.call("set_open", true)
	if not bool(menu.call("is_open")) or not paused:
		_fail("opening the picker did not pause the simulation")
		return
	if "--render" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		for _frame in 3:
			await process_frame
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://captures"))
		root.get_texture().get_image().save_png("res://captures/storm_spawn_menu.png")
	var close_key := InputEventKey.new()
	close_key.pressed = true
	close_key.physical_keycode = KEY_S
	menu.call("_input", close_key)
	if bool(menu.call("is_open")) or paused:
		_fail("S did not close the picker and restore simulation")
		return
	menu.call("set_open", true)
	var storm_button: Button
	for button_variant in menu.get("_buttons"):
		var button := button_variant as Button
		if button.text == "DUST 5: EXTREME":
			storm_button = button
			break
	if storm_button == null:
		_fail("environment column has no dust storm button")
		return
	storm_button.pressed.emit()
	await process_frame
	await process_frame
	var storm := get_first_node_in_group("dust_front") as Node3D
	if storm == null or bool(menu.call("is_open")) or paused \
			or not storm.initialized or storm.strength < 0.99 or storm.get_severity() != 5 \
			or absf(storm.get_arrival_seconds(Vector3.ZERO) - 600.0 / 14.0) > 2.0:
		_fail("dust storm button did not place an active approaching front nearby")
		return
	for entry in entries:
		if entry.get("spawn_kind", "") == "dust_storm":
			menu.call("spawn_environment_entry", entry)
			if storm.get_severity() != int(entry["severity"]):
				_fail("storm preset did not apply its strength")
				return
	storm.global_position += Vector3(5000.0, 0.0, 0.0)
	if menu.call("spawn_environment_entry", storm_entry) != storm \
			or storm.global_position.x > 1000.0 \
			or get_nodes_in_group("dust_front").size() != 1:
		_fail("repeated dust storm spawn did not reposition the existing front")
		return
	menu.call("set_open", true)
	var electrical_button: Button
	for button_variant in menu.get("_buttons"):
		var button := button_variant as Button
		if button.text == "ELECTRICAL STORM":
			electrical_button = button
			break
	if electrical_button == null:
		_fail("environment column has no electrical storm button")
		return
	var electrical_frame: Dictionary = menu.call("_get_spawn_frame")
	electrical_button.pressed.emit()
	await process_frame
	await process_frame
	var electrical := get_first_node_in_group("electrical_storm") as Node3D
	var expected_center: Vector3 = electrical_frame["origin"] + electrical_frame["forward"] * 2200.0
	if electrical == null or not electrical.active or bool(menu.call("is_open")) or paused \
			or not bool(electrical.get_meta("spawned_from_vehicle_menu", false)) \
			or Vector2(electrical.global_position.x, electrical.global_position.z).distance_to(
				Vector2(expected_center.x, expected_center.z)) > 10.0:
		_fail("electrical storm button did not place an active cell ahead of the view")
		return
	electrical.global_position += Vector3(5000.0, 0.0, 0.0)
	if menu.call("spawn_environment_entry", electrical_entry) != electrical \
			or Vector2(electrical.global_position.x, electrical.global_position.z).distance_to(
				Vector2(expected_center.x, expected_center.z)) > 1.0 \
			or get_nodes_in_group("electrical_storm").size() != 1:
		_fail("repeated electrical storm spawn did not reposition the existing cell")
		return

	var ground_entry := _entry_for(entries, "res://GroundVehicle/vehicle_friendly_light.tscn")
	var ground_vehicle := menu.call("spawn_entry", ground_entry) as Node3D
	if ground_vehicle == null or ground_vehicle.get_parent() != root \
			or not bool(ground_vehicle.get_meta("spawned_from_vehicle_menu", false)) \
			or not ground_vehicle.is_in_group("ground_vehicles"):
		_fail("friendly ground vehicle did not spawn into the active world")
		return
	var vulture := menu.call("spawn_wildlife_entry", vulture_entry) as Node3D
	if vulture == null or not vulture.is_in_group("wildlife") \
			or not bool(vulture.get_meta("spawned_from_vehicle_menu", false)):
		_fail("canyon vulture did not spawn through the wildlife manager")
		return

	var aircraft_entry := _entry_for(entries, "res://Aircraft/Aircraft_1.tscn")
	var aircraft := menu.call("spawn_entry", aircraft_entry) as RigidBody3D
	if aircraft == null or aircraft.linear_velocity.length() < 80.0:
		_fail("aircraft did not spawn airborne with safe forward speed")
		return
	if bool(aircraft.get_meta("visual_budget_pre_tree_presentation_prepared", false)) \
	or aircraft.get_node_or_null("CameraController") == null \
	or aircraft.get_node_or_null("HeadsUpDisplay") == null \
	or aircraft.get_node_or_null("InstrumentPanel") == null \
	or aircraft.get_node_or_null("CockpitPilot") == null:
		_fail("player-viewable spawn-menu aircraft did not retain its complete presentation")
		return
	for _frame in range(3):
		await process_frame
	if not aircraft.is_in_group("friendlies") or not aircraft.is_in_group("ai_aircraft") \
			or aircraft.is_in_group("aircraft"):
		_fail("spawned aircraft was not finalized as friendly AI")
		return

	print("[VehicleSpawnMenuSmoketest] PASS entries=%d pause_restore=true ground_spawn=true wildlife_spawn=true storm_spawn=true storm_reposition=true electrical_spawn=true electrical_reposition=true aircraft_spawn=true player_presentation_retained=true enemy_presets=4 aircraft14_named=%s land_carrier_excluded=true" % [
		entries.size(),
		str(not spitewing_entry.is_empty()),
	])
	aircraft.queue_free()
	ground_vehicle.queue_free()
	vulture.queue_free()
	storm.queue_free()
	electrical.queue_free()
	menu.queue_free()
	await process_frame
	await process_frame
	quit(0)


func _has_scene(entries: Array[Dictionary], scene_path: String) -> bool:
	return not _entry_for(entries, scene_path).is_empty()


func _entry_for(entries: Array[Dictionary], scene_path: String) -> Dictionary:
	for entry in entries:
		if str(entry.get("scene", "")) == scene_path:
			return entry
	return {}


func _enemy_preset_for(entries: Array[Dictionary], spawn_kind: String, role: String) -> Dictionary:
	for entry in entries:
		if str(entry.get("spawn_kind", "")) == spawn_kind \
				and str(entry.get("role", "")) == role:
			return entry
	return {}


func _fail(reason: String) -> void:
	push_error("[VehicleSpawnMenuSmoketest] FAIL %s" % reason)
	paused = false
	quit(1)
