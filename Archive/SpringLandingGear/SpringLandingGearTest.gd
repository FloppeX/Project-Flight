# SpringLandingGearTest.gd
# Test script for the new spring landing gear system

extends Node3D

@onready var aircraft = $Aircraft
@onready var camera = $Camera3D

func _ready():
	# Set up camera to follow aircraft
	if aircraft and camera:
		camera.position = aircraft.position + Vector3(0, 15, 15)
		camera.look_at(aircraft.position, Vector3.UP)

func _process(delta):
	# Follow aircraft with camera
	if aircraft and camera:
		var target_position = aircraft.position + Vector3(0, 15, 15)
		camera.position = camera.position.lerp(target_position, 2.0 * delta)
		camera.look_at(aircraft.position, Vector3.UP)

func _input(event):
	if event.is_action_pressed("ui_accept"):  # Space key
		# Toggle landing gear
		var landing_gear = aircraft.find_child("LandingGear")
		if landing_gear and landing_gear.has_method("deploy"):
			if landing_gear.is_deployed:
				landing_gear.stow()
			else:
				landing_gear.deploy()
	
	if event.is_action_pressed("ui_select"):  # Enter key
		# Apply some force to test suspension
		if aircraft:
			aircraft.apply_central_force(Vector3(0, 1000, 0))
	
	if event.is_action_pressed("ui_cancel"):  # Escape key
		# Reset aircraft position
		if aircraft:
			aircraft.position = Vector3(0, 5, 0)
			aircraft.linear_velocity = Vector3.ZERO
			aircraft.angular_velocity = Vector3.ZERO
