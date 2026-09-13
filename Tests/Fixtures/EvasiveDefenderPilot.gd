extends "res://AI/AIPilot.gd"
## Fixed mission heading; normal surfaces/navigation and production evasion.
func _state_dogfight(delta: float) -> void:
	_stop_firing()
	nav_waypoint = aircraft.global_position + Vector3(0, 0, 1500)
	nav_waypoint.y = 1000.0
	maneuver_waypoint = nav_waypoint
	target_altitude = 1000.0
	target_speed = 85.0
	_navigate_to_waypoint(delta)
func _state_search(delta: float) -> void:
	_state_dogfight(delta)
