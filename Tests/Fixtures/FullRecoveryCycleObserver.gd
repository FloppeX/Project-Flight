extends "res://Scenario/CarrierCombatTestMode.gd"

var test_result: Dictionary = {}

func _ready() -> void:
	set_physics_process(false)

func _log(message: String) -> void:
	if message.begins_with("RUN_RESULT json="):
		test_result = JSON.parse_string(message.trim_prefix("RUN_RESULT json="))
