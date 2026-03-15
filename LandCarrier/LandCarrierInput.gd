extends Node3D
class_name LandCarrierInput

# =============================================================================
# LAND CARRIER INPUT CONTROLS
# =============================================================================
# Simple input handler for Land Carrier movement and elevator control
# =============================================================================

@export var land_carrier: LandCarrier
@export var speed_increment: float = 5.0  # m/s speed change per key press
@export var max_speed: float = 20.0  # m/s maximum speed
@export var min_speed: float = 0.0   # m/s minimum speed
@export var enable_legacy_keyboard_controls: bool = false

var current_speed: float = 0.0
var current_direction: float = 0.0  # Direction in degrees

func _ready():
	# Find the land carrier if not assigned
	if not land_carrier:
		# If this script is a child of LandCarrier, get the parent
		if get_parent() is LandCarrier:
			land_carrier = get_parent()
		else:
			# Try to find the LandCarrier node in the scene
			land_carrier = get_node("../LandCarrier")
			if not land_carrier or not land_carrier is LandCarrier:
				# Try alternative paths
				land_carrier = get_node("../../LandCarrier")
				if not land_carrier or not land_carrier is LandCarrier:
					# Search for any LandCarrier in the scene
					land_carrier = get_tree().get_first_node_in_group("land_carrier")
	
	if not land_carrier or not land_carrier is LandCarrier:
		print("Error: No LandCarrier found for input controls")
		return
	
	print("Land Carrier Input Controls Ready!")
	if enable_legacy_keyboard_controls:
		print("Controls:")
		print("  E - Move elevator up")
		print("  D - Move elevator down") 
		print("  W - Increase speed")
		print("  S - Decrease speed")
		print("  A - Turn left")
		print("  D - Turn right")
		print("  ESC - Quit")

func _input(event):
	if not land_carrier:
		return

	# Arrow Up/Down always adjust max_speed regardless of legacy mode.
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_UP:
				land_carrier.max_speed = clamp(land_carrier.max_speed + 8.0, min_speed, 40.0)
				print("[Carrier] Speed → %.0f m/s" % land_carrier.max_speed)
				return
			KEY_DOWN:
				land_carrier.max_speed = clamp(land_carrier.max_speed - 8.0, min_speed, 40.0)
				print("[Carrier] Speed → %.0f m/s" % land_carrier.max_speed)
				return

	if not enable_legacy_keyboard_controls:
		return

	# Handle key presses
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_E:
				# Move elevator up
				if land_carrier.has_method("get_elevator"):
					var elevator = land_carrier.get_elevator()
					if elevator:
						elevator.move_platform_up()
						print("Elevator moving UP")
					else:
						print("No elevator system available")
				else:
					print("No elevator system available")
			
			KEY_D:
				# Move elevator down
				if land_carrier.has_method("get_elevator"):
					var elevator = land_carrier.get_elevator()
					if elevator:
						elevator.move_platform_down()
						print("Elevator moving DOWN")
					else:
						print("No elevator system available")
				else:
					print("No elevator system available")
			
			KEY_W:
				# Increase speed
				increase_speed()
			
			KEY_S:
				# Decrease speed
				decrease_speed()
			
			KEY_A:
				# Turn left
				turn_left()
			
			KEY_D:
				# Turn right (only if not using D for elevator)
				if not Input.is_key_pressed(KEY_E):  # Only turn if E is not pressed
					turn_right()
			
			KEY_ESCAPE:
				# Quit application
				get_tree().quit()

func increase_speed():
	"""Increase carrier speed"""
	land_carrier.increase_speed(speed_increment)
	current_speed = land_carrier.get_speed()
	print("Speed increased to: ", current_speed, " m/s")

func decrease_speed():
	"""Decrease carrier speed"""
	land_carrier.decrease_speed(speed_increment)
	current_speed = land_carrier.get_speed()
	print("Speed decreased to: ", current_speed, " m/s")

func turn_left():
	"""Turn carrier left"""
	land_carrier.turn_left(15.0)
	current_direction = land_carrier.get_direction()
	print("Turning left to: ", current_direction, " degrees")

func turn_right():
	"""Turn carrier right"""
	land_carrier.turn_right(15.0)
	current_direction = land_carrier.get_direction()
	print("Turning right to: ", current_direction, " degrees")

func get_status() -> Dictionary:
	"""Get current input status"""
	return {
		"current_speed": current_speed,
		"current_direction": current_direction,
		"max_speed": max_speed,
		"min_speed": min_speed
	}
