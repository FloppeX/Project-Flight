extends Node3D

# =============================================================================
# STABLE CARRIER TEST - Test carrier stability
# =============================================================================

var land_carrier: LandCarrier

func _ready():
	land_carrier = $LandCarrier
	
	print("=== Stable Carrier Test ===")
	print("Carrier should be stable and not bounce")
	print("Press SPACE to test movement")
	print("Press ESC to quit")

func _process(delta):
	if land_carrier:
		var velocity = land_carrier.linear_velocity.length()
		var angular_velocity = land_carrier.angular_velocity.length()
		var y_pos = land_carrier.global_position.y
		
		if velocity > 5.0 or angular_velocity > 2.0:
			print("WARNING: Carrier moving too fast! V=", velocity, " A=", angular_velocity)
		
		if y_pos < -5.0:
			print("ERROR: Carrier fell through ground! Y=", y_pos)
		elif y_pos < 0.0:
			print("WARNING: Carrier below ground! Y=", y_pos)
		
		# Only print every 60 frames to avoid spam
		if Engine.get_process_frames() % 60 == 0:
			print("Position: Y=", y_pos, " V=", velocity, " A=", angular_velocity)

func _input(event):
	if event.is_action_pressed("ui_accept"):  # Space key
		print("\n--- Testing Movement ---")
		var test_pos = land_carrier.global_position + Vector3(5, 0, 0)
		land_carrier.set_target_position(test_pos)
		print("Moving to: ", test_pos)
	elif event.is_action_pressed("ui_cancel"):  # ESC key
		get_tree().quit()
