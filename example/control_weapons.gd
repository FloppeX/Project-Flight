extends AircraftModule
class_name ControlWeapons

@export var hardpoints: Array[Hardpoint] = []
var selected_hardpoint_index: int = 0
var is_trigger_held: bool = false

func _input(event):
	if Input.is_action_just_pressed("fire_weapon"):
		is_trigger_held = true
		fire_current_weapon()
	
	if Input.is_action_just_released("fire_weapon"):
		is_trigger_held = false
	
	if Input.is_action_just_pressed("cycle_weapon"):
		cycle_weapon()

func _process(delta):
	# Continuous firing for automatic weapons
	if is_trigger_held:
		fire_current_weapon()

func fire_current_weapon():
	var fired = false
	
	# First try to fire all automatic weapons (autocannons)
	for hardpoint in hardpoints:
		if hardpoint.weapon_instance and hardpoint.weapon_instance.automatic_fire:
			if hardpoint.fire():
				fired = true
	
	# If no automatic weapons fired, fire the currently selected single-shot weapon
	if not fired and hardpoints.size() > 0:
		var current_hardpoint = hardpoints[selected_hardpoint_index]
		if current_hardpoint and current_hardpoint.weapon_instance:
			if not current_hardpoint.weapon_instance.automatic_fire:
				# Only fire single-shot weapons once per trigger pull
				if Input.is_action_just_pressed("fire_weapon"):
					current_hardpoint.fire()

func cycle_weapon():
	if hardpoints.size() > 1:
		selected_hardpoint_index = (selected_hardpoint_index + 1) % hardpoints.size()
