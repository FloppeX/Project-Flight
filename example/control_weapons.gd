extends AircraftModule
class_name ControlWeapons

@export var hardpoints: Array[Hardpoint] = []  # Drag all hardpoints here
var selected_hardpoint_index: int = 0

func _input(event):
	if Input.is_action_just_pressed("fire_weapon"):
		fire_current_weapon()
	if Input.is_action_just_pressed("cycle_weapon"):  # If you want weapon cycling
		cycle_weapon()

func fire_current_weapon():
	if hardpoints.size() > 0:
		var current_hardpoint = hardpoints[selected_hardpoint_index]
		if current_hardpoint and current_hardpoint.fire():
			# Weapon fired successfully
			pass

func cycle_weapon():
	if hardpoints.size() > 1:
		selected_hardpoint_index = (selected_hardpoint_index + 1) % hardpoints.size()
