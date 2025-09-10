extends Node3D

# =============================================================================
# SIMPLE CARRIER TEST - Just show the carrier without movement
# =============================================================================

var land_carrier: LandCarrier

func _ready():
	land_carrier = $LandCarrier
	print("=== Simple Carrier Test ===")
	print("Carrier should be stable on the ground")
	print("")
	print("Controls:")
	print("  E - Move elevator up")
	print("  D - Move elevator down")
	print("  W - Increase speed")
	print("  S - Decrease speed")
	print("  SPACE - Test movement (legacy)")
	print("  ESC - Quit")

func _process(delta):
	if land_carrier:
		print("Carrier Position: ", land_carrier.global_position)
		print("Carrier Velocity: ", land_carrier.linear_velocity.length(), " m/s")

func _input(event):
	if event.is_action_pressed("ui_accept"):  # Space key
		print("\n--- Testing Movement ---")
		var test_pos = land_carrier.global_position + Vector3(10, 0, 0)
		land_carrier.set_target_position(test_pos)
		print("Moving to: ", test_pos)
	elif event.is_action_pressed("ui_cancel"):  # ESC key
		get_tree().quit()
