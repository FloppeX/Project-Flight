extends Node

const MENU_SCRIPT: Script = preload("res://UI/VehicleSpawnMenu.gd")


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var menu := MENU_SCRIPT.new() as CanvasLayer
	menu.set("hangar_mode", true)
	get_tree().root.add_child(menu)
	await get_tree().process_frame
	var aircraft_entries: Array[Dictionary] = []
	var selected: Dictionary = {}
	for entry in menu.call("get_spawn_entries"):
		if str(entry.get("category", "")) in ["AIRPLANES", "HELICOPTERS"]:
			aircraft_entries.append(entry)
			if str(entry.get("scene", "")) == "res://Aircraft/Aircraft_13.tscn":
				selected = entry
	if selected.is_empty() or int(menu.call("get_spawn_button_count")) != aircraft_entries.size():
		_fail("D menu does not list exactly the available aircraft")
		return
	var d_key := InputEventKey.new()
	d_key.pressed = true
	d_key.physical_keycode = KEY_D
	if not bool(menu.call("_is_spawn_key_event", d_key)):
		_fail("D does not close the hangar picker")
		return
	var s_key := InputEventKey.new()
	s_key.pressed = true
	s_key.physical_keycode = KEY_S
	if bool(menu.call("_is_spawn_key_event", s_key)):
		_fail("S incorrectly closes the hangar picker")
		return
	var requested: Array[Dictionary] = []
	menu.connect("hangar_aircraft_requested", func(entry: Dictionary) -> void: requested.append(entry))
	menu.call("set_open", true)
	menu.call("_on_entry_pressed", selected)
	if requested.size() != 1 or str(requested[0].get("scene", "")) != "res://Aircraft/Aircraft_13.tscn" \
			or bool(menu.call("is_open")) or get_tree().paused:
		_fail("selection did not emit Aircraft_13 and restore play")
		return
	menu.queue_free()

	var deck := (load("res://Tests/Fixtures/HangarRequestDeckFixture.gd") as Script).new() as FlightDeckManager
	get_tree().root.add_child(deck)
	await get_tree().process_frame
	if not deck.stored_aircraft.is_empty():
		_fail("test carrier did not start with an empty hangar")
		return
	if not deck.request_hangar_aircraft_for_launch("res://Aircraft/Aircraft_13.tscn"):
		_fail("empty hangar rejected Aircraft_13 retrieval")
		return
	if deck.current_state != FlightDeckManager.DeckState.RETRIEVING_FROM_HANGAR \
			or deck.stored_aircraft.size() != 1 \
			or str(deck.stored_aircraft[0].get("scene_file", "")) != "res://Aircraft/Aircraft_13.tscn":
		_fail("request did not reserve the real hangar retrieval flow")
		return
	if deck.request_hangar_aircraft_for_launch("res://Aircraft/Aircraft_11.tscn") \
			or deck.stored_aircraft.size() != 1:
		_fail("busy deck accepted a second retrieval")
		return
	print("[HangarSpawnMenuSmoketest] PASS aircraft_only=%d empty_inventory=true retrieval_reserved=true busy_rejected=true" % aircraft_entries.size())
	deck.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit(0)


func _fail(reason: String) -> void:
	push_error("[HangarSpawnMenuSmoketest] FAIL " + reason)
	get_tree().paused = false
	get_tree().quit(1)
