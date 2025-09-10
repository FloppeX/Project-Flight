extends Node3D

# =============================================================================
# REAL CARRIER ELEVATOR TEST - Test with actual carrier GLB
# =============================================================================

var land_carrier: RigidBody3D
var elevator: CarrierElevator

func _ready():
	print("=== Real Carrier Elevator Test ===")
	print("Testing elevator with your actual carrier GLB")
	print("Press SPACE to toggle elevator sequence")
	print("Press ESC to quit")
	
	# Get the land carrier
	land_carrier = $LandCarrier
	
	# Wait for carrier to initialize
	await get_tree().process_frame
	
	# Get the elevator from the carrier (it's already built-in)
	elevator = land_carrier.get_elevator()
	
	if elevator:
		print("Elevator found and ready!")
	else:
		print("No elevator found - creating one...")
		# Fallback: create elevator if not found
		elevator = CarrierElevator.new()
		add_child(elevator)
		elevator.setup(land_carrier)

func _process(delta):
	if elevator:
		elevator.update(delta)

func _input(event):
	if event.is_action_pressed("ui_accept"):  # Space key
		print("\n--- Toggling Elevator Sequence ---")
		elevator.reverse_elevator_sequence()
	elif event.is_action_pressed("ui_cancel"):  # ESC key
		get_tree().quit()
