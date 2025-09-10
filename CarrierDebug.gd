extends Node3D

# =============================================================================
# CARRIER DEBUG - Help diagnose physics issues
# =============================================================================

var land_carrier: LandCarrier

func _ready():
	land_carrier = $LandCarrier
	print("=== Carrier Debug Started ===")
	print("Press SPACE to test movement")
	print("Press ESC to quit")

func _process(delta):
	if land_carrier:
		var status = land_carrier.get_status()
		print("Carrier Status:")
		print("  Health: ", status.health_percentage * 100, "%")
		print("  Position: ", land_carrier.global_position)
		print("  Velocity: ", land_carrier.linear_velocity.length(), " m/s")
		print("  Angular Velocity: ", land_carrier.angular_velocity.length(), " rad/s")
		print("  Moving: ", status.is_moving, " Rotating: ", status.is_rotating)
		print("  Tread Positions: ", land_carrier.tread_positions.size())

func _input(event):
	if event.is_action_pressed("ui_accept"):  # Space key
		print("\n--- Testing Movement ---")
		var test_pos = land_carrier.global_position + Vector3(20, 0, 0)
		land_carrier.set_target_position(test_pos)
		print("Moving to: ", test_pos)
	elif event.is_action_pressed("ui_cancel"):  # ESC key
		get_tree().quit()
