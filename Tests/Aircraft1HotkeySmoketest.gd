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

	var key_event := InputEventKey.new()
	key_event.keycode = KEY_1
	key_event.pressed = true
	manager._input(key_event)

	_expect(manager.retrieval_start_count == 1, "key 1 did not start exactly one hangar retrieval")
	_expect(manager.stored_aircraft.size() == 1, "key 1 did not add Aircraft 1 to the hangar retrieval queue")
	if manager.stored_aircraft.size() == 1:
		var queued_aircraft: Dictionary = manager.stored_aircraft[0]
		var queued_scene := queued_aircraft.get("scene", null) as PackedScene
		var metadata := queued_aircraft.get("metadata", {}) as Dictionary
		_expect(str(queued_aircraft.get("name", "")) == "Aircraft_1", "key 1 queued the wrong aircraft model")
		_expect(str(queued_aircraft.get("scene_file", "")) == "res://Aircraft/Aircraft_1.tscn", "key 1 queued the wrong scene path")
		_expect(queued_scene != null, "key 1 did not load the Aircraft 1 scene")
		if queued_scene != null:
			_expect(queued_scene.resource_path == "res://Aircraft/Aircraft_1.tscn", "queued PackedScene is not Aircraft 1")
		_expect(int(metadata.get("pilot_id", -1)) > 0, "queued Aircraft 1 was not assigned a pilot")

	key_event.echo = true
	manager._input(key_event)
	_expect(manager.retrieval_start_count == 1, "a held key repeat started another retrieval")
	_expect(manager.stored_aircraft.size() == 1, "a held key repeat queued another aircraft")

	key_event.echo = false
	manager.current_state = FlightDeckManager.DeckState.LAUNCH_IN_PROGRESS
	manager._input(key_event)
	_expect(manager.retrieval_start_count == 1, "key 1 started another retrieval while the deck was busy")
	_expect(manager.stored_aircraft.size() == 1, "key 1 queued an aircraft while the deck was busy")

	manager.free()
	carrier_manager.free()
	if _failures.is_empty():
		print("AIRCRAFT_1_HOTKEY_SMOKETEST_OK")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error("[Aircraft1HotkeySmoketest] %s" % failure)
	get_tree().quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
