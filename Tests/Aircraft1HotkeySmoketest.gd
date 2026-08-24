extends Node

class TestFlightDeckManager:
	extends FlightDeckManager

	var retrieval_start_count: int = 0

	func _ready() -> void:
		pass

	func start_hangar_retrieval():
		retrieval_start_count += 1


var _failures: PackedStringArray = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var carrier_manager := CarrierManager.new()
	add_child(carrier_manager)
	var manager := TestFlightDeckManager.new()
	manager.carrier_manager = carrier_manager
	add_child(manager)
	manager.set_process_input(false)

	var hotkeys: Array[Key] = [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9, KEY_0]
	var key_event := InputEventKey.new()
	key_event.pressed = true
	for index in range(hotkeys.size()):
		var aircraft_number := index + 1
		key_event.keycode = hotkeys[index]
		manager._input(key_event)
		_expect(
			manager.retrieval_start_count == aircraft_number,
			"number hotkey did not start exactly one retrieval for Aircraft %d" % aircraft_number
		)
		_expect(
			manager.stored_aircraft.size() == aircraft_number,
			"number hotkey did not add Aircraft %d to the retrieval queue" % aircraft_number
		)
		if manager.stored_aircraft.size() != aircraft_number:
			continue
		var queued_aircraft: Dictionary = manager.stored_aircraft[0]
		var expected_name := "Aircraft_%d" % aircraft_number
		var expected_path := "res://Aircraft/Aircraft_%d.tscn" % aircraft_number
		var queued_scene := queued_aircraft.get("scene", null) as PackedScene
		var metadata := queued_aircraft.get("metadata", {}) as Dictionary
		_expect(str(queued_aircraft.get("name", "")) == expected_name, "hotkey queued the wrong aircraft model for %s" % expected_name)
		_expect(str(queued_aircraft.get("scene_file", "")) == expected_path, "hotkey queued the wrong scene path for %s" % expected_name)
		_expect(queued_scene != null, "hotkey did not load the scene for %s" % expected_name)
		if queued_scene != null:
			_expect(queued_scene.resource_path == expected_path, "queued PackedScene is not %s" % expected_name)
		_expect(int(metadata.get("pilot_id", -1)) > 0, "queued %s was not assigned a pilot" % expected_name)

	key_event.echo = true
	manager._input(key_event)
	_expect(manager.retrieval_start_count == 10, "a held key repeat started another retrieval")
	_expect(manager.stored_aircraft.size() == 10, "a held key repeat queued another aircraft")

	key_event.echo = false
	manager.current_state = FlightDeckManager.DeckState.LAUNCH_IN_PROGRESS
	manager._input(key_event)
	_expect(manager.retrieval_start_count == 10, "a number key started another retrieval while the deck was busy")
	_expect(manager.stored_aircraft.size() == 10, "a number key queued an aircraft while the deck was busy")

	manager.free()
	carrier_manager.free()
	if _failures.is_empty():
		print("AIRCRAFT_NUMBER_HOTKEY_SMOKETEST_OK")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error("[Aircraft1HotkeySmoketest] %s" % failure)
	get_tree().quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
