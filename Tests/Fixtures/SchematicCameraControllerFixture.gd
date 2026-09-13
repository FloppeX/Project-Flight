extends "res://Camera/CameraController.gd"

# Exercise the real camera-switch helpers without creating a player aircraft.
func _ready() -> void:
	set_process(false)
	set_physics_process(false)
	set_process_input(false)
