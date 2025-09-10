extends Node3D

# =============================================================================
# SIMPLE LAND CARRIER TEST - Test the stable carrier
# =============================================================================

var land_carrier: RigidBody3D

func _ready():
	land_carrier = $LandCarrier
	print("=== Simple Land Carrier Test ===")
	print("Carrier should be stable and not bounce")
	print("Press SPACE to test movement")
	print("Press R to reset position")
	print("Press ESC to quit")

func _process(delta):
	if land_carrier:
		var y_pos = land_carrier.global_position.y
		var velocity = land_carrier.linear_velocity.length()
		var angular_velocity = land_carrier.angular_velocity.length()
		
		if y_pos < -5.0:
			print("ERROR: Carrier fell through ground! Y=", y_pos)
		elif y_pos < 0.0:
			print("WARNING: Carrier below ground! Y=", y_pos)
		
		# Print status every 60 frames
		if Engine.get_process_frames() % 60 == 0:
			print("Position: Y=", y_pos, " V=", velocity, " A=", angular_velocity)

func _input(event):
	if event.is_action_pressed("ui_accept"):  # Space key
		print("\n--- Testing Movement ---")
		var test_pos = land_carrier.global_position + Vector3(10, 0, 0)
		land_carrier.call("set_target_position", test_pos)
		print("Moving to: ", test_pos)
	elif event.is_action_pressed("ui_select"):  # R key
		print("\n--- Resetting Position ---")
		land_carrier.global_position = Vector3(0, 1, 0)
		land_carrier.linear_velocity = Vector3.ZERO
		land_carrier.angular_velocity = Vector3.ZERO
		print("Reset to origin")
	elif event.is_action_pressed("ui_cancel"):  # ESC key
		get_tree().quit()
