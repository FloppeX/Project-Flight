extends Node3D

# =============================================================================
# CARRIER ELEVATOR INTEGRATION - Test with real carrier GLB
# =============================================================================

var land_carrier: RigidBody3D
var elevator: CarrierElevator

func _ready():
	print("=== Carrier Elevator Integration Test ===")
	print("Testing elevator with stable carrier")
	print("Press SPACE to toggle elevator sequence")
	print("Press ESC to quit")
	
	# Get the land carrier
	land_carrier = $LandCarrier
	
	# Get the elevator from the carrier
	elevator = land_carrier.get_elevator()
	
	print("Elevator integrated with carrier")

func _process(delta):
	if elevator:
		elevator.update(delta)

func _input(event):
	if event.is_action_pressed("ui_accept"):  # Space key
		print("\n--- Toggling Elevator Sequence ---")
		elevator.reverse_elevator_sequence()
	elif event.is_action_pressed("ui_cancel"):  # ESC key
		get_tree().quit()
