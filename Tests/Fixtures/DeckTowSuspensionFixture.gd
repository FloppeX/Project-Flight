extends "res://LandCarrier/FlightDeckManager.gd"

# Exercise production positioning/towing without starting hangar jobs or scenarios.
func _ready() -> void:
	set_physics_process(false)

