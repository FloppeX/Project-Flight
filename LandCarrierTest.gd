extends Node3D

# =============================================================================
# LAND CARRIER TEST SCENE
# =============================================================================
# Simple test scene to demonstrate the LandCarrier functionality
# =============================================================================

var land_carrier: LandCarrier
var test_positions: Array[Vector3] = [
	Vector3(0, 0, 0),
	Vector3(50, 0, 0),
	Vector3(50, 0, 50),
	Vector3(0, 0, 50),
	Vector3(-50, 0, 50),
	Vector3(-50, 0, 0),
	Vector3(-50, 0, -50),
	Vector3(0, 0, -50),
	Vector3(50, 0, -50)
]
var current_position_index: int = 0

func _ready():
	# Get reference to the land carrier
	land_carrier = $LandCarrier
	
	# Connect to carrier signals
	land_carrier.connect("carrier_moved", Callable(self, "_on_carrier_moved"))
	land_carrier.connect("carrier_rotated", Callable(self, "_on_carrier_rotated"))
	land_carrier.connect("carrier_damaged", Callable(self, "_on_carrier_damaged"))
	
	# Start the test sequence
	start_test_sequence()

func _input(event):
	if event.is_action_pressed("ui_accept"):  # Space key
		move_to_next_position()
	elif event.is_action_pressed("ui_cancel"):  # ESC key
		get_tree().quit()

func start_test_sequence():
	"""Start the automated test sequence"""
	print("Land Carrier Test Started!")
	print("Press SPACE to move to next position")
	print("Press ESC to quit")
	
	# Move to first test position
	move_to_next_position()

func move_to_next_position():
	"""Move carrier to the next test position"""
	if current_position_index >= test_positions.size():
		current_position_index = 0
	
	var target_pos = test_positions[current_position_index]
	print("Moving carrier to position: ", target_pos)
	
	land_carrier.set_target_position(target_pos)
	current_position_index += 1

func _on_carrier_moved(new_position: Vector3):
	"""Called when carrier reaches its target position"""
	print("Carrier moved to: ", new_position)
	
	# Wait a bit, then move to next position
	await get_tree().create_timer(2.0).timeout
	move_to_next_position()

func _on_carrier_rotated(new_rotation: float):
	"""Called when carrier finishes rotating"""
	print("Carrier rotated to: ", rad_to_deg(new_rotation), " degrees")

func _on_carrier_damaged(damage_amount: float, current_health: float):
	"""Called when carrier takes damage"""
	print("Carrier damaged! Damage: ", damage_amount, " Health: ", current_health)

func _process(delta):
	"""Update test scene"""
	# Display carrier status
	if land_carrier:
		var status = land_carrier.get_status()
		var health_percent = status.health_percentage * 100
		print("Carrier Health: ", health_percent, "% | Moving: ", status.is_moving, " | Rotating: ", status.is_rotating)
