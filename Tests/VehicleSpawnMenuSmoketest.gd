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
	var close_key := InputEventKey.new()
	close_key.pressed = true
	close_key.physical_keycode = KEY_S
	menu.call("_input", close_key)
	if bool(menu.call("is_open")) or paused:
		_fail("S did not close the picker and restore simulation")
		return

	var ground_entry := _entry_for(entries, "res://GroundVehicle/vehicle_friendly_light.tscn")
	var ground_vehicle := menu.call("spawn_entry", ground_entry) as Node3D
	if ground_vehicle == null or ground_vehicle.get_parent() != root \
			or not bool(ground_vehicle.get_meta("spawned_from_vehicle_menu", false)) \
			or not ground_vehicle.is_in_group("ground_vehicles"):
		_fail("friendly ground vehicle did not spawn into the active world")
		return

	var aircraft_entry := _entry_for(entries, "res://Aircraft/Aircraft_1.tscn")
	var aircraft := menu.call("spawn_entry", aircraft_entry) as RigidBody3D
	if aircraft == null or aircraft.linear_velocity.length() < 80.0:
		_fail("aircraft did not spawn airborne with safe forward speed")
		return
	for _frame in range(3):
		await process_frame
	if not aircraft.is_in_group("friendlies") or not aircraft.is_in_group("ai_aircraft") \
			or aircraft.is_in_group("aircraft"):
		_fail("spawned aircraft was not finalized as friendly AI")
		return

	print("[VehicleSpawnMenuSmoketest] PASS entries=%d pause_restore=true ground_spawn=true aircraft_spawn=true enemy_presets=4 aircraft14_named=%s land_carrier_excluded=true" % [
		entries.size(),
		str(not spitewing_entry.is_empty()),
	])
	aircraft.queue_free()
	ground_vehicle.queue_free()
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
