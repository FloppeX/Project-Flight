extends Node3D

# =============================================================================
# ELEVATOR TEST - Test the elevator system
# =============================================================================

var elevator: CarrierElevator

func _ready():
	print("=== Elevator Test ===")
	print("Testing elevator system...")
	
	# Create elevator
	elevator = CarrierElevator.new()
	add_child(elevator)
	
	# Set up elevator
	elevator.setup(null)  # No carrier needed for basic test
	
	print("Elevator created and ready")
	print("Press SPACE to toggle elevator sequence (up/down)")
	print("Press ESC to quit")

func _process(delta):
	if elevator:
		elevator.update(delta)

func _input(event):
	if event.is_action_pressed("ui_accept"):  # Space key
		print("\n--- Toggling Elevator Sequence ---")
		elevator.reverse_elevator_sequence()
	elif event.is_action_pressed("ui_cancel"):  # ESC key
		get_tree().quit()
