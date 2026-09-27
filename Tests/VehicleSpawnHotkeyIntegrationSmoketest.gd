extends SceneTree

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	# Load after the project autoloads have entered the tree. A compile-time preload
	# resolves Main_Scene's global singleton types before they are registered.
	var packed := load("res://Main_Scene.tscn") as PackedScene
	var world := packed.instantiate() as Node3D if packed != null else null
	if world == null:
		_fail("main scene could not be instantiated")
		return
	root.add_child(world)
	current_scene = world
	await process_frame
	await process_frame

	var menu := world.get_node_or_null("VehicleSpawnMenu") as CanvasLayer
	if menu == null:
		_fail("ScenarioManager did not install the vehicle spawn menu")
		return

	var spawn_key := InputEventKey.new()
	spawn_key.pressed = true
	spawn_key.physical_keycode = KEY_S
	Input.parse_input_event(spawn_key)
	await process_frame
	if not bool(menu.call("is_open")) or not paused:
		_fail("S did not open the picker and pause the main scene")
		return

	var escape_key := InputEventKey.new()
	escape_key.pressed = true
	escape_key.keycode = KEY_ESCAPE
	escape_key.physical_keycode = KEY_ESCAPE
	menu.call("_input", escape_key)
	if bool(menu.call("is_open")) or paused:
		_fail("Escape did not close the picker and restore the main scene")
		return
	var hangar_menu := world.get_node_or_null("HangarSpawnMenu") as CanvasLayer
	if hangar_menu == null:
		_fail("ScenarioManager did not install the hangar spawn menu")
		return
	var hangar_key := InputEventKey.new()
	hangar_key.pressed = true
	hangar_key.physical_keycode = KEY_D
	Input.parse_input_event(hangar_key)
	await process_frame
	if not bool(hangar_menu.call("is_open")) or not paused:
		_fail("D did not open the aircraft picker and pause the main scene open=%s paused=%s" % [str(hangar_menu.call("is_open")), str(paused)])
		return
	hangar_key.pressed = false
	Input.parse_input_event(hangar_key.duplicate())
	await process_frame
	hangar_key.pressed = true
	Input.parse_input_event(hangar_key.duplicate())
	await process_frame
	if bool(hangar_menu.call("is_open")) or paused:
		_fail("a second D press did not close the hangar picker")
		return
	hangar_key.pressed = false
	Input.parse_input_event(hangar_key.duplicate())
	await process_frame
	hangar_key.pressed = true
	Input.parse_input_event(hangar_key.duplicate())
	await process_frame
	if not bool(hangar_menu.call("is_open")) or not paused:
		_fail("D did not reopen the hangar picker")
		return
	var selected: Dictionary = {}
	for entry in hangar_menu.call("get_spawn_entries"):
		if str(entry.get("scene", "")) == "res://Aircraft/Aircraft_13.tscn":
			selected = entry
			break
	if selected.is_empty():
		_fail("Aircraft_13 is absent from the hangar picker")
		return
	var deck := world.get_node_or_null("LandCarrier/FlightDeckManager")
	if deck == null:
		_fail("main scene has no carrier flight deck")
		return
	deck.stored_aircraft.clear()
	hangar_menu.call("_on_entry_pressed", selected)
	if paused or int(deck.current_state) != 5 \
			or deck.stored_aircraft.size() != 1 \
			or str(deck.stored_aircraft[0].get("scene_file", "")) != "res://Aircraft/Aircraft_13.tscn":
		_fail("D selection did not retrieve Aircraft_13 from an empty hangar")
		return

	print("[VehicleSpawnHotkeyIntegrationSmoketest] PASS main_scene=true s_opens=true d_opens=true aircraft13_empty_hangar_retrieval=true pause_restore=true")
	world.free()
	quit(0)


func _fail(reason: String) -> void:
	push_error("[VehicleSpawnHotkeyIntegrationSmoketest] FAIL %s" % reason)
	paused = false
	quit(1)
