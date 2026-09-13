extends "res://AI/AIPilot.gd"
var terrain_test_height: float = 0.0

func _get_recovery_carrier_frame() -> Dictionary:
	return {"valid": true, "origin": Vector3.ZERO, "forward": Vector3.BACK,
		"right": Vector3.RIGHT, "deck_y": 0.0}

func _update_recovery_carrier_relative_gates(_frame: Dictionary) -> void:
	pass

func _get_ground_height_at_position(_position: Vector3) -> float:
	return terrain_test_height
